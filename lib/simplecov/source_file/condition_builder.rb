# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Builds the `SourceFile::Condition` objects for a source file from the
    # condition data `ConditionCoverage` recorded, marking the arms inside
    # disabled chunks as skipped.
    class ConditionBuilder
      def initialize(source_file)
        @source_file = source_file
      end

      def call
        condition_data = @source_file.coverage_data["conditions"] || {}
        conditions = condition_data.flat_map do |condition, arms|
          build_conditions_from(RubyDataParser.call(condition), arms)
        end

        process_skipped(conditions)
      end

      private

      # The condition hands in `[:"&&", 0, 3, 4, 3, 21]`, its arms
      # `[:evaluated, 0, ...]` and `[:short_circuited, 1, ...]`, each
      # [type, id, start_line, start_col, end_line, end_col]. The
      # short-circuit arm spans the operator, so its line is the one to report
      # both arms on.
      def build_conditions_from(condition, arms)
        operator, _id, start_line, _start_col, end_line, = condition
        parsed = arms.map { |arm, hits| [RubyDataParser.call(arm), hits] } #: Array[[Array[untyped], Integer]]
        report_line = operator_line(parsed)

        parsed.map do |arm, hits|
          Condition.new(
            start_line: start_line, end_line: end_line, coverage: hits,
            type: arm.first, operator: operator, report_line: report_line
          )
        end
      end

      def operator_line(parsed)
        # Every condition records both arms, so the search always finds one.
        short_circuit, _hits = _ = parsed.find { |arm, _hits| arm.first.equal?(:short_circuited) }
        short_circuit.fetch(2)
      end

      # The operator sits inside the expression, so a disabled region over any
      # of the expression, the operator's line included, skips the arm.
      def process_skipped(conditions)
        chunks = @source_file.skip_chunks_for(:condition)

        conditions.each do |condition|
          condition.skipped! if chunks.any? { |chunk| condition.overlaps_with?(chunk) }
        end
      end
    end
  end
end
