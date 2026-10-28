# frozen_string_literal: true

require "helper"
require "json"

# Condition coverage takes over loading, which only a fresh process can show:
# the suite's own Coverage is already running, and its files already loaded.
RSpec.describe "Measuring conditions as files load", if: RUBY_ENGINE == "ruby", mutant: false do
  def run_fixture(mode)
    Dir.chdir(File.join(__dir__, "fixtures", "condition_coverage_loading")) do
      FileUtils.rm_rf("tmp")
      stdout, stderr, status = Open3.capture3(child_env, RbConfig.ruby, "runner.rb", mode)
      raise "fixture failed: #{stderr}" unless status.success?

      JSON.parse(stdout.lines.last)
    end
  end

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
end
