# frozen_string_literal: true

require "spec_helper"

RSpec.describe ProsopiteTodo::Railtie do
  it "is a Rails::Railtie" do
    expect(described_class.superclass).to eq(Rails::Railtie)
  end

  it "has rake tasks" do
    expect(described_class.rake_tasks).not_to be_empty
  end
end
