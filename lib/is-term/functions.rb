# frozen_string_literal: true

require_relative 'info'
require_relative 'statustable'

# Provides calculation functions for status table rows and aggregates.
#
# This module contains methods for retrieving and calculating timing metrics
# (start/finish times, elapsed time, estimated completion), progress percentages,
# and aggregate statistics (sum, average, min, max, count) for rows in a
# {IS::Term::StatusTable}.
#
# Methods support polymorphic signatures accepting either a Hash row,
# an identifier, or no argument (for table-wide aggregation).
#
# @example Calculating progress for a specific row
#   percent(some_row)  # => 45
#   elapsed(some_row)  # => 123.45
#
# @example Table-wide aggregation
#   percent    # => 32 (percent for entire table)
#   active     # => 3 (count of active rows)
#   sum(:size) # => 1024 (sum of :size field across all rows)
#
module IS::Term::StatusTable::Functions

  protected

  # @group Internal Setup

  # @api private
  # The status table context for function execution.
  #
  # Returns the singleton instance by default, but can be overridden to use
  # a different table context (e.g., for testing or custom implementations).
  # The setter validates that the value responds to both +row+ and +rows+ methods
  # (duck typing for table interface).
  #
  # @return [IS::Term::StatusTable]
  # @raise [ArgumentError] if assigned value does not respond to +row+ and +rows+
  # @!attribute [rw] _table

  def _table
    @status_table ||= IS::Term::StatusTable::instance
  end

  def _table= value
    raise ArgumentError, "Invalid value for '_table': #{ value.inspect }", caller_locations unless value.respond_to?(:row) && value.respond_to?(:rows)
    @status_table = value
  end

  # @endgroup

  public

  # @group Row or Table Functions

  # Return starting time of row or whole table.
  # @return [Time, nil]
  #
  # @overload started(row)
  #   When this row was started.
  #   @param [Hash] row the row hash containing +:_started+ key
  #
  # @overload started(id)
  #   Find row by id and return when it started. Returns +nil+ if row not found.
  #   @param [Object] id the row identifier
  #
  # @overload started
  #   When the whole table was started (minimum start time across all rows).
  #   Returns +nil+ if table is empty or no rows have started.
  def started row = nil
    if row.is_a?(Hash)
      row[:_started]
    else
      tbl = _table
      if row.nil?
        tbl.rows.map { |r| r[:_started] }.min
      else
        r = tbl.row row
        r.nil? ? nil : started(r)
      end
    end
  end

  # Return finishing time of row or whole table.
  # @return [Time, nil]
  #
  # @overload finished(row)
  #   When this row was finished.
  #   @param [Hash] row the row hash containing +:_finished+ key
  #
  # @overload finished(id)
  #   Find row by id and return when it finished. Returns +nil+ if row not found or not finished
  #   @param [Object] id the row identifier
  #
  # @overload finished
  #   When the whole table was finished (maximum finish time across all rows).
  #   Returns +nil+ if any row is still active (not finished) or table is empty.
  def finished row = nil
    if row.is_a?(Hash)
      row[:_finished]
    else
      tbl = _table
      if row.nil?
        values = tbl.rows.map { |r| r[:_finished] }
        if values.any? { |v| v.nil? }
          nil
        else
          values.max
        end
      else
        r = tbl.row row
        r.nil? ? nil : finished(r)
      end
    end
  end

  # Return a percent of execution — +(0 .. 100)+.
  #
  # @overload percent(row)
  #   Execution percent of row
  #   @param [Hash] row
  #
  # @overload percent(id)
  #   Execution percent of row with specified id
  #   @param [Object] id
  #
  # @overload percent
  #   Execution percent of whole table
  #
  # @return [Integer, nil]
  def percent row = nil
    current = self.current row
    total = self.total row
    if current.nil? || total.nil? || total == 0
      nil
    else
      (current * 100) / total
    end
  end

  # Return estimated remaining execution time is seconds.
  #
  # @overload estimated(row)
  #   Estimated remaining time of row execution
  #   @param [Hash] row
  #
  # @overload estimated(id)
  #   Estimated remaining time of row with specified id
  #   @param [Object] id
  #
  # @overload estimated
  #   Estimated remaining time of whole table
  #
  # @return [Float, nil] Value in seconds
  def estimated row = nil
    elapsed = self.elapsed row
    current = self.current row
    total = self.total row
    if elapsed.nil? || current.nil? || total.nil? || current == 0
      nil
    else
      (elapsed.to_f / current) * (total - current)
    end
  end

  # Return elapsed time in seconds.
  #
  # @overload elapsed(row)
  #   Elapsed time of row execution
  #   @param [Hash] row
  #
  # @overload elapsed(id)
  #   Elapsed time of row with specified id
  #   @param [Object] id
  #
  # @overload elapsed
  #   Elapsed time of whole table
  #
  # @return [Float, nil] Value in seconds
  def elapsed row = nil
    started = self.started row
    finished = self.finished row
    if started.nil?
      nil
    elsif finished.nil?
      Time::now - started
    else
      finished - started
    end
  end

  # Return average execution speed (steps in second).
  #
  # @overload speed(row)
  #   Speed of row execution
  #   @param [Hash] row
  #
  # @overload speed(id)
  #   Speed of row with specified id
  #   @param [Object] id
  # 
  # @overload speed
  #   Execution speed of whole table
  #
  # @return [Float, nil]
  def speed row = nil
    elapsed = self.elapsed row
    current = self.current row
    finished = self.finished row
    total = self.total row
    if elapsed.nil? || current.nil?
      nil
    else
      if finished && total
        total.to_f / elapsed
      else
        current.to_f / elapsed
      end
    end
  end

  # Return current steps value for row or whole table.
  #
  # @overload current(row)
  #   Current step in specified row
  #   @param [Hash] row
  #
  # @overload current(id)
  #   Current step in row with specified id
  #   @param [Object] id
  #
  # @overload current
  #   Sum of current of whole table
  #
  # @return [Integer, nil]
  def current row = nil
    if row.is_a?(Hash)
      row[:current]
    else
      tbl = _table
      if row.nil?
        tbl.rows.map { |r| r[:total] ? r[:current] : nil }.compact.sum
      else
        r = tbl.row row
        r.nil? ? nil : current(r)
      end
    end
  end

  # Return total steps value of row or table.
  #
  # @overload total(row)
  #   Total step count of row
  #   @param [Hash] row
  #
  # @overload total(id)
  #   Total step count of row with specified id
  #   @param [Object] id
  #
  # @overload total
  #   Total step count of whole table
  #
  # @return [Integer, nil]
  def total row = nil
    if row.is_a?(Hash)
      row[:total]
    else
      tbl = _table
      if row.nil?
        tbl.rows.map { |r| r[:total] }.compact.sum
      else
        r = tbl.row row
        r.nil? ? nil : total(r)
      end
    end
  end

  # Is a row or table active?
  #
  # @overload active?(row)
  #   Is this row active?
  #   @param [Hash] row
  #
  # @overload active?(id)
  #   Is row with specified id active?
  #   @param [Object] id
  #
  # @overload active?
  #   Is any row of table active?
  #
  # @return [Boolean, nil]
  def active? row = nil
    if row.is_a?(Hash)
      row[:_active]
    else
      tbl = _table
      if row.nil?
        tbl.rows.any? { |r| r[:_active] }
      else
        r = tbl.row row
        r.nil? ? nil : active?(r)
      end
    end
  end

  # Is a row or table done?
  #
  # @overload done?(row)
  #   Is this row done?
  #   @param [Hash] row
  #
  # @overload done?(id)
  #   Is row with specified id done?
  #   @param [Object] id
  #
  # @overload done?
  #   Is all rows if table done?
  #
  # @return [Boolean, nil]
  def done? row = nil
    active = self.active? row
    active.nil? ? nil : !active
  end

  # @endgroup

  # @group Table-only Functions

  # Count of active rows
  # @return [Integer]
  def active
    tbl = _table
    tbl.rows.select { |r| r[:_active] }.count
  end

  # Count of done rows
  # @return [Integer]
  def done
    tbl = _table
    tbl.rows.select { |r| !r[:_active] }.count
  end

  # Is table empty?
  # @return [Boolean]
  def empty?
    self.count == 0
  end

  # @endgroup

  # @group Aggregate Functions

  # Sum of field values
  # @return [Numeric]
  def sum name
    tbl = _table
    tbl.rows.map { |r| r[name] }.compact.sum
  end

  # Average value of field
  # @return [Numeric, nil]
  def avg name
    tbl = _table
    vls = tbl.rows.map { |r| r[name] }.compact
    sum = vls.sum
    cnt = vls.count
    if cnt == 0
      nil
    else
      sum / cnt
    end
  end

  # Minimum of field values
  # @return [Comparable, nil]
  def min name
    tbl = _table
    tbl.rows.map { |r| r[name] }.compact.min
  end

  # Maximum of field values
  # @return [Comparable, nil]
  def max name
    tbl = _table
    tbl.rows.map { |r| r[name] }.compact.max
  end

  # @endgroup

  # @group Aggregate or Table Function

  # Count of rows, See Details.
  #
  # @overload cnt(name)
  #   Count of unique not null values of field
  #   @param [Symbol] name
  #
  # @overload count
  #   Count of rows
  #
  # @return [Integer]
  def count name = nil
    rows = _table.rows
    if name.nil?
      rows.count
    else
      rows.map { |r| r[name] }.compact.uniq.count
    end
  end

  alias :cnt :count

  # @endgroup

  extend self

  # @api private
  ROW_METHODS = [ :started, :finished, :percent, :estimated, :elapsed, :speed, :current, :total, :active?, :done? ].freeze

  # @api private
  TABLE_METHODS = [ :started, :finished, :percent, :estimated, :elapsed, :speed, :current, :total, :active, :active?, :done, :done?, :count, :empty? ].freeze

  # @api private
  AGGREGATE_METHODS = [ :sum, :avg, :min, :max, :cnt, :count ].freeze

  class << self

    # @group Function Access

    # @return [Proc]
    def row_func method_name
      raise NameError, "Invalid function name: #{ method_name.inspect }", caller_locations unless ROW_METHODS.include?(method_name)
      self.method(method_name).to_proc
    end

    # @return [Proc]
    def table_func method_name
      raise NameError, "Invalid function name: #{ method_name.inspect }", caller_locations unless TABLE_METHODS.include?(method_name)
      meth = self.method method_name
      if ROW_METHODS.include?(method_name) || AGGREGATE_METHODS.include?(method_name) 
        lambda { meth.call(nil) }
      else
        meth.to_proc
      end
    end

    # @return [Proc]
    def aggregate_func method_name, field_name
      raise NameError, "Invalid function name: #{ method_name.inspect }", caller_locations unless AGGREGATE_METHODS.include?(method_name)
      meth = self.method method_name
      lambda { meth.call(field_name) }
    end

    alias :RF :row_func
    alias :TF :table_func
    alias :AF :aggregate_func

    # @endgroup

  end

end

class IS::Term::StatusTable
  include IS::Term::StatusTable::Functions

  protected

  # @private
  def _table
    self
  end

end
