# BPFreJIT Evaluation Experiment Spec

This document defines the experiment plan for the evaluation section.
It is organized by research question (RQ), then by experiment.
For each experiment, should reuse the current repo harnesses whenever possible rather than building new ad hoc scripts.

## Canonical RQs

- **RQ1:** How effectively does `\tool` improve the efficiency of generated native code?
- **RQ2:** How much application-level performance benefit can `\tool` deliver in realistic deployments?
- **RQ3:** What is the overhead of online re-compilation in `\tool`?
- **RQ4:** Does `\tool` preserve the existing eBPF safety model and semantic correctness of its rewrites?
- **RQ5:** How easily can `\tool` be extended with new optimization capabilities?

## Global Rules

- Reuse the repository's existing entrypoints whenever possible:
  - `make vm-micro`, `micro/driver.py`
  - `make vm-corpus`, `corpus/driver.py`
  - `make vm-e2e`, `e2e/driver.py`
  - `bpfrejit-daemon serve` plus its Unix socket JSON protocol
- Use paired comparisons on the same machine / VM / kernel image.
- Baselines must be consistent:
  - **stock** = kernel eBPF JIT without REJIT
  - **rejit** = kernel eBPF JIT after `BPF_PROG_REJIT`
  - **llvmbpf** is used only for RQ1 micro benchmarks as an upper-bound reference, not as an end-to-end baseline.
- Unless an experiment explicitly overrides them, keep the manifest defaults for iterations / warmups / repeats.
- Report both per-case results and aggregate summaries.
- For per-program or per-benchmark aggregates, use median and geomean where appropriate.
- Use 95% confidence intervals or bootstrap CIs for primary scalar comparisons.
- Keep raw JSON/Markdown outputs under the repo's results directories; keep paper figures/tables under a dedicated `docs/tmp/` or `docs/paper/generated/` path.
- Do **not** mix "unsupported / not applicable / zero-site" cases into the main speedup aggregates. Report them separately.

## Current Repo Status Labels

Use one of these labels for each experiment:
- **Existing**: harness and most logic already exist.
- **Adjust**: harness exists, but the experiment needs filtering, cleanup, or better analysis.
- **Missing**: the experiment is not yet implemented as a paper-grade measurement.

---

# RQ1. Native-code efficiency

## Intent
RQ1 is about the generated code itself, not end-to-end application benefit.
The main question is whether REJIT produces smaller and/or faster native code than the stock kernel JIT.

## Current repo coverage
- **Already available:** active micro benchmark harness, stock/kernel-rejit/llvmbpf runtimes, perf-counter support, active transform pipeline (`wide_mem`, `rotate`, `cond_select`, `branch_flip`).
- **Needs adjustment:** main figures must use only benchmark families that are actually supported by the current default pipeline.
- **Missing:** a clean paper figure that separates supported families from tracked-but-not-yet-mainlined families.

## Experiment 1.1 — Supported-family micro benchmark suite
- **Status:** Adjust
- **Goal:** Prove that `\tool` improves the efficiency of native code emitted by the kernel JIT on controlled micro benchmarks.
- **Compare with:** `stock`, `rejit`, and `llvmbpf` (upper-bound reference only).
- **Setup:**
  - Use the active micro benchmark harness (`micro/driver.py` or the paper wrapper script that calls it).
  - Start from `micro/config/micro_pure_jit.yaml`.
  - Restrict the primary paper figure to benchmarks that map to currently supported/default families:
    - `wide_mem`: at minimum `load_byte_recompose` and any other benchmark where the daemon reports `wide_mem` sites.
    - `rotate`: at minimum `rotate64_hash`, `packet_rss_hash` if present.
    - `cond_select`: at minimum `cmov_select`, `cmov_dense`.
    - `branch_flip`: optional appendix unless branch-profile injection is made fully reproducible.
  - Run all three runtimes on the same host/VM and kernel build.
- **Criteria:**
  - Runtime per iteration: `ns/op`
  - CPU cycles per iteration
  - Optional: instructions, branch-misses, i-cache related counters if available
  - Native code size: JIT image length in bytes (`jited_prog_len` or equivalent existing path)
- **Output format:**
  - Figure: normalized runtime bar chart per benchmark (`stock = 1.0`)
  - Figure: CDF of code-size reduction (`stock -> rejit`)
  - Table: geomean / median for runtime, cycles, code bytes
- **Expected results:**
  - `rejit` should outperform `stock` on most applicable benchmarks.
  - Code-size reduction should be more stable than runtime speedup.
  - `llvmbpf` may remain stronger overall, but `rejit` should recover a clear non-zero fraction of the remaining headroom.

## Experiment 1.2 — Family-sliced attribution
- **Status:** Adjust
- **Goal:** Show which transform family contributes to which type of native-code improvement.
- **Compare with:** family-grouped subsets of the same `stock` vs `rejit` results from Experiment 1.1.
- **Setup:**
  - Reuse Experiment 1.1 outputs.
  - Group results by transform family: `wide_mem`, `rotate`, `cond_select`, optional `branch_flip`.
  - Do not implement a new pass-ablation framework for the first paper version unless it already exists cleanly; a family-sliced analysis is sufficient.
- **Criteria:**
  - Median speedup per family
  - Median code-size reduction per family
  - Optional median counter deltas per family
- **Output format:**
  - Figure: grouped bar chart by family
  - Figure: benchmark × family heatmap for normalized speedup or code shrink
- **Expected results:**
  - `wide_mem` should show the most stable code-size benefit.
  - `rotate` should show clear code-size and runtime benefit on its dedicated cases.
  - `cond_select` should show the most variance because it is more workload-sensitive.

## Experiment 1.3 — Corpus site census and code-size delta
- **Status:** Adjust
- **Goal:** Show that native-code opportunities are present in real eBPF programs, not only synthetic micro benchmarks.
- **Compare with:** `stock` vs `rejit` over the real-world corpus in code-size mode.
- **Setup:**
  - Use `corpus/driver.py` in code-size-oriented mode over `corpus/config/macro_corpus.yaml`.
  - Run all corpus programs that can be built and analyzed.
  - Record, for each program:
    - whether any optimization site exists
    - total sites
    - sites by family
    - JIT size before and after REJIT
  - Break down results by subsystem/category: networking, security, observability, selftests, resource-control.
- **Criteria:**
  - Eligible-program ratio (`eligible / total`)
  - Site count per program
  - Code-size delta in bytes and percent
  - Distribution by family and subsystem
- **Output format:**
  - Figure: CDF of per-program code-size reduction
  - Figure: subsystem × family heatmap of site counts
  - Table: total programs, eligible programs, total sites, total bytes saved
- **Expected results:**
  - A non-trivial fraction of real programs should contain optimization sites.
  - Median code-size delta should be positive on the eligible subset.
  - Different subsystems should expose different family mixes.

---

# RQ2. Application-level performance benefit in realistic deployments

## Intent
RQ2 is about end-to-end or deployment-level value: do code-generation improvements produce user-visible performance gains?

## Current repo coverage
- **Already available:** end-to-end harnesses for `tracee`, `tetragon`, `bpftrace`, `scx`, and `katran`.
- **Needs adjustment:** current checked-in results are not uniformly paper-ready.
- **Missing:** a stable, publication-quality set of primary end-to-end figures.

## Inclusion rule for main-paper RQ2 results
A case qualifies for the main paper only if all three are true:
1. the case is comparable (`Comparable: True` or equivalent successful two-phase result),
2. it has non-zero eligible optimization sites, and
3. the observed difference is not dominated by a known harness artifact.

Cases that fail this rule should be reported in an appendix / limitations table, not in the primary benefit figure.

## Experiment 2.1 — Tracee end-to-end evaluation
- **Status:** Adjust
- **Goal:** Measure application-level benefit for a realistic security/observability deployment.
- **Compare with:** `stock` vs `rejit`.
- **Setup:**
  - Use `python3 e2e/driver.py tracee`.
  - Keep the current three workload classes if they can be made stable: `exec_storm`, `file_io`, `network`.
  - Before using all three in the paper, debug the current `exec_storm` anomaly. If the anomaly cannot be resolved, exclude `exec_storm` from the main figure and keep it in an appendix limitations table.
  - Run with the same tracee binary, workload duration, and kernel build for both phases.
- **Criteria:**
  - Application throughput (`bogo-ops/s`, `IOPS`, or `req/s`, depending on workload)
  - `events/s`
  - Drop counters
  - Agent CPU
  - `bpf_avg_ns`
- **Output format:**
  - Table: one row per workload, with baseline, post-rejit, and delta
  - Figure: normalized bar chart for app throughput and `bpf_avg_ns`
- **Expected results:**
  - `bpf_avg_ns` should be the most stable improvement signal.
  - App-level gains may be modest, but should generally move in the same direction when the harness is healthy.
  - Drops must remain zero or near-zero.
- **Decision rule:**
  - If one workload is clearly dominated by harness artifacts, exclude it from the primary figure and say so explicitly.

## Experiment 2.2 — Katran end-to-end evaluation
- **Status:** Adjust
- **Goal:** Measure deployment-level benefit for a realistic networking/XDP system.
- **Compare with:** `stock` vs `rejit`.
- **Setup:**
  - Use `python3 e2e/driver.py katran`.
  - Fix the current methodological issues before finalizing results:
    - remove fixed phase ordering (`stock -> rejit` only);
    - use counterbalanced or reversed order across paired runs;
    - if feasible, replace the current Python short-flow traffic driver with a lower-overhead generator; if not feasible, keep it but make the limitation explicit.
  - Keep the same topology, interface, workload model, and concurrency across phases.
- **Criteria:**
  - App throughput (`req/s`)
  - Packet PPS
  - p99 latency
  - System CPU busy
  - `bpf avg ns/run`
- **Output format:**
  - Table: baseline vs post-rejit medians
  - Figure: paired points per cycle plus median summary
- **Expected results:**
  - After fixing order bias, `bpf avg ns/run` should show the clearest benefit signal.
  - Throughput/latency gains may be small, but they should not be systematically worse than stock once the harness is cleaned up.

## Experiment 2.3 — End-to-end case qualification sweep
- **Status:** Adjust
- **Goal:** Determine which checked-in end-to-end cases are valid main-paper evidence and which should be reported only as limitations / coverage.
- **Compare with:** all active e2e cases: `tracee`, `tetragon`, `bpftrace`, `scx`, `katran`.
- **Setup:**
  - Run all checked-in end-to-end cases using their current harnesses.
  - For each case, record:
    - whether the run completed successfully,
    - whether it had non-zero eligible sites,
    - whether runtime counters were available,
    - whether known harness caveats dominate the result.
- **Criteria:**
  - Success / failure status
  - Eligible-site count
  - Counter availability (`run_cnt`, `run_time_ns`, per-program stats)
  - Comparable yes/no
- **Output format:**
  - Table: case qualification matrix with columns `Comparable`, `Eligible sites`, `Use in main paper?`, `Reason if not`
- **Expected results:**
  - `tracee` and `katran` are the most likely primary cases.
  - `tetragon` is currently a non-comparable failure case.
  - `bpftrace` and `scx` currently behave more like transparency/coverage cases than benefit cases because they report zero sites.

---

# RQ3. Online re-compilation overhead

## Intent
RQ3 measures the cost of using BPFreJIT online on live programs.
This is about the price of applying REJIT, not the benefit it produces.

## Current repo coverage
- **Already available:** `serve` mode, its JSON optimize protocol, and live integration tests.
- **Needs adjustment:** no paper-grade overhead figure exists yet.
- **Missing:** stage-level timing and steady-state daemon-overhead measurements.

## Experiment 3.1 — One-shot vs persistent server latency
- **Status:** Missing
- **Goal:** Quantify the overhead saved by keeping the daemon alive in `serve` mode instead of starting a fresh daemon process per optimize request.
- **Compare with:** per-request daemon startup + socket optimize vs long-lived `serve` socket API.
- **Setup:**
  - Use a live program with known sites, such as the integration-test program (`load_byte_recompose.bpf.o`) and optionally one larger real program.
  - Measure end-to-end wall-clock latency for repeated single-program optimizations using:
    - start `bpfrejit-daemon serve`, issue one `{"cmd": "optimize", "prog_id": ...}` request, then tear it down
    - reuse one long-lived `bpfrejit-daemon serve` instance for repeated `optimize` requests
  - Use at least 30 repetitions per mode.
- **Criteria:**
  - Total latency per optimize/apply request (`ms`)
  - p50 / p95 / max
- **Output format:**
  - Figure: boxplot or grouped bar chart
  - Table: p50/p95 summary
- **Expected results:**
  - `serve` should be meaningfully faster than one-shot mode.
  - The difference should mostly come from daemon startup / process launch overhead.

## Experiment 3.2 — Re-compilation pipeline breakdown
- **Status:** Missing
- **Goal:** Identify where online REJIT time is spent.
- **Compare with:** not a baseline comparison; this is a breakdown experiment.
- **Setup:**
  - Instrument the daemon and syscall path so that one optimize request is split into stages:
    - live-program discovery / fetch
    - get original program
    - analysis
    - rewrite
    - verifier
    - JIT
    - atomic swap / apply
  - Measure at least one small program and one larger program.
- **Criteria:**
  - Per-stage latency (`ms`), p50 and p95
  - Total latency (`ms`)
- **Output format:**
  - Figure: stacked bar or waterfall chart
- **Expected results:**
  - Verifier + JIT are likely the dominant costs.
  - Analysis/rewrite should be a minority of the total.
  - Total latency should still be small enough to justify online use.

## Experiment 3.3 — Steady-state daemon overhead
- **Status:** Missing
- **Goal:** Measure the background cost of leaving BPFreJIT enabled on a live system.
- **Compare with:** daemon off, idle `serve`, and active `serve` handling optimize requests.
- **Setup:**
  - Pick one stable long-running workload (Tracee or Katran are both acceptable once stabilized).
  - Run three modes:
    1. no daemon,
    2. idle daemon `serve`,
    3. daemon `serve` with periodic optimize requests.
  - Use identical workload duration for all modes.
- **Criteria:**
  - Daemon CPU usage
  - Daemon memory footprint
  - Incremental workload slowdown / throughput perturbation
- **Output format:**
  - Table: CPU, memory, app delta
  - Figure: grouped bar chart
- **Expected results:**
  - Idle `serve` should be near-negligible.
  - Active optimize traffic can cost more, but should remain much smaller than the application-level gain on the cases where REJIT helps.

---

# RQ4. Safety model preservation and semantic correctness

## Intent
RQ4 must clearly separate two claims:
- **Safety:** strong claim, enforced by the kernel verifier and fail-safe behavior.
- **Correctness:** empirical claim, supported by differential testing; do not present verifier output as a proof of semantic equivalence.

## Current repo coverage
- **Already available:** targeted adversarial negative tests, fuzz-based negative tests, live daemon integration smoke test.
- **Needs adjustment:** current evidence is strong for fail-safe safety but weak for semantic correctness.
- **Missing:** a dedicated differential semantic testing harness.

## Experiment 4.1 — Adversarial fail-safe rejection
- **Status:** Existing
- **Goal:** Show that invalid or malicious rewrites are rejected and that the original program remains unchanged.
- **Compare with:** valid live program vs deliberately invalid rewritten bytecode.
- **Setup:**
  - Use the existing negative tests:
    - `tests/negative/adversarial_rejit.c`
    - `tests/negative/fuzz_rejit.c`
  - Run the full adversarial suite (A01-A20 categories) and a large fuzz campaign.
  - Record verifier rejection and post-failure program state.
- **Criteria:**
  - Reject rate for invalid rewrites
  - Whether the original program stays loaded and unchanged
  - Kernel warnings / oops / panic count
- **Output format:**
  - Table: adversarial categories × result
  - Table: fuzz summary (attempts, rejects, any unexpected accepts)
- **Expected results:**
  - Invalid rewrites should be rejected.
  - The original program should remain intact.
  - Kernel crash / oops count should be zero.
- **Important note:**
  - Use verifier logs to classify safety failures, not to claim semantic correctness.

## Experiment 4.2 — Normal live-path safety and continuity
- **Status:** Existing, needs extension
- **Goal:** Show that the normal live rewrite/apply path is stable and does not produce kernel warnings or break the running program.
- **Compare with:** before vs after normal live optimize requests through `serve`.
- **Setup:**
  - Start from the existing integration test `tests/integration/vm_daemon_live.sh`.
  - Keep the current checks:
    - daemon `serve` startup
    - daemon `status`
    - daemon `optimize` dry run
    - daemon `optimize` with explicit pass override
    - `dmesg` scan for `WARNING|BUG|Oops`
  - Extend the test to record whether the target program remains attached and reachable during the `serve` session.
- **Criteria:**
  - Success/failure of each daemon stage
  - Presence of kernel warnings
  - Program continuity after apply
- **Output format:**
  - Table: live-path checks and outcomes
- **Expected results:**
  - All normal-path steps should succeed.
  - No kernel warnings should appear.
  - The rewritten program should remain live and functional.

## Experiment 4.3 — Differential semantic testing
- **Status:** Missing
- **Goal:** Provide strong empirical evidence that supported rewrites preserve program behavior.
- **Compare with:** original program vs rewritten program on identical inputs and initial state.
- **Setup:**
  - Build a differential-testing harness for all currently supported families.
  - For each test case:
    - run the original bytecode,
    - run the rewritten bytecode,
    - use the same input packet / staged input,
    - use the same initial map state,
    - compare outputs and side effects.
  - At minimum cover:
    - micro benchmarks for `wide_mem`, `rotate`, `cond_select`
    - 1–2 real corpus programs where sites exist and outputs are observable.
- **Criteria:**
  - Return-value mismatch count
  - Map-update mismatch count
  - Side-effect / emitted-event mismatch count
  - Total test cases per family
- **Output format:**
  - Table: family, tests run, mismatches
- **Expected results:**
  - Mismatch count should be zero for supported families.
  - Any mismatch found during development should be fixed before final paper reporting.
- **Important note:**
  - This experiment is the semantic-correctness evidence. Verifier acceptance alone is not enough.

---

# RQ5. Extensibility

## Intent
RQ5 must show that BPFreJIT is a framework, not just a fixed set of hand-coded passes.
The strongest version is: add one new optimization capability with low engineering cost and demonstrate that it works.

## Current repo coverage
- **Already available:** pass framework, kfunc discovery, known kfunc list includes `bpf_extract64`.
- **Needs adjustment:** current repo has the framework shell but no paper-grade "new capability added later" case study.
- **Missing:** the actual extension experiment and its evaluation.

## Recommended new capability
Use a capability that is already conceptually tracked by the repo but not part of the default pipeline.
The best candidate is **bitfield extraction** using `bpf_extract64` if feasible, because the daemon already knows about that kfunc.
If that path turns out to be blocked, the fallback is **address calculation** or **endian fusion**, but pick one and keep the paper focused.

## Experiment 5.1 — Engineering cost of adding one new capability
- **Status:** Missing
- **Goal:** Quantify how much code and kernel churn is required to add a new optimization capability.
- **Compare with:** the BPFreJIT extension path itself; optionally contrast informally with what would have been required in the in-tree kernel JIT.
- **Setup:**
  - Implement one new pass, preferably `bitfield_extract` / `extract64`.
  - Record all touched files and changed LOC in:
    - daemon
    - module / kfunc layer
    - core kernel
    - verifier
  - Record whether any new syscall/API changes were needed.
- **Criteria:**
  - LOC changed by component
  - Number of files touched
  - Whether core kernel or verifier changed
- **Output format:**
  - Table: component-wise implementation cost
- **Expected results:**
  - Most or all changes should be confined to the daemon and module/kfunc layer.
  - Core-kernel and verifier changes should be zero or near-zero.

## Experiment 5.2 — Benefit demonstration of the new capability
- **Status:** Missing
- **Goal:** Show that the new capability is not only easy to add, but also useful.
- **Compare with:** `stock` vs `rejit` before and after adding the new capability.
- **Setup:**
  - Use at least:
    - one dedicated micro benchmark for that family (reuse an existing benchmark if present in `micro_pure_jit.yaml`; otherwise add one minimal pure-JIT benchmark), and
    - one real corpus program with at least one matching site.
  - Report both site counts and performance/code-size impact.
- **Criteria:**
  - Site count found by the new pass
  - Code-size delta
  - Runtime delta on the dedicated benchmark
- **Output format:**
  - Table: before/after site coverage and performance
  - Optional code diff snippet for one representative site
- **Expected results:**
  - The new capability should trigger on at least one benchmark and at least one real program.
  - It should produce a measurable benefit on its dedicated benchmark.

## Experiment 5.3 — Capability availability / graceful degradation
- **Status:** Missing
- **Goal:** Show that extensibility remains safe even when the new capability is unavailable at runtime.
- **Compare with:** module loaded vs module absent (or capability enabled vs disabled).
- **Setup:**
  - For the new capability, run three states if applicable:
    1. capability available,
    2. capability unavailable,
    3. capability removed after being available.
  - Observe whether the daemon safely skips, rejects, or falls back without breaking the system.
- **Criteria:**
  - Apply success / reject status
  - Whether the program remains runnable
  - Whether performance falls back cleanly to stock/rejit-without-that-pass behavior
- **Output format:**
  - Table: state vs behavior
- **Expected results:**
  - Missing capability should never compromise safety.
  - The worst case should be "optimization not applied," not kernel breakage.
