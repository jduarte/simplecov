# frozen_string_literal: true

# Loaded via RUBYOPT=-r.../spike/boot.rb. Instruments every file under
# SPIKE_CC_SCOPE and dumps per-process condition results to SPIKE_CC_OUT.
# Prism is required lazily, on the first in-scope load, so bundler has
# already picked the gem version by then.

if (scope = ENV["SPIKE_CC_SCOPE"]) && defined?(RubyVM::InstructionSequence)
  module SpikeCCBoot
    SCOPE = ENV.fetch("SPIKE_CC_SCOPE")

    module EarlyHook
      def load_iseq(path)
        if path.start_with?(SpikeCCBoot::SCOPE) && !defined?(::SpikeCC)
          require_relative "condition_coverage"
          ::SpikeCC.install!(SpikeCCBoot::SCOPE)
          return ::SpikeCC.instrument(path) || (defined?(super) ? super : nil)
        end
        defined?(super) ? super : nil
      end
    end
  end

  RubyVM::InstructionSequence.singleton_class.prepend(SpikeCCBoot::EarlyHook)

  at_exit do
    next unless defined?(::SpikeCC) && (out = ENV["SPIKE_CC_OUT"])

    require "json"
    Dir.mkdir(out) unless Dir.exist?(out)
    payload = SpikeCC.result.transform_values { |t| t.map { |k, arms| [k, arms.to_a] } }
    File.write(File.join(out, "#{Process.pid}.json"), JSON.dump(payload))
  end
end
