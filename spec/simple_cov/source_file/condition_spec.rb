# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::SourceFile::Condition do
  def condition(coverage: 1, start_line: 4, end_line: 6)
    described_class.new(
      start_line: start_line, end_line: end_line, coverage: coverage,
      type: :evaluated, operator: :"&&", report_line: 5
    )
  end

  it "keeps every attribute it was built with" do
    expect(condition(coverage: 3)).to have_attributes(
      start_line: 4, end_line: 6, coverage: 3, type: :evaluated, operator: :"&&", report_line: 5
    )
  end

  it "reports its operator, its arm, and its hits" do
    expect(condition(coverage: 2).report).to eq([:"&&", :evaluated, 2])
  end

  it "starts out not skipped" do
    expect(condition.skipped?).to be(false)
  end

  it "is covered once it has a hit" do
    expect(condition(coverage: 1)).to have_attributes(covered?: true, missed?: false)
  end

  it "is missed with no hits" do
    expect(condition(coverage: 0)).to have_attributes(covered?: false, missed?: true)
  end

  it "is neither covered nor missed once skipped, hit or not" do
    hit = condition(coverage: 1).tap(&:skipped!)
    unhit = condition(coverage: 0).tap(&:skipped!)

    expect([hit, unhit]).to all(have_attributes(covered?: false, missed?: false, skipped?: true))
  end

  describe "#overlaps_with?" do
    it "overlaps a range reaching its first line" do
      expect(condition.overlaps_with?(1..4)).to be(true)
    end

    it "overlaps a range starting on its last line" do
      expect(condition.overlaps_with?(6..9)).to be(true)
    end

    it "doesn't overlap a range ending above it" do
      expect(condition.overlaps_with?(1..3)).to be(false)
    end

    it "doesn't overlap a range starting below it" do
      expect(condition.overlaps_with?(7..9)).to be(false)
    end
  end
end
