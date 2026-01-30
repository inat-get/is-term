# frozen_string_literal: true

require 'singleton'
require 'tty-screen'

require_relative 'info'
require_relative 'boolean'
require_relative 'string_helpers'
require_relative 'formats'

class IS::Term::Error < StandardError; end
class IS::Term::StateError < IS::Term::Error; end

class IS::Term::StatusTable

  include Singleton

  using IS::Term::StringHelpers

  INVERT = "\e[7m"

  FUNC_ESTIMATED = lambda { |row| row[:current] && row[:current] != 0 ? ((Time::now - row[:_started]) / row[:current]) * (row[:total] - row[:current]) : 0 }
  FUNC_ELAPSED = lambda { |row| Time::now - row[:_started] }
  FUNC_SPEED = lambda { |row| row[:_active] ? format('%.2f', row[:current].to_f / (Time::now - row[:_started])) : '' }
  FUNC_PERCENT = lambda { |row| (row[:current] * 100) / row[:total] }
  
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

  # @group Status

  # @return [Time, nil]
  def started row_id = nil
    if row_id.nil?
      @started
    else
      return nil if @id_field.nil?
      row = find_row row_id
      return nil if row.nil?
      row[:_started]
    end
  end

  # @return [Boolean, nil]
  def active? row_id = nil
    if row_id.nil?
      @rows.any? { |r| r[:_active] }
    else
      return nil if @id_field.nil?
      row = find_row row_id
      return nil if row.nil?
      row[:_active]
    end
  end

  # @return [Boolean, nil]
  def done? row_id = nil
    active = self.active?
    return nil if active.nil?
    !active
  end

  # @return [Integer, nil] in seconds
  def elapsed row_id = nil
    if row_id.nil?
      Time::now - @started
    else
      return nil if @id_field.nil?
      row = find_row row_id
      return nil if row.nil?
      Time::now - row[:_started]
    end
  end

  # @return [Integer, nil] in seconds
  def estimated row_id = nil
    elapsed = self.elapsed row_id
    current = self.current row_id
    total   = self.total   row_id
    return nil if elapsed.nil? || current.nil? || current == 0 || total.nil?
    (elapsed / current) * (total - current)
  end

  # @return [Float, nil] steps by second (average)
  def speed row_id = nil
    elapsed = self.elapsed row_id
    current = self.current row_id
    return nil if elapsed.nil? || current.nil? || elapsed == 0
    current.to_f / elapsed.to_f
  end

  # @return [Integer, nil]
  # @see #current
  # @see #total
  def percent row_id = nil
    current = self.current row_id
    total   = self.total   row_id
    return nil if current.nil? || total.nil? || total == 0
    (current * 100) / total
  end

  # @return [Integer, nil]
  # @see #total
  def current row_id = nil
    if row_id.nil?
      @rows.select { |r| r[:current] != nil && r[:total] != nil }.map { |r| r[:current] }.sum
    else
      return nil if @id_field.nil?
      row = find_row row_id
      return nil if row.nil?
      row[:current]
    end
  end

  # @return [Integer, nil]
  # @see #current
  def total row_id = nil
    if row_id.nil?
      @rows.select { |r| r[:current] != nil && r[:total] != nil }.map { |r| r[:total] }.sum
    else
      return nil if @id_field.nil?
      row = find_row row_id
      return nil if row.nil?
      row[:total]
    end
  end

  # @return [Integer, nil]
  # @see #count
  # @see #done
  def active
    @rows.count { |r| r[:_active] }
  end

  # @return [Integer, nil]
  # @see #count
  # @see #active
  def done
    @rows.count { |r| !r[:_active] }
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
    row
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
        render_table
      else
        render_line row
      end
    end
    row
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
    when Symbol
      IS::Term::Formats.send format, value
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
        when :none, nil
          ''
        when :sum
          @rows.map { |r| r[name] }.compact.sum
        when :avg
          if @rows.size > 0
            @rows.map { |r| r[name] }.compact.sum / @rows.size
          else
            ''
          end
        when :min
          @rows.map { |r| r[name] }.compact.min
        when :max
          @rows.map { |r| r[name] }.compact.max
        when :count
          @rows.map { |r| r[name] }.compact.size
        when :elapsed
          self.elapsed
        when :estimated
          self.estimated
        when :percent
          self.percent
        when :speed
          '%.2f' % self.speed
        when :current
          self.current
        when :total
          self.total
        when :active
          self.active
        when :done
          self.done
        when :value
          @summary_values[name]
        when Proc
          definition.summary.call
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

  SPECIAL_FORMATS = [ :time ]   # :percent_bar?
  SUMMARY_FORMATS = [ :none, :sum, :avg, :max, :min, :count, :elapsed, :estimated, :percent, :speed, :current, :total, :active, :done, :value ]

  # @return [void]
  def column name, id: false, func: nil, format: nil, width: nil, align: nil, summary: nil
    raise ArgumentError, "Invalid name value: #{ name.inspect }", caller_locations unless name.is_a?(String) || name.is_a?(Symbol)
    raise ArgumentError, "Name can not be empty", caller_locations if name == '' || name == :''
    name = name.to_sym
    raise ArgumentError, "Column name already exists: #{ name }", caller_locations if @defs.any? { |d| d.is_a?(Hash) && d[:name] == name }
    raise ArgumentError, "Invalid id value: #{ id.inspect }", caller_locations unless id.nil? || id == true || id == false
    id = nil if id == false
    raise ArgumentError, "Id field already exists (#{ @id_field })" if @id_field && id
    raise ArgumentError, "Invalid func value: #{ func.inspect }", caller_locations unless func.nil? || func.respond_to?(:call)
    raise ArgumentError, "Invalid format value: #{ format.inspect }", caller_locations unless format.nil? || format.is_a?(String) || format.respond_to?(:call) || SPECIAL_FORMATS.include?(format)
    raise ArgumentError, "Invalid width value: #{ width.inspect }", caller_locations unless width.nil? || width.is_a?(Integer)
    raise ArgumentError, "Invalid align value: #{ align.inspect }", caller_locations unless align.nil? || IS::Term::StringHelpers::ALIGN_MODES.include?(align)
    raise ArgumentError, "Invalid summary value: #{ summary.inspect }", caller_locations unless summary.nil? || summary == false || summary.is_a?(Proc) || SUMMARY_FORMATS.include?(summary)
    summary = nil if summary == false || summary == :none
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
