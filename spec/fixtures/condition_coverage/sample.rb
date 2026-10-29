# frozen_string_literal: true

module ConditionCoverageSample
  def self.both(left, right) = left && right

  def self.memo(cache) = cache[:value] ||= :computed
end
