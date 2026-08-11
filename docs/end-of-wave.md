# End-of-Wave Procedure

Every implementation wave ends with a mandatory integration and verification pass.

A wave is **not complete** because every delegated task claims completion.

The wave is complete only when all work has been integrated into the main working tree, the application builds, tests pass, and the actual running app has been verified where applicable.

Do not begin the next wave until this procedure passes.

---

## 1. Stop Feature Work

Once all tasks assigned to the current wave are complete:

- Stop starting new implementation tasks.
- Stop agents from beginning work from the next wave.
- Collect the completion report from every agent.
- Identify unfinished work, known limitations, and architecture deviations.
- Make sure every agent has committed or clearly isolated its changes.

Do not mix next-wave work into the integration pass.

---

## 2. Review Agent Results

For every task in the wave, confirm:

- [ ] Acceptance criteria were addressed.
- [ ] Required tests were added or updated.
- [ ] The agent actually ran its claimed tests.
- [ ] Known limitations were reported.
- [ ] No unrelated refactors were introduced.
- [ ] No architecture rules from `PRD.md` or `TECHNICAL_SPEC.md` were violated.
- [ ] No duplicate implementation of shared services was introduced.

Pay particular attention to accidental duplicates of:

```text
InteractionOrchestrator
SessionManager
ContextEngine
EntityStore
ReferentStore
ToolBroker
PolicyEngine
LanguageModel
VoiceEngine
AssistantRequest
AssistantEvent
```

If two agents implemented overlapping concepts separately, resolve that before proceeding.

---

## 3. Integrate All Wave Changes

Merge/rebase/cherry-pick the completed work into the primary integration branch or working tree.

After integration:

```bash
git status
git diff --stat
git diff
```

Review the combined diff.

Check for:

- merge artifacts
- duplicated implementations
- abandoned files
- inconsistent naming
- incompatible interface changes
- temporary debug hacks
- commented-out production code
- accidental generated files
- accidental secrets or credentials
- unrelated formatting churn

Resolve integration issues deliberately.

Do not choose one side of a merge conflict blindly.

---

## 4. Dependency Sanity Check

Confirm package/project dependencies still make sense.

Look for:

- duplicate Swift packages
- unnecessary dependencies
- multiple libraries solving the same problem
- packages accidentally linked to the wrong target
- test-only dependencies included in production
- CLI dependencies leaking into `LEO.app`
- GUI dependencies leaking unnecessarily into `LEOCLI`

If `Package.resolved` or project configuration changed, inspect the changes explicitly.

---

## 5. Clean Build

First determine the actual project/workspace and available schemes if needed:

```bash
xcodebuild -list
```

Then perform a clean Debug build of the actual LEO application.

Example:

```bash
xcodebuild \
  -scheme LEO \
  -configuration Debug \
  -destination 'platform=macOS' \
  clean build
```

If the repository uses an `.xcworkspace`, use it explicitly:

```bash
xcodebuild \
  -workspace LEO.xcworkspace \
  -scheme LEO \
  -configuration Debug \
  -destination 'platform=macOS' \
  clean build
```

If it uses an `.xcodeproj`:

```bash
xcodebuild \
  -project LEO.xcodeproj \
  -scheme LEO \
  -configuration Debug \
  -destination 'platform=macOS' \
  clean build
```

Use the repository's actual configuration rather than blindly copying these commands.

Required:

- [ ] Build exits successfully.
- [ ] No new compiler errors.
- [ ] Investigate new warnings related to the wave.
- [ ] No missing resources/models/frameworks.
- [ ] CLI target also builds if touched by the wave.

If the CLI exists:

```bash
xcodebuild \
  -scheme LEOCLI \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

A successful incremental build is not enough for the wave gate.

At least one clean build must succeed.

---

## 6. Run Focused Tests

Run the tests specifically associated with every task completed in the wave.

Examples:

```bash
xcodebuild \
  -scheme LEO \
  -destination 'platform=macOS' \
  -only-testing:LEOTests/SessionManagerTests \
  test
```

or:

```bash
swift test --filter RelevantFeatureTests
```

Use the repository's actual test system.

Required:

- [ ] Every new test passes.
- [ ] Every modified subsystem's focused tests pass.
- [ ] No skipped/failing test is silently ignored.

If a test is flaky, investigate the flake.

Do not repeatedly rerun it until it happens to pass and call that success.

---

## 7. Run the Full Test Suite

After focused tests pass, run the complete relevant suite.

Example:

```bash
xcodebuild \
  -scheme LEO \
  -destination 'platform=macOS' \
  test
```

If multiple test schemes exist, run all relevant ones.

Required:

- [ ] Full test suite passes.
- [ ] No previous passing test now fails.
- [ ] No significant test count unexpectedly disappeared.
- [ ] No tests were disabled simply to make the wave pass.

Record:

```text
Tests executed:
Passed:
Failed:
Skipped:
```

---

## 8. Build the Actual Runnable App

Locate the newly built Debug product rather than accidentally launching an old copy from `/Applications`.

The agent should determine the build product path from Xcode/DerivedData.

Useful command:

```bash
xcodebuild \
  -scheme LEO \
  -configuration Debug \
  -showBuildSettings
```

Find:

```text
TARGET_BUILD_DIR
FULL_PRODUCT_NAME
```

The resulting app should resemble:

```text
<DerivedData>/Build/Products/Debug/LEO.app
```

Verify the executable exists:

```bash
test -x "/path/to/LEO.app/Contents/MacOS/LEO"
```

Do not runtime-test an older installed build by accident.

---

## 9. Launch the Fresh Build

Terminate any currently running LEO instance first.

Example:

```bash
pkill -x LEO || true
```

Then launch the exact newly built application:

```bash
open "/path/to/fresh/Debug/LEO.app"
```

Confirm the launched process corresponds to the fresh build.

Useful checks:

```bash
pgrep -fl LEO
```

and, if needed:

```bash
ps aux | grep '[L]EO'
```

---

## 10. Inspect Runtime Logs

Use macOS unified logging where appropriate.

Example:

```bash
log stream \
  --level debug \
  --predicate 'process == "LEO"'
```

Or inspect recent logs:

```bash
log show \
  --last 5m \
  --predicate 'process == "LEO"'
```

Look for:

- crashes
- uncaught errors
- repeated retries
- IPC failures
- permission failures
- model-loading failures
- unexpected tool errors
- actor/concurrency issues
- database errors
- excessive repeated events

Do not assume the UI looking correct means the internals are healthy.

---

## 11. Runtime Smoke Test

Actually use the running application.

Do not count compilation or unit tests as runtime verification.

At minimum verify all user-facing behavior introduced or modified in the current wave.

Examples depending on the wave:

### Menu bar

- [ ] LEO appears correctly.
- [ ] Menu opens.
- [ ] Settings opens.
- [ ] Quit works.

### Typed palette

- [ ] Global hotkey works while another application is active.
- [ ] Input receives focus.
- [ ] Return submits.
- [ ] Escape dismisses.
- [ ] Typed responses remain silent.
- [ ] `🔊` speaks only when explicitly clicked.

### CLI

```bash
leo "test request"
```

Verify:

- [ ] CLI reaches the running LEO instance.
- [ ] No separate model is started.
- [ ] Output streams correctly.
- [ ] CLI is silent.
- [ ] Session state is shared where expected.

### Context

- [ ] Switch applications and confirm LiveState changes.
- [ ] Select files in Finder.
- [ ] Verify references such as `this` and `it`.
- [ ] Confirm stale entity paths are updated after move/rename.

### Tools

Perform actual safe actions:

```text
open Xcode
open this
move this test file
rename it
```

Confirm the real resulting system state rather than trusting the tool's return value.

### Quarantine

Using a disposable test file:

```text
trash this
```

Then:

```text
undo that
```

Verify the file physically moves to Quarantine and returns correctly.

### Voice

- [ ] PTT starts listening.
- [ ] Transcript is accurate enough.
- [ ] Voice requests reach the same Core.
- [ ] Spoken output works.
- [ ] Typed input remains silent afterward.

### Interruption

Where implemented:

- [ ] Interrupt LEO near the beginning of speech.
- [ ] Interrupt in the middle.
- [ ] Interrupt near the end.
- [ ] Confirm old TTS does not resume.
- [ ] Confirm unheard text is not treated as spoken.

---

## 12. Visual Verification

For UI-affecting waves, visually inspect the actual running application.

Do not assume SwiftUI code is correct because snapshots/tests pass.

Check:

- spacing
- clipping
- truncation
- window sizing
- focus behavior
- dark mode
- light mode when relevant
- menu-bar positioning
- animation state
- command palette transitions
- confirmation UI
- long text
- empty states
- errors

Use screenshots, computer-use tooling, `osascript`, Accessibility inspection, or other available runtime tools where useful.

If a debug visual harness exists, inspect the important states through it.

---

## 13. Verify Cross-Feature Integration

A wave may contain individually correct tasks that fail when combined.

Exercise at least one flow crossing multiple components changed in the wave.

Example:

```text
Typed hotkey
→ Command Palette
→ AssistantRequest
→ SessionManager
→ Orchestrator
→ AssistantEvent
→ Palette result
```

Later:

```text
Finder selection
→ ContextEngine
→ EntityStore
→ model
→ ToolBroker
→ file move
→ ReferentStore
→ CLI "open it"
```

Test the integrated path, not just individual pieces.

---

## 14. Check Safety Invariants

At every relevant wave, verify these invariants still hold:

- [ ] Typed interaction does not automatically invoke TTS.
- [ ] CLI interaction does not automatically invoke TTS.
- [ ] CLI has no independent execution path.
- [ ] CLI cannot bypass PolicyEngine.
- [ ] Model has no normal permanent-delete tool.
- [ ] Quarantine remains reversible.
- [ ] Protected actions still require trusted confirmation.
- [ ] Secure text values are not stored/logged.
- [ ] No raw chain-of-thought is shown to the user.
- [ ] Context collection does not continuously invoke the LLM.
- [ ] No unexpected network server has been introduced.

For IPC waves, verify no accidental TCP listener:

```bash
lsof -nP -iTCP -sTCP:LISTEN
```

LEO should not appear there unless a future spec explicitly requires networking.

---

## 15. Resource Check

For waves affecting models, audio, context collection, IPC, animation, or background work, measure resources.

At minimum inspect:

```text
Resident memory
CPU
GPU where practical
unexpected background activity
```

Compare against previous checkpoint.

Record:

```text
Idle RAM:
Active RAM:
Peak RAM:
Idle CPU:
Relevant latency:
```

For semantic computer-control or visual-context waves, also record:

```text
TTFT:
Tokens/sec:
AX elements / compressed payload bytes:
Context retrieval latency:
Tool/action latency:
Screen Recording state:
Accessibility state:
Input Monitoring state:
Exact executable identity/signature:
Warm/cold state:
Vision result: measured / unavailable / deferred
```

Do not substitute compile or unit-test evidence for runtime permission,
identity, latency, or RSS evidence. A Screen Recording or vision result is
`deferred` when the exact signed candidate cannot be authorized and exercised.

Important targets:

```text
Idle RAM:      <300 MB
Voice-active:  approximately ≤3 GB
Idle GPU:      effectively zero
```

Do not postpone major resource regressions until the end of the project.

If a wave introduces a major regression, fix it before continuing.

---

## 16. Architecture Review

Before declaring the wave complete, compare the integrated result against:

```text
PRD.md
TECHNICAL_SPEC.md
IMPLEMENTATION_PLAN.md
PARALLELIZATION.md
```

Check specifically for:

- duplicated Core logic
- modality-specific reasoning
- accidental model coupling
- inappropriate raw shell usage
- vision being used where semantic APIs exist
- bypassing ToolBroker
- bypassing PolicyEngine
- excessive new abstractions
- speculative future infrastructure
- feature creep

If implementation legitimately needs to diverge from the specification, document the reason.

Do not silently change architecture.

---

## 17. Remove Temporary Development Artifacts

Before closing the wave, remove or clearly isolate:

- temporary debug files
- throwaway scripts
- test recordings that should not ship
- generated benchmark junk
- copied models accidentally added to Git
- commented-out implementations
- TODO hacks that affect production behavior
- hard-coded local paths
- developer-specific usernames
- secrets
- temporary feature flags

Development-only diagnostics may remain when intentionally gated to Debug builds.

---

## 18. Git Hygiene

Check:

```bash
git status
```

Required:

- [ ] No accidental untracked files.
- [ ] No unresolved conflicts.
- [ ] No secrets.
- [ ] No large unintended binaries.
- [ ] Diff represents only intentional wave work.

Review:

```bash
git diff --check
```

Fix whitespace/conflict-marker issues.

Create a clean checkpoint commit if the workflow uses commits per wave.

Example:

```bash
git add -A
git commit -m "Complete wave N: <short description>"
```

Do not commit if tests/build are failing unless explicitly creating a known-broken diagnostic checkpoint.

---

## 19. Wave Completion Report

The agent must produce a report before starting the next wave.

Use this format:

```markdown
# Wave N Completion Report

## Status

PASS / FAIL / BLOCKED

## Tasks Completed

- Task X — ...
- Task Y — ...
- Task Z — ...

## Integration

- Branches/worktrees integrated:
- Merge conflicts encountered:
- How conflicts were resolved:

## Files / Areas Changed

- ...
- ...
- ...

## Build

Command:

`...`

Result:

PASS / FAIL

Warnings requiring attention:

- ...

## Focused Tests

Commands:

`...`

Results:

- X passed
- Y failed
- Z skipped

## Full Test Suite

Command:

`...`

Result:

- Tests run:
- Passed:
- Failed:
- Skipped:

## Runtime Verification

Verified:

- [ ] ...
- [ ] ...
- [ ] ...

Fresh app path tested:

`/path/to/LEO.app`

## Visual Verification

- States inspected:
- Problems found:
- Fixes made:

## Safety Invariants

- [ ] PolicyEngine remains mandatory.
- [ ] Typed/CLI remain silent.
- [ ] No permanent-delete tool.
- [ ] CLI cannot bypass confirmation.
- [ ] No secrets logged/stored.
- [ ] No raw chain-of-thought exposed.

## Resource Measurements

Idle RAM:

`...`

Active RAM:

`...`

Peak RAM:

`...`

Relevant latency:

`...`

Regressions:

- ...

## Known Limitations

- ...
- ...

## Architecture Deviations

None

or:

- Deviation:
- Reason:
- Impact:

## Remaining Problems

- ...

## Next-Wave Readiness

SAFE TO BEGIN / NOT SAFE TO BEGIN

Reason:

...
```

---

## 20. Wave Gate

The next wave may begin only when all of these are true:

- [ ] All required current-wave tasks are integrated.
- [ ] No unresolved merge conflicts.
- [ ] Clean Debug build succeeds.
- [ ] Focused tests pass.
- [ ] Full relevant test suite passes.
- [ ] Freshly built app was launched.
- [ ] Relevant features were manually/runtime verified.
- [ ] UI changes were visually verified.
- [ ] Cross-feature integration was exercised.
- [ ] Safety invariants still hold.
- [ ] Resource regressions were investigated.
- [ ] For computer-control waves, semantic and visual/permission evidence are separated; deferred Screen Recording/vision work is not marked complete.
- [ ] TTFT, tokens/sec, AX payload size, context/tool latency, idle RSS, and peak RSS are recorded or explicitly unavailable with reasons.
- [ ] Git working state is clean/intentionally accounted for.
- [ ] Wave Completion Report exists.
- [ ] No blocker makes the next wave unsafe.

If any required gate fails:

```text
DO NOT START THE NEXT WAVE.
```

Fix the current wave first.

---

# Definition of "Verified"

For LEO:

```text
compiled
≠ verified

unit tests passed
≠ verified

agent says it works
≠ verified
```

A user-facing feature is verified only when:

```text
code compiles
+
focused tests pass
+
full relevant tests pass
+
fresh app build launches
+
feature is exercised in the running app
+
actual resulting system state is inspected
```

For UI changes, add:

```text
+
visual inspection
```

For performance-sensitive changes, add:

```text
+
resource/latency measurement
```

For consequential actions, add:

```text
+
safety-policy verification
```

The purpose of the end-of-wave procedure is to prevent several individually plausible changes from accumulating into an application that only works on paper.
