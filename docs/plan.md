# Implementation Plan: LEO v0.1

## Local Execution Orchestrator

**Source of truth:** `PRD.md` + `TECHNICAL_SPEC.md`
**Platform:** macOS / Apple Silicon
**Primary language:** Swift 6
**Target:** Useful local Alpha first; polish second
**Active memory target:** approximately ≤3 GB
**Idle memory target:** <300 MB

---

# 1. Objective

Build LEO as one shared local assistant core with three clients:

```text
Voice
   \
Text Palette ───► LEO Core ───► Context / Model / Tools
   /
CLI
```

The implementation must prove these things early:

1. Typed commands can execute useful Mac actions.
2. CLI and GUI share one session/core.
3. The local model is capable enough within the RAM budget.
4. Context/referents work across modalities.
5. Destructive actions remain reversible.
6. Voice can later plug into the same architecture without duplicating agent logic.
7. Continuous listening/barge-in is feasible without breaking the resource budget.

---

# 2. Non-Negotiable Architecture Rules

Do not violate these during implementation:

* Voice, typed palette, and CLI are clients of one shared LEO Core.
* Clients never implement their own reasoning or tools.
* Typed and CLI interactions are silent by default.
* Typed output only speaks after explicit user action.
* Voice interactions may speak automatically.
* All clients share session state, context, entities, and referents.
* Tool calls are typed and schema validated.
* Every consequential tool call passes through `PolicyEngine`.
* Model-facing deletion means LEO Quarantine.
* No ordinary permanent-delete tool exists.
* CLI cannot bypass trusted GUI confirmation.
* Core CLI IPC is local-only.
* No TCP/HTTP server for v0.1.
* Context collection is event-driven.
* Do not continuously run the LLM.
* Do not continuously capture screenshots.
* Main-model and voice runtimes must be independently unloadable.
* Reasoning UI shows concise summaries, never raw chain-of-thought.
* Prefer native/semantic APIs over Accessibility.
* Prefer Accessibility over vision.
* Target approximately ≤3 GB active memory.

---

# 3. High-Level Dependency Graph

```text
Application shell
      │
      ▼
Shared request/event contracts
      │
      ▼
SessionManager + Orchestrator shell
      │
      ├──────────────────┐
      ▼                  ▼
Text Palette        Local IPC + CLI
      │                  │
      └─────────┬────────┘
                ▼
          Local Model Host
                │
                ▼
        Structured Tool System
                │
                ▼
        First Real Mac Action
                │
       ┌────────┴─────────┐
       ▼                  ▼
  Context System       Safety Layer
       │                  │
       ▼                  ▼
 Cross-modal          Quarantine
 referents            + Policy
       │
       └────────┬─────────┘
                ▼
             Voice
                │
       ┌────────┼─────────┐
       ▼        ▼         ▼
      STT      TTS    Audio Engine
                         │
                         ▼
                     Duplex Audio
                    /      |       \
                  AEC     VAD   Speaker ID
                         │
                         ▼
                      Barge-in
                         │
                         ▼
                  Native integrations
                         │
                         ▼
                  Reliability / polish
```

---

# 4. Phase 0 — Repository Baseline

## Task 0: Establish repository baseline

**Description:**
Before making architectural changes, inspect the existing project and document what already exists. Do not rewrite working components just to match filenames in the spec.

**Acceptance criteria:**

* [ ] Current targets, packages, app entry points, and test targets are identified.
* [ ] Existing relevant code is mapped to the LEO architecture.
* [ ] Build/test baseline is recorded before modifications.

**Verification:**

* [ ] Run current build successfully or document existing failures.
* [ ] Run current tests and record baseline.
* [ ] Create/update `Docs/current-architecture.md`.

**Dependencies:** None

**Files likely touched:**

* `Docs/current-architecture.md`

**Estimated scope:** S

---

# Checkpoint 0 — Known Starting State

Before implementation:

* [ ] Existing build health is known.
* [ ] Existing useful code has been identified.
* [ ] No duplicate implementation is planned unnecessarily.

---

# 5. Phase 1 — Shared Core Contracts

## Task 1: Establish LEO application shell

**Description:**
Ensure the project runs as a native menu-bar utility with a clean application entry point and shared application state.

**Acceptance criteria:**

* [ ] App launches as a menu-bar utility.
* [ ] Basic menu contains status, Settings, and Quit.
* [ ] Core application state exists independently from individual UI clients.

**Verification:**

* [ ] `xcodebuild` succeeds.
* [ ] Test target succeeds.
* [ ] Manual launch/quit test passes.

**Dependencies:** Task 0

**Files likely touched:**

* `LEO/App/LEOApp.swift`
* `LEO/App/AppState.swift`
* `LEO/UI/MenuBar/MenuBarView.swift`
* tests

**Estimated scope:** M

---

## Task 2: Define shared request and event contracts

**Description:**
Implement modality-independent Core contracts before building any client behavior.

Required types:

```text
AssistantRequest
AssistantInput
RequestSource
PresentationPreference
AssistantEvent
```

**Acceptance criteria:**

* [ ] Voice, text, and CLI requests can use the same request type.
* [ ] Event stream supports reasoning status, actions, responses, confirmations, and failure.
* [ ] Typed/CLI presentation defaults explicitly disable speech.

**Verification:**

* [ ] Codable round-trip tests pass.
* [ ] Request source does not affect permissions.
* [ ] Tests assert typed/CLI `speakResponse == false`.

**Dependencies:** Task 1

**Files likely touched:**

* `LEO/Core/AssistantRequest.swift`
* `LEO/Core/AssistantEvent.swift`
* `LEO/Core/PresentationPreference.swift`
* tests

**Estimated scope:** S

---

## Task 3: Implement SessionManager and ConversationState

**Description:**
Create one default session shared by all primary clients.

**Acceptance criteria:**

* [ ] Default session persists across multiple requests.
* [ ] Conversation state stores recent turns, active task, and referents.
* [ ] Session ownership is independent from modality.

**Verification:**

* [ ] Unit test alternates `.commandPalette`, `.cli`, `.voice` requests using one session.
* [ ] State persists between calls.
* [ ] New isolated session can be created internally.

**Dependencies:** Task 2

**Files likely touched:**

* `LEO/Core/SessionManager.swift`
* `LEO/Core/ConversationState.swift`
* `LEO/Core/TaskState.swift`
* tests

**Estimated scope:** M

---

## Task 4: Implement Orchestrator shell using a mock model

**Description:**
Build the central async request/event lifecycle using a fake model and no real tools yet.

**Acceptance criteria:**

* [ ] `submit(request)` returns streamed `AssistantEvent`s.
* [ ] Request enters correct session.
* [ ] Mock response can stream reasoning status and final response.
* [ ] Orchestrator contains no UI-specific behavior.

**Verification:**

* [ ] Unit test receives ordered event stream.
* [ ] Cancellation terminates the mock request.
* [ ] Same orchestrator handles all RequestSource values.

**Dependencies:** Tasks 2–3

**Files likely touched:**

* `LEO/Core/InteractionOrchestrator.swift`
* `LEO/Models/MockLanguageModel.swift`
* tests

**Estimated scope:** M

---

# Checkpoint A — Shared Core

Required architecture:

```text
AssistantRequest
       ↓
SessionManager
       ↓
InteractionOrchestrator
       ↓
AssistantEvent stream
```

* [ ] Build passes.
* [ ] Tests pass.
* [ ] No client-specific agent logic exists.

---

# 6. Phase 2 — Typed LEO First

Typed interaction is deliberately implemented before voice because it lets us validate the assistant without debugging audio at the same time.

## Task 5: Implement typed global hotkey

**Description:**
Add a configurable hotkey for the command palette.

Initial candidate:

```text
⌥⇧ Space
```

**Acceptance criteria:**

* [ ] Hotkey works while another app is frontmost.
* [ ] Hotkey can be changed later without rewriting client logic.
* [ ] Voice and text shortcuts have separate identifiers.

**Verification:**

* [ ] Manual test from Finder, browser, and Xcode.
* [ ] Registration/unregistration tests where practical.

**Dependencies:** Task 1

**Files likely touched:**

* `LEO/App/HotkeyManager.swift`
* tests

**Estimated scope:** S

---

## Task 6: Build command palette window

**Description:**
Create the compact keyboard-first typed interface using `NSPanel` + SwiftUI.

**Acceptance criteria:**

* [ ] Hotkey opens palette quickly.
* [ ] Text field immediately has focus.
* [ ] Return submits.
* [ ] Escape closes.
* [ ] Palette does not become a full chat window.

**Verification:**

* [ ] Manual keyboard-only interaction.
* [ ] Window focus behavior verified while other apps are active.
* [ ] Repeated open/close does not create extra windows.

**Dependencies:** Task 5

**Files likely touched:**

* `LEO/UI/CommandPalette/CommandPaletteController.swift`
* `LEO/UI/CommandPalette/CommandPaletteView.swift`
* `LEO/Clients/Text/TextClientController.swift`
* tests

**Estimated scope:** M

---

## Task 7: Connect typed palette to Core

**Description:**
Submit typed input as `AssistantRequest(source: .commandPalette)` and render streamed events.

**Acceptance criteria:**

* [ ] Typed text reaches the shared Orchestrator.
* [ ] Reasoning/action/result events render incrementally.
* [ ] No TTS is invoked automatically.
* [ ] Response contains optional explicit speak button.

**Verification:**

* [ ] Mock request visibly streams status/result.
* [ ] Automated test verifies no speech invocation occurs.
* [ ] Explicit speaker button can call a mock TTS service but does not alter default behavior.

**Dependencies:** Tasks 4, 6

**Files likely touched:**

* `LEO/Clients/Text/TextClientController.swift`
* `LEO/UI/CommandPalette/CommandPaletteView.swift`
* tests

**Estimated scope:** M

---

## Task 8: Implement varied reasoning-status presentation

**Description:**
Add UI rules for concise non-repetitive reasoning/progress summaries.

**Acceptance criteria:**

* [ ] Trivial actions show direct status such as `Opening Xcode…`.
* [ ] Non-trivial work can display `reasoningSummary`.
* [ ] Same conversational opener is not repeatedly rendered back-to-back.
* [ ] No raw model reasoning is displayed.

**Verification:**

* [ ] Unit tests for status deduplication/repetition rules.
* [ ] Manual scenarios show natural status variation.
* [ ] Raw chain-of-thought fields do not exist in public Core API.

**Dependencies:** Task 7

**Files likely touched:**

* `LEO/UI/CommandPalette/StatusPresenter.swift`
* `LEO/UI/CommandPalette/CommandPaletteView.swift`
* tests

**Estimated scope:** S

---

# Checkpoint B — Typed Assistant Shell

Required:

```text
typed hotkey
↓
palette
↓
"hello"
↓
shared Core
↓
reasoning/action event
↓
text result
```

* [ ] Completely silent unless 🔊 is explicitly pressed.
* [ ] Build and tests pass.

---

# 7. Phase 3 — Local IPC and CLI

## Task 9: Define IPC protocol

**Description:**
Define framed local messages for AssistantRequests and AssistantEvents.

**Acceptance criteria:**

* [ ] Protocol supports streaming multiple events per request.
* [ ] Invalid/malformed messages are rejected.
* [ ] Protocol has explicit version field.

**Verification:**

* [ ] Encoding/decoding tests.
* [ ] Invalid payload tests.
* [ ] Large/partial frame handling tested.

**Dependencies:** Task 2

**Files likely touched:**

* `LEO/IPC/IPCMessage.swift`
* `LEO/IPC/IPCFraming.swift`
* tests

**Estimated scope:** S

---

## Task 10: Implement same-user Unix socket server

**Description:**
Expose the shared Core locally through a user-only Unix-domain socket.

Suggested location:

```text
~/Library/Application Support/LEO/runtime/leo.sock
```

**Acceptance criteria:**

* [ ] No TCP/HTTP listener exists.
* [ ] Runtime directory uses restrictive permissions.
* [ ] Request is forwarded to shared Orchestrator.
* [ ] AssistantEvents stream back to client.

**Verification:**

* [ ] IPC integration test.
* [ ] Verify no TCP listener.
* [ ] Check directory/socket permissions.
* [ ] Malformed clients cannot crash LEO.

**Dependencies:** Tasks 4, 9

**Files likely touched:**

* `LEO/IPC/LocalIPCServer.swift`
* `LEO/IPC/LocalIPCConnection.swift`
* tests

**Estimated scope:** M

---

## Task 11: Build basic `leo` CLI

**Description:**
Create separate executable target that submits one natural-language request.

Example:

```bash
leo "open Xcode"
```

**Acceptance criteria:**

* [ ] Connects to running LEO.
* [ ] Streams text events to terminal.
* [ ] Does not contain model/tool/context code.
* [ ] Produces no voice output.

**Verification:**

* [ ] CLI → socket → mock Core end-to-end.
* [ ] `leo "hello"` prints result.
* [ ] Search binary/project for prohibited duplicate agent implementation.

**Dependencies:** Task 10

**Files likely touched:**

* `LEOCLI/main.swift`
* `LEOCLI/CLIClient.swift`
* `LEOCLI/TerminalRenderer.swift`
* tests

**Estimated scope:** M

---

## Task 12: Add CLI interactive mode

**Description:**
Running `leo` with no request starts a simple REPL using the shared default session.

**Acceptance criteria:**

* [ ] Multiple turns use same session.
* [ ] Ctrl-D exits cleanly.
* [ ] Ctrl-C cancels appropriate active request.
* [ ] Output stays silent.

**Verification:**

* [ ] Manual multi-turn test.
* [ ] Automated session-continuity test over IPC.

**Dependencies:** Task 11

**Files likely touched:**

* `LEOCLI/main.swift`
* `LEOCLI/InteractiveSession.swift`
* tests

**Estimated scope:** S

---

# Checkpoint C — One Core, Two Clients

Required:

```text
Palette:
"remember the word falcon for this conversation"

CLI:
"what word did I just give you?"
```

Using mock/session logic, both calls must prove they see the same state.

---

# 8. Phase 4 — Main Local Model Feasibility

This is a fail-fast phase.

Do not build dozens of tools before proving the model fits and performs adequately.

## Task 13: Implement LanguageModel protocol and ModelHost

**Description:**
Create replaceable local-model infrastructure.

**Acceptance criteria:**

* [ ] Model backend is hidden behind `LanguageModel`.
* [ ] `prepare`, stream response, cancel, unload all work.
* [ ] Runtime memory can be measured.
* [ ] No client imports concrete model runtime types.

**Verification:**

* [ ] Mock + real backend satisfy same contract.
* [ ] Load/unload repeatedly without obvious leak.
* [ ] Cancellation test.

**Dependencies:** Task 4

**Files likely touched:**

* `LEO/Models/LanguageModel.swift`
* `LEO/Models/ModelHost.swift`
* `LEO/Models/ModelRequest.swift`
* tests

**Estimated scope:** M

---

## Task 14: Create LEO-specific model benchmark

**Description:**
Build a small test corpus focused on actual LEO reasoning instead of generic benchmarks.

Include at least:

```text
open Xcode
open this
move this to Downloads
find the PDF from earlier
use the other one
trash this
undo that
what is next on my calendar?
```

**Acceptance criteria:**

* [ ] At least 20 test prompts.
* [ ] Measures structured output correctness.
* [ ] Measures TTFT, tokens/sec, and peak RAM.

**Verification:**

* [ ] Benchmark outputs machine-readable results.
* [ ] Same corpus runs against multiple backends.

**Dependencies:** Task 13

**Files likely touched:**

* `LEOBenchmarks/ModelBenchmark.swift`
* `LEOBenchmarks/Fixtures/model-cases.json`
* docs

**Estimated scope:** M

---

## Task 15: Select the main local model

**Description:**
Benchmark realistic candidate models and choose the best one for LEO's RAM/reliability constraints.

**Acceptance criteria:**

* [ ] At least two realistic candidates compared if available.
* [ ] Selection rationale includes RAM and tool accuracy.
* [ ] Selected model leaves plausible headroom for voice runtime.

**Verification:**

* [ ] Results saved to `Docs/benchmarks/model-selection.md`.
* [ ] Peak model-only memory recorded.
* [ ] Tool/referent cases manually inspected.

**Dependencies:** Task 14

**Files likely touched:**

* benchmark files
* `Docs/benchmarks/model-selection.md`

**Estimated scope:** S

---

## Task 16: Replace mock model in Core

**Description:**
Use selected local model from both typed palette and CLI.

**Acceptance criteria:**

* [ ] Typed queries use real local inference.
* [ ] CLI queries use the same loaded model.
* [ ] Model loads only once inside LEO Core.
* [ ] No internet dependency.

**Verification:**

* [ ] Typed response test.
* [ ] CLI response test.
* [ ] Confirm only one model instance/resident copy.

**Dependencies:** Tasks 13–15

**Files likely touched:**

* `LEO/Core/InteractionOrchestrator.swift`
* `LEO/Models/ModelHost.swift`
* app composition root
* tests

**Estimated scope:** M

---

# Checkpoint D — Real Local Text LEO

At this stage:

```text
Text hotkey → local LLM → text response
CLI         → same LLM → text response
```

Record:

* [ ] RAM
* [ ] TTFT
* [ ] warm latency
* [ ] cold latency

If the model alone consumes too much memory, resolve it **before continuing**.

---

# 9. Phase 5 — Structured Tool Execution

## Task 17: Implement tool contracts and schema validation

**Description:**
Create typed `ToolDefinition`, `ToolProposal`, `ToolResult`, effects, and idempotency metadata.

**Acceptance criteria:**

* [ ] Invalid tool name rejected.
* [ ] Invalid arguments rejected.
* [ ] Model cannot submit arbitrary code disguised as tool args.
* [ ] Each tool declares effect and idempotency.

**Verification:**

* [ ] Comprehensive schema tests.
* [ ] Fuzz/invalid-input tests where practical.

**Dependencies:** Task 16

**Files likely touched:**

* `LEO/Tools/ToolDefinition.swift`
* `LEO/Tools/ToolProposal.swift`
* `LEO/Tools/ToolResult.swift`
* tests

**Estimated scope:** M

---

## Task 18: Implement ToolBroker

**Description:**
Create central registry/execution broker.

**Acceptance criteria:**

* [ ] Tool lookup and validation centralized.
* [ ] Execution produces normalized result.
* [ ] Timeout/cancellation handled.
* [ ] Every tool call receives unique trace ID.

**Verification:**

* [ ] Mock tools prove registration/execution.
* [ ] Unknown tool fails safely.

**Dependencies:** Task 17

**Files likely touched:**

* `LEO/Tools/ToolBroker.swift`
* `LEO/Diagnostics/ToolTrace.swift`
* tests

**Estimated scope:** M

---

## Task 19: Implement `apps.open` vertical slice

**Description:**
Make the first actual end-to-end Mac action work.

Example:

```text
open Xcode
```

**Acceptance criteria:**

* [ ] Model produces `apps.open`.
* [ ] App lookup resolves installed application.
* [ ] `NSWorkspace` opens/activates it.
* [ ] Result is verified before LEO says it succeeded.

**Verification:**

* [ ] Test using provider abstraction.
* [ ] Manually open five installed apps.
* [ ] Invalid app name does not hallucinate success.

**Dependencies:** Task 18

**Files likely touched:**

* `LEO/Tools/Apps/AppTools.swift`
* `LEO/Tools/Apps/AppProvider.swift`
* Orchestrator integration
* tests

**Estimated scope:** M

---

# Checkpoint E — First Useful Command

Required:

```text
⌥⇧ Space
> open Xcode

Opening Xcode…
Opened.
```

and:

```bash
leo "open Xcode"
```

must perform the exact same Core/tool flow.

---

# 10. Phase 6 — Live Context and Files

## Task 20: Implement frontmost-application LiveState

**Description:**
Observe current application without LLM polling.

**Acceptance criteria:**

* [ ] State updates on app activation.
* [ ] Current bundle/name is available to Context Engine.
* [ ] Observation adds negligible idle load.

**Verification:**

* [ ] Manual app-switch test.
* [ ] Unit tests for state updates.

**Dependencies:** Task 1

**Files likely touched:**

* `LEO/Context/ContextEngine.swift`
* `LEO/Context/LiveState.swift`
* `LEO/Context/WorkspaceContextProvider.swift`
* tests

**Estimated scope:** S

---

## Task 21: Implement Finder selection context

**Description:**
Track selected Finder file(s) and convert them into entities.

**Acceptance criteria:**

* [ ] Current Finder selection can be retrieved.
* [ ] Files have stable LEO entity IDs.
* [ ] Secure/unrelated Finder data is not dumped into model context.

**Verification:**

* [ ] Select PDF/image/folder and inspect debug state.
* [ ] Selection replacement updates correctly.

**Dependencies:** Task 20

**Files likely touched:**

* `LEO/Context/FinderContextProvider.swift`
* `LEO/Context/EntityStore.swift`
* tests

**Estimated scope:** M

---

## Task 22: Implement core file tools

Implement:

```text
files.inspect
files.open
files.reveal
files.move
files.rename
```

**Acceptance criteria:**

* [ ] Operations work on real temporary files.
* [ ] EntityStore updates after move/rename.
* [ ] Collisions/errors return explicit failure.

**Verification:**

* [ ] Integration tests against temporary directories.
* [ ] Manual Finder tests.

**Dependencies:** Tasks 18, 21

**Files likely touched:**

* `LEO/Tools/Files/FileTools.swift`
* `LEO/Tools/Files/FileProvider.swift`
* `LEO/Context/EntityStore.swift`
* tests

**Estimated scope:** M

---

## Task 23: Implement "open this"

**Description:**
Inject compact LiveState into model requests.

**Acceptance criteria:**

* [ ] Finder selection is available as relevant current context.
* [ ] `open this` opens selected file.
* [ ] Model request remains compact.
* [ ] No giant AX/Finder dump.

**Verification:**

* [ ] Integration test using synthetic LiveState.
* [ ] Manual PDF/folder/image tests.

**Dependencies:** Tasks 21–22

**Files likely touched:**

* `LEO/Context/ContextRetriever.swift`
* `LEO/Core/InteractionOrchestrator.swift`
* tests

**Estimated scope:** M

---

# Checkpoint F — Contextual Typed Commands

Required:

```text
Select file in Finder

Typed:
open this
```

and:

```bash
leo "open this"
```

must both resolve the selected file from the same LiveState.

---

# 11. Phase 7 — Entities and Cross-Modality Referents

## Task 24: Complete EntityStore identity/update behavior

**Description:**
Ensure files retain identity across moves and renames.

**Acceptance criteria:**

* [ ] File entity retains same ID after move.
* [ ] Previous paths retained as history.
* [ ] Resource identifier used where available.

**Verification:**

* [ ] Move/rename entity tests.
* [ ] Restart persistence if EntityStore is already durable; otherwise persistence added later with DB task.

**Dependencies:** Task 22

**Estimated scope:** M

---

## Task 25: Implement ReferentStore

**Description:**
Track high-salience recent entities so `it`, `that`, etc. resolve deterministically when possible.

**Acceptance criteria:**

* [ ] Recent tool result gains referent.
* [ ] Referent salience decays/reorders.
* [ ] Same referent shared across clients through session.

**Verification:**

* [ ] Unit tests for `it`, `that file`, result ordering.
* [ ] Cross-source session test.

**Dependencies:** Tasks 3, 24

**Files likely touched:**

* `LEO/Context/ReferentStore.swift`
* `LEO/Core/ConversationState.swift`
* tests

**Estimated scope:** M

---

## Task 26: Implement cross-modality follow-up flow

**Description:**
Make this a required integration path:

```text
Typed:
open this

CLI:
move it to Downloads
```

**Acceptance criteria:**

* [ ] CLI resolves `it` to typed request's entity.
* [ ] Entity path updates after tool call.
* [ ] Further typed request can still refer to it.

**Verification:**

* [ ] Automated integration test.
* [ ] Manual three-turn test alternating clients.

**Dependencies:** Tasks 23–25

**Estimated scope:** S

---

# Checkpoint G — Shared Assistant Identity

Required:

```text
Typed → file entity
CLI   → "move it"
Typed → "open it"
```

All must operate on one entity.

---

# 12. Phase 8 — Persistent Activity Memory

## Task 27: Add SQLite storage and migrations

**Description:**
Establish local durable database infrastructure.

**Acceptance criteria:**

* [ ] Database initializes safely.
* [ ] Migration mechanism exists.
* [ ] Tests can use temporary/in-memory database.

**Verification:**

* [ ] Fresh install database test.
* [ ] Migration test.
* [ ] Corrupt/missing database fails safely.

**Dependencies:** Task 1

**Files likely touched:**

* `LEO/Storage/Database.swift`
* `LEO/Storage/Migrations.swift`
* tests

**Estimated scope:** M

---

## Task 28: Implement EventJournal

**Description:**
Persist meaningful app/file/assistant events.

**Acceptance criteria:**

* [ ] Events contain timestamp/type/source/entity/sensitivity.
* [ ] Recency/entity indexes exist.
* [ ] Duplicate/noisy events are filtered.
* [ ] Tool actions are recorded.

**Verification:**

* [ ] Persistence tests.
* [ ] Event-query tests.
* [ ] Five-minute manual usage does not produce unreasonable event volume.

**Dependencies:** Tasks 20, 27

**Files likely touched:**

* `LEO/Context/EventJournal.swift`
* database migration
* tests

**Estimated scope:** M

---

## Task 29: Implement recent-activity retrieval

**Description:**
Retrieve relevant history using simple rules before adding embeddings.

Rank using:

* referent
* current state
* recency
* entity type
* keyword
* alias

**Acceptance criteria:**

* [ ] Recent matching files/apps can be found.
* [ ] Result count/context size bounded.
* [ ] No embedding model required.

**Verification:**

* [ ] Synthetic event-ranking tests.
* [ ] `open the PDF from earlier` scenario.

**Dependencies:** Tasks 25, 28

**Files likely touched:**

* `LEO/Context/ContextRetriever.swift`
* `LEO/Context/ContextRanking.swift`
* tests

**Estimated scope:** M

---

## Task 30: Add explicit long-term aliases

**Description:**
Support durable aliases such as:

```text
school folder → ~/School
coding folder → ~/Developer
```

**Acceptance criteria:**

* [ ] Create/read/update/delete alias.
* [ ] Alias survives restart.
* [ ] Context resolution applies alias before model guesswork.

**Verification:**

* [ ] Unit tests.
* [ ] Manual `move this into my school folder`.

**Dependencies:** Tasks 27, 29

**Files likely touched:**

* `LEO/Context/MemoryStore.swift`
* database migration
* tests

**Estimated scope:** M

---

# Checkpoint H — "From Earlier"

Required:

```text
User interacted with geometry.pdf earlier.

Later:
open that PDF from earlier
```

LEO should retrieve a sensible matching entity without replaying the entire activity history into the model.

---

# 13. Phase 9 — Safety and Reversibility

## Task 31: Implement PolicyEngine foundation

**Description:**
Policy decisions occur independently from model reasoning.

**Acceptance criteria:**

* [ ] Every ToolBroker execution calls PolicyEngine.
* [ ] Decisions: allow / confirm / deny.
* [ ] Model cannot bypass decision.

**Verification:**

* [ ] Unit tests for each ToolEffect.
* [ ] Integration test proves tool cannot execute when denied.

**Dependencies:** Task 18

**Files likely touched:**

* `LEO/Safety/PolicyEngine.swift`
* `LEO/Safety/PolicyDecision.swift`
* `LEO/Tools/ToolBroker.swift`
* tests

**Estimated scope:** M

---

## Task 32: Implement LEO Quarantine

**Description:**
Implement reversible deletion with persistent metadata.

**Acceptance criteria:**

* [ ] `files.quarantine` moves item into LEO-controlled location.
* [ ] Original path/request/entity/source recorded.
* [ ] `files.restore` restores safely.
* [ ] No ordinary model-facing permanent-delete tool exists.

**Verification:**

* [ ] Temporary-file integration tests.
* [ ] Restart then restore.
* [ ] Collision behavior tested.

**Dependencies:** Tasks 22, 27, 31

**Files likely touched:**

* `LEO/Safety/QuarantineService.swift`
* `LEO/Tools/Files/FileTools.swift`
* database migration
* tests

**Estimated scope:** M

---

## Task 33: Implement trusted confirmation UI

**Description:**
Protected actions require GUI approval regardless of originating client.

**Acceptance criteria:**

* [ ] Palette request can trigger confirmation UI.
* [ ] CLI request reports confirmation required and waits/fails appropriately.
* [ ] CLI cannot substitute terminal `y/n` for strong confirmation.
* [ ] Confirmation identifies exact intended action.

**Verification:**

* [ ] Unit tests for policy routing.
* [ ] CLI protected-action integration test.
* [ ] Manual approve/reject test.

**Dependencies:** Tasks 31–32

**Files likely touched:**

* `LEO/UI/Confirmation/ConfirmationView.swift`
* `LEO/Safety/ConfirmationRequest.swift`
* Orchestrator/IPC routing
* tests

**Estimated scope:** M

---

# Checkpoint I — Safe Files

Required:

```text
trash this
→ quarantine

undo that
→ restore
```

from typed and CLI.

Absolute condition:

* [ ] No permanent delete tool exposed to the model.

---

# 14. Phase 10 — Voice Input

Only now add voice as another client of the proven Core.

## Task 34: Implement voice hotkey

**Description:**
Add separate configurable PTT hotkey.

Initial candidate:

```text
⌥ Space
```

**Acceptance criteria:**

* [ ] Separate from typed shortcut.
* [ ] Key down/up events distinguish start/end speech.
* [ ] PTT can interrupt later TTS.

**Verification:**

* [ ] Manual test from multiple foreground apps.

**Dependencies:** Task 1

**Estimated scope:** S

---

## Task 35: Implement AudioInput

**Description:**
Capture microphone audio through AVAudioEngine and expose normalized frames.

**Acceptance criteria:**

* [ ] Capture begins quickly.
* [ ] Repeated start/stop stable.
* [ ] Internal format documented.
* [ ] No audio recordings persisted.

**Verification:**

* [ ] Debug amplitude meter.
* [ ] Format conversion tests.
* [ ] Repeated lifecycle test.

**Dependencies:** Task 34

**Files likely touched:**

* `LEO/Voice/AudioInput.swift`
* `LEO/Voice/AudioFrame.swift`
* tests

**Estimated scope:** M

---

## Task 36: Integrate streaming local STT

**Description:**
Implement one local `SpeechRecognizer`.

**Acceptance criteria:**

* [ ] Partial transcripts.
* [ ] Final transcript.
* [ ] Fully local.
* [ ] Final text becomes ordinary `AssistantRequest`.

**Verification:**

* [ ] Recorded fixture test.
* [ ] Normal/fast/quiet manual test.
* [ ] Measure partial/final latency and RAM.

**Dependencies:** Task 35

**Files likely touched:**

* `LEO/Voice/SpeechRecognizer.swift`
* backend implementation
* `LEO/Clients/Voice/VoiceClient.swift`
* tests

**Estimated scope:** M

---

## Task 37: Connect voice to shared Core

**Description:**
Voice transcript submits through the same Orchestrator and default session.

**Acceptance criteria:**

* [ ] No duplicate model/tool path.
* [ ] Voice-created referent immediately available to text/CLI.
* [ ] Voice source uses speech-enabled presentation preference.

**Verification:**

* [ ] Voice → typed cross-modality test.
* [ ] Inspect trace proves same Orchestrator.

**Dependencies:** Tasks 26, 36

**Estimated scope:** S

---

# Checkpoint J — Three Inputs

Required:

```text
Voice:
find this PDF

Typed:
move it to Downloads

CLI:
open it
```

Same entity. Same session. Same Core.

---

# 15. Phase 11 — Voice Output

## Task 38: Implement SpeechSynthesizer abstraction

**Description:**
Create swappable TTS interface with immediate cancellation and accessible audio frames.

**Acceptance criteria:**

* [ ] TTS backend isolated behind protocol.
* [ ] Speech can be stopped quickly.
* [ ] Audio frames accessible for later AEC.
* [ ] Typed/CLI do not invoke it automatically.

**Verification:**

* [ ] Cancellation test.
* [ ] Unit test enforcing typed silence.
* [ ] Measure first-audio latency.

**Dependencies:** Task 37

**Estimated scope:** M

---

## Task 39: Add TTS backend evaluation harness

**Description:**
Compare practical voices using standardized LEO phrases.

Evaluate initially:

* Supertonic
* Kokoro
* macOS Premium voices

Test phrases should include:

```text
Opened.
I found three files.
Your next event is at four.
I need confirmation before doing that.
Let me check which file you meant.
```

**Acceptance criteria:**

* [ ] Voice engines can be compared without app architecture changes.
* [ ] RAM/latency recorded.
* [ ] Selected default voice documented.

**Verification:**

* [ ] Debug Voice Lab or simple benchmark UI/command.
* [ ] Selection written to docs/settings defaults.

**Dependencies:** Task 38

**Estimated scope:** M

---

## Task 40: Connect voice responses and explicit typed 🔊

**Description:**
Voice requests speak automatically; typed responses only speak after user clicks the speaker control.

**Acceptance criteria:**

* [ ] Voice response invokes TTS.
* [ ] Typed result remains silent.
* [ ] Clicking 🔊 speaks exactly that result once.
* [ ] Future typed responses remain silent.

**Verification:**

* [ ] Automated presentation-policy tests.
* [ ] Manual around-client tests.

**Dependencies:** Tasks 7, 38–39

**Estimated scope:** M

---

# Checkpoint K — Socially Safe Audio

Verify:

```text
Typed → silent
CLI   → silent
Voice → speech
Typed + explicit 🔊 → speech once
```

No accidental audio output is acceptable.

---

# 16. Phase 12 — Manual Voice Interruption

## Task 41: Track assistant utterance presentation state

**Description:**
Record full generated text versus what has actually been presented through TTS.

**Acceptance criteria:**

* [ ] Response has stable response ID.
* [ ] Playback progress maps to presented text.
* [ ] Partial presentation can be persisted to conversation state.

**Verification:**

* [ ] Unit tests interrupt at multiple points.

**Dependencies:** Task 40

**Estimated scope:** M

---

## Task 42: Implement PTT interruption during TTS

**Description:**
Pressing voice hotkey while LEO speaks should immediately stop speech and start listening.

**Acceptance criteria:**

* [ ] TTS stop latency approximately <100 ms.
* [ ] Microphone starts immediately.
* [ ] Unspoken response remainder is not treated as heard.
* [ ] Active task remains available.

**Verification:**

* [ ] Manual interrupt beginning/middle/end.
* [ ] State-transition tests.
* [ ] No old speech resumes unexpectedly.

**Dependencies:** Tasks 34, 41

**Estimated scope:** M

---

# Checkpoint L — Conversational Correction

Required:

```text
LEO speaking...
PTT
→ immediate stop
→ user correction
→ same task updates
```

---

# 17. Phase 13 — Duplex Audio Feasibility

This is one of the highest-risk parts of the project. Do not hide failure.

## Task 43: Keep microphone pipeline active during TTS

**Description:**
Allow simultaneous audio input and TTS output.

**Acceptance criteria:**

* [ ] Mic frames continue while TTS plays.
* [ ] STT path can receive frames during output.
* [ ] Existing manual PTT remains functional.

**Verification:**

* [ ] Debug trace proves simultaneous input/output.
* [ ] Measure CPU/RAM impact.

**Dependencies:** Tasks 36, 40

**Estimated scope:** M

---

## Task 44: Integrate acoustic echo cancellation

**Description:**
Feed TTS output as reference audio into AEC.

**Acceptance criteria:**

* [ ] TTS reference synchronized sufficiently with mic input.
* [ ] Self-transcription substantially reduced.
* [ ] AEC can be disabled cleanly for comparison/fallback.

**Verification:**

* [ ] Before/after audio/STT tests.
* [ ] Test Mac speakers at several volumes.
* [ ] Record self-transcription rate.

**Dependencies:** Task 43

**Estimated scope:** M

---

## Task 45: Integrate VAD

**Description:**
Detect plausible user-speech regions for endpointing and barge-in.

**Acceptance criteria:**

* [ ] Speech probability produced from mic stream.
* [ ] Short noises do not usually become speech.
* [ ] VAD does not authorize actions itself.

**Verification:**

* [ ] Fixtures: speech, silence, typing, cough/noise.
* [ ] Threshold configurable in debug.

**Dependencies:** Task 43

**Estimated scope:** S

---

# Checkpoint M — Duplex Feasibility

Before speaker identification:

* [ ] LEO can speak while mic remains active.
* [ ] AEC substantially suppresses LEO's voice.
* [ ] VAD can distinguish likely speech from obvious noise.

If not, stop and fix audio architecture here.

---

# 18. Phase 14 — Speaker Verification and Automatic Barge-In

## Task 46: Implement speaker enrollment

**Description:**
Create owner voice profile from short local enrollment session.

**Acceptance criteria:**

* [ ] Multiple samples collected.
* [ ] Embeddings stored locally.
* [ ] Raw enrollment audio can be discarded.
* [ ] Profile can be reset.

**Verification:**

* [ ] Enrollment survives restart.
* [ ] Debug UI shows similarity scores.

**Dependencies:** Task 35

**Estimated scope:** M

---

## Task 47: Implement runtime speaker verification

**Description:**
Score candidate speech against enrolled owner.

**Acceptance criteria:**

* [ ] Owner and non-owner samples produce useful separation.
* [ ] Threshold configurable.
* [ ] PTT bypasses speaker rejection.

**Verification:**

* [ ] Recorded owner/non-owner test set.
* [ ] Manual second-speaker test.

**Dependencies:** Task 46

**Estimated scope:** M

---

## Task 48: Implement automatic barge-in detector

**Description:**
Combine AEC + VAD + speaker verification + plausible STT to interrupt automatically.

**Acceptance criteria:**

* [ ] Owner speech usually interrupts.
* [ ] Nearby unrelated speech normally does not.
* [ ] Cough/keyboard noise normally does not.
* [ ] PTT remains reliable fallback.

**Verification:**

* [ ] Measure false-positive and missed-interruption rates.
* [ ] Manual testing with another person nearby.
* [ ] Measure barge-in latency.

**Dependencies:** Tasks 44–47

**Estimated scope:** M

---

## Task 49: Handle interruption as task continuation

**Description:**
New speech during LEO response should modify the active task rather than always creating an unrelated fresh conversation.

**Acceptance criteria:**

* [ ] Corrections such as `tomorrow` update prior request.
* [ ] Constraints such as `only PDFs` update active task.
* [ ] `never mind` cancels task.
* [ ] Unheard output is excluded from previous assistant turn.

**Verification:**

* [ ] Calendar correction fixture.
* [ ] File-filter fixture.
* [ ] Cancellation fixture.

**Dependencies:** Tasks 41, 48

**Estimated scope:** M

---

# Checkpoint N — Natural Barge-In

Required:

```text
User:
what's on my calendar today?

LEO:
You have Geometry at—

User:
Wait, tomorrow.

LEO:
(stops)
Tomorrow you have...
```

No PTT required for this test.

---

# 19. Phase 15 — Native Integrations

Do not build these until the core/context/safety path works.

## Task 50: Calendar integration

**Description:**
Implement EventKit-backed list/search/create tools.

**Acceptance criteria:**

* [ ] Permission requested only when first needed.
* [ ] Read upcoming events.
* [ ] Create explicit event.
* [ ] Tool results become entities/referents.

**Verification:**

* [ ] Provider unit tests.
* [ ] Manual read/create.
* [ ] No duplicate event on retry.

**Dependencies:** Tasks 18, 31

**Estimated scope:** M

**Implementation status (2026-08-10):** EventKit provider and typed
`calendar.list`/`calendar.create` tools are integrated into the default
ToolBroker. Provider and policy tests pass; manual permission/read/create and
retry-without-duplicate verification remain open.

---

## Task 51: Shortcuts integration

**Description:**
List/run user Shortcuts through typed tool.

**Acceptance criteria:**

* [ ] Named Shortcut can execute.
* [ ] Missing Shortcut returns failure.
* [ ] Result goes through ToolBroker.

**Verification:**

* [ ] Fake executor tests.
* [ ] Manual run of two shortcuts.

**Dependencies:** Task 18

**Estimated scope:** S

**Implementation status (2026-08-10):** Typed system Shortcut list/run
adapters are integrated into the default ToolBroker. Fake executor and policy
tests pass; manual execution of two user Shortcuts remains open.

---

## Task 52: Add basic browser context

**Description:**
Capture browser app/title/active URL without full visual computer use.

**Acceptance criteria:**

* [ ] Active URL/title available for supported browser(s).
* [ ] Browser context enters LiveState.
* [ ] Recent URLs can become entities/events.

**Verification:**

* [ ] Manual browser-switch tests.
* [ ] Context retrieval test.

**Dependencies:** Tasks 20, 28

**Estimated scope:** M

**Implementation status (2026-08-10):** Allowlisted browser metadata capture
for Safari, Chrome, Brave, and Arc is integrated into ContextEngine/LiveState.
Provider tests pass; manual browser switching and recent-URL entity/event
verification remain open.

---

# Checkpoint O — Useful Daily Assistant

Test:

* [ ] apps
* [ ] files
* [ ] recent activity
* [ ] aliases
* [ ] calendar
* [ ] shortcuts
* [ ] browser context
* [ ] typed
* [ ] CLI
* [ ] voice

Do not add broad automation until these are dependable.

---

# 20. Phase 16 — Accessibility

## Task 53: Introduce AccessibilityController abstraction

**Description:**
Define LEO-owned semantic UI interface.

**Acceptance criteria:**

* [ ] App logic depends on LEO protocol, not concrete SDK.
* [ ] Permission failures handled cleanly.
* [ ] Mock implementation supports tests.

**Verification:**

* [ ] Mock tests.
* [ ] Accessibility denial test.

**Dependencies:** Task 1

**Estimated scope:** S

---

## Task 54: Integrate MacosUseSDK implementation

**Description:**
Use MacosUseSDK behind `AccessibilityController` for semantic UI inspection/actions.

**Acceptance criteria:**

* [ ] Snapshot frontmost app.
* [ ] Find element semantically.
* [ ] Perform one supported action.
* [ ] SDK-specific types do not leak into Core.

**Verification:**

* [ ] Finder/browser/System Settings inspection.
* [ ] Controlled semantic action.

**Dependencies:** Task 53

**Estimated scope:** M

---

## Task 55: Compress AX state for the model

**Description:**
Strip raw Accessibility trees into compact semantic representations.

**Acceptance criteria:**

* [ ] Invisible/structural noise removed.
* [ ] Useful roles/labels/actions preserved.
* [ ] Context size bounded.

**Verification:**

* [ ] Snapshot fixtures.
* [ ] Measure compression ratio.
* [ ] Common controls remain identifiable.

**Dependencies:** Task 54

**Estimated scope:** M

---

## Task 56: Implement one guarded semantic UI tool

**Description:**
Prove Accessibility actions through normal ToolBroker/Policy flow.

**Acceptance criteria:**

* [ ] Tool targets semantic element, not arbitrary coordinates.
* [ ] Ambiguity causes failure/clarification rather than guessing.
* [ ] Tool still passes PolicyEngine.

**Verification:**

* [ ] Controlled test app.
* [ ] Two real-app manual tests.

**Dependencies:** Tasks 31, 55

**Estimated scope:** M

---

# 21. Phase 17 — Resource Management

## Task 57: Implement ResourceMonitor and request telemetry

**Description:**
Track resource/latency data locally.

Metrics:

```text
hotkey → palette
PTT → audio
speech → STT partial
speech end → transcript
context retrieval
LLM TTFT
tokens/sec
tool duration
TTS first audio
barge-in
peak RSS
```

**Acceptance criteria:**

* [ ] Debug panel exposes metrics.
* [ ] Benchmark can record them.
* [ ] Telemetry has low overhead.

**Verification:**

* [ ] Real request trace.
* [ ] Peak RSS validated against OS measurement.

**Dependencies:** Tasks 13, 35

**Estimated scope:** M

---

## Task 58: Implement independent voice-runtime unloading

**Description:**
Typed/CLI use should not keep expensive speech components loaded.

**Acceptance criteria:**

* [ ] STT/TTS/speaker runtime unload independently where supported.
* [ ] Typed/CLI remain functional afterward.
* [ ] Measurable RAM reduction.

**Verification:**

* [ ] Compare voice-active vs text-active RSS.
* [ ] Repeated unload/reload tests.

**Dependencies:** Tasks 36, 40, 47, 57

**Estimated scope:** M

---

## Task 59: Implement LLM unload/prewarm policy

**Description:**
Unload main model after inactivity and prewarm on likely use.

**Acceptance criteria:**

* [ ] Configurable idle timeout.
* [ ] Hotkey starts prewarm concurrently with user input.
* [ ] Input collection never waits for model load.
* [ ] Memory decreases after unload.

**Verification:**

* [ ] Cold/warm latency comparison.
* [ ] Leak test over repeated cycles.

**Dependencies:** Tasks 13, 57

**Estimated scope:** M

---

# Checkpoint P — Memory Budget

Measure a real voice interaction with:

```text
LLM
STT
TTS
AEC
VAD
speaker verifier
ContextEngine
LEO UI
```

Targets:

* [ ] voice-active ≈ ≤3 GB
* [ ] idle <300 MB
* [ ] typed/CLI materially lighter
* [ ] idle GPU effectively zero

If not, optimize before feature expansion.

---

# 22. Phase 18 — UX Polish

## Task 60: Implement state-driven LEO animation

**Description:**
Add lightweight animation driven by actual assistant/audio state.

States:

```text
idle
listening
thinking
acting
speaking
interrupted
confirming
```

**Acceptance criteria:**

* [ ] Listening reacts to mic.
* [ ] Speaking reacts to TTS.
* [ ] Thinking/acting visually distinct.
* [ ] Negligible idle GPU use.

**Verification:**

* [ ] Profile animation overhead.
* [ ] Manual transitions.

**Dependencies:** Tasks 35, 40

**Estimated scope:** M

---

## Task 61: Polish command palette

**Description:**
Make typed LEO feel like a premium system command surface.

**Acceptance criteria:**

* [ ] Smooth appearance/dismissal.
* [ ] Reasoning statuses compact.
* [ ] Tool/action progress readable.
* [ ] Results easy to scan.
* [ ] 🔊 unobtrusive.
* [ ] Long responses can expand without becoming a full chat window.

**Verification:**

* [ ] Manual interaction pass.
* [ ] Keyboard-only usability.

**Dependencies:** Tasks 8, 40

**Estimated scope:** M

---

## Task 62: Build Quarantine/Memory/History UI

**Description:**
Expose recoverability and inspectable assistant memory.

**Acceptance criteria:**

* [ ] View/restore Quarantine.
* [ ] Inspect/edit aliases.
* [ ] View recent assistant actions.
* [ ] Permanent purge clearly separated and confirmed.

**Verification:**

* [ ] Manual edit/restore.
* [ ] Restart persistence.

**Dependencies:** Tasks 30, 32

**Estimated scope:** M

---

# 23. Phase 19 — Reliability and Hardening

## Task 63: Build canonical benchmark runner

**Description:**
Create repeatable suite of ~50 workflows.

Each case records:

```text
modality
input
context fixture
expected entity
expected tool
expected policy
expected effect/result
latency
RAM
```

**Acceptance criteria:**

* [ ] ≥50 representative workflows.
* [ ] Machine-readable results.
* [ ] Failure classified by layer.

**Verification:**

* [ ] Entire benchmark runs repeatedly.
* [ ] Summary report generated.

**Dependencies:** Core functionality above

**Estimated scope:** M

---

## Task 64: Add cross-modality benchmark

**Description:**
Explicitly test shared sessions/entities across clients.

Canonical test:

```text
Finder selects geometry.pdf

Voice:
find this

Typed:
move it into my school folder

CLI:
rename it chapter-one.pdf

Voice:
trash that

Typed:
undo that
```

**Acceptance criteria:**

* [ ] Same entity ID maintained throughout.
* [ ] No source-specific behavior differences except presentation.
* [ ] Quarantine/restore correct.

**Verification:**

* [ ] Automated where possible.
* [ ] Full manual run.

**Dependencies:** Task 63

**Estimated scope:** S

---

## Task 65: Add duplex voice benchmark

**Description:**
Measure barge-in reliability under realistic conditions.

Cases:

* owner interrupts
* owner whispers
* another person speaks
* keyboard noise
* music
* LEO speaks loudly
* PTT interruption

**Acceptance criteria:**

* [ ] False/missed interruptions recorded.
* [ ] Self-transcription rate recorded.
* [ ] Results reproducible.

**Verification:**

* [ ] Voice fixture suite runs.
* [ ] Manual real-room test.

**Dependencies:** Task 48

**Estimated scope:** M

---

## Task 66: Reliability hardening pass

**Description:**
Freeze features and fix recurring failures from benchmark results.

**Acceptance criteria:**

* [ ] Supported workflows approach ≥90% success.
* [ ] Zero silent irreversible destructive actions.
* [ ] Top remaining failure categories documented.
* [ ] Build/tests/benchmark all green enough for Alpha.

**Verification:**

* [ ] Full test suite.
* [ ] Full benchmark.
* [ ] Manual canonical flows.

**Dependencies:** Tasks 63–65

**Estimated scope:** M

---

# 24. Phase 20 — Semantic computer control, targeted visual context, and latency

This phase follows the reliability gate. It does not broaden v0.1 into an
arbitrary computer-use agent. The existing semantic types, mock controller,
AX compression tests, and permission hooks are a partial seam; real adapter
behavior remains unproven until the tasks below pass.

## Task 67: Complete one guarded semantic control slice

**Description:** Implement one reversible semantic UI action behind
`AccessibilityController`, `ToolBroker`, and `PolicyEngine`. Never fall back
to coordinates when the target is ambiguous.

**Acceptance criteria:**

* [ ] One controlled-app flow and two supported real-app flows succeed.
* [ ] Ambiguous target, stale element, cancellation, and permission denial fail closed.
* [ ] No SDK-specific types or direct UI-control path leaks into Core.

**Verification:** Focused policy/denial/cancellation tests; runtime evidence
names the exact executable and Accessibility/Input Monitoring status; manual
actions are reversible.

**Dependencies:** Tasks 31, 53–56, 66

**Estimated scope:** M

## Task 68: Add targeted visual-context fallback seam

**Description:** Add a user-requested, one-shot visual-context path only after
native, structured, and semantic context are insufficient. Capture and vision
must be explicit interfaces so unavailable permission/model state is reported,
not guessed.

**Acceptance criteria:**

* [ ] No continuous capture, background screenshots, coordinate automation, or broad VLM is introduced.
* [ ] The request records why semantic context was insufficient, capture bounds, redaction policy, and permission state.
* [ ] Without explicit Screen Recording approval, the path returns a recoverable unavailable result and requests no launch-time permission.

**Verification:** Fixture tests cover semantic-first routing and unavailable
vision. If authorized on a signed candidate, manually verify one targeted
capture; otherwise report it as deferred.

**Dependencies:** Task 67

**Estimated scope:** M

## Task 69: Instrument computer-control evidence

**Description:** Extend local telemetry and benchmark records without logging
secure text, raw AX trees, screenshots, or chain of thought.

**Acceptance criteria:**

* [ ] Each case records permission/runtime state, AX element count and payload bytes, context retrieval time, tool duration, outcome, and failure layer.
* [ ] Model metrics include TTFT and tokens/sec; process metrics include idle and peak RSS.
* [ ] Warm/cold state, hardware/build identity, and unavailable reasons are recorded.

**Verification:** Unit tests validate bounded/redacted records; OS-level RSS
and runtime logs agree within the documented measurement method.

**Dependencies:** Tasks 57, 63, 67–68

**Estimated scope:** S

## Task 70: Run the computer-use performance gate

**Description:** Run the canonical semantic/visual fixture set and publish
reproducible results in `docs/benchmarks/computer-use-performance.md`. This is
a measurement gate, not a production-readiness claim.

**Acceptance criteria:**

* [ ] Semantic, visual-fixture, and Screen Recording/vision-unavailable cases are reported separately.
* [ ] TTFT, tokens/sec, AX payload bytes, context/tool latency, idle/peak RSS, and success/failure counts are present or explicitly unavailable.
* [ ] Any threshold miss, permission blocker, or runtime limitation prevents the next expansion wave.

**Verification:** Repeat the suite on the same signed candidate and retain raw
machine-readable output outside the repository unless intentionally approved.

**Dependencies:** Tasks 67–69

**Estimated scope:** S

---

# Checkpoint Q — Computer-control evidence

* [ ] Semantic action is real, guarded, reversible, and manually verified.
* [ ] Visual fallback is targeted and explicitly permission-gated, or clearly deferred.
* [ ] TTFT/tokens-sec, AX payload, latency, and RSS evidence is reproducible.
* [ ] No implementation-complete claim is made for Screen Recording or vision.

# 25. Final v0.1 Checkpoint

## Core

* [ ] Shared AssistantRequest
* [ ] Shared AssistantEvents
* [ ] Shared SessionManager
* [ ] Shared Core
* [ ] Local model
* [ ] Typed tools

## Typed

* [ ] Dedicated hotkey
* [ ] Command palette
* [ ] Silent by default
* [ ] Explicit 🔊 only

## CLI

* [ ] `leo "request"`
* [ ] interactive mode
* [ ] same session
* [ ] Unix socket only
* [ ] silent
* [ ] no duplicated agent

## Context

* [ ] frontmost app
* [ ] Finder selection
* [ ] entities
* [ ] referents
* [ ] EventJournal
* [ ] aliases
* [ ] "from earlier"

## Safety

* [ ] PolicyEngine
* [ ] Quarantine
* [ ] restore
* [ ] no model permanent delete
* [ ] GUI confirmation
* [ ] CLI cannot bypass

## Voice

* [ ] PTT
* [ ] streaming STT
* [ ] local TTS
* [ ] voice selection
* [ ] manual interruption
* [ ] duplex STT
* [ ] AEC
* [ ] VAD
* [ ] speaker verification
* [ ] automatic barge-in
* [ ] spoken/unspoken tracking

## Integrations

* [ ] apps
* [ ] files
* [ ] Calendar
* [ ] Shortcuts
* [ ] browser context
* [ ] limited Accessibility

## UX

* [ ] varied concise reasoning summaries
* [ ] no raw chain-of-thought
* [ ] no fake thinking for trivial commands
* [ ] state animation
* [ ] inspectable memory/Quarantine

## Performance

* [ ] active voice RAM ≈ ≤3 GB
* [ ] idle RAM <300 MB
* [ ] text/CLI lighter than voice
* [ ] effectively zero idle GPU use

## Reliability

* [ ] ~50-command benchmark
* [ ] cross-modality benchmark
* [ ] duplex benchmark
* [ ] supported flows ≈ ≥90%
* [ ] zero silent irreversible destructive actions

---

# 25. Recommended Milestones

Do not think of all 66 tasks as one release.

## Alpha 0 — Typed Core

Tasks:

```text
0–19
```

Result:

```text
typed palette
+
CLI
+
local model
+
apps.open
```

This is the first proof that LEO's architecture works.

---

## Alpha 1 — Contextual Executor

Tasks:

```text
20–33
```

Result:

```text
files
+
LiveState
+
entities
+
referents
+
recent activity
+
aliases
+
Quarantine
+
PolicyEngine
```

At this point LEO should already be useful without voice.

---

## Alpha 2 — Voice Client

Tasks:

```text
34–42
```

Result:

```text
PTT
+
STT
+
TTS
+
shared voice session
+
manual interruption
```

---

## Alpha 3 — Duplex Voice

Tasks:

```text
43–49
```

Result:

```text
continuous listening
+
AEC
+
VAD
+
speaker verification
+
automatic barge-in
```

---

## Alpha 4 — Mac Depth

Tasks:

```text
50–56
```

Result:

```text
Calendar
Shortcuts
browser context
Accessibility
```

---

## Alpha 5 — Ship-Quality Personal Build

Tasks:

```text
57–66
```

Result:

```text
resource control
+
UI polish
+
benchmarks
+
hardening
```

---

# 26. One-Week Codex Priority

Do **not** instruct Codex to "complete all of LEO in a week."

Use the week to maximize validated architecture.

## Days 1–2

Aim for:

```text
Tasks 0–12
```

Result:

* menu-bar app
* shared Core
* typed palette
* Unix IPC
* CLI

---

## Days 2–3

Aim for:

```text
Tasks 13–19
```

Result:

* chosen local model
* typed tool calls
* apps.open

---

## Days 3–4

Aim for:

```text
Tasks 20–33
```

Prioritize:

* Finder selection
* files
* entities
* referents
* Quarantine
* PolicyEngine

Event memory/aliases may slip slightly if necessary.

---

## Days 4–5

Aim for:

```text
Tasks 34–42
```

Result:

* PTT
* STT
* TTS
* manual interruption

---

## Days 5–7

Focus on:

```text
Tasks 43–49
Tasks 57–59
```

Result:

* duplex feasibility
* AEC
* speaker verification
* barge-in
* real memory measurement

If there is extra time:

```text
Calendar
Shortcuts
UI polish
benchmarking
```

---

# 27. Agent Execution Rules

When implementing this plan:

## One task at a time

Do not tell the agent:

```text
implement phases 1–5
```

Tell it:

```text
Implement Task 17 from IMPLEMENTATION_PLAN.md.
```

---

## Before each task

The agent should:

1. read the task
2. inspect affected existing code
3. identify reusable patterns
4. avoid unrelated refactors

---

## During each task

The agent should:

* stay inside scope
* add tests
* preserve architecture
* update code rather than duplicate it
* avoid speculative abstractions not required by the task

---

## After each task

The agent must:

```text
build
↓
run focused tests
↓
run relevant broader tests
↓
perform runtime/manual verification where applicable
↓
report what changed
```

Compilation alone is not verification.

---

# 28. Required Agent Completion Report

After every task, report:

```text
Task completed:
Files changed:
Tests added/updated:
Build result:
Test result:
Runtime/manual verification:
Known limitations:
Architecture deviations:
Recommended next task:
```

If architecture had to deviate from the spec, stop and explain rather than silently redesigning LEO.

---

# 29. Parallelization Rules

Safe to parallelize **only after shared interfaces are committed**.

Likely parallel pairs:

```text
STT                     TTS
Calendar                Shortcuts
AEC                     Speaker verification
Telemetry               UI animation
```

Do not parallelize separate competing implementations of:

```text
InteractionOrchestrator
SessionManager
ToolBroker
ContextEngine
EntityStore
LanguageModel contract
```

Shared contracts come first.

---

# 30. Stop Conditions

Stop feature expansion and fix the problem if:

* model runtime makes ~3 GB target clearly impossible
* typed and CLI don't share state correctly
* context frequently resolves wrong entities
* Quarantine can lose data
* PolicyEngine can be bypassed
* CLI creates an alternative privileged path
* TTS unexpectedly plays during typed/CLI requests
* AEC makes STT worse
* LEO consistently transcribes itself
* automatic barge-in frequently triggers on other people/noise
* idle resource usage becomes significant
* tests/build start degrading from stacked unverified changes

---

# 31. Canonical Alpha Test

Before calling LEO's core architecture validated, this must work:

```text
User selects geometry.pdf in Finder.

Typed hotkey:

> open this

LEO opens geometry.pdf.

CLI:

$ leo "move it into my school folder"

LEO moves the same file entity.

Voice:

"Open it."

LEO opens the moved file.

Typed:

> trash that

LEO quarantines it.

CLI:

$ leo "undo that"

LEO restores it.
```

Then:

```text
Voice:

"What's on my calendar today?"

LEO begins answering.

User interrupts:

"Wait, tomorrow."

LEO stops,
hears the correction,
retains the active task,
and answers for tomorrow.
```

That is the target architecture expressed as behavior.

---

# 32. Completion Principle

Do not judge LEO by how many features exist.

Judge each implementation step by:

```text
Does it work?
Is it verified?
Does it share the Core?
Is the context correct?
Is the action reversible where possible?
Does it fit the resource budget?
Is it easier than doing the task manually?
```

LEO should grow only after the current layer is dependable.
