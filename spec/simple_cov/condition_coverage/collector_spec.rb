# frozen_string_literal: true

require "helper"

# Asking loads the rewriter on any CRuby where Prism loads, whether or not
# that Ruby can measure with it. Nothing else measures conditions.
SimpleCov::ConditionCoverage.supported?
return unless defined?(SimpleCov::ConditionCoverage::Rewriter)

RSpec.describe SimpleCov::ConditionCoverage::Collector do
  def sites(source)
    collector = described_class.new
    Prism.parse(source).value.accept(collector)
    collector.sites
  end

  def conditions(source) = sites(source).map(&:condition)

  def kinds(source) = conditions(source).map { |condition| condition.tuple.first }

  describe "the operators it measures" do
    it "measures both spellings of conjunction as &&" do
      expect(kinds("a && b\nc and d\n")).to eq(%i[&& &&])
    end

    it "measures both spellings of disjunction as ||" do
      expect(kinds("a || b\nc or d\n")).to eq(%i[|| ||])
    end

    {
      "x" => "local variable", "@x" => "instance variable", "@@x" => "class variable", "$x" => "global variable",
      "X" => "constant", "A::X" => "constant path", "o.x" => "attribute", "h[k]" => "index"
    }.each do |target, name|
      it "measures ||= and &&= on a #{name}" do
        expect(kinds("#{target} ||= 1\n#{target} &&= 2\n")).to eq(%i[||= &&=])
      end
    end

    it "measures nothing in plain code" do
      expect(sites("a = b + c\nfoo(a) if bar\n")).to be_empty
    end
  end

  describe "the tuples it names a condition by" do
    let(:condition) { conditions("x = foo && bar\n").first }

    it "spans the whole expression" do
      expect(condition.tuple).to eq([:"&&", 0, 1, 4, 1, 14])
    end

    it "spans the right operand for the evaluated arm" do
      expect(condition.evaluated_tuple).to eq([:evaluated, 0, 1, 11, 1, 14])
    end

    it "spans the operator for the short-circuit arm" do
      expect(condition.short_circuited_tuple).to eq([:short_circuited, 1, 1, 8, 1, 10])
    end

    it "numbers conditions in source order, two arm ids apiece" do
      second = conditions("a && b\nc || d\n").last

      expect([second.tuple[1], second.evaluated_tuple[1], second.short_circuited_tuple[1]]).to eq([1, 2, 3])
    end

    it "spans an assignment's value for its evaluated arm, and its operator for the other" do
      write = conditions("@memo ||= compute\n").first

      expect([write.evaluated_tuple, write.short_circuited_tuple])
        .to eq([[:evaluated, 0, 1, 10, 1, 17], [:short_circuited, 1, 1, 6, 1, 9]])
    end

    it "marks only the assignment operators as counting by subtraction" do
      expect(conditions("a && b\n@x ||= 1\n").map(&:write?)).to eq([false, true])
    end
  end

  describe "the sites it hands the rewriter" do
    it "keeps the left operand of && and ||" do
      expect(sites("first && second\n").first.left.slice).to eq("first")
    end

    it "keeps no left operand for an assignment, whose target can't be wrapped" do
      expect(sites("@x ||= 1\n").first.left).to be_nil
    end

    it "keeps the right operand, an assignment's value" do
      expect(sites("@x ||= value\n").first.right.slice).to eq("value")
    end

    it "keeps the whole node" do
      expect(sites("@x ||= value\n").first.node.slice).to eq("@x ||= value")
    end

    it "counts how many measured conditions enclose each one" do
      expect(sites("a || (b && (c ||= d))\ne && f\n").map(&:depth)).to eq([0, 1, 2, 0])
    end

    it "nests the left operand of a chain inside the outer condition" do
      expect(sites("a && b && c\n").map { |site| [site.depth, site.left.slice] }).to eq([[0, "a && b"], [1, "a"]])
    end
  end

  describe "what it leaves alone" do
    it "measures nothing inside defined?, which never evaluates its operand" do
      expect(sites("defined?(@x ||= a && b)\n")).to be_empty
    end

    it "leaves a bare regexp that matches $_ in a condition" do
      expect(sites("if /foo/ && bar then 1 end\n")).to be_empty
    end

    it "leaves an interpolated bare regexp the same way" do
      expect(sites("if bar || /f\#{x}o/ then 1 end\n")).to be_empty
    end

    it "leaves a flip-flop" do
      expect(sites("if ((a == 1)..(b == 2)) || c then 1 end\n")).to be_empty
    end

    it "sees a special operand through single-statement parentheses" do
      expect(sites("if ((/foo/)) && bar then 1 end\n")).to be_empty
    end

    it "measures an operand whose parentheses hold more than one statement" do
      expect(sites("if (x; /foo/) && bar then 1 end\n").size).to eq(1)
    end

    it "still measures conditions nested inside one it leaves" do
      expect(kinds("if /foo/ && (a || b) then 1 end\n")).to eq(%i[||])
    end
  end
end
