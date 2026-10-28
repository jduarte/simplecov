# frozen_string_literal: true

require_relative "collector"
require_relative "column_map"

module SimpleCov
  module ConditionCoverage
    # Splices hit counters into a file's source around every condition
    # `Collector` finds, as calls to the condition's `Probe` taking the
    # original code as their only argument (`P` standing for
    # `::SimpleCov::ConditionCoverage::Hits::PROBES[file]`):
    #
    #   a && b       =>  P[0].and_left(a) && b
    #   x ||= v      =>  P[0].write(x ||= P[0].value(v))
    #   a && b && c  =>  P[1].and_left(a) && P[0].and_left(b) && c
    #
    # A `&&` or `||` left operand decides both arms (the right operand runs
    # exactly when it doesn't settle the answer), so the right operand stays
    # as it was. An assignment's target can't be wrapped, so its skips are
    # counted as completions its value didn't take part in. In a chain, the
    # outer condition's left side is the inner condition, whose value is its
    # right operand's whenever it didn't short-circuit, so the outer probe
    # wraps that operand, and the inner short-circuits are added to the
    # outer counts (`Condition#chain`).
    #
    # Nothing is spliced across a line, so line numbers stay put, and a call
    # is the one wrapper that also leaves Coverage's line counts alone:
    # Prism marks the statements inside parentheses as new lines, so `(a)` in
    # an endless method body, or starting a line of its own, would fire a
    # line event the original never did. Parentheses are only the fallback
    # for an operand that isn't valid as a sole argument (`x = foo 1`,
    # `a rescue b`), which only the keyword operators and the assignment
    # operators can have.
    #
    # Column positions on a rewritten line shift; `ColumnMap` translates the
    # columns Coverage reports back.
    module Rewriter
      extend self

      PROBES = "::SimpleCov::ConditionCoverage::Hits::PROBES"
      private_constant :PROBES

      nothing = [] #: Array[untyped]
      NOTHING = nothing.freeze
      private_constant :NOTHING

      # A splice: `text` goes in at byte `offset`. Splices sharing an offset
      # are ordered closers before openers, closers innermost first, and
      # openers outermost first, which is what keeps nested conditions
      # balanced.
      Splice = Data.define(:offset, :closer, :rank, :text)

      class Splice
        def sort_key
          [offset, closer ? 0 : 1, closer ? -rank : rank]
        end
      end

      # Answers `[rewritten_source, conditions, column_map]`. Source Prism
      # can't parse comes back as it was, with nothing to measure.
      # `file_index` is the counter array the rewritten code increments.
      def call(source, file_index)
        result = Prism.parse(source)
        return [source, NOTHING, ColumnMap.new(NOTHING)] if result.failure?

        collector = Collector.new
        result.value.accept(collector)
        sites = collector.sites
        by_node = sites.to_h { |site| [site.node, site] }.compare_by_identity
        planned = sites.map { |site| plan(site, by_node.fetch(site.left, nil)) }
        splices = planned.flat_map { |site, target| splices(site, target, file_index) }.sort_by(&:sort_key)
        [splice(source, splices), planned.map { |site, _target| site.condition }, column_map(result.source, splices)]
      end

      private

      # The site, its condition chained where its left side is another
      # measured `&&` or `||`, and the node its probe wraps.
      def plan(site, inner)
        left = site.left
        return [site, left] unless inner&.left

        condition = site.condition
        arm = inner.condition.tuple.first.equal?(condition.tuple.first) ? :short_circuited : :evaluated #: :short_circuited | :evaluated
        [site.with(condition: condition.with(chain: [inner.condition.tuple.fetch(1), arm])), inner.right]
      end

      def splices(site, target, file_index)
        probe = "#{PROBES}[#{file_index}][#{site.condition.tuple.fetch(1)}]"
        rank = site.depth * 2
        return write_splices(site, probe, rank) unless target

        method = site.condition.tuple.first.equal?(:"&&") ? "and_left" : "or_left"
        # `&&` and `||` take only operands valid as arguments; `and` and `or`
        # take statements, so theirs need checking.
        bare = site.node.operator_loc.slice.start_with?("&&", "||") || bare_argument?(target)
        wrap(target, rank, "#{probe}.#{method}(", bare)
      end

      # The value nests inside the wrapped assignment, hence its higher rank.
      def write_splices(site, probe, rank)
        node = site.node
        value = site.right
        wrap(node, rank, "#{probe}.write(", bare_argument?(node)) +
          wrap(value, rank + 1, "#{probe}.value(", bare_argument?(value))
      end

      def wrap(node, rank, call, bare)
        location = node.location
        opener, closer = bare ? [call, ")"] : ["#{call}(", "))"]
        [
          Splice.new(offset: location.start_offset, closer: false, rank:, text: opener),
          Splice.new(offset: location.end_offset, closer: true, rank:, text: closer)
        ]
      end

      # Whether `node`'s source reads back as one whole argument: `x => y`
      # would read back as a keyword argument, and a `do` block could attach
      # to the probe call instead. The probe can't know the file's local
      # variables, so a local can read back as a method call, which passes
      # the same way. A heredoc's body lives past the call's closing
      # parenthesis, so its opener alone never parses, and falls back to
      # parentheses too.
      def bare_argument?(node)
        source = node.slice
        result = Prism.parse("_(#{source}\n)")
        return false if result.failure?

        call = _ = result.value.statements.body.first
        arguments = call.arguments.arguments
        argument = arguments.first
        arguments.one? && !argument.is_a?(Prism::KeywordHashNode) && argument.location.length.eql?(source.bytesize)
      end

      def column_map(source, splices)
        ColumnMap.new(splices.map do |splice|
          offset = splice.offset
          [source.line(offset), source.column(offset), splice.text.bytesize]
        end)
      end

      # Prism's offsets are bytes, so the splicing happens on the bytes, and
      # the result takes the source's encoding back.
      def splice(source, splices)
        bytes = source.b
        rewritten = "".b
        cursor = 0
        splices.each do |splice|
          rewritten << (_ = bytes.byteslice(cursor, splice.offset - cursor)) << splice.text
          cursor = splice.offset
        end
        rewritten << (_ = bytes.byteslice(cursor..))
        rewritten.force_encoding(source.encoding)
      end
    end
  end
end
