# frozen_string_literal: true

require_relative 'info'

module IS::Term::Formats

  def time value
    return '' if value == 0
    value = value.to_i
    result = ''
    m, s = value.divmod 60
    if m == 0
      result = ('%ds' % s)
    else
      result = ('%02ds' % s)
      h, m = m.divmod 60
      if h == 0
        result = ('%dm' % m) + result
      else
        result = ('%02dm' % m) + result
        d, h = h.divmod 24
        if d == 0
          result = ('%dh' % h) + result
        else
          result = ('%dd' % d) + ('%02dh' % h) + ':' + result
        end
      end
    end
    result
  end

  module_function :time

end
