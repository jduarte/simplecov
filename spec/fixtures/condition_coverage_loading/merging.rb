# frozen_string_literal: true

# One of two runs under different command names, each taking a different arm
# of the same condition. The second merges the first's stored result into its
# own and prints the merged conditions, as JSON, for lib/checks.rb and for
# lib/never_loaded.rb, which neither run requires.

require "json"
require_relative "../../../lib/simplecov"

part = ARGV.fetch(0)

SimpleCov.start do
  root __dir__
  command_name "condition coverage merging #{part}"
  coverage_dir "tmp/coverage"
  formatter SimpleCov::Formatter::SimpleFormatter
  cover "lib/**/*.rb"
  enable_coverage :condition
end

require_relative "lib/checks"
(part == "one") ? Checks.both(false, :never) : Checks.both(true, :yes)

files = SimpleCov.result.files.to_h { |file| [File.basename(file.filename), file] }
puts JSON.dump(
  files.slice("checks.rb", "never_loaded.rb").transform_values do |file|
    file.conditions.map { |condition| condition.report.map(&:to_s) }
  end
)
