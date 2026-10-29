# frozen_string_literal: true

require "helper"
require "json"

# Condition coverage takes over loading, which only a fresh process can show:
# the suite's own Coverage is already running, and its files already loaded.
RSpec.describe "Measuring conditions as files load", mutant: false do
  def run_fixture(mode)
    Dir.chdir(File.join(__dir__, "fixtures", "condition_coverage_loading")) do
      FileUtils.rm_rf("tmp")
      stdout, stderr, status = Open3.capture3(child_env, RbConfig.ruby, "runner.rb", mode)
      raise "fixture failed: #{stderr}" unless status.success?

      JSON.parse(stdout.lines.last)
    end
  end

  # The version table is all that stands between a Ruby that leaves compiled
  # code out of Coverage and a run that loses its line coverage.
  it "agrees with this Ruby about whether compiled code keeps its coverage", if: RUBY_ENGINE == "ruby" do
    probe = 'require "coverage"; Coverage.start(lines: true); ' \
            'RubyVM::InstructionSequence.compile("x = 1", "/probe.rb", "/probe.rb"); ' \
            'print Coverage.peek_result.key?("/probe.rb")'
    stdout, = Open3.capture3(child_env, RbConfig.ruby, "-e", probe)

    expect(SimpleCov::ConditionCoverage.compile_keeps_coverage?.to_s).to eq(stdout)
  end

  context "when this Ruby can measure conditions", if: SimpleCov::ConditionCoverage.supported? do
    let(:measured) { run_fixture("conditions") }

    it "reports every arm of every condition the loaded file holds" do
      expect(measured.fetch("conditions")).to eq([
        %w[|| evaluated 1], %w[|| short_circuited 1],
        %w[&& evaluated 1], %w[&& short_circuited 1],
        %w[||= evaluated 1], %w[||= short_circuited 0]
      ])
    end

    it "leaves the line coverage what it is without it" do
      expect(measured.fetch("lines")).to eq(run_fixture("lines_only").fetch("lines"))
    end

    it "leaves the branch coverage what it is without it, columns and all" do
      expect(measured.fetch("branches")).to eq(run_fixture("lines_only").fetch("branches"))
    end

    it "measures a file in another encoding, whose strings keep it" do
      expect(measured.values_at("latin1_encoding", "latin1_conditions")).to eq(["ISO-8859-1", 2])
    end

    it "still measures where a bootsnap-like loader was installed first" do
      expect(run_fixture("bootsnap_before").fetch("conditions")).to eq(measured.fetch("conditions"))
    end

    it "still measures where a bootsnap-like loader is installed after SimpleCov starts" do
      expect(run_fixture("bootsnap_after").fetch("conditions")).to eq(measured.fetch("conditions"))
    end

    context "when two runs merge" do
      let(:merged) do
        Dir.chdir(File.join(__dir__, "fixtures", "condition_coverage_loading")) do
          FileUtils.rm_rf("tmp")
          %w[one two].map do |part|
            stdout, stderr, status = Open3.capture3(child_env, RbConfig.ruby, "merging.rb", part)
            raise "fixture failed: #{stderr}" unless status.success?

            JSON.parse(stdout.lines.last)
          end.last
        end
      end

      it "adds up the arms each run took" do
        expect(merged.fetch("checks.rb").first(4)).to eq([
          %w[|| evaluated 1], %w[|| short_circuited 1], %w[&& evaluated 1], %w[&& short_circuited 1]
        ])
      end

      it "counts every condition of a covered file neither run loaded, at zero" do
        expect(merged.fetch("never_loaded.rb")).to eq([%w[|| evaluated 0], %w[|| short_circuited 0]])
      end
    end
  end
end
