# frozen_string_literal: true

require "helper"

RSpec.describe "A Ruby whose Prism cannot load" do
  before { skip "TruffleRuby's Ripper is built on Prism" if RUBY_ENGINE == "truffleruby" }

  def run_fixture(*args)
    Dir.chdir(File.join(__dir__, "fixtures", "unloadable_prism")) do
      FileUtils.rm_rf("tmp")
      stdout, stderr, status = Open3.capture3(child_env, RbConfig.ruby, "unloadable_prism.rb", *args)
      raise "fixture failed: #{stderr}" unless status.success?

      stdout
    end
  end

  context "when only line coverage is enabled" do
    let(:output) { run_fixture }

    it "reports without ever reaching for Prism" do
      expect(output).to include("prism attempted: no")
    end

    it "reports the loaded and the tracked files" do
      expect(output.lines).to include("lib/loaded.rb 100\n", "lib/never_loaded.rb 0\n")
    end
  end

  context "when condition coverage is asked for" do
    let(:streams) do
      Dir.chdir(File.join(__dir__, "fixtures", "unloadable_prism")) do
        FileUtils.rm_rf("tmp")
        Open3.capture3(child_env, RbConfig.ruby, "unloadable_prism.rb", "condition")
      end
    end

    it "says it can't measure conditions" do
      expect(streams[1]).to include("[SimpleCov]: condition coverage needs CRuby with Prism")
    end

    it "reports the files all the same" do
      expect(streams[0].lines).to include("lib/loaded.rb 100\n", "lib/never_loaded.rb 0\n")
    end
  end

  context "when branch and method coverage are enabled" do
    let(:output) { run_fixture("all") }

    it "reaches for Prism where the criteria are supported" do
      skip "no branch coverage on this Ruby" unless SimpleCov.branch_coverage_supported?

      expect(output).to include("prism attempted: yes")
    end

    it "falls back to reporting without the static extraction" do
      expect(output.lines).to include("lib/loaded.rb 100\n", "lib/never_loaded.rb 0\n")
    end
  end
end
