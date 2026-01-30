# frozen_string_literal: true

module Boolean

  include Comparable

  # +false+ ⇒ +0+
  # +true+ ⇒ +1+
  # @return [Integer]
  def to_i
    if self
      1
    else
      0
    end
  end

  # +false < true+
  # @return [Integer]
  def <=> other
    if other.is_a?(Boolean)
      self.to_i <=> other.to_i
    else
      nil
    end
  end

end

class TrueClass
  include Boolean
end

class FalseClass
  include Boolean
end
