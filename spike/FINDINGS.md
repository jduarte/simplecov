# Phase 0 spike: findings

Throwaway prototype of condition coverage (`&&`, `||`, `and`, `or`, `&&=`, `||=`) built by rewriting source with Prism at load time (`spike/condition_coverage.rb`, `spike/boot.rb`). All results below are from Ruby 3.4.10 on arm64-darwin.

**Verdict: go.** The approach holds up on real code. Phase 1 has to address two fixes and one tuning item.

## 1. The rewriter holds up on real code

- I rewrote every `.rb` file under this repo's `lib/`, `spec/` and `test_projects/`, the 3.4.10 stdlib, and all installed gems: **34,542 files and 82,379 conditions**.
  - By kind: 36,808 `&&`, 31,877 `||`, 13,613 `||=` and 81 `&&=`.
  - **Failures: 0.** Every rewritten file still parses with Prism, compiles with `RubyVM::InstructionSequence.compile`, and keeps the same line count. (71 files that didn't compile before rewriting were skipped.)
- Nesting is handled by ordering insertions at the same offset: closers first, innermost first; openers outermost first. This covers `a && b && c`, `a || b && c`, `h[k] ||= (k and :v)`, heredoc operands, the `def … = a or return` precedence case, and multi-line operands.

## 2. SimpleCov's own suite still passes with `lib/` instrumented

I ran `bundle exec rake spec` with `RUBYOPT=-rspike/boot.rb`, which instruments `lib/` in every process, including the sandbox subprocesses.

| | examples | failures | wall time |
|---|---|---|---|
| baseline | 6391 | 0 | 176s |
| instrumented | 6391 | 4 | 166s |

- **The 4 failures** are all in `spec/unloadable_prism_spec.rb`. That spec simulates a Ruby where Prism can't load, and the spike requires Prism with no fallback. *Phase 1:* `condition_coverage_supported?` must rescue `LoadError` and turn the criterion off.
- **Dogfood stayed at 100%.** Its only uncovered entries were in the spike file itself, which sits under the project root. Instrumentation adds no lines, branches or methods, and line/branch/method `Coverage` is still recorded for rewritten files (iseq.c sets coverage up on the `ISeq.compile` path).
- **Wall time** shows no measurable overhead at suite level; the difference is noise.

## 3. What it found in SimpleCov's own suite

- 439 conditions measured, against 440 found statically (one file never loads on this platform). 862 of 878 arms are covered (98.18%), even though the suite has 100% line and branch coverage.
- **15 arms never short-circuited.** Most are `||=` memoization that is never hit a second time, e.g. `source_file.rb:64`, `file_list.rb:24`, `configuration/thresholds.rb:124`.
- **1 right operand never evaluated:** `cli/affected/runner.rb:34`. It is already inside `# simplecov:disable branch`, so a `:condition` directive category would cover it.
- **Some arms can never be hit:** `stdout.puts(usage) || 0` (`cli.rb:92-93`) can never short-circuit, because `puts` always returns nil. *Phase 3/5:* document this, and consider ignore types or directives for such idioms.

## 4. Overhead (micro-benchmark, worst case)

Tested on a hot loop of nothing but boolean operations (5M iterations × 4 operators):

| | plain | instrumented |
|---|---|---|
| interpreter | 46 ns per op | 129 ns per op (2.8×) |
| YJIT | 25 ns per op | 50 ns per op (2.0×) |

Most of the cost is the method call used to count left-operand outcomes (`SpikeCC.a(f, k, (a))`). *Phase 1:* benchmark replacing it with inline counters, `(H[f][e] += 1; a && (H[f][r] += 1; b))` with skips = e − r. The trade-off is that if `a` raises, that evaluation counts as a skip. Also try binding a per-file hits constant to save one index lookup.

## 5. Bootsnap

- bootsnap's `InstructionSequenceMixin#load_iseq` does `return nil if Coverage.running?` **without calling super**, so any hook below it in the chain is never reached.
- When bootsnap loads after SimpleCov starts (the usual Rails order: `SimpleCov.start`, then `config/boot`, then `bootsnap/setup`), the control run was **not instrumented**. Line coverage was unaffected.
- **Fix, verified:** if bootsnap is already loaded, prepend our hook into `Bootsnap::CompileCache::ISeq::InstructionSequenceMixin`. If not, watch with `TracePoint(:class)` and prepend when that module is defined. Instrumentation then works in both orders. *Phase 1:* ship this, with a sandbox spec.
- Environment note: on this machine, `require "bootsnap"` alone already installs the mixin.

## Carry into Phase 1

1. Prism `LoadError` → condition coverage is unsupported, warn, carry on.
2. bootsnap mixin handling plus a spec.
3. Choose the counter strategy using the benchmark above.
4. `:condition` directive category (needed even for SimpleCov's own code).
5. Exclude SimpleCov's own instrumentation from its dogfood report.
