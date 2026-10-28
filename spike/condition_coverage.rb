# frozen_string_literal: true

# Phase 0 spike: condition coverage via Prism source rewriting at load time.
# Throwaway code. Not loaded by the gem.

require "prism"

module SpikeCC
  # H[file_index] is a flat Integer array, two slots per condition:
  #   and/or:  [2k] right evaluated,  [2k+1] short-circuited
  #   writes:  [2k] right evaluated,  [2k+1] node entered (skips = entered - evaluated)
  H = [] # standard:disable Style/MutableConstant
  FILES = [] # standard:disable Style/MutableConstant

  Condition = Struct.new(:kind, :node, :left, :right, :operator_loc, :write, :depth, keyword_init: true)

  WRITE_NODES = Prism.constants.grep(/(?:And|Or)WriteNode\z/).map { Prism.const_get(_1) }.freeze

  class Collector < Prism::Visitor
    attr_reader :conditions

    def initialize
      super
      @conditions = []
      @depth = 0
    end

    def visit_and_node(node) = record(:"&&", node, left: node.left, right: node.right) { super }
    def visit_or_node(node) = record(:"||", node, left: node.left, right: node.right) { super }

    WRITE_NODES.each do |klass|
      method_name = :"visit_#{klass.name.split("::").last.gsub(/(?<!^)([A-Z])/, '_\1').downcase}"
      kind = klass.name.include?("AndWrite") ? :"&&=" : :"||="
      define_method(method_name) do |node|
        record(kind, node, left: nil, right: node.value, write: true) { super(node) }
      end
    end

    private

    def record(kind, node, left:, right:, write: false)
      @conditions << Condition.new(kind:, node:, left:, right:, operator_loc: node.operator_loc, write:, depth: @depth)
      @depth += 1
      yield
    ensure
      @depth -= 1
    end
  end

  Edit = Struct.new(:offset, :closer, :order, :text)

  module_function

  def collect(source)
    result = Prism.parse(source)
    return nil if result.failure?

    collector = Collector.new
    result.value.accept(collector)
    collector.conditions
  end

  # Returns [rewritten_source, conditions] or nil.
  def rewrite(source, file_index)
    conditions = collect(source)
    return nil unless conditions
    return [source, conditions] if conditions.empty?

    h = "::SpikeCC::H[#{file_index}]"
    edits = []
    conditions.each_with_index do |c, k|
      d = c.depth * 2
      if c.write
        edits << Edit.new(c.node.location.start_offset, false, d, "(#{h}[#{2 * k + 1}] += 1; ")
        edits << Edit.new(c.node.location.end_offset, true, d, ")")
      else
        meth = (c.kind == :"&&") ? "a" : "o"
        edits << Edit.new(c.left.location.start_offset, false, d, "::SpikeCC.#{meth}(#{file_index}, #{2 * k + 1}, (")
        edits << Edit.new(c.left.location.end_offset, true, d, "))")
      end
      # The right operand nests inside the node's own wrapper.
      edits << Edit.new(c.right.location.start_offset, false, d + 1, "(#{h}[#{2 * k}] += 1; ")
      edits << Edit.new(c.right.location.end_offset, true, d + 1, ")")
    end

    # At one offset: closers before openers; closers innermost-first, openers outermost-first.
    edits.sort_by! { |e| [e.offset, e.closer ? 0 : 1, e.closer ? -e.order : e.order] }

    bytes = source.b
    out = +"".b
    cursor = 0
    edits.each do |e|
      out << bytes.byteslice(cursor, e.offset - cursor) << e.text
      cursor = e.offset
    end
    out << bytes.byteslice(cursor, bytes.bytesize - cursor)
    [out.force_encoding(source.encoding), conditions]
  end

  def a(file_index, slot, value)
    H[file_index][slot] += 1 unless value
    value
  end

  def o(file_index, slot, value)
    H[file_index][slot] += 1 if value
    value
  end

  def register(path, conditions)
    FILES << [path, conditions]
    H << Array.new(conditions.size * 2, 0)
    FILES.size - 1
  end

  # Returns compiled iseq or nil.
  def instrument(path)
    source = File.binread(path).force_encoding(Encoding::UTF_8)
    index = FILES.size
    rewritten, conditions = rewrite(source, index)
    return nil unless rewritten

    register(path, conditions)
    RubyVM::InstructionSequence.compile(rewritten, path, path)
  rescue SyntaxError, StandardError => e
    warn "[spike-cc] fallback for #{path}: #{e.class}: #{e.message.lines.first}" if ENV["SPIKE_CC_DEBUG"]
    FILES.pop && H.pop if FILES.size > index
    nil
  end

  def tuple(kind, id, loc) = [kind, id, loc.start_line, loc.start_column, loc.end_line, loc.end_column]

  # Shape mirrors Ruby's branch coverage.
  def result
    FILES.each_with_index.to_h do |(path, conditions), f|
      hits = H[f]
      table = conditions.each_with_index.to_h do |c, k|
        evaluated = hits[2 * k]
        skipped = c.write ? hits[2 * k + 1] - evaluated : hits[2 * k + 1]
        [tuple(c.kind, k, c.node.location),
          {tuple(:evaluated, 2 * k, c.right.location) => evaluated,
           tuple(:short_circuited, 2 * k + 1, c.operator_loc) => skipped}]
      end
      [path, table]
    end
  end

  # --- load hook -----------------------------------------------------------

  class << self
    attr_accessor :scope
  end

  def in_scope?(path) = scope && path.start_with?(scope)

  module LoadHook
    def load_iseq(path)
      if SpikeCC.in_scope?(path) && (iseq = SpikeCC.instrument(path))
        return iseq
      end
      defined?(super) ? super : nil
    end
  end

  BOOTSNAP_MIXIN = "Bootsnap::CompileCache::ISeq::InstructionSequenceMixin"

  # bootsnap's mixin returns nil without calling super whenever Coverage is
  # running, so anything below it in the chain is never reached. Make sure we
  # sit above it whichever loads first.
  def install!(scope)
    self.scope = scope
    RubyVM::InstructionSequence.singleton_class.prepend(LoadHook)
    if (mixin = bootsnap_mixin)
      mixin.prepend(LoadHook)
    else
      @class_watch = TracePoint.new(:class) do |tp|
        next unless tp.self.is_a?(Module) && tp.self.name == BOOTSNAP_MIXIN

        tp.self.prepend(LoadHook)
        @class_watch.disable
      end
      @class_watch.enable
    end
  end

  def bootsnap_mixin
    Object.const_get(BOOTSNAP_MIXIN) if defined?(::Bootsnap::CompileCache::ISeq::InstructionSequenceMixin)
  end
end
