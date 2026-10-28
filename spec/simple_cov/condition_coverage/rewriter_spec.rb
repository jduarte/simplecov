# frozen_string_literal: true

require "helper"

# Asking loads the rewriter on any CRuby where Prism loads, whether or not
# that Ruby can measure with it.
SimpleCov::ConditionCoverage.supported?
return unless defined?(SimpleCov::ConditionCoverage::Rewriter)

RSpec.describe SimpleCov::ConditionCoverage::Rewriter, mutant_expression: "SimpleCov::ConditionCoverage::Rewriter*" do
  let(:hits) { SimpleCov::ConditionCoverage::Hits }

  around do |example|
    counters = hits::COUNTERS.dup
    probes = hits::PROBES.dup
    files = hits.send(:files).dup
    example.run
  ensure
    hits::COUNTERS.replace(counters)
    hits::PROBES.replace(probes)
    hits.instance_variable_set(:@files, files)
  end

  def rewrite(source, file_index = 7)
    described_class.call(source, file_index).first.gsub("::SimpleCov::ConditionCoverage::Hits::PROBES[7]", "P")
  end

  # Rewrites `source`, registers its counters, and evaluates it as the body
  # of a fresh module, answering the module and the file's index.
  def instrument(source)
    index = hits.reserve
    rewritten, conditions, column_map = described_class.call(source, index)
    hits.commit(index, "rewriter_spec_#{index}.rb", conditions, column_map)
    [quietly { Module.new.tap { |mod| mod.module_eval(rewritten) } }, index]
  end

  def original(source) = quietly { Module.new.tap { |mod| mod.module_eval(source) } }

  # A bare regexp in a condition warns, and the shapes include one on
  # purpose.
  def quietly
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end

  # `[evaluated, short_circuited]` per condition, in source order.
  def arms(index) = hits.result.fetch("rewriter_spec_#{index}.rb").values.map(&:values)

  def call_raising
    yield
  rescue RuntimeError
    nil
  end

  def inputs = [true, false].repeated_permutation(3).to_a

  # What each condition's arms come to over every input, from the operator
  # and the value its left side had in each run (nil where it never ran).
  def expected_arms(lefts)
    inputs.map { |args| lefts.call(*args) }.transpose.map do |runs|
      runs.compact.each_with_object([0, 0]) do |(operator, left), tally|
        evaluated = operator.equal?(:"&&") ? left : !left
        tally[evaluated ? 0 : 1] += 1
      end
    end
  end

  # How many line events each line fires, across every nested sequence.
  def line_events(iseq, tally = Hash.new(0))
    iseq.trace_points.each { |line, event| tally[line] += 1 if event.equal?(:line) }
    iseq.each_child { |child| line_events(child, tally) }
    tally
  end

  describe "what it splices in" do
    it "hands a && left operand to its probe as the only argument, and leaves the right one alone" do
      expect(rewrite("a && b\n")).to eq("P[0].and_left(a) && b\n")
    end

    it "counts a || through the probe's or_left" do
      expect(rewrite("a || b\n")).to eq("P[0].or_left(a) || b\n")
    end

    it "wraps an assignment whole, and its value, since its target can't be wrapped" do
      expect(rewrite("@x ||= v\n")).to eq("P[0].write(@x ||= P[0].value(v))\n")
    end

    it "flattens a chain, each probe wrapping the operand that decides its condition" do
      expect(rewrite("a && b && c\n")).to eq("P[1].and_left(a) && P[0].and_left(b) && c\n")
    end

    it "chains a condition to the one on its left" do
      expect(described_class.call("a && b || c\n", 0)[1].map(&:chain)).to eq([[1, :evaluated], nil])
    end

    it "chains on the short-circuit arm where the operators are the same" do
      expect(described_class.call("a || b || c\n", 0)[1].map(&:chain)).to eq([[1, :short_circuited], nil])
    end

    it "wraps a parenthesized inner condition whole, which isn't a chain" do
      expect(rewrite("(a || b) && c\n")).to eq("P[0].and_left((P[1].or_left(a) || b)) && c\n")
    end

    it "opens the outer probe first where two start at one offset" do
      expect(rewrite("a || b && c and d\n")).to eq("P[1].or_left(a) || P[0].and_left(P[2].and_left(b) && c) and d\n")
    end

    it "takes a keyword operand bare wherever a sole argument may be the same" do
      expect(rewrite("not a or puts 1 and b\n")).to eq("P[1].or_left(not a) or P[0].and_left(puts 1) and b\n")
    end

    it "parenthesizes a keyword operand that isn't a valid argument" do
      expect(rewrite("x in Integer and z\n")).to eq("P[0].and_left((x in Integer)) and z\n")
    end

    it "parenthesizes an assignment of a command call" do
      expect(rewrite("x = foo 1 and c\n")).to eq("P[0].and_left((x = foo 1)) and c\n")
    end

    it "parenthesizes a value with a rescue modifier" do
      expect(rewrite("@x ||= a rescue b\n")).to eq("P[0].write(@x ||= P[0].value((a rescue b)))\n")
    end

    it "parenthesizes an assignment of a command call with a do block" do
      expect(rewrite("@x ||= foo 1 do end\n")).to eq("P[0].write((@x ||= P[0].value(foo 1 do end)))\n")
    end

    it "closes a heredoc's parentheses after its opener, not its body" do
      expect(rewrite("@x ||= <<~S\n  body\nS\n")).to eq("P[0].write((@x ||= P[0].value((<<~S))))\n  body\nS\n")
    end

    it "answers the source untouched where there is nothing to measure" do
      expect(rewrite("a = 1\n")).to eq("a = 1\n")
    end

    it "answers the conditions alongside" do
      expect(described_class.call("a && b\n", 0)[1].map { |condition| condition.tuple.first }).to eq(%i[&&])
    end

    it "answers a column map for the splices" do
      expect(described_class.call("a && b\n", 0).last.original_column(1, 63)).to eq(2)
    end

    it "answers source Prism can't parse as it was, with nothing to measure" do
      expect(described_class.call("def f(\n", 0).take(2)).to eq(["def f(\n", []])
    end

    it "answers a column map that moves nothing for source Prism can't parse" do
      expect(described_class.call("def f(\n", 0).last.original_column(1, 5)).to eq(5)
    end
  end

  describe "what the rewrite preserves" do
    {
      "nesting" => "def self.f(a, b, c) = [a && b && c, a || b && c, ((a or b) and c)]",
      "a multi-line operand" => "def self.f(a, b, c) = (a &&\n  b) ||\n  c",
      "a heredoc operand" => "def self.f(a, b, c)\n  a || <<~S\n    \#{b}\n  S\nend",
      "not" => "def self.f(a, b, c) = (not a) && (not b)",
      "a rescue modifier" => "def self.f(a, b, c) = (a && (b || raise('no')) rescue :rescued)",
      "an index assignment" => "def self.f(a, b, c) = ((h = {})[a] ||= b) && (h[a] &&= c)",
      "a pattern guard" => "def self.f(a, b, c) = case a\n  in Integer if a > 0 && b then :guarded\n  else :other\n  end",
      "the precedence of `and` and `or`" => "def self.f(a, b, c)\n  x = a or b\n  y = a and c\n  [x, y]\nend",
      "an early return" => "def self.f(a, b, c)\n  a or return :early\n  b && c\nend",
      "defined?" => "def self.f(a, b, c) = [defined?(@x ||= a), defined?(a && b)]",
      "a bare regexp matching $_" => "def self.f(a, b, c)\n  $_ = a.to_s\n  /true/ && b ? :matched : :not\nend",
      "keyword operands that need parentheses" =>
        "def self.f(a, b, c)\n  x = (a in Integer and b)\n  y = (z = Array a and c)\n  [x, y, z]\nend",
      "a raise as the right operand" =>
        "def self.f(a, b, c)\n  a or raise ArgumentError, \"no\"\nrescue ArgumentError\n  :raised\nend",
      "an assignment of a command" => "def self.f(a, b, c)\n  h = {}\n  h[a] ||= Array b\n  h[a] &&= Array c\nend",
      "an endless method body" => "def self.f(a, b, c) = a && (b ||= c)",
      "a multi-line assignment" => "def self.f(a, b, c)\n  b ||=\n    c\n  a &&\n    b\nend"
    }.each do |shape, source|
      it "keeps what #{shape} evaluates to" do
        rewritten, = instrument(source)
        plain = original(source)
        inputs = [true, false, nil, 1].repeated_permutation(3)

        expect(inputs.map { |args| rewritten.f(*args) }).to eq(inputs.map { |args| plain.f(*args) })
      end

      it "keeps every line where it was for #{shape}" do
        expect(rewrite(source).count("\n")).to eq(source.count("\n"))
      end

      it "fires the line events #{shape} fired, so Coverage counts its lines the same" do
        rewritten = described_class.call(source, 7).first

        expect(line_events(RubyVM::InstructionSequence.compile(rewritten)))
          .to eq(line_events(RubyVM::InstructionSequence.compile(source)))
      end
    end

    it "keeps the source's encoding, magic comment and all" do
      source = (+"# encoding: iso-8859-1\ndef self.f(a, b, c) = a && \"caf\xE9\"\n").force_encoding("ISO-8859-1")
      rewritten, = instrument(source)

      expect(rewritten.f(true, nil, nil).encoding).to eq(Encoding::ISO_8859_1)
    end

    it "keeps the rewritten bytes in the source's encoding" do
      source = (+"x = a && \"caf\xC3\xA9\"\n").force_encoding("UTF-8")

      expect(rewrite(source).encoding).to eq(Encoding::UTF_8)
    end
  end

  describe "what the probes record" do
    it "counts a && whose right operand ran and one that short-circuited" do
      mod, index = instrument("def self.f(a, b) = a && b")
      [[true, 1], [false, 1], [nil, 1]].each { |args| mod.f(*args) }

      expect(arms(index)).to eq([[1, 2]])
    end

    it "counts a || the other way around" do
      mod, index = instrument("def self.f(a, b) = a || b")
      [[true, 1], [false, 1], [nil, 1]].each { |args| mod.f(*args) }

      expect(arms(index)).to eq([[2, 1]])
    end

    it "counts an assignment's evaluations and its skips" do
      mod, index = instrument("def self.f(h) = h[:k] ||= :v")
      hash = {}
      3.times { mod.f(hash) }

      expect(arms(index)).to eq([[1, 2]])
    end

    it "counts an assignment whose value raised in neither arm" do
      mod, index = instrument("def self.f(h) = h[:k] ||= raise('boom')")
      call_raising { mod.f({}) }

      expect(arms(index)).to eq([[0, 0]])
    end

    it "counts neither arm when the left operand raises" do
      mod, index = instrument("def self.f = raise('boom') && :never")
      call_raising { mod.f }

      expect(arms(index)).to eq([[0, 0]])
    end

    # Each shape's conditions in source order, as the operator and the value
    # its left side had, or nil where the condition never ran.
    {
      "a && b && c" => ->(a, b, _c) { [[:"&&", a && b], [:"&&", a]] },
      "a || b || c" => ->(a, b, _c) { [[:"||", a || b], [:"||", a]] },
      "a && b || c" => ->(a, b, _c) { [[:"||", a && b], [:"&&", a]] },
      "a || b && c" => ->(a, b, _c) { [[:"||", a], (a ? nil : [:"&&", b])] },
      "a and b or c" => ->(a, b, _c) { [[:"||", a && b], [:"&&", a]] },
      "a || b || c && d" => ->(a, b, c) { [[:"||", a || b], [:"||", a], ((a || b) ? nil : [:"&&", c])] }
    }.each do |shape, lefts|
      it "counts #{shape} the way measuring each operator on its own would" do
        mod, index = instrument("def self.f(a, b, c, d = true) = (#{shape})")
        inputs.each { |args| mod.f(*args) }

        expect(arms(index)).to eq(expected_arms(lefts))
      end
    end
  end
end
