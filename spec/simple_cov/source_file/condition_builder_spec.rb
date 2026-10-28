# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::SourceFile::ConditionBuilder do
  # `a && b` spanning lines 2-3, its operator ending line 2.
  def and_condition(evaluated: 0, short_circuited: 1)
    {
      [:"&&", 0, 2, 4, 3, 5] => {
        [:evaluated, 0, 3, 4, 3, 5] => evaluated,
        [:short_circuited, 1, 2, 6, 2, 8] => short_circuited
      }
    }
  end

  def build(conditions, source = ["x = 1", "y = a &&", "  b", "z = 2"])
    source_file = SimpleCov::SourceFile.new("inline_source.rb", {"lines" => [], "conditions" => conditions})
    source_file.instance_variable_set(:@src, source)
    described_class.new(source_file).call
  end

  it "builds one condition per arm" do
    expect(build(and_condition).map(&:type)).to eq(%i[evaluated short_circuited])
  end

  it "gives each arm its own hits" do
    expect(build(and_condition(evaluated: 4, short_circuited: 0)).map(&:coverage)).to eq([4, 0])
  end

  it "spans every arm across the whole expression" do
    expect(build(and_condition)).to all(have_attributes(start_line: 2, end_line: 3))
  end

  it "reports both arms on the operator's line" do
    expect(build(and_condition)).to all(have_attributes(report_line: 2, operator: :"&&"))
  end

  it "reads conditions a resultset stored as strings" do
    stored = and_condition.to_h { |condition, arms| [condition.inspect, arms.transform_keys(&:inspect)] }

    expect(build(stored).map(&:report)).to eq([[:"&&", :evaluated, 0], [:"&&", :short_circuited, 1]])
  end

  it "builds nothing for a file without conditions" do
    source_file = SimpleCov::SourceFile.new("inline_source.rb", {"lines" => []})
    source_file.instance_variable_set(:@src, ["x = 1"])

    expect(described_class.new(source_file).call).to be_empty
  end

  context "with directives" do
    it "skips the arms of an expression a disabled condition region overlaps" do
      source = ["x = 1", "y = a && # simplecov:disable condition", "  b", "z = 2"]

      expect(build(and_condition, source)).to all(be_skipped)
    end

    it "leaves the arms alone when another category is disabled" do
      source = ["x = 1", "y = a && # simplecov:disable branch", "  b", "z = 2"]

      expect(build(and_condition, source)).to all(have_attributes(skipped?: false))
    end

    it "leaves the arms alone when the disabled region is elsewhere" do
      source = ["x = 1 # simplecov:disable condition", "y = a &&", "  b", "z = 2"]

      expect(build(and_condition, source)).to all(have_attributes(skipped?: false))
    end
  end
end
