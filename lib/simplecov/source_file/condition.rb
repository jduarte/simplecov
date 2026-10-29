# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # One arm of a measured operator: `:evaluated` (the right operand ran) or
    # `:short_circuited` (the left side settled it), for the operator typed
    # `operator`. Answers what `SourceFile::Branch` does, so statistics and
    # skipping treat the two alike.
    class Condition
      attr_reader :start_line, :end_line, :coverage, :type, :operator, :report_line

      # `start_line` and `end_line` span the whole expression, which is what a
      # disabled region has to overlap. `report_line` is the operator's line,
      # where a reader looks for it.
      def initialize(start_line:, end_line:, coverage:, type:, operator:, report_line:)
        @start_line = start_line
        @end_line = end_line
        @coverage = coverage
        @type = type
        @operator = operator
        @report_line = report_line
        @skipped = false
      end

      def covered?
        !skipped? && coverage.positive?
      end

      def missed?
        !skipped? && coverage.zero?
      end

      def skipped!
        @skipped = true
      end

      def skipped?
        @skipped
      end

      def overlaps_with?(line_range)
        start_line <= line_range.end && end_line >= line_range.begin
      end

      def report
        [operator, type, coverage]
      end
    end
  end
end
