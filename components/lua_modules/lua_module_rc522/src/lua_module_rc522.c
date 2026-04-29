/*
 * SPDX-FileCopyrightText: 2026 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include "lua_module_rc522.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "cap_lua.h"
#include "driver/gpio.h"
#include "driver/spi_master.h"
#include "esp_check.h"
#include "esp_err.h"
#include "esp_rom_sys.h"
#include "lauxlib.h"

#define LUA_MODULE_RC522_METATABLE      "rc522"
#define LUA_MODULE_RC522_DEFAULT_HOST   2
#define LUA_MODULE_RC522_DEFAULT_CLOCK  (1000000)
#define LUA_MODULE_RC522_MAX_UID_LEN    10

/* MFRC522 registers */
#define RC522_REG_COMMAND               0x01
#define RC522_REG_COM_I_EN             0x02
#define RC522_REG_DIV_I_EN             0x03
#define RC522_REG_COM_IRQ              0x04
#define RC522_REG_DIV_IRQ              0x05
#define RC522_REG_ERROR                0x06
#define RC522_REG_STATUS1              0x07
#define RC522_REG_STATUS2              0x08
#define RC522_REG_FIFO_DATA            0x09
#define RC522_REG_FIFO_LEVEL           0x0A
#define RC522_REG_CONTROL              0x0C
#define RC522_REG_BIT_FRAMING         0x0D
#define RC522_REG_COLL                0x0E
#define RC522_REG_MODE                0x11
#define RC522_REG_TX_MODE             0x12
#define RC522_REG_RX_MODE             0x13
#define RC522_REG_TX_CONTROL          0x14
#define RC522_REG_TX_ASK              0x15
#define RC522_REG_MOD_WIDTH           0x24
#define RC522_REG_T_MODE              0x2A
#define RC522_REG_T_PRESCALER         0x2B
#define RC522_REG_T_RELOAD_H          0x2C
#define RC522_REG_T_RELOAD_L          0x2D
#define RC522_REG_VERSION             0x37

/* MFRC522 commands */
#define RC522_CMD_IDLE                 0x00
#define RC522_CMD_MEM                  0x01
#define RC522_CMD_CALC_CRC             0x03
#define RC522_CMD_TRANSCEIVE           0x0C
#define RC522_CMD_SOFT_RESET           0x0F

/* PICC commands */
#define PICC_CMD_REQA                  0x26
#define PICC_CMD_SEL_CL1               0x93

typedef struct {
    spi_device_handle_t spi;
    spi_host_device_t host;
    int sck_gpio;
    int mosi_gpio;
    int miso_gpio;
    int cs_gpio;
    int rst_gpio;
    bool bus_inited;
    bool dev_added;
} lua_module_rc522_ud_t;

static lua_module_rc522_ud_t *lua_module_rc522_get_ud(lua_State *L, int idx)
{
    lua_module_rc522_ud_t *ud =
        (lua_module_rc522_ud_t *)luaL_checkudata(L, idx, LUA_MODULE_RC522_METATABLE);
    if (!ud || !ud->spi) {
        luaL_error(L, "rc522: invalid or closed handle");
    }
    return ud;
}

static spi_host_device_t lua_module_rc522_parse_host(lua_State *L, lua_Integer host_id)
{
    if (host_id == 2) {
        return SPI2_HOST;
    }
    if (host_id == 3) {
        return SPI3_HOST;
    }
    luaL_error(L, "rc522.new: host must be 2 or 3");
    return SPI2_HOST;
}

static esp_err_t rc522_write_reg(lua_module_rc522_ud_t *ud, uint8_t reg, uint8_t value)
{
    uint8_t tx[2] = {
        (uint8_t)((reg << 1U) & 0x7EU),
        value,
    };
    spi_transaction_t t = {
        .length = 16,
        .tx_buffer = tx,
    };
    return spi_device_transmit(ud->spi, &t);
}

static esp_err_t rc522_read_reg(lua_module_rc522_ud_t *ud, uint8_t reg, uint8_t *value)
{
    uint8_t tx[2] = {
        (uint8_t)(((reg << 1U) & 0x7EU) | 0x80U),
        0x00,
    };
    uint8_t rx[2] = {0};
    spi_transaction_t t = {
        .length = 16,
        .tx_buffer = tx,
        .rx_buffer = rx,
    };
    esp_err_t err = spi_device_transmit(ud->spi, &t);
    if (err == ESP_OK) {
        *value = rx[1];
    }
    return err;
}

static esp_err_t rc522_set_bitmask(lua_module_rc522_ud_t *ud, uint8_t reg, uint8_t mask)
{
    uint8_t value = 0;
    esp_err_t err = rc522_read_reg(ud, reg, &value);
    if (err != ESP_OK) {
        return err;
    }
    return rc522_write_reg(ud, reg, value | mask);
}

static esp_err_t rc522_clear_bitmask(lua_module_rc522_ud_t *ud, uint8_t reg, uint8_t mask)
{
    uint8_t value = 0;
    esp_err_t err = rc522_read_reg(ud, reg, &value);
    if (err != ESP_OK) {
        return err;
    }
    return rc522_write_reg(ud, reg, value & (uint8_t)(~mask));
}

static esp_err_t rc522_reset(lua_module_rc522_ud_t *ud)
{
    if (ud->rst_gpio >= 0) {
        ESP_RETURN_ON_ERROR(gpio_set_level((gpio_num_t)ud->rst_gpio, 0), "rc522", "rst low");
        esp_rom_delay_us(50);
        ESP_RETURN_ON_ERROR(gpio_set_level((gpio_num_t)ud->rst_gpio, 1), "rc522", "rst high");
        esp_rom_delay_us(5000);
    }
    ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_COMMAND, RC522_CMD_SOFT_RESET), "rc522", "soft reset");
    esp_rom_delay_us(5000);
    return ESP_OK;
}

static esp_err_t rc522_init_chip(lua_module_rc522_ud_t *ud)
{
    ESP_RETURN_ON_ERROR(rc522_reset(ud), "rc522", "reset failed");
    ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_T_MODE, 0x80), "rc522", "tmode");
    ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_T_PRESCALER, 0xA9), "rc522", "tprescaler");
    ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_T_RELOAD_H, 0x03), "rc522", "treloadh");
    ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_T_RELOAD_L, 0xE8), "rc522", "treloadl");
    ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_TX_ASK, 0x40), "rc522", "txask");
    ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_MODE, 0x3D), "rc522", "mode");
    ESP_RETURN_ON_ERROR(rc522_set_bitmask(ud, RC522_REG_TX_CONTROL, 0x03), "rc522", "antenna on");
    return ESP_OK;
}

static esp_err_t rc522_transceive(lua_module_rc522_ud_t *ud,
                                  const uint8_t *send_data,
                                  size_t send_len,
                                  uint8_t *back_data,
                                  size_t *back_len,
                                  uint8_t *valid_bits)
{
    uint8_t irq_en = 0x77;
    uint8_t wait_irq = 0x30;
    uint8_t n = 0;
    size_t i = 0;

    ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_COMMAND, RC522_CMD_IDLE), "rc522", "idle");
    ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_COM_I_EN, irq_en | 0x80), "rc522", "irq en");
    ESP_RETURN_ON_ERROR(rc522_clear_bitmask(ud, RC522_REG_COM_IRQ, 0x80), "rc522", "clear irq");
    ESP_RETURN_ON_ERROR(rc522_set_bitmask(ud, RC522_REG_FIFO_LEVEL, 0x80), "rc522", "flush fifo");

    for (i = 0; i < send_len; i++) {
        ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_FIFO_DATA, send_data[i]), "rc522", "fifo write");
    }

    ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_COMMAND, RC522_CMD_TRANSCEIVE), "rc522", "transceive");
    ESP_RETURN_ON_ERROR(rc522_set_bitmask(ud, RC522_REG_BIT_FRAMING, 0x80), "rc522", "start send");

    for (i = 0; i < 2000; i++) {
        ESP_RETURN_ON_ERROR(rc522_read_reg(ud, RC522_REG_COM_IRQ, &n), "rc522", "irq read");
        if (n & wait_irq) {
            break;
        }
        if (n & 0x01) {
            return ESP_ERR_TIMEOUT;
        }
        esp_rom_delay_us(50);
    }
    ESP_RETURN_ON_ERROR(rc522_clear_bitmask(ud, RC522_REG_BIT_FRAMING, 0x80), "rc522", "stop send");

    if (i == 2000) {
        return ESP_ERR_TIMEOUT;
    }

    ESP_RETURN_ON_ERROR(rc522_read_reg(ud, RC522_REG_ERROR, &n), "rc522", "error read");
    if (n & 0x13) {
        return ESP_FAIL;
    }

    if (back_data && back_len) {
        uint8_t fifo_level = 0;
        uint8_t control = 0;
        size_t len = 0;
        ESP_RETURN_ON_ERROR(rc522_read_reg(ud, RC522_REG_FIFO_LEVEL, &fifo_level), "rc522", "fifo level");
        ESP_RETURN_ON_ERROR(rc522_read_reg(ud, RC522_REG_CONTROL, &control), "rc522", "control");
        len = fifo_level;
        if (*back_len < len) {
            return ESP_ERR_INVALID_SIZE;
        }
        *back_len = len;
        if (valid_bits) {
            *valid_bits = control & 0x07;
        }
        for (i = 0; i < len; i++) {
            ESP_RETURN_ON_ERROR(rc522_read_reg(ud, RC522_REG_FIFO_DATA, &back_data[i]), "rc522", "fifo read");
        }
    }

    return ESP_OK;
}

static esp_err_t rc522_request_a(lua_module_rc522_ud_t *ud)
{
    uint8_t req = PICC_CMD_REQA;
    uint8_t atqa[2] = {0};
    size_t atqa_len = sizeof(atqa);
    uint8_t valid_bits = 0;

    ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_BIT_FRAMING, 0x07), "rc522", "bit framing");
    esp_err_t err = rc522_transceive(ud, &req, 1, atqa, &atqa_len, &valid_bits);
    rc522_write_reg(ud, RC522_REG_BIT_FRAMING, 0x00);
    if (err != ESP_OK) {
        return err;
    }
    if (atqa_len != 2 || valid_bits != 0) {
        return ESP_FAIL;
    }
    return ESP_OK;
}

static esp_err_t rc522_anticoll(lua_module_rc522_ud_t *ud, uint8_t *uid, size_t *uid_len)
{
    uint8_t cmd[2] = { PICC_CMD_SEL_CL1, 0x20 };
    uint8_t back[5] = {0};
    size_t back_len = sizeof(back);
    uint8_t bcc = 0;
    size_t i = 0;

    ESP_RETURN_ON_ERROR(rc522_write_reg(ud, RC522_REG_BIT_FRAMING, 0x00), "rc522", "bit framing reset");
    ESP_RETURN_ON_ERROR(rc522_transceive(ud, cmd, 2, back, &back_len, NULL), "rc522", "anticoll");
    if (back_len != 5 || *uid_len < 4) {
        return ESP_FAIL;
    }
    for (i = 0; i < 4; i++) {
        uid[i] = back[i];
        bcc ^= back[i];
    }
    if (bcc != back[4]) {
        return ESP_FAIL;
    }
    *uid_len = 4;
    return ESP_OK;
}

static int lua_module_rc522_gc(lua_State *L)
{
    lua_module_rc522_ud_t *ud =
        (lua_module_rc522_ud_t *)luaL_testudata(L, 1, LUA_MODULE_RC522_METATABLE);
    if (!ud) {
        return 0;
    }
    if (ud->dev_added && ud->spi) {
        spi_bus_remove_device(ud->spi);
        ud->spi = NULL;
        ud->dev_added = false;
    }
    if (ud->bus_inited) {
        spi_bus_free(ud->host);
        ud->bus_inited = false;
    }
    return 0;
}

static int lua_module_rc522_close(lua_State *L)
{
    return lua_module_rc522_gc(L);
}

static int lua_module_rc522_version(lua_State *L)
{
    lua_module_rc522_ud_t *ud = lua_module_rc522_get_ud(L, 1);
    uint8_t version = 0;
    esp_err_t err = rc522_read_reg(ud, RC522_REG_VERSION, &version);
    if (err != ESP_OK) {
        return luaL_error(L, "rc522 version failed: %s", esp_err_to_name(err));
    }
    lua_pushinteger(L, version);
    return 1;
}

static int lua_module_rc522_read_uid(lua_State *L)
{
    lua_module_rc522_ud_t *ud = lua_module_rc522_get_ud(L, 1);
    uint8_t uid[LUA_MODULE_RC522_MAX_UID_LEN] = {0};
    size_t uid_len = sizeof(uid);
    size_t i = 0;
    char uid_hex[(LUA_MODULE_RC522_MAX_UID_LEN * 2) + 1];

    if (rc522_request_a(ud) != ESP_OK) {
        lua_pushnil(L);
        return 1;
    }
    if (rc522_anticoll(ud, uid, &uid_len) != ESP_OK) {
        lua_pushnil(L);
        return 1;
    }

    for (i = 0; i < uid_len; i++) {
        snprintf(&uid_hex[i * 2], 3, "%02X", uid[i]);
    }
    uid_hex[uid_len * 2] = '\0';

    lua_pushstring(L, uid_hex);
    return 1;
}

static int lua_module_rc522_new(lua_State *L)
{
    spi_host_device_t host = SPI2_HOST;
    spi_bus_config_t bus_cfg = {0};
    spi_device_interface_config_t dev_cfg = {0};
    gpio_config_t rst_cfg = {0};
    esp_err_t err = ESP_OK;
    lua_module_rc522_ud_t *ud = NULL;
    lua_Integer host_id = LUA_MODULE_RC522_DEFAULT_HOST;
    lua_Integer clock_hz = LUA_MODULE_RC522_DEFAULT_CLOCK;
    int sck = 0;
    int mosi = 0;
    int miso = 0;
    int cs = 0;
    int rst = -1;

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_getfield(L, 1, "host");
    if (!lua_isnil(L, -1)) {
        host_id = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    host = lua_module_rc522_parse_host(L, host_id);

    lua_getfield(L, 1, "clock_hz");
    if (!lua_isnil(L, -1)) {
        clock_hz = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);

    lua_getfield(L, 1, "sck");
    sck = (int)luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    lua_getfield(L, 1, "mosi");
    mosi = (int)luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    lua_getfield(L, 1, "miso");
    miso = (int)luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    lua_getfield(L, 1, "cs");
    cs = (int)luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    lua_getfield(L, 1, "rst");
    if (!lua_isnil(L, -1)) {
        rst = (int)luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);

    ud = (lua_module_rc522_ud_t *)lua_newuserdata(L, sizeof(*ud));
    memset(ud, 0, sizeof(*ud));
    ud->host = host;
    ud->sck_gpio = sck;
    ud->mosi_gpio = mosi;
    ud->miso_gpio = miso;
    ud->cs_gpio = cs;
    ud->rst_gpio = rst;

    bus_cfg.sclk_io_num = sck;
    bus_cfg.mosi_io_num = mosi;
    bus_cfg.miso_io_num = miso;
    bus_cfg.quadwp_io_num = -1;
    bus_cfg.quadhd_io_num = -1;
    bus_cfg.max_transfer_sz = 32;

    err = spi_bus_initialize(host, &bus_cfg, SPI_DMA_DISABLED);
    if (err == ESP_ERR_INVALID_STATE) {
        err = ESP_OK;
    } else if (err != ESP_OK) {
        return luaL_error(L, "rc522 bus init failed: %s", esp_err_to_name(err));
    } else {
        ud->bus_inited = true;
    }

    dev_cfg.clock_speed_hz = (int)clock_hz;
    dev_cfg.mode = 0;
    dev_cfg.spics_io_num = cs;
    dev_cfg.queue_size = 1;
    dev_cfg.command_bits = 0;
    dev_cfg.address_bits = 0;
    dev_cfg.flags = 0;

    err = spi_bus_add_device(host, &dev_cfg, &ud->spi);
    if (err != ESP_OK) {
        lua_module_rc522_gc(L);
        return luaL_error(L, "rc522 add device failed: %s", esp_err_to_name(err));
    }
    ud->dev_added = true;

    if (rst >= 0) {
        rst_cfg.pin_bit_mask = 1ULL << rst;
        rst_cfg.mode = GPIO_MODE_OUTPUT;
        rst_cfg.pull_up_en = GPIO_PULLUP_DISABLE;
        rst_cfg.pull_down_en = GPIO_PULLDOWN_DISABLE;
        rst_cfg.intr_type = GPIO_INTR_DISABLE;
        err = gpio_config(&rst_cfg);
        if (err != ESP_OK) {
            lua_module_rc522_gc(L);
            return luaL_error(L, "rc522 rst gpio config failed: %s", esp_err_to_name(err));
        }
        gpio_set_level((gpio_num_t)rst, 1);
    }

    err = rc522_init_chip(ud);
    if (err != ESP_OK) {
        lua_module_rc522_gc(L);
        return luaL_error(L, "rc522 init failed: %s", esp_err_to_name(err));
    }

    luaL_getmetatable(L, LUA_MODULE_RC522_METATABLE);
    lua_setmetatable(L, -2);
    return 1;
}

int luaopen_rc522(lua_State *L)
{
    if (luaL_newmetatable(L, LUA_MODULE_RC522_METATABLE)) {
        lua_pushcfunction(L, lua_module_rc522_gc);
        lua_setfield(L, -2, "__gc");
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, lua_module_rc522_close);
        lua_setfield(L, -2, "close");
        lua_pushcfunction(L, lua_module_rc522_version);
        lua_setfield(L, -2, "version");
        lua_pushcfunction(L, lua_module_rc522_read_uid);
        lua_setfield(L, -2, "read_uid");
    }
    lua_pop(L, 1);

    lua_newtable(L);
    lua_pushcfunction(L, lua_module_rc522_new);
    lua_setfield(L, -2, "new");
    return 1;
}

esp_err_t lua_module_rc522_register(void)
{
    return cap_lua_register_module("rc522", luaopen_rc522);
}
