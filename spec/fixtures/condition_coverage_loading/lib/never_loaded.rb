# frozen_string_literal: true

module NeverLoaded
  def self.fallback(value) = value || :default
end
