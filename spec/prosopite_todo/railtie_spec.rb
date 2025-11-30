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
      # Reset Prosopite state
      if defined?(Prosopite)
        Prosopite.instance_variable_set(:@finish_callback, nil)
      end
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
      before do
        stub_const("Prosopite", Class.new do
          class << self
            attr_accessor :finish_callback

            def instance_variable_get(name)
              @finish_callback if name == :@finish_callback
            end
          end
        end)
      end

      it "sets finish_callback on Prosopite" do
        described_class.setup_prosopite_integration
        expect(Prosopite.finish_callback).to be_a(Proc)
      end

      it "filters notifications through Scanner" do
        described_class.setup_prosopite_integration

        notifications = {
          "SELECT * FROM users" => [["app/models/user.rb:10"]]
        }

        result = Prosopite.finish_callback.call(notifications)

        # Should return filtered notifications (all in this case since nothing is ignored)
        expect(result).to eq(notifications)
      end

      it "accumulates notifications in pending_notifications" do
        described_class.setup_prosopite_integration

        notifications = {
          "SELECT * FROM users" => [["app/models/user.rb:10"]]
        }

        Prosopite.finish_callback.call(notifications)

        expect(ProsopiteTodo.pending_notifications).to have_key("SELECT * FROM users")
      end

      context "when original callback exists" do
        it "preserves and calls original callback" do
          callback_called = false
          original_callback = proc do |filtered|
            callback_called = true
            expect(filtered).to be_a(Hash)
          end

          Prosopite.finish_callback = original_callback

          described_class.setup_prosopite_integration

          notifications = {
            "SELECT * FROM users" => [["app/models/user.rb:10"]]
          }

          Prosopite.finish_callback.call(notifications)

          expect(callback_called).to be true
        end

        it "passes filtered notifications to original callback" do
          received_notifications = nil
          original_callback = proc { |filtered| received_notifications = filtered }

          Prosopite.finish_callback = original_callback

          # Create a todo file entry to filter out
          todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
          fp = ProsopiteTodo::Scanner.fingerprint(
            query: "SELECT * FROM users",
            location: ["app/models/user.rb:10"]
          )
          todo_file.add_entry(
            fingerprint: fp,
            query: "SELECT * FROM users",
            location: "app/models/user.rb:10"
          )
          todo_file.save

          described_class.setup_prosopite_integration

          notifications = {
            "SELECT * FROM users" => [["app/models/user.rb:10"]],
            "SELECT * FROM posts" => [["app/models/post.rb:20"]]
          }

          Prosopite.finish_callback.call(notifications)

          # Original callback should only receive non-ignored notifications
          expect(received_notifications.keys).to eq(["SELECT * FROM posts"])
        end
      end

      context "when original callback is nil" do
        before do
          Prosopite.finish_callback = nil
        end

        it "does not raise error" do
          described_class.setup_prosopite_integration

          notifications = {
            "SELECT * FROM users" => [["app/models/user.rb:10"]]
          }

          expect { Prosopite.finish_callback.call(notifications) }.not_to raise_error
        end
      end
    end
  end
end
