# Computer-control performance gate

This document is the Wave 26 reporting template. It is intentionally not a
claim that semantic computer control, Screen Recording, or vision is complete.
Report implemented semantic behavior separately from fixture-only and deferred
visual behavior.

## Scope

The required routing order is native/structured context, then Accessibility
semantics, then a user-requested targeted visual capture. Continuous screenshots,
coordinate guessing, broad autonomous computer use, and a large VLM are out of
scope.

## Run identity

| Field | Result |
|---|---|
| Date / hardware / macOS | `2026-08-10 / Apple Silicon macOS 26.5.2` |
| Build configuration and exact executable | Debug / `dist/LEO.app` |
| Code-signing identity/hash | Recorded during build; full identity matrix pending |
| Warm/cold protocol and repetitions | Not run; LM Studio adapter unavailable in benchmark runner |
| Accessibility / Input Monitoring | Unit-covered; live permission matrix pending |
| Screen Recording | Not granted/live-capture unverified; deferred |

## Metrics

| Case class | Count | Success | TTFT | Tokens/sec | AX payload bytes | Context ms | Tool/action ms | Idle RSS | Peak RSS | Vision status |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Semantic implemented | 135 tests | 135/135 | unavailable | unavailable | fixture-covered | unavailable | unavailable | unavailable | unavailable | not used |
| Visual fixture / routing | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` | n/a | `TODO` | `TODO` | fixture-only |
| Screen Recording / vision | 0 | deferred | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable | deferred |

Unavailable values must remain `null`/`unavailable` in machine-readable output
with a reason; do not replace them with mock measurements.

## Evidence and gate

- [ ] One reversible semantic action passes controlled-app and supported real-app checks.
- [ ] Ambiguity, stale targets, cancellation, and denied permissions fail closed.
- [ ] No raw AX tree, screenshot, secure text, or chain-of-thought is persisted.
- [ ] Runtime logs identify the exact candidate and permission state.
- [ ] Repeated runs report latency and RSS using the same protocol.
- [ ] Screen Recording/vision is marked deferred unless explicitly authorized and exercised.

**Decision:** `BLOCKED`

The canonical 20-case benchmark executed for `qwen/qwen3-4b:2`, but the
benchmark runner has no LM Studio backend configured. TTFT, tokens/sec, and
RSS therefore remain explicitly unavailable. Live Screen Recording capture
and signed-candidate permission evidence were not exercised.

**Known limitations:** LM Studio benchmark adapter, live Accessibility matrix,
and authorized targeted capture remain before the next expansion wave.
