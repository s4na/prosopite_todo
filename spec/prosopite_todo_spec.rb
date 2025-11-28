# frozen_string_literal: true

RSpec.describe ProsopiteTodo do
  it "has a version number" do
    expect(ProsopiteTodo::VERSION).not_to be_nil
  end

  describe ".todo_file_path" do
    it "returns default path" do
      expect(ProsopiteTodo.todo_file_path).to eq(ProsopiteTodo::TodoFile.default_path)
    end

    it "can be configured" do
      original = ProsopiteTodo.todo_file_path
      ProsopiteTodo.todo_file_path = "/custom/path.yaml"
      expect(ProsopiteTodo.todo_file_path).to eq("/custom/path.yaml")
      ProsopiteTodo.todo_file_path = nil
    end
  end

  describe ".pending_notifications" do
    after do
      ProsopiteTodo.clear_pending_notifications
    end

    it "returns empty hash by default" do
      expect(ProsopiteTodo.pending_notifications).to eq({})
    end

    it "can add pending notifications" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )
      expect(ProsopiteTodo.pending_notifications).to have_key("SELECT * FROM users")
    end
  end
end
