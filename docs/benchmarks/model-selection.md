# LEO model selection

Wave 8 Task 16 is a feasibility and documentation checkpoint. The repository
currently contains a deterministic mock model only; no local model runtime,
runtime adapter, or candidate model weights are configured.

The selection is therefore intentionally **not frozen**. `leo-benchmark [backend]` runs the same 20-case fixture for each requested backend and writes one JSON object to stdout. Each metric has a nullable `value`, a `unit`, an `availability` (`measured` or `unavailable`), and an optional `reason`. Unavailable values remain `null`; the mock backend is not treated as a model-accuracy measurement.

```sh
swift run leo-benchmark mock > benchmark.json
swift run leo-benchmark candidate-a > candidate-a.json
```

For `mock`, the benchmark reports fixture-execution metrics only. Its
structured-output score is a measured zero because the canned response is not
structured model output; its timing and memory values describe the benchmark
process, not a local LLM. For any other backend name, all metrics are
`null`/`unavailable` because no adapter is configured. No real-model result is
claimed.

The corresponding runtime contract is `ModelRuntimeStatus`. Its current state
is explicitly `fixture-only`, and `isProductionReady` is false. A production
state may only be reported after a real backend and its weights are configured;
this task does not download, select, or invent either one.

Required Task 15 comparison when local backends become available:

- at least two Apple-Silicon-compatible local candidates;
- structured tool/referent accuracy on `Sources/LEOBenchmarks/Fixtures/model-cases.json`;
- TTFT, tokens/sec, and peak resident memory;
- headroom for the voice runtime under the approximately 3 GB active-memory target.

## Feasibility result

No local model runtime or downloadable candidate weights are present in this
workspace, so real-model integration is unavailable and a production model
cannot be selected without inventing measurements. Development may continue
with the deterministic mock backend for plumbing and contract tests, but Wave 8
Task 16 remains incomplete for real inference. The next implementation step is
to provide an approved Apple-Silicon-compatible backend and weights, then run
at least two candidates on the shared fixture and record reproducible results.

### Evidence inspected

- `Sources/LEO/Models/ModelHost.swift` defines the injectable `ModelBackend`
  protocol and `MockModelBackend`; it contains no real runtime integration.
- `Sources/LEOBenchmarks/main.swift` runs the 20-case fixture and correctly
  emits unavailable metrics for unconfigured backend names.
- `Sources/LEOBenchmarks/Fixtures/model-cases.json` is the shared benchmark
  corpus.

### Acceptance status

| Requirement | Status |
| --- | --- |
| Existing model-host seam documented | Complete |
| Explicit unavailable/fixture-only runtime state | Complete |
| No fabricated model or weights | Complete |
| Real local inference through text clients | Unavailable; no backend or weights configured |
| Two-candidate comparison and frozen production selection | Deferred until approved backends exist |
