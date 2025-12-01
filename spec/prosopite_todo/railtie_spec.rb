# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe ProsopiteTodo::Railtie do
  it "is a Rails::Railtie" do
    expect(described_class.superclass).to eq(Rails::Railtie)
  end

  it "has rake tasks" do
    expect(described_class.rake_tasks).not_to be_empty
  end

  describe ".setup_prosopite_integration" do
    let(:tmp_dir) { Dir.mktmpdir }
    let(:todo_file_path) { File.join(tmp_dir, ".prosopite_todo.yaml") }

    before do
      allow(ProsopiteTodo::TodoFile).to receive(:new).and_return(
        ProsopiteTodo::TodoFile.new(todo_file_path)
      )
    end

    after do
      FileUtils.rm_rf(tmp_dir)
      ProsopiteTodo.clear_pending_notifications
    end

    context "when Prosopite is not defined" do
      before do
        hide_const("Prosopite") if defined?(Prosopite)
      end

      it "does not raise error" do
        expect { described_class.setup_prosopite_integration }.not_to raise_error
      end

      it "returns nil" do
        result = described_class.setup_prosopite_integration
        expect(result).to be_nil
      end
    end

    context "when Prosopite is defined" do
      let(:mock_prosopite) do
        Class.new do
          class << self
            def singleton_class
              @singleton_class ||= Class.new
            end

            def create_notifications
              # Default implementation sets empty notifications
              Thread.current[:prosopite_notifications] = {}
            end
          end
        end
      end

      before do
        stub_const("Prosopite", mock_prosopite)
      end

      it "prepends integration module to Prosopite singleton class" do
        described_class.setup_prosopite_integration
        # The prepend should have been called
        expect(Prosopite.singleton_class.ancestors.first).to be_a(Module)
      end
    end
  end

  describe "SqliteFingerprintSupport" do
    let(:sqlite_support) { described_class::SqliteFingerprintSupport }

    describe "#sqlite_fingerprint" do
      let(:dummy_class) do
        Class.new do
          include ProsopiteTodo::Railtie::SqliteFingerprintSupport
        end
      end
      let(:instance) { dummy_class.new }

      it "normalizes strings to ?" do
        query = "SELECT * FROM users WHERE name = 'John'"
        result = instance.sqlite_fingerprint(query)
        expect(result).to include("?")
        expect(result).not_to include("John")
      end

      it "normalizes numbers to ?" do
        query = "SELECT * FROM users WHERE id = 123"
        result = instance.sqlite_fingerprint(query)
        expect(result).to include("?")
        expect(result).not_to include("123")
      end

      it "normalizes boolean values to ?" do
        query = "SELECT * FROM users WHERE active = true"
        result = instance.sqlite_fingerprint(query)
        expect(result).to include("?")
        expect(result).not_to include("true")
      end

      it "normalizes whitespace" do
        query = "SELECT  *   FROM    users"
        result = instance.sqlite_fingerprint(query)
        expect(result).to eq("select * from users")
      end

      it "removes SQL comments" do
        query = "SELECT * FROM users /* comment */ WHERE id = 1"
        result = instance.sqlite_fingerprint(query)
        expect(result).not_to include("comment")
      end

      it "produces consistent fingerprints for same query structure" do
        query1 = "SELECT * FROM users WHERE id = 1"
        query2 = "SELECT * FROM users WHERE id = 999"
        result1 = instance.sqlite_fingerprint(query1)
        result2 = instance.sqlite_fingerprint(query2)
        expect(result1).to eq(result2)
      end

      it "produces different fingerprints for different query structures" do
        query1 = "SELECT * FROM users WHERE id = 1"
        query2 = "SELECT * FROM posts WHERE id = 1"
        result1 = instance.sqlite_fingerprint(query1)
        result2 = instance.sqlite_fingerprint(query2)
        expect(result1).not_to eq(result2)
      end
    end
  end

  describe ".add_sqlite_fingerprint_support" do
    context "when Prosopite is not defined" do
      before do
        hide_const("Prosopite") if defined?(Prosopite)
      end

      it "does not raise error" do
        expect { described_class.add_sqlite_fingerprint_support }.not_to raise_error
      end
    end
  end
end
