# frozen_string_literal: true

require_relative 'info'

module IS::Term::StringHelpers

  def str_width str
    # TODO: implement
  end

  def str_truncate str, width
    # TODO: implement
  end

  module_function :str_width, :str_truncate

  refine String do

    def width
      IS::Term::StringHelpers::str_width self
    end

    def truncate width
      IS::Term::StringHelpers::str_truncate self, width
    end

  end

end
