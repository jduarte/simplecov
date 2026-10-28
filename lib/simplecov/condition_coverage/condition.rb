# frozen_string_literal: true

module SimpleCov
  module ConditionCoverage
    # One measured operator, as the coverage data names it. Tuples follow the
    # shape Ruby's Coverage gives branches, `[type, id, start_line,
    # start_column, end_line, end_column]`, so they persist and merge the same
    # way:
    #
    # - `tuple` spans the whole expression, typed `:"&&"`, `:"||"`, `:"&&="`
    #   or `:"||="` (`and` and `or` fold into `&&` and `||`).
    # - `evaluated_tuple` spans the right operand: the arm taken when the
    #   operator had to look at it.
    # - `short_circuited_tuple` spans the operator: the arm taken when the
    #   left side settled the answer on its own.
    #
    # `write` marks `&&=` and `||=`, which count their skips by subtraction.
    # `chain` is set where the left side is itself a measured `&&` or `||`
    # (`a && b && c`): `[inner_index, arm]`, the inner condition's
    # short-circuits deciding this one too, on `arm` (see `Rewriter`).
    Condition = Data.define(:tuple, :evaluated_tuple, :short_circuited_tuple, :write, :chain)

    class Condition
      def initialize(tuple:, evaluated_tuple:, short_circuited_tuple:, write:, chain: nil)
        super
      end

      def write?
        write
      end
    end
  end
end
