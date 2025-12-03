# frozen_string_literal: true

require_relative "task_helpers"

namespace :prosopite_todo do
  desc "Generate .prosopite_todo.yaml from current N+1 detections (overwrites existing)"
  task :generate do
    ProsopiteTodo::TaskHelpers.generate
  end

  desc "Update .prosopite_todo.yaml by adding new N+1 detections"
  task :update do
    ProsopiteTodo::TaskHelpers.update
  end

  desc "List all entries in .prosopite_todo.yaml"
  task :list do
    ProsopiteTodo::TaskHelpers.list
  end

  desc "Clean .prosopite_todo.yaml by removing entries no longer detected"
  task :clean do
    ProsopiteTodo::TaskHelpers.clean
  end
end
