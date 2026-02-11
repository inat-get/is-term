# frozen_string_literal: true

require 'is-duration'

require_relative 'info'
require_relative 'string_helpers'
require_relative 'statustable'

module IS::Term::StatusTable::Formats

  class << self

    using IS::Term::StringHelpers

    # @group Formatters

    # @return [String]
    def duration value
      IS::Duration::format value, units: (:s..:w), empty: :minor, zeros: :fill
    end

    # @return [String]
    def skip value
      ''
    end

    # @return [String]
    def percent_bar value, width, complete: '=', incomplete: ' ', head: '>', done: '≡', widths: [ nil, nil, nil, nil ]
      return '' if value.nil?
      cw = widths[0] || complete&.width   || 0
      iw = widths[1] || incomplete&.width || 0
      hw = widths[2] || head&.width       || 0
      dw = widths[3] || done&.width       || 0
      if value >= 100
        done * (width / dw)
      elsif value == 0
        incomplete * (width / iw)
      else
        point = 100 / width
        i = (100 - value) / (point * iw)
        #h = 1
        c = (width - i * iw - hw) / cw
        if c < 0
          i += c
          c = 0
        end
        complete * c + head + incomplete * i
      end
    end

    # @endgroup

  end

  SPECIAL_FORMATS = [ :duration, :skip ]

  class << self

    using IS::Term::StringHelpers

    # @group Formatter Access

    # @return [Proc]
    def fmt desc
      case desc
      when String
        lambda do |value|
          return '' if value.nil?
          desc % value
        end
      when Symbol
        raise NameError, "Invalid format name: #{ desc.inspect }", caller_locations unless SPECIAL_FORMATS.include?(desc)
        self.method(desc).to_proc
      else
        raise ArgumentError, "Invalid format: #{ desc.inspect }", caller_locations
      end
    end

    # @return [Proc]
    def bar width, complete: '=', incomplete: ' ', head: '>', done: '≡'
      opts = {
        complete: complete,
        incomplete: incomplete,
        head: head,
        done: done,
        widths: [ complete&.width, incomplete&.width, head&.width, done&.width ]
      }
      lambda { |value| self.percent_bar(value, width, **opts) }
    end

    # @endgroup

  end

end
