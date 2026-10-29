# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ConditionCoverage::ColumnMap do
  # On line 2: a four-byte splice at original column 3, then a one-byte one
  # at original column 6. In the rewritten line the first ends at column 7,
  # the second runs from 10 to 11.
  let(:map) { described_class.new([[2, 3, 4], [2, 6, 1]]) }

  describe "#original_column" do
    it "leaves a column before every splice alone" do
      expect(map.original_column(2, 1)).to eq(1)
    end

    it "leaves the column a splice opens at alone, where the wrapped code begins" do
      expect(map.original_column(2, 3)).to eq(3)
    end

    it "moves a column past a splice back by its length" do
      expect(map.original_column(2, 7)).to eq(3)
    end

    it "moves a column right after a closing splice back to where the wrapped code ended" do
      expect(map.original_column(2, 11)).to eq(6)
    end

    it "moves a column past both splices back by both lengths" do
      expect(map.original_column(2, 15)).to eq(10)
    end

    it "leaves a line without splices alone" do
      expect(map.original_column(3, 15)).to eq(15)
    end

    it "moves a column right after a splice that opens a line back to the line's start" do
      expect(described_class.new([[1, 0, 3]]).original_column(1, 3)).to eq(0)
    end

    it "places each splice past every earlier one on its line" do
      third_splice_in = described_class.new([[1, 0, 2], [1, 5, 3], [1, 9, 4]])

      expect(third_splice_in.original_column(1, 17)).to eq(12)
    end

    it "leaves a column inside a splice that opens a line alone" do
      expect(described_class.new([[1, 0, 3]]).original_column(1, 2)).to eq(2)
    end
  end

  describe "#translate" do
    it "translates both ends of a tuple, each against its own line" do
      expect(map.translate([:if, 4, 1, 9, 2, 15])).to eq([:if, 4, 1, 9, 2, 10])
    end

    it "translates the start against its own line too" do
      expect(map.translate([:if, 4, 2, 11, 3, 1])).to eq([:if, 4, 2, 6, 3, 1])
    end
  end

  describe "#translate_branches" do
    it "translates every condition and arm" do
      expect(map.translate_branches([:if, 0, 2, 7, 2, 15] => {[:then, 1, 2, 11, 2, 15] => 3}))
        .to eq([:if, 0, 2, 3, 2, 10] => {[:then, 1, 2, 6, 2, 10] => 3})
    end
  end

  describe "#translate_methods" do
    it "translates every method, keeping its hits" do
      expect(map.translate_methods(["A", :m, 2, 0, 2, 15] => 2)).to eq(["A", :m, 2, 0, 2, 10] => 2)
    end
  end
end
