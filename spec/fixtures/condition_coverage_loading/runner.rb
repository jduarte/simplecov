# frozen_string_literal: true

# Measures lib/ in a fresh process and prints what SimpleCov saw, as JSON.
# ARGV[0] picks the variation:
#   conditions       condition coverage on
#   lines_only       condition coverage off, to compare line and branch data
#   bootsnap_before  a bootsnap-like loader installed before SimpleCov starts
#   bootsnap_after   the same loader installed after, the usual Rails order

require "json"
require_relative "../../../lib/simplecov"

mode = ARGV.fetch(0)
require_relative "bootsnap_like" if mode == "bootsnap_before"

SimpleCov.start do
  root __dir__
  command_name "condition coverage loading #{mode}"
  coverage_dir "tmp/coverage"
  formatter SimpleCov::Formatter::SimpleFormatter
  cover "lib/**/*.rb"
  enable_coverage :branch
  enable_coverage :condition unless mode == "lines_only"
end

require_relative "bootsnap_like" if mode == "bootsnap_after"

require_relative "lib/checks"
require_relative "lib/latin1"
Checks.both(false, :never)
Checks.both(true, :yes)
Checks.memo({})

files = SimpleCov.result.files.to_h { |file| [File.basename(file.filename), file] }
checks = files.fetch("checks.rb")
puts JSON.dump(
  "lines" => checks.coverage_data["lines"],
  "branches" => checks.coverage_data["branches"].to_h { |condition, arms| [condition.to_s, arms.values] },
  "conditions" => checks.conditions.map { |condition| condition.report.map(&:to_s) },
  "latin1_encoding" => Latin1.cafe(true).encoding.name,
  "latin1_conditions" => files.fetch("latin1.rb").conditions.size
)
