# frozen_string_literal: true

require_relative 'info'

  # Terminal string rendering utilities with proper width calculation for Unicode
  # characters, emoji, East Asian characters, and ANSI escape sequences.
  #
  # This module provides essential string manipulation methods for terminal UIs,
  # handling complex Unicode display widths correctly while ignoring ANSI color/style
  # codes. It extends +String+ via Refinements to provide
  # a clean, chainable API.
  #
  # == Features
  #
  # * Correct width calculation (emoji=2, CJK=2, ASCII=1, ANSI=0)
  # * Safe truncation preserving ANSI codes
  # * Flexible alignment (left, right, center)
  # * Ellipsis with configurable marker
  #
  # == Usage
  #
  #   require 'is-term/string_helpers'
  #
  # Standalone (no refinements, no includes):
  #   IS::Term::StringHelpers.str_width("中👨‍⚕️")
  #   # => 4
  #
  # Include private methods:
  #   include IS::Term::StringHelpers
  #   str_width("中👨‍⚕️")
  #   # => 4
  #
  # With refinements (recommended):
  #   using IS::Term::StringHelpers
  #   "中👨‍⚕️".width       # => 4
  #   "中👨‍⚕️".ellipsis(3) # => "中…"
  #
module IS::Term::StringHelpers

  # @private
  ESC_CODES = /\e\[[0-9;]*[a-zA-Z]/
  # @private
  EMOJI     = /\p{Emoji_Presentation}/
  # @private
  EAST_ASIA = /\p{Han}|\p{Hiragana}|\p{Katakana}|\p{Hangul}/

  private_constant :ESC_CODES, :EMOJI, :EAST_ASIA

  ALIGN_LEFT   = :left
  ALIGN_RIGHT  = :right
  ALIGN_CENTER = :center
  ALIGN_MODES  = [ ALIGN_LEFT, ALIGN_RIGHT, ALIGN_CENTER ]

  DEFAULT_ELLIPSIS_MARKER = '…'
  DEFAULT_ALIGN_MODE = ALIGN_LEFT

  # Calculates the display width of a string in terminal context.
  #
  # Handles Unicode display rules:
  # * ANSI escape sequences: width 0
  # * Emoji: width 2
  # * East Asian characters (Han, Hiragana, Katakana, Hangul): width 2
  # * Other characters: width 1
  #
  # @param str [String] Input string
  # @return [Integer] Display width in columns
  # @example
  #   IS::Term::StringHelpers.str_width("中👨‍⚕️A")         # => 5
  #   IS::Term::StringHelpers.str_width("\e[31mHi\e[0m") # => 2
  def str_width str
    current = 0
    str.scan(/#{ ESC_CODES }|\X/) do |match|
      w = case match
      when ESC_CODES
        0
      when EMOJI, EAST_ASIA
        2
      else
        1
      end
      current += w
    end
    current
  end

  # Truncates string to specified display width, preserving ANSI escape sequences.
  #
  # ANSI codes are fully skipped (width 0), truncation occurs only on visible
  # characters. Returns original string if already within width or empty string
  # for non-positive widths.
  #
  # @param str [String] Input string
  # @param width [Integer] Maximum display width
  # @return [String] Truncated string (may be empty)
  # @raise +ArgumentError+ if width is invalid
  # @example
  #   IS::Term::StringHelpers.str_truncate("中ABC", 2)            # => "中"
  #   IS::Term::StringHelpers.str_truncate("\e[31mHello\e[0m", 3) # => "\e[31mHel"
  def str_truncate str, width
    return str if str.length <= width
    return '' if width <= 0
    current = 0
    position = 0
    str.scan(/#{ ESC_CODES }|\X/) do |match|
      w = case match
      when ESC_CODES
        0
      when EMOJI, EAST_ASIA
        2
      else
        1
      end
      current += w
      return str[0, position] if current > width
      position += match.length
    end
    str
  end

  # Truncates string to fit within width, appending ellipsis marker if truncated.
  #
  # Raises +ArgumentError+ if marker display width exceeds target width.
  # Preserves ANSI codes and handles Unicode widths correctly.
  #
  # @param str [String] Input string
  # @param width [Integer] Target display width
  # @param marker [String] Ellipsis marker (default: +…+)
  # @return [String] Truncated string with marker or original string
  # @raise +ArgumentError+ if {str_width} of +marker+ > +width+
  # @example
  #   IS::Term::StringHelpers.str_ellipsis("中ABC", 3)  # => "中…"
  #   IS::Term::StringHelpers.str_ellipsis("short", 10) # => "short"
  def str_ellipsis str, width, marker = DEFAULT_ELLIPSIS_MARKER
    marker_width = str_width marker
    raise ArgumentError, "Marker too long: #{ marker.inspect }", caller_locations if marker_width > width
    if str_width(str) > width
      str_truncate(str, width - marker_width) + marker
    else
      str
    end
  end

  # Aligns string within specified display width using spaces.
  #
  # Returns original string if source width is greater than or equal to target.
  # Supports left, right, and center alignment.
  #
  # @param str [String] Input string
  # @param width [Integer] Target display width
  # @param mode [:left, :right, :center] Alignment mode
  # @return [String] Aligned string padded with spaces
  # @raise +ArgumentError+ if invalid alignment +mode+
  # @example
  #   IS::Term::StringHelpers.str_align("hi", 6)          # => "hi    "
  #   IS::Term::StringHelpers.str_align("hi", 6, :right)  # => "    hi"
  #   IS::Term::StringHelpers.str_align("hi", 6, :center) # => "  hi  "
  def str_align str, width, mode = DEFAULT_ALIGN_MODE
    src_width = str_width str
    return str if src_width >= width
    case mode
    when ALIGN_LEFT
      str + ' ' * (width - src_width)
    when ALIGN_RIGHT
      ' ' * (width - src_width) + str
    when ALIGN_CENTER
      left = (width - src_width) / 2
      right = width - src_width - left
      ' ' * left + str + ' ' * right
    else
      raise ArgumentError, "Invalid align value: #{ mode.inspect }", caller_locations
    end
  end

  module_function :str_width, :str_truncate, :str_ellipsis, :str_align

  refine String do

    def width
      IS::Term::StringHelpers::str_width self
    end

    def truncate width
      IS::Term::StringHelpers::str_truncate self, width
    end

    def ellipsis width, marker = DEFAULT_ELLIPSIS_MARKER
      IS::Term::StringHelpers::str_ellipsis self, width, marker
    end

    def align width, mode = DEFAULT_ALIGN_MODE
      IS::Term::StringHelpers::str_align self, width, mode
    end

  end

end
