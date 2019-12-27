# frozen_string_literal: true

RSpec.describe RahBme280::Driver do
  let(:subject) { RahBme280::Driver.new }

  describe '#i2c_get' do
    it 'reads from device' do
      expect(File).to receive(:open).and_return(StringIO.new)
      expect(subject.i2c_get(0x00, 1, 1)).to eq nil
    end
  end

  describe '#i2c_set' do
    it 'writes to device' do
      expect(File).to receive(:open).and_return(StringIO.new)
      expect(subject.i2c_set(0x00, 1)).to eq nil
    end
  end
end
