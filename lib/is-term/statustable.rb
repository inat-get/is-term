# frozen_string_literal: true

require 'set'
require 'singleton'
require 'tty-screen'

require_relative 'info'
require_relative 'boolean'
require_relative 'string_helpers'

class IS::Term::Error < StandardError; end
class IS::Term::StateError < IS::Term::Error; end

class IS::Term::StatusTable

  # module Formats; end
  # module Functions; end

  include Singleton
  
  using IS::Term::StringHelpers

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
    result = @rows.find { |r| r[@id_field] == row_id }.dup
    result.delete :_mutex if result
    result.freeze
  end

  # @endgroup

  # @group State

  def configured?
    !!@id_field && !@defs.empty?
  end

  def available?
    !!@term && @term.is_a?(IO) && File.chardev?(@term)
  end

  # @return [self]
  def reset!
    if @in_configure
      @defs = []
      @id_field = nil
      @inactivate_if = nil
      @term = DEFAULT_IO
      @show_summary = nil
      @summary_prefix = DEFAULT_SUMMARY_PREFIX
      @summary_values = {}
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

  # @group Data Manipulation

  # @yield
  # @yieldparam [Hash] row
  # @return [Hash]
  def append **data
    raise IS::Term::StateError, "StatusTable is not ready for work", caller_locations unless available? && configured?
    data.transform_keys!(&:to_sym)
    id = data[@id_field]
    raise ArgumentError, "Row Id must be specified", caller_locations if id.nil?
    raise ArgumentError, "Row with Id = #{ id.inspect } already exists", caller_locations if @rows.any? { |r| r[@id_field] == id }
    row = {}
    row[:_active] = true
    row[:_started] = Time::now
    row[:_mutex] = Thread::Mutex::new
    row.merge! data
    yield row if block_given?
    @mutex.synchronize do
      @rows << row
      @term.puts ''
      render_table
    end
    result = row.dup
    result.delete :_mutex
    result.freeze
  end

  # @yield
  # @yieldparam [Hash] row
  # @return [Hash]
  def update **data
    raise IS::Term::StateError, "StatusTable is not ready for work", caller_locations unless available? && configured?
    data.transform_keys!(&:to_sym)
    id = data[@id_field]
    raise ArgumentError, "Row Id must be specified", caller_locations if id.nil?
    row = find_row id
    raise ArgumentError, "Row with Id = #{id.inspect} must be exists", caller_locations if row.nil?
    row[:_mutex].synchronize do
      row.merge! data
      yield row if block_given?
      if row[:_active] && @inactivate_if && @inactivate_if.call(row)
        row[:_active] = false
        row[:_finished] = Time::now
        render_table
      else
        render_line row
      end
    end
    result = row.dup
    result.delete :_mutex
    result.freeze
  end

  # @endgroup

  # @group Configuration

  # @yield
  # @return [self]
  def configure &block
    if block_given?
      @mutex.synchronize do
        @in_configure = true
        instance_eval(&block)
        @in_configure = nil
      end
    end
    @term.puts ''
    self
  end

  # @endgroup

  private

  # @private
  def find_row id
    @rows.find { |r| r[@id_field] == id }
  end

  # @private
  def apply_format value, format
    case format
    when String
      format % value
    when Proc
      format[value]
    else
      raise ArgumentError, "Unknown format value: #{ format.inspect }", caller_locations
    end
  end

  # @private
  def prerender_line row
    result = []
    @defs.each do |definition|
      case definition
      when String
        result << definition
      when Hash
        value = if definition[:func]
          definition[:func].call row
        else
          row[definition[:name]]
        end
        skip_width = value.is_a?(Array)
        value = value.first if skip_width
        if definition[:format]
          value = apply_format value, definition[:format]
        else
          value = value.to_s
        end
        if definition[:width] && !skip_width
          value = value.ellipsis definition[:width]
          value = value.align definition[:width], definition[:align]
        end
        return false if !skip_width && value.width > definition[:_width] && !@in_table_render
        result << value
        break if skip_width
      else
        raise IS::Term::StateError, "Invalid column definition: #{ definition.inspect }", caller_locations
      end
    end
    result
  end

  # @private
  def prerender_table
    result = @rows.map { |r| prerender_line r }
    result << prerender_summary if @show_summary
    result
  end

  # @private
  def prerender_summary
    result = []
    @defs.each do |definition|
      case definition
      when String
        result << definition
      when Hash
        name = definition[:name]
        value = case definition[:summary]
        when nil
          ''
        when :value
          @summary_values[name]
        when Proc
          definition[:summary].call
        end
        skip_width = value.is_a?(Array)
        value = value.first if skip_width
        if definition[:format] && !value.nil? && value != ''
          value = apply_format value, definition[:format]
        else
          value = value.to_s
        end
        if definition[:width] && !skip_width
          value = value.ellipsis definition[:width]
          value = value.align definition[:width], definition[:align]
        end
        return false if !skip_width && value.width > definition[:_width] && !@in_table_render
        result << value
        break if skip_width
      else
        raise IS::Term::StateError, "Invalid column definition: #{definition.inspect}", caller_locations
      end
    end
    result
  end

  # @private
  def render_line row
    prerendered = prerender_line row 
    summary = @show_summary ? prerender_summary : :skip
    if prerendered && summary
      line = ''
      (0 .. prerendered.size - 1).each do |idx|
        value = prerendered[idx]
        definition = @defs[idx]
        value = value.align definition[:_width], (definition[:align] || IS::Term::StringHelpers::ALIGN_LEFT) if !definition.is_a?(String)
        line += value
      end
      shift = row[:_shift]
      @term.print "\e[0m\e[#{ shift }A\e[0m#{ line.ellipsis TTY::Screen::width }\e[0m\e[K\r\e[#{ shift }B"
      if @show_summary
        line = ''
        (0 .. summary.size - 1).each do |idx|
          value = summary[idx]
          definition = @defs[idx]
          value = value.align definition[:_width], (definition[:align] || IS::Term::StringHelpers::ALIGN_LEFT) if !definition.is_a?(String)
          line += value
        end
        @term.print "\e[0m\e[1A#{ @summary_prefix }#{ line.ellipsis TTY::Screen::width }\e[0m\e[K\r\e[1B"
      end
    else
      @mutex.synchronize { render_table } unless @in_table_render
    end
  end

  # @private
  def render_table
    @in_table_render = true
    @rows.sort_by! { |r| [ r[:_active], r[:_started] ] }
    size = @rows.size
    size += 1 if @show_summary
    @rows.each_with_index { |row, idx| row[:_shift] = size - idx }
    prerendered = prerender_table
    @defs.each_with_index do |definition, idx|
      case definition
      when Hash
        definition[:_width] = prerendered.map { |row| row[idx]&.width }.compact.max
      end
    end
    text = ''
    last = prerendered.size - 1
    prerendered.each_with_index do |ln, i|
      if @show_summary && i == last
        line = @summary_prefix
      else
        line = ''
      end
      ln.each_with_index do |value, idx|
        definition = @defs[idx]
        value = value.align definition[:_width], (definition[:align] || IS::Term::StringHelpers::ALIGN_LEFT) if !definition.is_a?(String)
        line += value
      end
      text += "\e[0m\e[K#{ line.ellipsis TTY::Screen::width }\e[0m\e[K\n"
    end
    @term.print "\e[0m\e[#{ prerendered.size }A#{ text }\e[0m\e[1B"
    @in_table_render = nil
  end

  # @group Configuration DSL

  # @private
  SUMMARY_NONE = [ :none, false ].freeze
  # @private
  SUMMARY_VALS = [ :value ].freeze  

  # @return [void]
  def column name, id: false, func: nil, format: nil, width: nil, align: nil, summary: nil
    raise ArgumentError, "Invalid name value: #{ name.inspect }", caller_locations unless name.is_a?(String) || name.is_a?(Symbol)
    raise ArgumentError, "Name can not be empty", caller_locations if name == '' || name == :''
    name = name.to_sym
    raise ArgumentError, "Column name already exists: #{ name }", caller_locations if @defs.any? { |d| d.is_a?(Hash) && d[:name] == name }
    raise ArgumentError, "Invalid id value: #{ id.inspect }", caller_locations unless id.nil? || id == true || id == false
    id = nil if id == false
    raise ArgumentError, "Id field already exists (#{ @id_field })" if @id_field && id
    func_keys = Set[]
    if self.class.const_defined?(:Functions)
      func_keys |= Set[*Functions::ROW_METHODS]
    end
    raise ArgumentError, "Invalid func value: #{ func.inspect }", caller_locations unless func.nil? || func.respond_to?(:call) || func_keys.include?(func)
    if self.class.const_defined?(:Functions) && func.is_a?(Symbol)
      func = Functions::RF func
    end
    format_keys = Set[]
    if self.class.const_defined?(:Formats)
      format_keys |= Set[*Formats::SPECIAL_FORMATS]
    end
    raise ArgumentError, "Invalid format value: #{ format.inspect }", caller_locations unless format.nil? || format.is_a?(String) || format.is_a?(Array) || format.respond_to?(:call) || format_keys.include?(format)
    if self.class.const_defined?(:Formats) && format && !format.respond_to?(:call)
      format = Formats::fmt format if format.is_a?(Symbol) || format.is_a?(String)
      format = Formats::bar(*format) if format.is_a?(Array) 
    end
    raise ArgumentError, "Invalid width value: #{ width.inspect }", caller_locations unless width.nil? || width.is_a?(Integer)
    raise ArgumentError, "Invalid align value: #{ align.inspect }", caller_locations unless align.nil? || IS::Term::StringHelpers::ALIGN_MODES.include?(align)
    align = IS::Term::StringHelpers::DEFAULT_ALIGN_MODE if align.nil?
    summary_keys = Set[*(SUMMARY_NONE + SUMMARY_VALS)]
    if self.class.const_defined?(:Functions)
      summary_keys |= Set[*(Functions::TABLE_METHODS + Functions::AGGREGATE_METHODS)]
    end
    raise ArgumentError, "Invalid summary value: #{ summary.inspect }", caller_locations unless summary_keys.include?(summary) || summary.is_a?(Proc) || summary.nil?
    summary = nil if SUMMARY_NONE.include?(summary) || summary.nil?
    if self.class.const_defined?(:Functions)
      summary = Functions::TF summary if Functions::TABLE_METHODS.include?(summary)
      summary = Functions::AF summary, name if Functions::AGGREGATE_METHODS.include?(summary)
    end
    definition = { name: name, id: id, func: func, format: format, width: width, _width: (width || 0), align: align, summary: summary }.compact
    @defs << definition
    @id_field = name if id
    self
  end

  # @return [void]
  def separator str = ' '
    raise ArgumentError, "Invalid separator: #{ str.inspect }", caller_locations unless str.is_a?(String)
    @defs << str
    self
  end

  # @yield
  # @yieldparam [Hash] row
  # @return [void]
  def inactivate_if &block
    raise ArgumentError, "Block condition must be specified", caller_locations unless block_given?
    @inactivate_if = block
    self
  end

  # @return [void]
  def terminal io
    raise ArgumentError, "Invalid terminal value: #{ io.inspect }", caller_locations unless io.is_a?(IO) && File.chardev?(io)
    @term = io
    self
  end

  public

  # @return [void]
  def summary show = nil, prefix: nil, **values
    @show_summary = show unless show.nil?
    @show_summary = true if @show_summary.nil?
    @summary_prefix = prefix unless prefix.nil?
    @summary_values.merge! values.transform_keys(&:to_sym)
    self
  end

  # @endgroup

end

