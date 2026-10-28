# frozen_string_literal: true

module SimpleCov
  module ConditionCoverage
    # Prepended onto `RubyVM::InstructionSequence`'s singleton class. Ruby asks
    # `load_iseq` for every file it requires or loads, and a non-nil answer is
    # the instruction sequence it runs instead of compiling the file itself.
    # Files out of scope go on to whatever else hooks the same method, and
    # past the last hook Ruby compiles them as usual.
    module LoadHook
      def load_iseq(path)
        ConditionCoverage.instrument(path) || (super if defined?(super)) # steep:ignore UnexpectedSuper
      end
    end
  end
end
