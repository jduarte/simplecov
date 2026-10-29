# frozen_string_literal: true

require "prism"
require_relative "condition"

module SimpleCov
  module ConditionCoverage
    # Finds every operator condition coverage measures, in source order, with
    # the byte offsets `Rewriter` splices counters at. The one place that
    # decides what a condition is, so the rewritten code and the reported
    # tuples can't disagree about it.
    class Collector < Prism::Visitor
      # Where a condition's counters go. `left` is nil for the assignment
      # operators, whose left side is a target that can't be wrapped; their
      # counter wraps the whole `node` instead. `depth` is how many measured
      # conditions enclose this one, which orders splices landing on the same
      # offset.
      Site = Data.define(:condition, :node, :left, :right, :depth)

      KIND_BY_OPERATOR = {and: :"&&", or: :"||", and_write: :"&&=", or_write: :"||="}.freeze
      private_constant :KIND_BY_OPERATOR

      # These only mean what they mean directly in a condition: a bare regexp
      # matches `$_`, a range flips a flip-flop. Wrapping one as an argument or
      # behind a counter would quietly turn it into a plain truthy value.
      CONDITION_ONLY_NODES = [
        Prism::MatchLastLineNode,
        Prism::InterpolatedMatchLastLineNode,
        Prism::FlipFlopNode
      ].freeze
      private_constant :CONDITION_ONLY_NODES

      attr_reader :sites

      # Prism's Visitor is a stateless dispatch table whose initializer is
      # Object's, so no mutation of the `super` call can be told apart.
      # mutant:disable
      def initialize
        super
        @sites = [] #: Array[Site]
        @depth = 0
      end

      def visit_and_node(node)
        measure_operator(:and, node) { super }
      end

      def visit_or_node(node)
        measure_operator(:or, node) { super }
      end

      # `defined?` never evaluates its operand, and wrapping one would change
      # what it answers (`"assignment"` becomes `"expression"`), so nothing
      # inside it is measured.
      def visit_defined_node(node)
      end

      # Prism names each assignment operator's node after its target: eight
      # targets, two operators.
      def visit_call_and_write_node(node) = measure_write(:and_write, node) { super }
      def visit_call_or_write_node(node) = measure_write(:or_write, node) { super }
      def visit_class_variable_and_write_node(node) = measure_write(:and_write, node) { super }
      def visit_class_variable_or_write_node(node) = measure_write(:or_write, node) { super }
      def visit_constant_and_write_node(node) = measure_write(:and_write, node) { super }
      def visit_constant_or_write_node(node) = measure_write(:or_write, node) { super }
      def visit_constant_path_and_write_node(node) = measure_write(:and_write, node) { super }
      def visit_constant_path_or_write_node(node) = measure_write(:or_write, node) { super }
      def visit_global_variable_and_write_node(node) = measure_write(:and_write, node) { super }
      def visit_global_variable_or_write_node(node) = measure_write(:or_write, node) { super }
      def visit_index_and_write_node(node) = measure_write(:and_write, node) { super }
      def visit_index_or_write_node(node) = measure_write(:or_write, node) { super }
      def visit_instance_variable_and_write_node(node) = measure_write(:and_write, node) { super }
      def visit_instance_variable_or_write_node(node) = measure_write(:or_write, node) { super }
      def visit_local_variable_and_write_node(node) = measure_write(:and_write, node) { super }
      def visit_local_variable_or_write_node(node) = measure_write(:or_write, node) { super }

      private

      def measure_operator(operator, node, &)
        return yield if condition_only?(node.left) || condition_only?(node.right)

        record(operator, node, left: node.left, right: node.right, &)
      end

      def measure_write(operator, node, &)
        record(operator, node, left: nil, right: node.value, &)
      end

      # A failure anywhere abandons the whole collection, so the depth needs
      # no unwinding on the way out.
      def record(operator, node, left:, right:)
        condition = condition(operator, node, right, @sites.size, write: left.nil?)
        @sites << Site.new(condition:, node:, left:, right:, depth: @depth)
        @depth += 1
        yield
        @depth -= 1
      end

      def condition(operator, node, right, index, write:)
        Condition.new(
          tuple: tuple(KIND_BY_OPERATOR.fetch(operator), index, node.location),
          evaluated_tuple: tuple(:evaluated, 2 * index, right.location),
          short_circuited_tuple: tuple(:short_circuited, (2 * index) + 1, node.operator_loc),
          write:
        )
      end

      def tuple(type, id, location)
        [type, id, location.start_line, location.start_column, location.end_line, location.end_column]
      end

      # Parentheses around a single statement keep its meaning in a
      # condition, so they don't hide one of the special nodes.
      def condition_only?(node)
        # @type var current: untyped
        current = node
        while current.is_a?(Prism::ParenthesesNode)
          body = current.body
          break unless body.is_a?(Prism::StatementsNode) && body.body.one?

          current = body.body.first
        end
        CONDITION_ONLY_NODES.any? { |klass| current.is_a?(klass) }
      end
    end
  end
end
