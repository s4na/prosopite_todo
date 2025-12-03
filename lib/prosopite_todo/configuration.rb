# frozen_string_literal: true

module ProsopiteTodo
  class Configuration
    # Maximum number of stack frames to include in the location field.
    # Set to nil to include all frames. Default: 5
    attr_accessor :max_location_frames

    # Custom callable for filtering stack frames.
    # When set, this takes precedence over Rails.backtrace_cleaner.
    # Should respond to #call(backtrace) and return an array of cleaned frames.
    # Example: ->(backtrace) { backtrace.select { |frame| frame.include?('/app/') } }
    attr_accessor :location_filter

    def initialize
      @max_location_frames = 5
      @location_filter = nil
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
