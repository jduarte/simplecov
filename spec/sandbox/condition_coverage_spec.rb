# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "condition coverage", :sandbox, if: SimpleCov::ConditionCoverage.supported? do
  before do
    setup_project("faked_project")
    write_file("lib/faked_project/conditions.rb", <<~RUBY)
      # frozen_string_literal: true

      module Conditions
        def self.both(left, right) = left && right
      end
    RUBY
    write_file("spec/conditions_spec.rb", <<~RUBY)
      # frozen_string_literal: true

      require "spec_helper"

      describe Conditions do
        it "only ever short-circuits" do
          expect(Conditions.both(false, :never)).to be(false)
        end
      end
    RUBY
  end

  context "when enabled" do
    let!(:result) do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start { enable_coverage :condition }
      RUBY
      run_command_and_expect_success(sorted_rspec_command)
    end

    it "prints the condition coverage summary, the && never having evaluated its right operand" do
      expect(result.output).to include("Condition coverage: 1 / 2 (50.00%)")
    end

    it "still prints the line coverage summary" do
      expect(result.output).to include("Line coverage:")
    end
  end

  context "when a condition threshold fails" do
    let!(:result) do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          enable_coverage :condition
          coverage :condition, minimum: 90
        end
      RUBY
      run_command(sorted_rspec_command)
    end

    it "fails the run with the coverage exit status" do
      expect(result.exit_status).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
    end

    it "says which condition threshold failed" do
      expect(result.output).to include("Condition coverage (50.00%) is below the expected minimum coverage (90.00%).")
    end

    it "still writes the report" do
      expect_coverage_report_generated(result)
    end
  end

  context "when not enabled" do
    let!(:result) do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start
      RUBY
      run_command_and_expect_success(sorted_rspec_command)
    end

    it "prints no condition coverage summary" do
      expect(result.output).not_to include("Condition coverage:")
    end
  end
end
