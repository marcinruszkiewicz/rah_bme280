# frozen_string_literal: true

module RahBme280
  # I2C-dev interface driver
  class Driver
    I2C_SLAVE = 0x0703
    I2C_SLAVE_FORCE = 0x0706

    def initialize(path: '/dev/i2c-1')
      @path = path
      @slave_command = I2C_SLAVE
    end

    def i2c_get(address, param, length = 1)
      i2c = File.open(@path, 'r+')
      i2c.ioctl(@slave_command, address)
      i2c.syswrite(param.chr) unless param.nil?
      ret = i2c.sysread(length)
      i2c.close
      ret
    rescue Errno::EIO => e
      raise RahBme280::I2CIOError, e.message
    end

    def i2c_set(address, *data)
      i2c = File.open(@path, 'r+')
      i2c.ioctl(@slave_command, address)
      i2c.syswrite(data.pack('C*'))
      i2c.close
    rescue Errno::EIO => e
      raise RahBme280::I2CIOError, e.message
    end
  end
end