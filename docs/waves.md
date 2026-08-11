# LEO v0.1 — Parallelization Waves

Each wave is a merge barrier.

Tasks inside the same wave may run in parallel when they do not touch the same ownership area.

Do not begin the next wave until:

- all required tasks in the current wave are complete
- branches/worktrees are integrated
- the project builds
- relevant tests pass
- the wave checkpoint is satisfied

| Wave | Parallel work | Tasks | Suggested agents | Gate before next wave |
|---|---|---:|---:|---|
| **0 — Baseline** | Inspect repo/build/tests | **0** | 1 | Existing architecture and build state documented |
| **1 — Foundation** | App shell | **1** | 1 | Menu-bar app builds and tests |
| **2 — Independent foundations** | Core contracts · Typed hotkey · Live app context · Database · Voice hotkey · AX abstraction | **2, 5, 20, 27, 34, 53** | 3–4 | Contracts/build remain compatible |
| **3 — Build on foundations** | Sessions · Palette UI · IPC protocol · Finder context · Audio capture · MacosUse adapter | **3, 6, 9, 21, 35, 54** | 3–4 | Each subsystem independently tested |
| **4 — Core + peripheral infrastructure** | Orchestrator · File tools foundation · EventJournal · STT · Speaker enrollment · AX compression | **4, 22, 28, 36, 46, 55** | 3–4 | Shared Core works; components compile together |
| **5 — Connect first clients** | Palette→Core · IPC server · ModelHost · File identity · Speaker verification | **7, 10, 13, 24, 47** | 3–4 | Typed Core + IPC + model infrastructure functional |
| **6 — Client/model/context expansion** | Reasoning UI · CLI · Model benchmark · ReferentStore | **8, 11, 14, 25** | 3–4 | CLI connects; referent + model tests pass |
| **7 — Pick model + cross-client state** | Interactive CLI · Model selection · Cross-modality referent integration | **12, 15, 26** | 3 | Model decision frozen; CLI/palette share session |
| **8 — Real intelligence + memory retrieval** | Real model integration · Recent-activity retrieval | **16, 29** | 2 | Real local model works through text clients |
| **9 — Tool contracts + memory aliases** | Typed tool schema · Long-term aliases | **17, 30** | 2 | Tool contract frozen before tool fan-out |
| **10 — Execution foundation** | ToolBroker | **18** | 1 | Central execution path verified |
| **11 — Independent execution slices** | `apps.open` · PolicyEngine | **19, 31** | 2 | Real tool + policy pipeline works |
| **12 — Contextual + safe file behavior** | `open this` · Quarantine | **23, 32** | 2 | Current context and reversible deletion work |
| **13 — Safety/UI + voice Core connection** | Confirmation UI · Voice→Core | **33, 37** | 2 | Three clients use one Core; policy enforced |
| **14 — Voice output foundation + integrations** | TTS abstraction · Calendar · Shortcuts · Browser context | **38, 50, 51, 52** | 3–4 | TTS works; integrations independently verified |
| **15 — Voice evaluation + Accessibility tool** | Voice/TTS benchmark · Guarded semantic AX action | **39, 56** | 2 | Default voice selected; AX path proven |
| **16 — Presentation + telemetry** | Voice/typed audio policy · Resource telemetry | **40, 57** | 2 | Voice speaks, typed/CLI stay silent; metrics available |
| **17 — Interruption state + UI work** | Spoken/unspoken tracking · Voice animation · Quarantine/memory/history UI | **41, 60, 62** | 3 | Presentation state trustworthy |
| **18 — Manual interruption + palette polish** | PTT interruption · Command-palette polish | **42, 61** | 2 | Manual barge-in reliable |
| **19 — Duplex foundation** | Simultaneous mic + TTS | **43** | 1 | True simultaneous input/output proven |
| **20 — Audio fan-out** | AEC · VAD | **44, 45** | 2 | Echo suppression + speech detection independently work |
| **21 — Automatic interruption** | Barge-in detector | **48** | 1 | Owner speech can reliably stop TTS |
| **22 — Conversational interruption + runtime optimization** | Task continuation · Voice runtime unloading · LLM unload/prewarm | **49, 58, 59** | 3 | Corrections work and RAM lifecycle is sane |
| **23 — Benchmark infrastructure** | Canonical benchmark runner | **63** | 1 | Reproducible test harness exists |
| **24 — Specialized benchmarks** | Cross-modality benchmark · Duplex benchmark | **64, 65** | 2 | Both major architectural claims measured |
| **25 — Hardening** | Fix benchmark failures | **66** | 1 primary + helpers | ≥90% supported-flow reliability |
| **26 — Semantic computer control + targeted visual context + latency** | One guarded semantic action · opt-in visual fallback seam · latency/resource gate | **67, 68, 69, 70** | 2–3 | Semantic path proven; visual path bounded and permission-gated; metrics reproducible |

## Wave Flow

```text
Wave 0
└── Repository baseline

Wave 1
└── Application shell

Wave 2
├── Core contracts
├── Typed hotkey
├── Live app context
├── Database
├── Voice hotkey
└── Accessibility abstraction

        ↓ MERGE + BUILD + TEST

Wave 3
├── SessionManager
├── Command palette
├── IPC protocol
├── Finder context
├── Audio capture
└── MacosUse adapter

        ↓ MERGE + BUILD + TEST

Wave 4
├── InteractionOrchestrator
├── File tool foundation
├── EventJournal
├── Streaming STT
├── Speaker enrollment
└── AX compression

        ↓ MERGE + BUILD + TEST

Wave 5
├── Palette → Core
├── IPC server
├── ModelHost
├── File identity
└── Speaker verification

        ↓

Wave 6
├── Reasoning-status UI
├── Basic CLI
├── Model benchmark
└── ReferentStore

        ↓

Wave 7
├── Interactive CLI
├── Model selection
└── Cross-client referents

        ↓

Wave 8
├── Real model integration
└── Recent-activity retrieval

        ↓

Wave 9
├── Tool contracts
└── Long-term aliases

        ↓

Wave 10
└── ToolBroker

        ↓

Wave 11
├── apps.open
└── PolicyEngine

        ↓

Wave 12
├── "open this"
└── LEO Quarantine

        ↓

Wave 13
├── Confirmation UI
└── Voice → shared Core

        ↓

Wave 14
├── TTS
├── Calendar
├── Shortcuts
└── Browser context

        ↓

Wave 15
├── TTS/voice evaluation
└── Semantic Accessibility action

        ↓

Wave 16
├── Presentation/audio policy
└── Resource telemetry

        ↓

Wave 17
├── Spoken/unspoken tracking
├── Voice animation
└── Quarantine / Memory / History UI

        ↓

Wave 18
├── PTT interruption
└── Command-palette polish

        ↓

Wave 19
└── Simultaneous microphone + TTS

        ↓

Wave 20
├── Acoustic Echo Cancellation
└── Voice Activity Detection

        ↓

Wave 21
└── Automatic barge-in

        ↓

Wave 22
├── Interruption task continuation
├── Voice runtime unloading
└── LLM unload / prewarm

        ↓

Wave 23
└── Benchmark runner

        ↓

Wave 24
├── Cross-modality benchmark
└── Duplex voice benchmark

        ↓

Wave 25
└── Reliability hardening

        ↓

Wave 26
├── Guarded semantic computer-control slice
├── Targeted visual-context fallback (deferred unless explicitly enabled)
├── Permission/runtime evidence matrix
└── Latency and resource benchmark
```

## Parallel Execution Rules

### Recommended concurrency

Use approximately:

```text
3–4 agents at once
```

even when a wave contains more independent tasks.

Do not automatically create one agent per task.

The cost of merging six simultaneous Swift changes can outweigh the speed gained.

### Shared ownership areas

Only one active agent should modify each of these at a time unless the interface has already been frozen:

```text
InteractionOrchestrator
SessionManager
ToolBroker
ContextEngine
EntityStore
LanguageModel contracts
AssistantRequest / AssistantEvent contracts
AppState
```

### Good parallel workstreams

These are especially suitable for parallel execution once their interfaces exist:

```text
STT                 || TTS

AEC                 || VAD
                    || Speaker Verification

Calendar            || Shortcuts
                    || Browser Context

Resource Telemetry  || Voice Animation
                    || UI Polish
```

### Merge barrier rule

At the end of every wave:

1. Stop all wave agents.
2. Integrate their changes.
3. Resolve conflicts deliberately.
4. Run focused tests.
5. Run the broader project test suite.
6. Build the actual app.
7. Perform relevant runtime/manual verification.
8. Fix integration regressions.
9. Only then start the next wave.

Never allow agents in Wave N+1 to build on unmerged work from Wave N.

## Wave 26 scope and boundary

Wave 26 is a follow-on gate, not a claim that computer control is complete.
The repository already has the semantic protocol seam, mock coverage, bounded
AX compression, and permission-request hooks. Runtime permission and
controlled-app evidence remain separate gates; no real semantic inspection or
action is counted as shipped until that evidence exists.

The wave may implement one narrow, reversible semantic action through
`ToolBroker` and `PolicyEngine`, with ambiguity and permission denial failing
closed. It may define a targeted screenshot/vision seam for a user-requested
question, but continuous screenshots, broad computer use, coordinate guessing,
and a large VLM remain out of scope. Screen Recording approval and vision
runtime performance are deferred until an explicitly authorized, signed
candidate can be tested on-device.

The semantic implementation is now present behind the protocol seam, including
bounded AX traversal, secure-field redaction, an allowlisted action set, and
ToolBroker registration. The runtime permission and controlled-app evidence
gate remains open until a signed app with Accessibility approval is exercised.

## Wave 14 integration status

Calendar, Shortcuts, and browser context are integrated into the production
composition path. Calendar uses EventKit with first-needed permission;
calendar creation and Shortcut execution remain consequential ToolBroker
operations requiring confirmation. Browser context is allowlisted to Safari,
Chrome, Brave, and Arc and refreshes into `LiveState` from frontmost-app
changes using title/URL metadata only.

Evidence: the focused Wave 14 suite passes 14/14 and the full suite passes
147/147; the fresh `dist/LEO.app` builds and contains the calendar usage
description. Manual Calendar permission/read/create, two Shortcut runs, and
browser-switch verification remain open because this run cannot approve or
exercise those user-controlled macOS integrations.

Wave 26 acceptance criteria:

- [ ] One real semantic query/action works in a controlled app and two supported real-app cases.
- [ ] Accessibility/Input Monitoring status, exact executable identity, denial, cancellation, and policy decisions are recorded as runtime evidence.
- [ ] Targeted visual context is opt-in, one-shot, bounded, redacted where applicable, and unavailable without Screen Recording; no permission is requested at launch.
- [ ] TTFT, tokens/sec, AX payload size, context retrieval time, tool duration, peak RSS, and idle RSS are recorded with warm/cold labels.
- [ ] The benchmark report separates implemented semantic results, fixture-only results, and deferred/unavailable Screen Recording/vision results.

## Agent Instruction

Use this when starting execution:

> Execute `IMPLEMENTATION_PLAN.md` using the wave schedule in `PARALLELIZATION.md`.
>
> Tasks within the current wave may be delegated in parallel only when their ownership areas do not overlap.
>
> Do not begin any task from the next wave until all required tasks in the current wave have been completed, integrated, built, tested, and verified.
>
> Use 3–4 concurrent agents maximum unless there is a clear reason to use more.
>
> Shared architectural components such as `InteractionOrchestrator`, `SessionManager`, `ToolBroker`, `ContextEngine`, `EntityStore`, and the public request/event/model contracts must not be independently redesigned by multiple agents.
>
> After each wave, produce a checkpoint report containing:
>
> - tasks completed
> - files changed
> - tests run
> - build result
> - runtime/manual verification
> - integration conflicts resolved
> - known failures
> - measured RAM/latency where relevant
> - whether the next wave is safe to begin
>
> If the wave checkpoint fails, fix the current wave before continuing.
