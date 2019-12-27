# frozen_string_literal: true

class StringIO
  def ioctl(cmd, arg); end

  def syswrite(str); end

  def sysread(arg); end
end
