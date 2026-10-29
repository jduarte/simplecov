# frozen_string_literal: true

module Checks
  def self.both(left, right)
    return :neither unless left || right

    left && right
  end

  def self.memo(cache) = cache[:value] ||= :computed
end
