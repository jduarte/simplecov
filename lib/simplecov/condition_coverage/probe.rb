# frozen_string_literal: true

module SimpleCov
  module ConditionCoverage
    # The counter a rewritten condition calls into, holding its two slots in
    # its file's counter array (see `Hits`). The original code is the call's
    # only argument, the position Ruby accepts the most in (`not a` and
    # `foo bar` among it), and every method answers it untouched, so the
    # expression's value and where an exception surfaces are the original's.
    #
    # Increments aren't atomic across threads, so two threads racing on one
    # slot can lose a count, but never turn a hit into a miss: a lost
    # increment leaves at least the other thread's.
    class Probe
      def initialize(counters, condition)
        @counters = counters
        @evaluated = 2 * condition
        @other = @evaluated + 1
      end

      # A `&&` left operand's truthiness decides both arms: truthy means the
      # right operand runs next, falsy that it never will.
      def and_left(value)
        @counters[value ? @evaluated : @other] += 1
        value
      end

      # The `||` counterpart: a falsy left operand is what sends `||` on.
      def or_left(value)
        @counters[value ? @other : @evaluated] += 1
        value
      end

      # An assignment operator's value, counted once computed: one that
      # raises counts in neither slot, which keeps the subtraction in `Hits`
      # exact.
      def value(value)
        @counters[@evaluated] += 1
        value
      end

      # A whole `&&=` or `||=`, counted once it completes.
      def write(value)
        @counters[@other] += 1
        value
      end
    end
  end
end
