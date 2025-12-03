# frozen_string_literal: true

require "spec_helper"

RSpec.describe ProsopiteTodo::Configuration do
  after do
    ProsopiteTodo.reset_configuration!
  end

  describe "#max_location_frames" do
    it "defaults to 5" do
      expect(described_class.new.max_location_frames).to eq(5)
    end

    it "can be configured" do
      ProsopiteTodo.configure do |config|
        config.max_location_frames = 10
      end

      expect(ProsopiteTodo.configuration.max_location_frames).to eq(10)
    end

    it "can be set to nil to include all frames" do
      ProsopiteTodo.configure do |config|
        config.max_location_frames = nil
      end

      expect(ProsopiteTodo.configuration.max_location_frames).to be_nil
    end
  end

  describe "#location_filter" do
    it "defaults to nil" do
      expect(described_class.new.location_filter).to be_nil
    end

    it "can be set to a custom callable" do
      custom_filter = ->(frames) { frames.select { |f| f.include?("/app/") } }

      ProsopiteTodo.configure do |config|
        config.location_filter = custom_filter
      end

      expect(ProsopiteTodo.configuration.location_filter).to eq(custom_filter)
    end
  end

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(ProsopiteTodo.configuration).to be_a(described_class)
    end

    it "returns the same instance on multiple calls" do
      config1 = ProsopiteTodo.configuration
      config2 = ProsopiteTodo.configuration

      expect(config1).to be(config2)
    end
  end

  describe ".configure" do
    it "yields the configuration" do
      expect { |b| ProsopiteTodo.configure(&b) }.to yield_with_args(ProsopiteTodo::Configuration)
    end
  end

  describe ".reset_configuration!" do
    it "resets configuration to defaults" do
      ProsopiteTodo.configure do |config|
        config.max_location_frames = 20
        config.location_filter = ->(frames) { frames }
      end

      ProsopiteTodo.reset_configuration!

      expect(ProsopiteTodo.configuration.max_location_frames).to eq(5)
      expect(ProsopiteTodo.configuration.location_filter).to be_nil
    end
  end
end
