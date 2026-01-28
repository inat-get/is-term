# frozen_string_literal: true

require 'singleton'

require_relative 'info'

class IS::Term::StatusTable

  include Singleton

  INVERT = "\e[7m"
  
  DEFAULT_IO = $stdout
  DEFAULT_SUMMARY_PREFIX = INVERT

  # @private
  def initialize
    @mutex = Thread::Mutex::new
    @in_configure = true
    reset!
    @in_configure = nil
  end

  # @group Configuration Info

  # @return [IO]
  attr_reader :term

  # @return [Array<Hash|String>]
  attr_reader :defs

  # @endgroup

  # @group Data Manipulation

  # @return [Array<Hash>]
  def rows
    @rows ||= []
    @rows.dup.freeze
  end

  # @return [Hash, nil]
  def row row_id
    return nil if @id_field.nil?
    @rows.find { |r| r[@id_field] == row_id }.dup.freeze
  end

  # @endgroup

  # @group State

  def configured?
    !!@id_field && !@defs.empty?
  end

  def empty?
    @rows.empty?
  end

  # @return [Integer]
  def count
    @rows.size
  end

  def available?
    !!@term && @term.is_a?(IO) && File.chardev?(@term)
  end

  # @return [self]
  def reset!
    if @in_configure
      @defs = []
      @id_field = nil
      @term = DEFAULT_IO
      @started = Time::now
      @rows = []
    else
      @mutex.synchronize do
        @started = Time::now
        @rows = []
      end
    end
    self
  end

  # @endgroup

  # @group Status

  # @return [Time, nil]
  def started row_id = nil
    if row_id.nil?
      @started
    else
      row = find_row row_id
      return nil if row.nil?
      row[:_started]
    end
  end

  # @return [Boolean, nil]
  def active? row_id = nil
    return nil if @id_field.nil?
    if row_id.nil?
      @rows.any? { |r| r[:_active] }
    else
      row = find_row row_id
      return nil if row.nil?
      row[:_active]
    end
  end

  # @return [Integer, nil] in seconds
  def elapsed row_id = nil
    # TODO: implement
  end

  # @return [Integer, nil] in seconds
  def estimated row_id = nil
    # TODO: implement
  end

  # @return [Float, nil] steps by second (average)
  def speed row_id = nil
    # TODO: implement
  end

  # @return [Integer, nil]
  def percent row_id = nil
    # TODO: implement
  end

  # @return [Integer, nil]
  def current row_id = nil
    # TODO: implement
  end

  # @return [Integer, nil]
  def total row_id = nil
    # TODO: implement
  end

  # @endgroup

  # @group Data Manipulation

  # @return [Hash]
  def append **data
    # TODO: implement
  end

  # @return [Hash]
  def update **data
    # TODO: implement
  end

  # @endgroup

  # @group Configuration

  # @return [self]
  def configure &block
    if block_given?
      @mutex.synchronize do
        @in_configure = true
        instance_eval(&block)
        @in_configure = nil
      end
    end
    self
  end

  # @endgroup

  private

  # @private
  def find_row id
    @rows.find { |r| r[@id_field] == id }
  end

  # @private
  def render_line row
    # TODO: implement
  end

  # @private
  def render_table
    # TODO: implement
  end

  # @group Configuration DSL

  # @return [void]
  def column name, id: false, func: nil, format: nil, width: nil, align: nil, summary: nil
    # TODO: implement
  end

  # @return [void]
  def separator str = ' '
    # TODO: implement
  end

  # @return [void]
  def inactivate_if &block
    # TODO: implement
  end

  # @return [void]
  def terminal io
    # TODO: implement
  end

  public

  # @return [void]
  def summary show = nil, prefix: nil, **values
    # TODO: implement
  end

  # @endgroup

end
