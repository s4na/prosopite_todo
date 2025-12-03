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

    it "returns true when PROSOPITE_TODO_UPDATE is 'YES' (case insensitive)" do
      ENV["PROSOPITE_TODO_UPDATE"] = "YES"
      expect(described_class.enabled?).to be true
    end

    it "returns false when PROSOPITE_TODO_UPDATE is empty string" do
      ENV["PROSOPITE_TODO_UPDATE"] = ""
      expect(described_class.enabled?).to be false
    end

    it "returns false when PROSOPITE_TODO_UPDATE is whitespace" do
      ENV["PROSOPITE_TODO_UPDATE"] = "   "
      expect(described_class.enabled?).to be false
    end

    it "returns false when PROSOPITE_TODO_UPDATE is 'no'" do
      ENV["PROSOPITE_TODO_UPDATE"] = "no"
      expect(described_class.enabled?).to be false
    end

    it "returns false for unexpected values" do
      ENV["PROSOPITE_TODO_UPDATE"] = "enabled"
      expect(described_class.enabled?).to be false
    end
  end

  describe ".setup" do
    after do
      ENV.delete("PROSOPITE_TODO_UPDATE")
    end

    context "when not enabled" do
      before do
        ENV.delete("PROSOPITE_TODO_UPDATE")
      end

      it "does not configure RSpec" do
        # Create a mock RSpec configuration
        mock_config = double("RSpec::Configuration")

        # setup should not call RSpec.configure when disabled
        expect(::RSpec).not_to receive(:configure)

        described_class.setup
      end
    end

    context "when enabled" do
      before do
        ENV["PROSOPITE_TODO_UPDATE"] = "1"
      end

      it "configures RSpec with after(:suite) hook" do
        # We can't easily test the actual RSpec configuration without running
        # a real test suite, but we can verify the method doesn't raise errors
        # The actual integration is tested by verifying the auto-setup works
        expect { described_class.setup }.not_to raise_error
      end
    end
  end

  describe ".clean_enabled?" do
    after do
      ENV.delete("PROSOPITE_TODO_CLEAN")
    end

    it "returns false when PROSOPITE_TODO_CLEAN is not set" do
      ENV.delete("PROSOPITE_TODO_CLEAN")
      expect(described_class.clean_enabled?).to be false
    end

    it "returns true when PROSOPITE_TODO_CLEAN is '1'" do
      ENV["PROSOPITE_TODO_CLEAN"] = "1"
      expect(described_class.clean_enabled?).to be true
    end

    it "returns true when PROSOPITE_TODO_CLEAN is 'true'" do
      ENV["PROSOPITE_TODO_CLEAN"] = "true"
      expect(described_class.clean_enabled?).to be true
    end

    it "returns true when PROSOPITE_TODO_CLEAN is 'yes'" do
      ENV["PROSOPITE_TODO_CLEAN"] = "yes"
      expect(described_class.clean_enabled?).to be true
    end

    it "returns false when PROSOPITE_TODO_CLEAN is '0'" do
      ENV["PROSOPITE_TODO_CLEAN"] = "0"
      expect(described_class.clean_enabled?).to be false
    end

    it "returns false when PROSOPITE_TODO_CLEAN is 'false'" do
      ENV["PROSOPITE_TODO_CLEAN"] = "false"
      expect(described_class.clean_enabled?).to be false
    end
  end
end
