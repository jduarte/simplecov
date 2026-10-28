# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ConditionCoverage::Hits do
  # The registry is process-wide, so every example leaves it the way it found
  # it.
  around do |example|
    counters = described_class::COUNTERS.dup
    probes = described_class::PROBES.dup
    files = described_class.send(:files).dup
    example.run
  ensure
    described_class::COUNTERS.replace(counters)
    described_class::PROBES.replace(probes)
    described_class.instance_variable_set(:@files, files)
  end

  let(:column_map) { SimpleCov::ConditionCoverage::ColumnMap.new([]) }

  def condition(id = 0, kind: :"&&", write: false, chain: nil)
    SimpleCov::ConditionCoverage::Condition.new(
      tuple: [kind, id, 1, 0, 1, 6],
      evaluated_tuple: [:evaluated, 2 * id, 1, 5, 1, 6],
      short_circuited_tuple: [:short_circuited, (2 * id) + 1, 1, 2, 1, 4],
      write: write, chain: chain
    )
  end

  def register(path, conditions)
    described_class.reserve.tap { |index| described_class.commit(index, path, conditions, column_map) }
  end

  def counters(index) = described_class::COUNTERS.fetch(index)

  def arms(path) = described_class.result.fetch(path).values.map(&:values)

  describe ".reserve" do
    it "hands out consecutive indexes" do
      first = described_class.reserve

      expect(described_class.reserve).to eq(first + 1)
    end

    it "holds no counters until the file commits" do
      expect(counters(described_class.reserve)).to be_empty
    end

    it "holds no probes until the file commits" do
      expect(described_class::PROBES.fetch(described_class.reserve)).to be_empty
    end
  end

  describe ".commit" do
    it "gives every condition two zeroed counters" do
      expect(counters(register("two.rb", [condition(0), condition(1)]))).to eq([0, 0, 0, 0])
    end

    it "gives every condition a probe counting into its own slots" do
      index = register("probed.rb", [condition(0), condition(1)])
      described_class::PROBES.fetch(index).last.and_left(true)

      expect(counters(index)).to eq([0, 0, 1, 0])
    end
  end

  describe ".result" do
    it "reports each arm's hits under the condition's tuple" do
      counters(register("result.rb", [condition])).replace([3, 2])

      expect(described_class.result.fetch("result.rb")).to eq(
        [:"&&", 0, 1, 0, 1, 6] => {[:evaluated, 0, 1, 5, 1, 6] => 3, [:short_circuited, 1, 1, 2, 1, 4] => 2}
      )
    end

    it "derives an assignment's skips from its completions" do
      counters(register("write.rb", [condition(write: true)])).replace([3, 5])

      expect(arms("write.rb")).to eq([[3, 2]])
    end

    it "adds an inner condition's short-circuits to a chained one's own, on the arm the chain names" do
      inner = condition(1)
      outer = condition(0, chain: [1, :short_circuited])
      counters(register("chain.rb", [outer, inner])).replace([4, 1, 6, 2])

      expect(arms("chain.rb")).to eq([[4, 3], [6, 2]])
    end

    it "adds them to a chained condition's evaluations where the operators differ" do
      inner = condition(1, kind: :"||")
      outer = condition(0, chain: [1, :evaluated])
      counters(register("mixed.rb", [outer, inner])).replace([4, 1, 6, 2])

      expect(arms("mixed.rb")).to eq([[6, 1], [6, 2]])
    end

    it "carries short-circuits all the way down a chain" do
      conditions = [condition(0, chain: [1, :short_circuited]), condition(1, chain: [2, :short_circuited]), condition(2)]
      counters(register("long.rb", conditions)).replace([1, 1, 2, 1, 4, 1])

      expect(arms("long.rb").map(&:last)).to eq([3, 2, 1])
    end

    it "reports nothing for a reservation that never committed" do
      described_class.reserve

      expect(described_class.result.keys).not_to include(nil)
    end

    it "reports every committed file, past an abandoned reservation" do
      described_class.reserve
      register("after.rb", [condition])

      expect(described_class.result).to have_key("after.rb")
    end
  end

  describe ".column_maps" do
    it "answers each committed file's column map" do
      register("mapped.rb", [condition])

      expect(described_class.column_maps.fetch("mapped.rb")).to be(column_map)
    end

    it "answers nothing for a reservation that never committed" do
      described_class.reserve

      expect(described_class.column_maps.keys).not_to include(nil)
    end
  end
end
