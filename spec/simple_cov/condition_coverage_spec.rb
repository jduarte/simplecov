# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ConditionCoverage do
  let(:hits) { described_class::Hits }

  def fixture(name) = File.expand_path("../fixtures/condition_coverage/#{name}", __dir__)

  describe ".supported?", mutant_expression: %w[
    SimpleCov::ConditionCoverage#supported? SimpleCov::ConditionCoverage#load_rewriter
  ] do
    around do |example|
      forget_support
      example.run
    ensure
      forget_support
    end

    def forget_support
      %i[@supported @rewriter_loaded].each do |memo|
        described_class.remove_instance_variable(memo) if described_class.instance_variable_defined?(memo)
      end
    end

    it "answers true on a CRuby whose compiled code keeps its coverage" do
      stub_const("RUBY_ENGINE", "ruby")
      stub_const("RUBY_VERSION", "3.4.10")
      allow(described_class).to receive(:require_relative).and_return(true)

      expect(described_class.supported?).to be(true)
    end

    it "answers the same however often it's asked" do
      stub_const("RUBY_ENGINE", "ruby")
      stub_const("RUBY_VERSION", "3.4.10")
      allow(described_class).to receive(:require_relative).and_return(true)

      expect(Array.new(2) { described_class.supported? }).to eq([true, true])
    end

    it "works its answer out once" do
      stub_const("RUBY_ENGINE", "ruby")
      allow(described_class).to receive_messages(rewriter_loaded?: true, compile_keeps_coverage?: true)
      2.times { described_class.supported? }

      expect(described_class).to have_received(:compile_keeps_coverage?).once
    end

    it "answers false on a CRuby whose compiled code loses its coverage" do
      stub_const("RUBY_ENGINE", "ruby")
      stub_const("RUBY_VERSION", "4.0.2")
      allow(described_class).to receive(:require_relative).and_return(true)

      expect(described_class.supported?).to be(false)
    end

    it "still loads the rewriter on a CRuby that can't measure with it" do
      stub_const("RUBY_ENGINE", "ruby")
      stub_const("RUBY_VERSION", "4.0.2")
      allow(described_class).to receive(:require_relative).and_return(true)
      described_class.supported?

      expect(described_class).to have_received(:require_relative)
    end

    it "answers true where the rewriter had already loaded" do
      stub_const("RUBY_ENGINE", "ruby")
      stub_const("RUBY_VERSION", "3.4.10")
      allow(described_class).to receive(:require_relative).and_return(false)

      expect(described_class.supported?).to be(true)
    end

    it "loads the rewriter" do
      allow(described_class).to receive(:require_relative).and_return(true)

      described_class.supported?

      expect(described_class).to have_received(:require_relative).with("condition_coverage/rewriter")
    end

    it "answers false on any other engine" do
      stub_const("RUBY_ENGINE", "jruby")

      expect(described_class.supported?).to be(false)
    end

    it "never reaches for Prism on any other engine" do
      stub_const("RUBY_ENGINE", "jruby")
      allow(described_class).to receive(:require_relative)
      described_class.supported?

      expect(described_class).not_to have_received(:require_relative)
    end

    context "when Prism cannot load" do
      before do
        stub_const("RUBY_ENGINE", "ruby")
        allow(described_class).to receive(:require_relative).and_raise(LoadError, "Could not open library 'libprism'")
      end

      it "answers false rather than raising" do
        expect(described_class.supported?).to be(false)
      end

      it "tries only once" do
        2.times { described_class.supported? }

        expect(described_class).to have_received(:require_relative).once
      end

      it "keeps answering false" do
        expect(Array.new(2) { described_class.supported? }).to eq([false, false])
      end
    end
  end

  describe ".compile_keeps_coverage?", mutant_expression: "SimpleCov::ConditionCoverage#compile_keeps_coverage?" do
    {
      "3.4.9" => false, "3.4.10" => true, "4.0.0" => false, "4.0.3" => false, "4.0.4" => true, "4.1.0" => true
    }.each do |version, keeps|
      it "answers #{keeps} for Ruby #{version}" do
        stub_const("RUBY_VERSION", version)

        expect(described_class.compile_keeps_coverage?).to be(keeps)
      end
    end
  end

  describe ".install", mutant_expression: %w[
    SimpleCov::ConditionCoverage#install SimpleCov::ConditionCoverage#install_above_bootsnap
    SimpleCov::ConditionCoverage#bootsnap_mixin
  ] do
    let(:target) { Class.new.singleton_class }

    after do
      watch = described_class.instance_variable_get(:@bootsnap_watch)
      watch&.disable
      described_class.remove_instance_variable(:@bootsnap_watch) if watch
    end

    it "puts the load hook first in the target's lookup" do
      stub_const("Bootsnap::CompileCache::ISeq::InstructionSequenceMixin", Module.new)

      described_class.install(target)

      expect(target.ancestors.first).to be(described_class::LoadHook)
    end

    it "installs onto RubyVM::InstructionSequence by default" do
      stub_const("Bootsnap::CompileCache::ISeq::InstructionSequenceMixin", Module.new)
      allow(RubyVM::InstructionSequence).to receive(:singleton_class).and_return(target)

      described_class.install

      expect(target.ancestors.first).to be(described_class::LoadHook)
    end

    it "watches for nothing when bootsnap already loaded" do
      stub_const("Bootsnap::CompileCache::ISeq::InstructionSequenceMixin", Module.new)

      described_class.install(target)

      expect(described_class.instance_variable_get(:@bootsnap_watch)).to be_nil
    end

    it "prepends the hook into bootsnap's mixin when bootsnap already loaded" do
      mixin = stub_const("Bootsnap::CompileCache::ISeq::InstructionSequenceMixin", Module.new)

      described_class.install(target)

      expect(mixin.ancestors.first).to be(described_class::LoadHook)
    end

    it "watches for bootsnap's mixin when bootsnap hasn't loaded yet" do
      described_class.install(target)

      expect(described_class.instance_variable_get(:@bootsnap_watch)).to be_enabled
    end

    context "when bootsnap loads after it" do
      before { described_class.install(target) }

      # The watch only sees a real `module` body, which stub_const can't open.
      after { Object.send(:remove_const, :Bootsnap) if defined?(Bootsnap) } # rubocop:disable RSpec/RemoveConst

      def define_bootsnap_mixin
        Object.class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          module Bootsnap; module CompileCache; module ISeq; module InstructionSequenceMixin; end; end; end; end
        RUBY
        Object.const_get("Bootsnap::CompileCache::ISeq::InstructionSequenceMixin")
      end

      it "prepends the hook into bootsnap's mixin as it is defined" do
        expect(define_bootsnap_mixin.ancestors.first).to be(described_class::LoadHook)
      end

      it "stops watching once it has" do
        define_bootsnap_mixin

        expect(described_class.instance_variable_get(:@bootsnap_watch)).not_to be_enabled
      end

      it "keeps watching past every other module" do
        Module.new { def self.name = "NotBootsnap" }.module_eval("module Inner; end", __FILE__, __LINE__)

        expect(described_class.instance_variable_get(:@bootsnap_watch)).to be_enabled
      end
    end

    it "watches only once however often it installs" do
      described_class.install(target)
      watch = described_class.instance_variable_get(:@bootsnap_watch)
      described_class.install(target)

      expect(described_class.instance_variable_get(:@bootsnap_watch)).to be(watch)
    end
  end

  describe ".instrument", if: RUBY_ENGINE == "ruby", mutant_expression: %w[
    SimpleCov::ConditionCoverage#instrument SimpleCov::ConditionCoverage#compile
  ] do
    around do |example|
      counters = hits::COUNTERS.dup
      probes = hits::PROBES.dup
      files = hits.send(:files).dup
      example.run
    ensure
      hits::COUNTERS.replace(counters)
      hits::PROBES.replace(probes)
      hits.instance_variable_set(:@files, files)
    end

    # Asking for support is what loads the rewriter, as it is in a real run.
    # It loads even where this Ruby can't measure with it, which these
    # examples don't need it to.
    before do
      described_class.supported?
      allow(SimpleCov).to receive(:condition_coverage?).and_return(true)
    end

    it "answers nil when the run doesn't measure conditions" do
      allow(SimpleCov).to receive(:condition_coverage?).and_return(false)

      expect(described_class.instrument(fixture("sample.rb"))).to be_nil
    end

    it "answers nil for a file out of scope" do
      allow(described_class).to receive(:in_scope?).and_return(false)

      expect(described_class.instrument(fixture("sample.rb"))).to be_nil
    end

    def with_link_to(target)
      Dir.mktmpdir do |dir|
        linked = File.join(dir, "linked.rb")
        File.symlink(target, linked)
        yield linked
      end
    rescue NotImplementedError, SystemCallError
      skip "no symlinks here"
    end

    it "compiles a symlinked file under the path it was loaded by, and its real path, as Ruby's loader does" do
      allow(described_class).to receive(:in_scope?).and_return(true)

      with_link_to(fixture("sample.rb")) do |linked|
        expect(described_class.instrument(linked).then { |iseq| [iseq.path, iseq.absolute_path] })
          .to eq([linked, fixture("sample.rb")])
      end
    end

    it "reads a file without a magic comment as UTF-8, the way Ruby's own loader does" do
      described_class.instrument(fixture("utf8.rb")).eval

      expect(ConditionCoverageUtf8.word(true).encoding).to eq(Encoding::UTF_8)
    end

    it "answers nil for a file with nothing to measure, leaving Ruby to load it" do
      expect(described_class.instrument(fixture("plain.rb"))).to be_nil
    end

    it "answers nil for a file Prism can't parse" do
      allow(File).to receive(:binread).with(fixture("sample.rb")).and_return(+"def f(\n")

      expect(described_class.instrument(fixture("sample.rb"))).to be_nil
    end

    it "answers nil rather than raising when the rewrite won't compile" do
      allow(RubyVM::InstructionSequence).to receive(:compile).and_raise(SyntaxError, "nope")

      expect(described_class.instrument(fixture("sample.rb"))).to be_nil
    end

    it "measures nothing for a file whose rewrite wouldn't compile" do
      allow(RubyVM::InstructionSequence).to receive(:compile).and_raise(SyntaxError, "nope")
      described_class.instrument(fixture("sample.rb"))

      expect(hits.result).not_to have_key(fixture("sample.rb"))
    end

    context "with a file to measure" do
      let(:iseq) { described_class.instrument(fixture("sample.rb")) }

      it "compiles it under its own path" do
        expect(iseq.path).to eq(fixture("sample.rb"))
      end

      it "registers the column map Coverage's columns for it will need" do
        iseq

        expect(hits.column_maps.fetch(fixture("sample.rb"))).to be_a(described_class::ColumnMap)
      end

      it "registers its conditions" do
        iseq

        expect(hits.result.fetch(fixture("sample.rb")).keys.map(&:first)).to eq(%i[&& ||=])
      end

      it "compiles code that counts what runs" do
        iseq.eval
        ConditionCoverageSample.both(false, :never)

        expect(hits.result.fetch(fixture("sample.rb")).values.first.values).to eq([0, 1])
      end
    end
  end

  describe ".in_scope?", mutant_expression: "SimpleCov::ConditionCoverage#in_scope?" do
    around do |example|
      previous_cover = SimpleCov.cover_filters.dup
      previous_filters = SimpleCov.filters.dup
      example.run
    ensure
      SimpleCov.instance_variable_set(:@cover_filters, previous_cover)
      SimpleCov.instance_variable_set(:@filters, previous_filters)
    end

    it "takes a project file" do
      expect(described_class.in_scope?(fixture("sample.rb"))).to be(true)
    end

    it "leaves SimpleCov's own source alone" do
      expect(described_class.in_scope?(File.expand_path("../../lib/simplecov/result.rb", __dir__))).to be(false)
    end

    it "leaves a file outside the project alone" do
      expect(described_class.in_scope?("/elsewhere/lib/thing.rb")).to be(false)
    end

    it "leaves a file a path filter skips" do
      SimpleCov.skip "condition_coverage"

      expect(described_class.in_scope?(fixture("sample.rb"))).to be(false)
    end

    it "takes a file only a block filter would skip, since that can't be decided yet" do
      SimpleCov.filters << SimpleCov::BlockFilter.new(->(source_file) { source_file.filename.include?("sample") })

      expect(described_class.in_scope?(fixture("sample.rb"))).to be(true)
    end

    it "takes a file a cover glob matches" do
      SimpleCov.cover "spec/fixtures/condition_coverage/*.rb"

      expect(described_class.in_scope?(fixture("sample.rb"))).to be(true)
    end

    it "leaves a file no cover glob matches" do
      SimpleCov.cover "lib/**/*.rb"

      expect(described_class.in_scope?(fixture("sample.rb"))).to be(false)
    end

    it "takes a file a cover block might match" do
      SimpleCov.cover "lib/**/*.rb"
      SimpleCov.cover { |source_file| source_file.filename.end_with?("never.rb") }

      expect(described_class.in_scope?(fixture("sample.rb"))).to be(true)
    end
  end

  describe ".unmeasured", mutant_expression: %w[
    SimpleCov::ConditionCoverage#unmeasured SimpleCov::ConditionCoverage#rewriter_loaded?
  ] do
    # Settled the way a run settles it, then put back however it was found:
    # absent, or answered.
    around do |example|
      memoized = described_class.instance_variable_defined?(:@rewriter_loaded)
      loaded = described_class.instance_variable_get(:@rewriter_loaded)
      described_class.rewriter_loaded?
      example.run
    ensure
      if memoized
        described_class.instance_variable_set(:@rewriter_loaded, loaded)
      elsif described_class.instance_variable_defined?(:@rewriter_loaded)
        described_class.remove_instance_variable(:@rewriter_loaded)
      end
    end

    it "names every condition at zero hits, by the tuples a measured run would" do
      expect(described_class.unmeasured("x = a && b\n")).to eq(
        [:"&&", 0, 1, 4, 1, 10] => {[:evaluated, 0, 1, 9, 1, 10] => 0, [:short_circuited, 1, 1, 6, 1, 8] => 0}
      )
    end

    it "names nothing for source Prism can't parse, even where it recovers a condition" do
      expect(described_class.unmeasured("x = a && b\ndef f(\n")).to eq({})
    end

    it "names nothing where the rewriter can't load" do
      described_class.instance_variable_set(:@rewriter_loaded, false)

      expect(described_class.unmeasured("x = a && b\n")).to eq({})
    end

    it "loads the rewriter once, however often it's asked" do
      described_class.remove_instance_variable(:@rewriter_loaded)
      allow(described_class).to receive(:require_relative).and_return(true)
      2.times { described_class.rewriter_loaded? }

      expect(described_class).to have_received(:require_relative).once
    end
  end

  describe ".merge_into", mutant_expression: %w[
    SimpleCov::ConditionCoverage#merge_into SimpleCov::ConditionCoverage#translated
  ] do
    let(:conditions) { {[:"&&", 0, 1, 0, 1, 6] => {}} }
    # Ten bytes spliced in at column 2 of line 1.
    let(:column_map) { described_class::ColumnMap.new([[1, 2, 10]]) }

    before do
      allow(hits).to receive_messages(result: {"measured.rb" => conditions}, column_maps: {"measured.rb" => column_map})
    end

    it "translates the columns of a rewritten file's branches back to the original's" do
      merged = described_class.merge_into(
        "measured.rb" => {branches: {[:if, 0, 1, 15, 1, 20] => {[:then, 1, 1, 18, 1, 19] => 1}}}
      )

      expect(merged.fetch("measured.rb").fetch(:branches)).to eq([:if, 0, 1, 5, 1, 10] => {[:then, 1, 1, 8, 1, 9] => 1})
    end

    it "translates the columns of a rewritten file's methods back to the original's" do
      merged = described_class.merge_into("measured.rb" => {methods: {["A", :m, 1, 0, 1, 30] => 2}})

      expect(merged.fetch("measured.rb").fetch(:methods)).to eq(["A", :m, 1, 0, 1, 20] => 2)
    end

    it "adds a file's conditions to what Coverage reported for it" do
      merged = described_class.merge_into("measured.rb" => {lines: [1]})

      expect(merged.fetch("measured.rb")).to eq(lines: [1], conditions: conditions)
    end

    it "starts an entry for a file Coverage didn't report" do
      expect(described_class.merge_into({}).fetch("measured.rb")).to eq(conditions: conditions)
    end

    it "keeps the files only Coverage reported" do
      expect(described_class.merge_into("other.rb" => {lines: [0]})).to include("other.rb" => {lines: [0]})
    end

    it "leaves the hash it was handed alone" do
      coverage = {"measured.rb" => {lines: [1]}}
      described_class.merge_into(coverage)

      expect(coverage).to eq("measured.rb" => {lines: [1]})
    end
  end

  describe SimpleCov::ConditionCoverage::LoadHook do
    let(:loader) do
      Class.new do
        def load_iseq(_path) = :loaded_further_down
      end.prepend(described_class).new
    end

    it "answers the instrumented sequence for a file it measures" do
      allow(SimpleCov::ConditionCoverage).to receive(:instrument).with("a.rb").and_return(:instrumented)

      expect(loader.load_iseq("a.rb")).to eq(:instrumented)
    end

    it "hands any other file on down the chain" do
      allow(SimpleCov::ConditionCoverage).to receive(:instrument).and_return(nil)

      expect(loader.load_iseq("a.rb")).to eq(:loaded_further_down)
    end

    it "answers nil, Ruby's own loading, where nothing is further down" do
      allow(SimpleCov::ConditionCoverage).to receive(:instrument).and_return(nil)
      bare = Class.new.prepend(described_class).new

      expect(bare.load_iseq("a.rb")).to be_nil
    end
  end
end
