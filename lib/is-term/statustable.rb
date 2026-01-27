# frozen_string_literal: true

require 'singleton'

require_relative 'info'

class IS::Term::StatusTable

  include Singleton

  attr_reader :term

  attr_reader :defs

  attr_reader :rows

  def started row_id = nil
  end

  def defined?
  end

  def empty?
  end

  def active? row_id = nil
  end

  def available?
  end

  def elapsed row_id = nil
  end

  def estimated row_id
  end

  def append **data
  end

  def update **data
  end

  def configure &block
  end

  private

  def column name, id: false, func: nil, format: nil, align: nil, summary: nil
  end

  def separator str = ' '
  end

  def inactivate_if &block
  end

  def terminal io
  end

  def summary show = true, **values
  end

end
