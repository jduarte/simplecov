# frozen_string_literal: true

module SimpleCov
  module ConditionCoverage
    # Translates the columns Coverage reports for a rewritten file back to
    # the original source's, so its branch and method tuples are the ones an
    # unrewritten run would have recorded and merge with them.
    #
    # Every splice sits on one line. A rewritten column that lies past the
    # end of a splice is that splice's length too far right; one at or
    # before its start isn't moved by it. A node Coverage names starting at a
    # wrapper's opening call starts, in the original, where the wrapped code
    # does, and one ending at a wrapper's closing parenthesis ends where the
    # wrapped code did, which is the same arithmetic.
    class ColumnMap
      # `splices` as `[line, original_column, length]`, in source order.
      def initialize(splices)
        @ends_by_line = {} #: Hash[Integer, Array[[Integer, Integer]]]
        shift_by_line = Hash.new(0) #: Hash[Integer, Integer]
        splices.each do |line, column, length|
          shift = shift_by_line[line]
          (@ends_by_line[line] ||= []) << [column + shift + length, length]
          shift_by_line[line] = shift + length
        end
      end

      def original_column(line, column)
        @ends_by_line.fetch(line, NONE).sum { |rewritten_end, length| (rewritten_end <= column) ? length : 0 }
          .then { |shift| column - shift }
      end

      # A branch or method tuple, `[type_or_class, id_or_name, start_line,
      # start_column, end_line, end_column]`.
      def translate(tuple)
        head, second, start_line, start_column, end_line, end_column = tuple
        [head, second, start_line, original_column(start_line, start_column),
          end_line, original_column(end_line, end_column)]
      end

      # Coverage's branches for the file, every condition and arm translated.
      def translate_branches(branches)
        branches.to_h do |condition, arms|
          [translate(condition), arms.transform_keys { |arm| translate(arm) }]
        end
      end

      def translate_methods(methods)
        methods.transform_keys { |method| translate(method) }
      end

      none = [] #: Array[[Integer, Integer]]
      NONE = none.freeze
      private_constant :NONE
    end
  end
end
