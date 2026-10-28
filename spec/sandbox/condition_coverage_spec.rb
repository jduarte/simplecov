# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "condition coverage", :sandbox, if: RUBY_ENGINE == "ruby" do
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
