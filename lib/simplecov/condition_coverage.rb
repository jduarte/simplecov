# frozen_string_literal: true

require_relative "condition_coverage/condition"
require_relative "condition_coverage/column_map"
require_relative "condition_coverage/hits"
require_relative "condition_coverage/load_hook"

module SimpleCov
  # Condition coverage: whether each `&&`, `||`, `and`, `or`, `&&=` and `||=`
  # has been seen both evaluating its right operand and short-circuiting past
  # it. Ruby's Coverage reports neither (a fully exercised `a && b` and one
  # whose `b` never ran look the same), so this measures them itself, by
  # rewriting each in-scope file's source with hit counters as Ruby loads it
  # (see `Rewriter`). Only CRuby lets a library take over loading, and the
  # rewrite needs Prism.
  #
  # Code that ran before `SimpleCov.start`, eval'd code, and templates aren't
  # loaded through the hook, so they carry no conditions.
  module ConditionCoverage
    extend self

    BOOTSNAP_MIXIN = "Bootsnap::CompileCache::ISeq::InstructionSequenceMixin"
    private_constant :BOOTSNAP_MIXIN

    # SimpleCov's own source. Rewriting it would route `Hits` through itself.
    OWN_SOURCE = File.expand_path("..", __dir__.to_s) + File::SEPARATOR
    private_constant :OWN_SOURCE

    # Memoized, because a failed Prism load leaves nothing in
    # $LOADED_FEATURES and would otherwise be retried on every question. The
    # rewriter loads wherever Prism does, even on a Ruby that can't measure
    # with it.
    def supported?
      return @supported if instance_variable_defined?(:@supported)

      @supported = RUBY_ENGINE.eql?("ruby") && load_rewriter && compile_keeps_coverage?
    end

    # Ruby 3.4.0 to 3.4.9 and 4.0.0 to 4.0.3 never register code compiled by
    # `RubyVM::InstructionSequence.compile` with Coverage when Prism compiles
    # it, so a rewritten file would lose its line, branch, and method
    # coverage to gain its conditions.
    def compile_keeps_coverage?
      COVERAGE_BLIND_COMPILERS.none? { |blind| blind.cover?(RUBY_VERSION) }
    end

    COVERAGE_BLIND_COMPILERS = [
      Gem::Version.new("3.4.0")...Gem::Version.new("3.4.10"),
      Gem::Version.new("4.0.0")...Gem::Version.new("4.0.4")
    ].freeze
    private_constant :COVERAGE_BLIND_COMPILERS

    # Takes over loading for the rest of the process. Prepending is a no-op
    # once the hook is in place, so a repeated `SimpleCov.start` changes
    # nothing.
    def install(target = RubyVM::InstructionSequence.singleton_class)
      target.prepend(LoadHook)
      install_above_bootsnap
    end

    # The instruction sequence for `path` with counters spliced in, or nil to
    # let Ruby load the file as it would have. Anything that goes wrong
    # answers nil: an unmeasured file beats a broken load.
    def instrument(path)
      return nil unless SimpleCov.condition_coverage? && in_scope?(path)

      compile(path, File.binread(path).force_encoding(Encoding::UTF_8))
    rescue SyntaxError, StandardError
      nil
    end

    # Decided before the file exists as a SourceFile, so only what its path
    # says counts: the root, the path-only `skip` filters, and the path-only
    # `cover` filters. A filter that needs more can't say no yet, so its files
    # are measured and the report's own filtering drops them later.
    # `UnloadedFileInjector.rejected?` answers whether any of the filters it's
    # given matches the path, which for `cover` is a match to keep.
    def in_scope?(path)
      return false if path.start_with?(OWN_SOURCE) || !path.match?(UselessResultsRemover.root_regex)
      return false if UnloadedFileInjector.rejected?(path, SimpleCov.filters.select(&:path_only?))

      covers = SimpleCov.cover_filters
      covers.empty? || covers.any? { |filter| !filter.path_only? || UnloadedFileInjector.rejected?(path, [filter]) }
    end

    nothing_measured = {} #: Hash[Symbol, untyped]
    NOTHING_MEASURED = nothing_measured.freeze
    private_constant :NOTHING_MEASURED

    # Adds each measured file's conditions to the `Coverage.result` entry for
    # it, the entry a file Coverage didn't see starting empty. The branches
    # and methods Coverage recorded for a rewritten file carry the rewritten
    # columns, so they're translated back to the original's.
    def merge_into(coverage_result)
      column_maps = Hits.column_maps
      Hits.result.each_with_object(coverage_result.dup) do |(path, conditions), merged|
        entry = translated(merged.fetch(path, NOTHING_MEASURED), column_maps.fetch(path))
        merged[path] = entry.merge(conditions: conditions)
      end
    end

    private

    def translated(entry, column_map)
      branches = entry[:branches]
      methods = entry[:methods]
      entry = entry.merge(branches: column_map.translate_branches(branches)) if branches
      entry = entry.merge(methods: column_map.translate_methods(methods)) if methods
      entry
    end

    # Source files default to UTF-8 and a magic comment overrides that, in
    # both Prism and the compiler, so the bytes are tagged the way Ruby's own
    # loader would see them.
    def compile(path, source)
      file_index = Hits.reserve
      rewritten, conditions, column_map = Rewriter.call(source, file_index)
      # Nothing to measure, or nothing Prism could parse: Ruby loads the file
      # itself, and the reservation stays empty.
      return nil if conditions.empty?

      # RBS's core signatures leave `compile` out.
      iseq = RubyVM::InstructionSequence.compile(rewritten, path, File.realpath(path)) # steep:ignore NoMethod
      Hits.commit(file_index, path, conditions, column_map)
      iseq
    end

    def load_rewriter
      require_relative "condition_coverage/rewriter"
      true
    rescue LoadError
      false
    end

    # bootsnap's hook answers nil without calling `super` whenever Coverage is
    # running, so a hook beneath it is never asked. bootsnap usually loads
    # after `SimpleCov.start` (`config/boot.rb` runs after the test helper's
    # first lines) and would prepend itself above. Prepending the hook into
    # bootsnap's mixin instead keeps it first whichever loads first: already
    # loaded, it happens now, and otherwise it happens as the mixin is defined.
    def install_above_bootsnap
      mixin = bootsnap_mixin
      return mixin.prepend(LoadHook) if mixin

      @bootsnap_watch ||= TracePoint.new(:class) do |trace|
        # simplecov:disable — Coverage does not count code run inside a TracePoint callback
        # A class event's self is always the module being opened.
        defined = trace.self
        if defined.name.eql?(BOOTSNAP_MIXIN)
          defined.prepend(LoadHook)
          trace.disable
        end
        # simplecov:enable
      end.tap(&:enable)
    end

    # A module's own constant lookup reaches the top level too, so asking
    # `self` rather than `Object` reads as equivalent.
    # mutant:disable
    def bootsnap_mixin
      Object.const_get(BOOTSNAP_MIXIN) if Object.const_defined?(BOOTSNAP_MIXIN)
    end
  end
end
