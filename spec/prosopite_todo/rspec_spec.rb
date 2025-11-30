# frozen_string_literal: true

require "prosopite_todo/rspec"

RSpec.describe ProsopiteTodo::RSpec do
  describe ".enabled?" do
    after do
      ENV.delete("PROSOPITE_TODO_UPDATE")
    end

    it "returns false when PROSOPITE_TODO_UPDATE is not set" do
      ENV.delete("PROSOPITE_TODO_UPDATE")
      expect(described_class.enabled?).to be false
    end

    it "returns true when PROSOPITE_TODO_UPDATE is '1'" do
      ENV["PROSOPITE_TODO_UPDATE"] = "1"
      expect(described_class.enabled?).to be true
    end

    it "returns true when PROSOPITE_TODO_UPDATE is 'true'" do
      ENV["PROSOPITE_TODO_UPDATE"] = "true"
      expect(described_class.enabled?).to be true
    end

    it "returns true when PROSOPITE_TODO_UPDATE is 'yes'" do
      ENV["PROSOPITE_TODO_UPDATE"] = "yes"
      expect(described_class.enabled?).to be true
    end

    it "returns true when PROSOPITE_TODO_UPDATE is 'TRUE' (case insensitive)" do
      ENV["PROSOPITE_TODO_UPDATE"] = "TRUE"
      expect(described_class.enabled?).to be true
    end

    it "returns false when PROSOPITE_TODO_UPDATE is '0'" do
      ENV["PROSOPITE_TODO_UPDATE"] = "0"
      expect(described_class.enabled?).to be false
    end

    it "returns false when PROSOPITE_TODO_UPDATE is 'false'" do
      ENV["PROSOPITE_TODO_UPDATE"] = "false"
      expect(described_class.enabled?).to be false
    end
  end
end
