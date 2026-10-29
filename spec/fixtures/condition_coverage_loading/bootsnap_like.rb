# frozen_string_literal: true

# Stands in for bootsnap's compile cache, whose hook never calls `super`: it
# answers nil whenever Coverage is running, and its cache otherwise. It
# installs the same way.
module Bootsnap
  module CompileCache
    module ISeq
      module InstructionSequenceMixin
        def load_iseq(_path)
          nil
        end
      end
    end
  end
end

class << RubyVM::InstructionSequence
  prepend(Bootsnap::CompileCache::ISeq::InstructionSequenceMixin)
end
