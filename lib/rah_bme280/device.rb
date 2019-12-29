# frozen_string_literal: true

module RahBme280
  # Implements the I2C-Device BMP280/BME280 - a Bosch temperature/humidity/pressure sensor
  # Datasheet: https://ae-bst.resource.bosch.com/media/_tech/media/datasheets/BST-BME280_DS002-13.pdf
  class Device
    REG_HUM_LSB = 0xFE
    REG_HUM_MSB = 0xFD
    REG_TEMP_XLSB = 0xFC
    REG_TEMP_LSB = 0xFB
    REG_TEMP_MSB = 0xFA
    REG_PRESS_XLSB = 0xF9
    REG_PRESS_LSB = 0xF8
    REG_PRESS_MSB = 0xF7
    REG_CONFIG = 0xF5
    REG_CTRL_MEAS = 0xF4
    REG_STATUS = 0xF3
    REG_CTRL_HUM = 0xF2
    REG_CALIB26 = 0xE1
    REG_CALIB41 = 0xF0
    REG_RESET = 0xE0
    REG_ID = 0xD0
    REG_CALIB00 = 0x88
    REG_CALIB25 = 0xA1

    OVERSAMPLE_SKIP = 0b000
    OVERSAMPLE_0 = 0b000
    OVERSAMPLE_1 = 0b001
    OVERSAMPLE_2 = 0b010
    OVERSAMPLE_4 = 0b011
    OVERSAMPLE_8 = 0b100
    OVERSAMPLE_16 = 0b101

    T_STANDBY_0_5MS = 0b000
    T_STANDBY_62_5MS = 0b001
    T_STANDBY_125MS = 0b010
    T_STANDBY_250MS = 0b011
    T_STANDBY_500MS = 0b100
    T_STANDBY_1000MS = 0b101

    T_STANDBY_10MS_BME280 = 0b110
    T_STANDBY_20MS_BME280 = 0b111

    T_STANDBY_2000MS_BMP280 = 0b110
    T_STANDBY_4000MS_BMP280 = 0b111

    FILTER_OFF = 0b000
    FILTER_2 = 0b001
    FILTER_4 = 0b010
    FILTER_8 = 0b011
    FILTER_16 = 0b100

    MODE_SLEEP = 0b00
    MODE_FORCED = 0b01
    MODE_NORMAL = 0b11

    def initialize(address:)
      @driver = RahBme280::Driver.new
      @address = address

      read_calibration
    end

    def status
      raw = read_raw
      temp, t_fine = compensate_T(raw[:temp_raw])

      {
        temperature: temp,
        pressure: compensate_P(raw[:pressure_raw], t_fine),
        humidity: compensate_H(raw[:hum_raw], t_fine)
      }
    end

    def i2c_get(param, length = 1)
      @driver.i2c_get(@address, param, length)
    end

    def i2c_set(*data)
      @driver.i2c_set(@address, *data)
    end

    def read_calibration
      # s< = little endian signed 16bit
      # S< = little endian unsigned 16bit
      # c = signed 8bit
      # C = unsigned 8bit
      @dig_T1,
      @dig_T2,
      @dig_T3,
      @dig_P1,
      @dig_P2,
      @dig_P3,
      @dig_P4,
      @dig_P5,
      @dig_P6,
      @dig_P7,
      @dig_P8,
      @dig_P9 = i2c_get(0x88, 24).unpack([
        'S<', # T1
        's<', # T2
        's<', # T3
        'S<', # P1
        's<', # P2
        's<', # P3
        's<', # P4
        's<', # P5
        's<', # P6
        's<', # P7
        's<', # P8
        's<' # P9
      ].join)

      @dig_H1, = *i2c_get(0xA1, 1).unpack('C')
      @dig_H2,
      @dig_H3,
      e4,
      e5,
      e6,
      @dig_H6 = *i2c_get(0xE1, 8).unpack([
        's<', # H2
        'C', # H3
        'C', # H4 (0xE4)
        'C', # H4/H5 (0xE5)
        'C', # H5 (0xE6)
        'c' # H6
      ].join)
      @dig_H4 = e4 << 4 | e5 & 0x0F
      @dig_H5 = e6 << 4 | e5 >> 4
      nil
    end

    def read_raw
      data = i2c_get(0xF7, 8)
      pressure_raw = (data[0].ord << 12) | (data[1].ord << 4) | (data[2].ord >> 2)
      temp_raw = (data[3].ord << 12) | (data[4].ord << 4) | (data[5].ord >> 2)
      hum_raw = (data[6].ord << 8) | data[7].ord

      {
        pressure_raw: pressure_raw,
        temp_raw: temp_raw,
        hum_raw: hum_raw
      }
    end

    def write_config(t_standby = T_STANDBY_0_5MS, filter = FILTER_OFF, spi3w_en = 0)
      num = (t_standby << 5) | (filter << 2) | spi3w_en
      i2c_set(REG_CONFIG, num)
    end

    def write_ctrl_meas(temp_oversamples = 1, pressure_oversamples = 1, mode = MODE_NORMAL)
      num = (temp_oversamples << 7) | (pressure_oversamples << 2) | mode
      i2c_set(REG_CTRL_MEAS, num)
    end

    def read_status
      st = i2c_get(REG_STATUS, 1).ord
      {
        measuring: st[3],
        im_update: st[0]
      }
    end

    def write_ctrl_hum(oversamples = 1)
      i2c_set(REG_CTRL_HUM, oversamples)
    end

    def read_id
      # BME280 = 0x60
      # BMP280 = 0x56 0x57 0x58
      i2c_get(REG_ID, 1).ord.to_s(16)
    end

    def reset
      i2c_set(REG_RESET, 0xB6)
    end

    def compensate_T(adc_T)
      var1 = ((((adc_T >> 3) - (@dig_T1 << 1))) * @dig_T2) >> 11
      var2 = (((((adc_T >> 4) - @dig_T1) * ((adc_T >> 4) - @dig_T1)) >> 12) * @dig_T3) >> 14
      t_fine = var1 + var2
      temp = (t_fine * 5 + 128) >> 8
      [temp / 100.to_f, t_fine]
    end

    def compensate_P(adc_P, t_fine)
      var1 = t_fine - 128_000
      var2 = var1 * var1 * @dig_P6
      var2 += ((var1 * @dig_P5) << 17)
      var2 += (@dig_P4 << 35)
      var1 = ((var1 * var1 * @dig_P3) >> 8) + ((var1 * @dig_P2) << 12)
      var1 = (((1 << 47) + var1)) * @dig_P1 >> 33
      return 0 if var1.zero?

      p = 1_048_576 - adc_P
      p = (((p << 31) - var2) * 3_125) / var1

      var1 = (@dig_P9 * (p >> 13) * (p >> 13)) >> 25
      var2 = (@dig_P8 * p) >> 19
      q24_8 = ((p + var1 + var2) >> 8) + (@dig_P7 << 4)
      # convert Q24.8 to hPa
      q24_8 / 256.to_f / 100
    end

    def compensate_H(adc_H, t_fine)
      v_x1_u32r = t_fine - 76_800

      v_x1_u32r = (((((adc_H << 14) - (@dig_H4 << 20) - (@dig_H5 * v_x1_u32r)) + 16_384) >> 15) * (((((((v_x1_u32r * @dig_H6) >> 10) * (((v_x1_u32r * (@dig_H3)) >> 11) + 32_768)) >> 10) + 2_097_152) * @dig_H2 + 8_192) >> 14))
      v_x1_u32r = (v_x1_u32r - (((((v_x1_u32r >> 15) * (v_x1_u32r >> 15)) >> 7) * @dig_H1) >> 4))
      v_x1_u32r = v_x1_u32r.negative? ? 0 : v_x1_u32r
      v_x1_u32r = v_x1_u32r > 419_430_400 ? 419_430_400 : v_x1_u32r

      q22_10 = v_x1_u32r >> 12
      # Q22.10 to %RH
      q22_10 / 1024.to_f
    end
  end
end
