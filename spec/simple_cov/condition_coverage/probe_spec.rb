# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ConditionCoverage::Probe do
  # Condition 2's slots are 4 and 5; the others stay untouched.
  let(:counters) { [0, 0, 0, 0, 0, 0] }
  let(:probe) { described_class.new(counters, 2) }

  describe "#and_left" do
    it "answers the operand it was handed" do
      expect(probe.and_left(:value)).to eq(:value)
    end

    it "counts a truthy operand as the right one's evaluation" do
      probe.and_left(0)

      expect(counters).to eq([0, 0, 0, 0, 1, 0])
    end

    it "counts a falsy operand as a short-circuit" do
      [nil, false].each { |falsy| probe.and_left(falsy) }

      expect(counters).to eq([0, 0, 0, 0, 0, 2])
    end
  end

  describe "#or_left" do
    it "answers the operand it was handed" do
      expect(probe.or_left(false)).to be(false)
    end

    it "counts a falsy operand as the right one's evaluation" do
      probe.or_left(nil)

      expect(counters).to eq([0, 0, 0, 0, 1, 0])
    end

    it "counts a truthy operand as a short-circuit" do
      probe.or_left(0)

      expect(counters).to eq([0, 0, 0, 0, 0, 1])
    end
  end

  describe "#value" do
    it "answers the value it was handed" do
      expect(probe.value(:computed)).to eq(:computed)
    end

    it "counts the value's evaluation" do
      probe.value(:computed)

      expect(counters).to eq([0, 0, 0, 0, 1, 0])
    end
  end

  describe "#write" do
    it "answers the value it was handed" do
      expect(probe.write(false)).to be(false)
    end

    it "counts the assignment's completion" do
      probe.write(:assigned)

      expect(counters).to eq([0, 0, 0, 0, 0, 1])
    end
  end
end
