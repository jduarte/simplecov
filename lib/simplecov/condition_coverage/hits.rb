# frozen_string_literal: true

require_relative "probe"

module SimpleCov
  module ConditionCoverage
    # The counters rewritten code increments, and what each file's counters
    # mean. Each condition owns two adjacent slots in its file's counter
    # array: `2k` counts evaluations of its right operand, and `2k + 1` counts
    # short-circuits (`&&`, `||`) or completed assignments (`&&=`, `||=`, whose
    # skips are the completions their value didn't take part in). Rewritten
    # code increments them through each condition's `Probe`, reached by the
    # constant path `::SimpleCov::ConditionCoverage::Hits::PROBES`, which
    # Ruby caches inline.
    module Hits
      extend self

      # One counter array, and one probe per condition, for each instrumented
      # file, indexed by registration order.
      COUNTERS = [] # rubocop:disable Style/MutableConstant
      PROBES = [] # rubocop:disable Style/MutableConstant

      # Claims the index a file's rewritten source will embed. The rewrite
      # needs the index before it knows the conditions, and two threads can be
      # loading files at once, so the claim and its placeholders go in
      # together. `files` needs no placeholder: `commit` assigns by index,
      # which pads it with the nils of reservations still uncommitted.
      # The lock only matters to threads racing one another, which no example
      # can make lose deterministically, so dropping it reads as equivalent.
      # mutant:disable
      def reserve
        MUTEX.synchronize do
          COUNTERS << EMPTY
          PROBES << EMPTY
          COUNTERS.size - 1
        end
      end

      # Called once the file has compiled, before any of its code runs.
      # `column_map` translates the columns Coverage will report for it.
      def commit(file_index, path, conditions, column_map)
        counters = Array.new(conditions.size * 2, 0)
        COUNTERS[file_index] = counters
        PROBES[file_index] = conditions.each_index.map { |index| Probe.new(counters, index) }
        files[file_index] = [path, conditions, column_map]
      end

      # `{path => {condition_tuple => {arm_tuple => hits}}}`, the shape Ruby's
      # Coverage gives branches. A reservation that never committed (its
      # rewrite failed, and the file loaded unrewritten) reports nothing. A
      # file loaded twice reports its latest load, the way Coverage restarts a
      # reloaded file's counts.
      def result
        tables = {} #: Hash[String, table]
        files.each_with_index do |entry, file_index|
          next unless entry

          path, conditions, = entry
          tables[path] = table(conditions, COUNTERS.fetch(file_index))
        end
        tables
      end

      # `{path => ColumnMap}` for every committed file, the latest load's.
      def column_maps
        files.compact.to_h { |path, _conditions, column_map| [path, column_map] }
      end

      MUTEX = Mutex.new
      private_constant :MUTEX

      empty = [] #: Array[untyped]
      EMPTY = empty.freeze
      private_constant :EMPTY

      private

      def files
        @files ||= [] #: Array[[String, Array[Condition], ColumnMap]?]
      end

      def table(conditions, counters)
        arms = arm_counts(conditions, counters)
        conditions.each_with_index.to_h do |condition, index|
          evaluated, skipped = arms.fetch(index)
          [condition.tuple, {condition.evaluated_tuple => evaluated, condition.short_circuited_tuple => skipped}]
        end
      end

      # `[evaluated, skipped]` per condition. A chained condition's inner one
      # has the higher index (it's found inside it), so walking backwards
      # settles every inner condition before the one that reads it.
      def arm_counts(conditions, counters)
        arms = {} #: Hash[Integer, [Integer, Integer]]
        conditions.each_index.reverse_each do |index|
          condition = conditions.fetch(index)
          evaluated = counters.fetch(2 * index)
          second = counters.fetch((2 * index) + 1)
          skipped = condition.write? ? second - evaluated : second
          arms[index] = chained(condition.chain, evaluated, skipped, arms)
        end
        arms
      end

      def chained(chain, evaluated, skipped, arms)
        return [evaluated, skipped] unless chain

        inner, arm = chain
        inner_skips = arms.fetch(inner).last
        arm.equal?(:evaluated) ? [evaluated + inner_skips, skipped] : [evaluated, skipped + inner_skips]
      end
    end
  end
end
