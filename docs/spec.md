# LEO — Local Execution Orchestrator

## Technical Design Specification — v0.1

**Status:** Draft
**Platform:** macOS / Apple Silicon
**Language:** Swift 6
**UI:** SwiftUI + AppKit where needed
**Application form:** Menu-bar application
**External client:** `leo` CLI
**Primary deployment:** Personal use on one Mac
**Active-memory target:** approximately ≤3 GB
**Idle-memory target:** <300 MB
**Core priorities:** Reliability > latency > capability > architectural novelty

---

# 1. Purpose

This document defines the implementation architecture for LEO v0.1.

LEO is a single local assistant core exposed through three interfaces:

1. voice
2. typed command palette
3. local CLI

All three interfaces must share:

* the same model
* the same conversation/session state
* the same contextual memory
* the same entities and referents
* the same tools
* the same safety policy

No client is allowed to become its own assistant implementation.

---

# 2. Architecture Summary

```text
┌────────────────────────────────────────────────────────────┐
│                         LEO.app                            │
│                                                            │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐  │
│  │Voice Client│  │Text Client │  │ Local IPC Server   │  │
│  └─────┬──────┘  └─────┬──────┘  └─────────┬──────────┘  │
│        │               │                   │             │
│        └───────────────┼───────────────────┘             │
│                        ▼                                 │
│              ┌────────────────────┐                      │
│              │      LEO Core      │                      │
│              │                    │                      │
│              │ SessionManager     │                      │
│              │ ContextEngine      │                      │
│              │ Orchestrator       │                      │
│              │ LanguageModel      │                      │
│              │ PolicyEngine       │                      │
│              │ ToolBroker         │                      │
│              └─────────┬──────────┘                      │
│                        │                                 │
│       ┌────────────────┼─────────────────┐               │
│       ▼                ▼                 ▼               │
│   Native APIs      Accessibility      App adapters       │
│       │                │                 │               │
│       └────────────────┴─────────────────┘               │
└────────────────────────────────────────────────────────────┘
                         ▲
                         │ Unix socket
                         │
                    ┌────┴────┐
                    │ leo CLI │
                    └─────────┘
```

---

# 3. Process Model

## 3.1 `LEO.app`

`LEO.app` owns:

* menu-bar lifecycle
* local assistant core
* language-model runtime
* Context Engine
* tool execution
* local database
* permissions
* voice stack
* command palette
* IPC server
* confirmation UI
* Quarantine UI

For v0.1, this remains one primary application process.

---

## 3.2 Why no separate daemon initially

A separate assistant daemon would create unnecessary complexity around:

* TCC permissions
* Accessibility authorization
* model ownership
* shared context
* model duplication
* IPC
* lifecycle
* debugging

The menu-bar application is already persistent enough to act as the local service.

Architecture should nevertheless use clean internal interfaces so the Core or ModelHost could move into XPC later.

---

## 3.3 `leo` executable

`leo` is a small separate executable.

Responsibilities:

* parse terminal arguments
* connect to LEO's Unix socket
* submit requests
* render streamed events
* optionally run an interactive REPL

It must not contain:

* models
* tools
* Accessibility code
* Context Engine
* Policy Engine

---

# 4. Core Request Contract

Every interaction becomes one `AssistantRequest`.

```swift
struct AssistantRequest: Codable, Sendable, Identifiable {
    let id: UUID
    let sessionID: UUID

    let input: AssistantInput
    let source: RequestSource

    let createdAt: Date
    let presentation: PresentationPreference
}
```

---

# 5. Assistant Input

For v0.1, LEO Core reasons primarily over text.

```swift
enum AssistantInput: Codable, Sendable {
    case text(String)
}
```

Voice conversion occurs before the Core:

```text
microphone
↓
STT
↓
AssistantInput.text(...)
↓
LEO Core
```

This keeps the assistant engine independent from speech implementation.

---

# 6. Request Source

```swift
enum RequestSource: String, Codable, Sendable {
    case voice
    case commandPalette
    case cli
}
```

Source affects presentation defaults.

It must not grant different tool permissions.

---

# 7. Presentation Preferences

```swift
struct PresentationPreference: Codable, Sendable {
    var showText: Bool
    var speakResponse: Bool
    var machineReadable: Bool
}
```

Defaults:

```text
Voice
showText       = true
speakResponse  = true

Command Palette
showText       = true
speakResponse  = false

CLI
showText       = true
speakResponse  = false
```

Typed and CLI requests must remain silent unless the user explicitly asks to hear that response.

---

# 8. Assistant Event Stream

The Core communicates through events rather than returning one blocking result.

```swift
enum AssistantEvent: Sendable {
    case accepted(UUID)

    case thinking
    case reasoningSummary(String)

    case actionStarted(ActionSummary)
    case actionProgress(ActionProgress)
    case actionFinished(ActionResultSummary)

    case responseDelta(String)
    case responseCompleted(String)

    case confirmationRequired(ConfirmationRequest)

    case failed(AssistantFailure)
}
```

This allows:

* streamed palette updates
* terminal progress
* voice responses
* status animation
* cancellation

without changing reasoning code.

---

# 9. Reasoning Summary

The model may perform internal reasoning, but LEO should expose only concise status summaries.

Examples:

```text
Let me check which file you meant…

I'm looking through your recent activity…

I found two possible matches — narrowing it down…

Checking Finder…

I'm tracing where that file moved…
```

Do not expose raw chain-of-thought.

---

## 9.1 Reasoning-summary generation

Preferred design:

```swift
struct ModelProgress {
    let category: ProgressCategory
    let summary: String
}
```

```swift
enum ProgressCategory {
    case thinking
    case searching
    case comparing
    case resolving
    case planning
    case waiting
}
```

The runtime or model adapter may produce these independently of hidden reasoning.

---

## 9.2 Repetition control

Maintain recent user-facing status phrases.

Avoid using identical openers repeatedly.

For trivial work:

```text
Opening Xcode…
```

is preferable to fabricated reasoning prose.

---

# 10. Sessions

All primary interfaces use a shared default session.

```swift
actor SessionManager {
    func defaultSessionID() -> UUID

    func createSession() -> UUID

    func state(
        for sessionID: UUID
    ) async -> ConversationState
}
```

---

# 11. Conversation State

```swift
struct ConversationState: Codable {
    var turns: [ConversationTurn]

    var activeTask: TaskState?

    var recentReferents: [Referent]

    var lastResponseID: UUID?
}
```

The state is modality-independent.

Example:

```text
Voice:
"Find my latest PDF."

Typed:
"Move it to Downloads."

CLI:
leo "open it"
```

All three can resolve `it` to the same entity.

---

# 12. Context Architecture

LEO maintains four distinct forms of context:

```text
LiveState
EventJournal
EntityStore
MemoryStore
```

plus session-local conversational referents.

---

# 13. Context Engine

```swift
actor ContextEngine {
    private(set) var liveState: LiveState

    let eventJournal: EventJournal
    let entityStore: EntityStore
    let memoryStore: MemoryStore
    let retriever: ContextRetriever
}
```

The Context Engine does not continuously invoke an LLM.

---

# 14. LiveState

```swift
struct LiveState: Codable, Sendable {
    var frontmostApplication: ApplicationEntity?
    var focusedWindow: WindowEntity?

    var finderSelection: [FileEntity]
    var browserContext: BrowserContext?

    var currentDocument: DocumentEntity?

    var focusedAccessibilityElement: AXElementSummary?

    var updatedAt: Date
}
```

---

# 15. Live Context Sources

Initial sources:

* `NSWorkspace`
* Finder
* recent LEO actions
* optional browser adapter

Later:

* MacosUseSDK
* richer app adapters
* browser DOM
* targeted screen capture

---

# 16. Event-Driven Observation

Avoid continuous polling.

Prefer:

```text
NSWorkspace notifications
AX observers
Finder/app adapters
filesystem events where useful
LEO's own tool results
```

Events should represent meaningful transitions rather than every raw UI mutation.

---

# 17. Event Journal

Use SQLite.

Recommended implementation:

```text
GRDB
```

or direct SQLite if dependency minimization is preferable.

Schema:

```sql
CREATE TABLE events (
    id TEXT PRIMARY KEY,
    timestamp REAL NOT NULL,

    type TEXT NOT NULL,
    source TEXT NOT NULL,

    application_id TEXT,
    entity_id TEXT,

    metadata BLOB,

    sensitivity INTEGER NOT NULL
);
```

Indexes:

```sql
CREATE INDEX events_timestamp_idx
ON events(timestamp DESC);

CREATE INDEX events_entity_idx
ON events(entity_id);

CREATE INDEX events_type_idx
ON events(type);
```

---

# 18. Initial Event Types

```text
applicationActivated
applicationTerminated

windowFocused
windowClosed

fileSelected
fileOpened
fileMoved
fileRenamed
fileQuarantined
fileRestored

browserTabActivated
browserURLChanged

assistantRequest
assistantToolStarted
assistantToolCompleted
assistantResponse
```

---

# 19. Event Retention

Initial personal-use defaults:

```text
high-frequency context       24 hours
general activity             30 days
assistant actions            indefinite initially
explicit memories            indefinite
```

Retention should eventually be configurable.

---

# 20. Entity Model

Entities represent persistent objects rather than transient strings.

```swift
protocol ContextEntity: Codable, Identifiable {
    var id: UUID { get }
    var firstSeen: Date { get }
    var lastSeen: Date { get }
}
```

Initial entities:

* file
* folder
* application
* window
* browser tab
* URL
* project
* contact
* calendar event
* assistant result

---

# 21. File Entity

```swift
struct FileEntity: Codable, Identifiable {
    let id: UUID

    var currentURL: URL
    var previousURLs: [URL]

    var resourceIdentifier: Data?

    var filename: String
    var contentTypeIdentifier: String?

    var firstSeen: Date
    var lastSeen: Date
}
```

Use file resource identifiers where practical.

Do not use path alone as identity.

---

# 22. Referents

```swift
struct Referent: Codable {
    let entityID: UUID

    var salience: Float
    var aliases: [String]
    var lastReferencedAt: Date
}
```

Examples:

```text
it
this
that
the file
that PDF
that repo
the second one
```

Recent tool outputs should gain high salience.

---

# 23. Referential Resolution Priority

When resolving an ambiguous reference:

```text
1. explicit entity named in current request
2. current conversational referent
3. current LiveState
4. recent tool result
5. recent matching entity
6. EventJournal
7. long-term alias
```

If confidence remains poor, ask rather than guessing consequentially.

---

# 24. Long-Term Memory

Schema:

```sql
CREATE TABLE memories (
    id TEXT PRIMARY KEY,

    key TEXT NOT NULL,
    value BLOB NOT NULL,

    confidence REAL NOT NULL,
    source TEXT NOT NULL,

    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);
```

Initial examples:

```text
school folder → ~/School
coding folder → ~/Developer
preferred browser → Zen
```

v0.1 should prioritize explicit memory.

Automatic preference learning can come later.

---

# 25. Context Retrieval

```swift
protocol ContextRetriever {
    func retrieve(
        request: String,
        liveState: LiveState,
        session: ConversationState
    ) async -> RetrievedContext
}
```

Initial retrieval should use:

* recency
* entity type
* exact/partial keyword matching
* aliases
* salience
* active application

Do not add an embedding model until simple retrieval proves insufficient.

---

# 26. Retrieved Context

```swift
struct RetrievedContext: Codable, Sendable {
    var live: [ContextFact]
    var relevantEvents: [ContextEvent]
    var relevantEntities: [EntityReference]
    var memories: [MemoryFact]
    var referents: [Referent]
}
```

Must be bounded before insertion into model context.

---

# 27. Model Context Policy

The model should receive:

```text
system instructions
tool definitions
current task state
compact live context
relevant recent events
relevant entities
long-term aliases
recent conversation turns
current request
```

Do not dump full history.

Target initial active model context:

```text
~2K–8K tokens
```

depending on measured memory impact.

---

# 28. Sensitive Context Filtering

Every passive context event passes through filtering before storage.

```swift
enum ContextSensitivity {
    case normal
    case sensitive
    case secret
}
```

Secret data is discarded or redacted.

Never intentionally persist:

* passwords
* secure-text contents
* private keys
* recovery codes
* auth tokens
* API keys
* raw keystrokes
* microphone recordings

---

# 29. Secure Fields

Accessibility representation:

```text
role: secureTextField
value: [REDACTED]
```

LEO may understand:

> authentication is required

without learning the credential.

---

# 30. Language Model Interface

```swift
protocol LanguageModel: Actor {
    func prepare() async throws

    func respond(
        to request: ModelRequest
    ) -> AsyncThrowingStream<ModelEvent, Error>

    func cancel()

    func unload()
}
```

---

# 31. Model Events

```swift
enum ModelEvent {
    case reasoningStatus(String)

    case textDelta(String)

    case toolProposal(ToolProposal)

    case completed
}
```

Raw chain-of-thought is not part of this interface.

---

# 32. Model Request

```swift
struct ModelRequest {
    let systemInstructions: String

    let userText: String

    let context: RetrievedContext
    let conversation: ConversationWindow

    let tools: [ToolDefinition]
}
```

---

# 33. Model Requirements

Primary model target:

```text
~2–4B-class capability
```

Evaluate candidates on:

* tool-call accuracy
* argument extraction
* contextual reasoning
* follow-up comprehension
* referent resolution
* latency
* runtime RAM

Do not select based primarily on generic benchmarks.

---

# 34. Model Selection Harness

Maintain a LEO-specific benchmark.

Example prompts:

```text
Open Xcode.

Move this into my school folder.

Open the PDF from earlier.

Actually use the other one.

What's my next calendar event?

Trash this.

Undo that.
```

Measure:

* correct tool
* argument correctness
* unnecessary tool calls
* contextual resolution
* time to first token
* memory
* tokens/sec

---

# 35. Model Runtime Isolation

v0.1 may run the model in-process behind `LanguageModel`.

Design so it can later move into:

```text
ModelHost.xpc
```

without changing callers.

---

# 36. Model Lifecycle

Main model states:

```text
unloaded
loading
ready
generating
unloading
```

Unload after configurable inactivity.

Initial target:

```text
5 minutes
```

When user presses either hotkey:

```text
begin input immediately
+
prewarm model concurrently
```

---

# 37. Voice Runtime Lifecycle

Voice resources should be independent from the reasoning runtime.

Typed or CLI usage must not require loading:

* STT
* TTS
* speaker verifier

unless already resident for another reason.

This reduces text-mode memory usage.

---

# 38. Voice Client

```swift
actor VoiceClient {
    let audioEngine: VoiceEngine
    let orchestrator: InteractionOrchestrator
}
```

Responsibilities:

* voice hotkey
* microphone capture
* STT
* AEC
* VAD
* speaker verification
* TTS
* barge-in
* audio presentation receipts

---

# 39. Audio Format

Normalize internally to one format appropriate for selected ASR.

Initial preferred logical format:

```text
16 kHz
mono
Float32
```

unless the backend requires a different representation.

Frame size:

```text
~20 ms
```

initially.

---

# 40. Streaming STT

```swift
protocol SpeechRecognizer: Actor {
    var partialTranscripts: AsyncStream<String> { get }

    func start() async throws
    func push(_ frame: AudioFrame) async
    func finish() async throws -> SpeechTranscript

    func reset()
}
```

Requirements:

* local
* partial transcripts
* fast finalization
* continuous operation during TTS

---

# 41. TTS

```swift
protocol SpeechSynthesizer: Actor {
    var audio: AsyncStream<AudioFrame> { get }

    func speak(
        _ text: String,
        voice: VoiceConfiguration
    ) async throws

    func stop()
}
```

Requirements:

* local
* lightweight
* immediate cancellation
* output audio accessible to AEC

---

# 42. Initial TTS Backends

Evaluate:

1. Supertonic 3
2. Kokoro
3. macOS Premium system voices

Avoid making Qwen TTS the only supported implementation.

Interface must allow switching engines.

---

# 43. Voice Configuration

```swift
struct VoiceConfiguration: Codable {
    let engineID: String
    let voiceID: String

    var rate: Float
    var pitch: Float?
}
```

---

# 44. Typed TTS Behavior

Typed mode never speaks automatically.

Palette response UI exposes an explicit:

```text
🔊
```

control.

Clicking it calls TTS for that single response.

It does not alter the default for future typed requests.

---

# 45. CLI TTS Behavior

CLI is text-only by default.

Future optional:

```bash
leo --speak "..."
```

but not required for v0.1.

---

# 46. Acoustic Echo Cancellation

TTS output becomes the AEC reference:

```text
                 ┌────────► speakers
TTS frames ──────┤
                 └────────► reference

Mic
 ↓
AEC
 ↓
cleaned mic
```

Interface:

```swift
protocol EchoCanceller: Actor {
    func pushReference(_ frame: AudioFrame)

    func process(
        microphone frame: AudioFrame
    ) async -> AudioFrame
}
```

Use an existing proven implementation.

Do not write custom DSP unless necessary.

---

# 47. VAD

```swift
protocol VoiceActivityDetector: Actor {
    func speechProbability(
        for frame: AudioFrame
    ) async -> Float
}
```

Uses:

* speech onset
* interruption candidate detection
* endpointing

VAD alone cannot authorize a command.

---

# 48. Speaker Verification

```swift
protocol SpeakerVerifier: Actor {
    func enroll(
        samples: [AudioBuffer]
    ) async throws -> SpeakerProfile

    func similarity(
        for sample: AudioBuffer
    ) async -> Float
}
```

Store embeddings locally.

Raw enrollment recordings should be removable after enrollment.

---

# 49. Speaker Policy

Passive interruption requires sufficiently strong owner match.

```text
speech detected
↓
speaker verification
├─ owner → candidate interruption
└─ unknown → ignore for control
```

PTT bypasses speaker verification.

---

# 50. Speaker Verification Is Not Authentication

Never use voice matching as sufficient authorization for:

* permanent deletion
* financial actions
* security settings
* privileged operations

Use explicit trusted UI / system authentication instead.

---

# 51. Barge-In

While TTS is playing:

* microphone remains active
* AEC remains active
* VAD remains active
* speaker verification remains active
* STT remains active

Candidate trigger:

```text
owner verified
+
speech > ~250 ms
+
credible STT output
```

Then:

```text
stop TTS
↓
preserve spoken position
↓
continue transcription
↓
submit updated request
```

---

# 52. Manual Barge-In

Voice PTT during speech:

```text
immediately stop TTS
↓
begin owner input
```

Target interruption latency:

```text
<100 ms
```

This remains the guaranteed fallback even if passive barge-in is imperfect.

---

# 53. Spoken vs Generated Output

```swift
struct AssistantUtterance {
    let id: UUID

    let fullText: String
    var presentedText: String

    var playbackPosition: Duration

    var completed: Bool
}
```

If interrupted, only `presentedText` becomes prior user-visible assistant context.

---

# 54. Presentation Receipt

Clients report what was actually presented.

```swift
struct PresentationReceipt {
    let responseID: UUID
    let source: RequestSource

    let presentedText: String
    let completed: Bool
}
```

Voice may be partial.

Typed/CLI output is usually complete once rendered.

---

# 55. Fast Voice Intent Handling

Deterministic fast path for:

```text
stop
cancel
never mind
pause
hold on
```

High-confidence detection can cancel speech before model inference.

---

# 56. Text Client

The typed command palette is a lightweight GUI client.

```swift
@MainActor
final class TextClientController: ObservableObject {
    var query: String
    var state: PaletteState

    func submit()
    func cancel()
    func speakLastResponse()
}
```

---

# 57. Command Palette

Use:

```text
NSPanel
+
SwiftUI
```

Requirements:

* global text hotkey
* appears quickly
* receives keyboard focus
* Return submits
* Escape closes
* streamed status/result display
* silent by default
* optional speak-response button

---

# 58. Palette States

```swift
enum PaletteState {
    case entering
    case submitting
    case thinking
    case acting
    case completed
    case confirming
    case error
}
```

---

# 59. Palette Presentation

Example:

```text
> move that PDF from earlier

Let me check which file you meant…

Moving geometry.pdf → ~/School…

Done.                                      🔊
```

Avoid exposing tool-debug details in normal mode.

---

# 60. CLI Architecture

`leo` sends serialized `AssistantRequest`s over IPC.

Normal:

```bash
leo "open Xcode"
```

Interactive:

```bash
leo
```

Possible later:

```bash
leo --json "..."
leo --new-session "..."
```

---

# 61. Local IPC

Use a Unix-domain socket.

Suggested path:

```text
~/Library/Application Support/LEO/runtime/leo.sock
```

Runtime directory:

```text
0700
```

Socket must be user-local.

No TCP listener.

---

# 62. IPC Protocol

Simple framed JSON is sufficient for v0.1.

Option A:

```text
4-byte length
JSON payload
```

Option B:

```text
newline-delimited JSON
```

Prefer framed messages if streamed response payloads become complex.

---

# 63. IPC Messages

Request:

```json
{
  "type": "request",
  "id": "uuid",
  "sessionID": "uuid",
  "source": "cli",
  "text": "open Xcode"
}
```

Events:

```json
{"type":"reasoningSummary","text":"Checking installed apps…"}
{"type":"actionStarted","text":"Opening Xcode…"}
{"type":"responseCompleted","text":"Opened."}
```

---

# 64. IPC Server

```swift
actor LocalIPCServer {
    func start() async throws
    func stop() async

    func handle(
        _ connection: LocalIPCConnection
    ) async
}
```

It forwards decoded requests directly to the same Orchestrator used by GUI clients.

---

# 65. CLI Startup

If LEO is not running:

```text
leo
↓
attempt open LEO.app
↓
wait for local socket
↓
connect
```

If unsuccessful:

```text
LEO is not running.
```

Do not implement a fallback standalone agent.

---

# 66. CLI Confirmation

Protected action:

```text
Confirmation required in LEO.app.
```

CLI may remain connected waiting for the GUI decision.

Do not allow terminal `y/n` to bypass trusted GUI confirmation for high-impact actions.

---

# 67. Interaction Orchestrator

```swift
actor InteractionOrchestrator {
    let sessions: SessionManager
    let context: ContextEngine
    let model: LanguageModel

    let policy: PolicyEngine
    let tools: ToolBroker

    func submit(
        _ request: AssistantRequest
    ) -> AsyncThrowingStream<AssistantEvent, Error>
}
```

---

# 68. Request Lifecycle

```text
AssistantRequest
↓
session lookup
↓
context retrieval
↓
fast-path detection
↓
model
↓
tool proposal
↓
policy
↓
tool execution
↓
tool result
↓
model / response formatter
↓
AssistantEvent stream
```

---

# 69. Deterministic Fast Path

Common obvious requests may bypass the LLM.

Potential examples:

```text
open Xcode
mute
volume up
stop
cancel
```

Fast-path matching must have high confidence.

If uncertain:

```text
fall back to model
```

rather than guessing.

---

# 70. Tool System

```swift
protocol AssistantTool: Sendable {
    static var definition: ToolDefinition { get }

    func execute(
        arguments: ToolArguments,
        context: ToolExecutionContext
    ) async throws -> ToolResult
}
```

---

# 71. Tool Definition

```swift
struct ToolDefinition: Codable, Sendable {
    let name: String
    let description: String

    let schema: JSONSchema
    let effect: ToolEffect

    let idempotency: Idempotency
}
```

---

# 72. Tool Effects

```swift
enum ToolEffect: String, Codable {
    case read
    case reversibleWrite
    case externalEffect
    case destructive
    case securitySensitive
    case financial
}
```

---

# 73. Idempotency

```swift
enum Idempotency {
    case safe
    case conditionallySafe
    case unsafe
}
```

Important for:

* retries
* cancellation
* timeouts
* reconnecting clients

---

# 74. Initial Tool Families

## Apps

```text
apps.open
apps.activate
apps.frontmost
apps.quit
```

## Files

```text
files.find
files.inspect
files.open
files.reveal
files.move
files.rename
files.quarantine
files.restore
```

## Calendar

```text
calendar.list
calendar.search
calendar.create
```

## Shortcuts

```text
shortcuts.list
shortcuts.run
```

## Context

```text
context.current
context.recent
```

## Accessibility

Later v0.1:

```text
ui.inspect
ui.find
ui.performAction
```

---

# 75. Tool Broker

```swift
actor ToolBroker {
    let policy: PolicyEngine

    func register(
        _ tool: any AssistantTool
    )

    func execute(
        proposal: ToolProposal,
        request: AssistantRequest
    ) async throws -> ToolResult
}
```

Responsibilities:

* lookup
* schema validation
* policy evaluation
* timeout
* execution
* result normalization
* logging
* event journal updates

---

# 76. Policy Engine

```swift
actor PolicyEngine {
    func decide(
        proposal: ToolProposal,
        request: AssistantRequest,
        context: PolicyContext
    ) async -> PolicyDecision
}
```

```swift
enum PolicyDecision {
    case allow
    case confirm(ConfirmationRequest)
    case deny(String)
}
```

The model cannot alter the result.

---

# 77. Initial Policy

Automatic:

* reads
* app open/activate
* explicitly requested single file move
* explicitly requested rename
* restore
* Calendar reads
* explicit Shortcut execution

Confirmation:

* bulk file operations
* overwrite existing important file
* model-initiated quarantine
* external communications later

Strong confirmation:

* permanent deletion
* empty Quarantine
* financial actions
* privileged/security changes

---

# 78. LEO Quarantine

Normal deletion request:

```text
files.quarantine
```

No model-facing:

```text
files.permanentDelete
```

---

# 79. Quarantine Record

```swift
struct QuarantineRecord: Codable, Identifiable {
    let id: UUID

    let originalURL: URL
    let quarantineURL: URL

    let entityID: UUID?

    let quarantinedAt: Date
    let initiatingRequestID: UUID
    let initiatingText: String
    let source: RequestSource

    var restoredAt: Date?
}
```

---

# 80. Quarantine Location

Initial:

```text
~/Library/Application Support/LEO/Quarantine/
```

Future optimization:

* per-volume quarantine when cross-volume movement would require copying large files

---

# 81. Restore

`files.restore`:

* reads original path
* checks collisions
* restores entity identity
* updates EventJournal
* updates referent

Collision must not silently overwrite an unrelated file.

---

# 82. Permanent Deletion

Permanent purge exists only behind trusted GUI/policy.

It is not a normal LLM tool.

---

# 83. Native macOS APIs

Use native APIs wherever practical.

Examples:

```text
NSWorkspace       app/file open and activation
EventKit          calendar
Contacts          future contact lookup
FileManager       file operations
AX APIs           UI semantics
Apple Events      scriptable app integration
Shortcuts         workflow execution
```

---

# 84. Accessibility

Wrap all Accessibility implementation behind:

```swift
protocol AccessibilityController: Actor {
    func snapshotFrontmostApplication() async throws -> AXSnapshot

    func find(
        _ query: AXQuery
    ) async throws -> [AXElementReference]

    func perform(
        _ action: AXAction,
        on element: AXElementReference
    ) async throws
}
```

---

# 85. MacosUseSDK

Initial implementation may use MacosUseSDK.

Do not expose its concrete types throughout LEO.

Implementation:

```text
MacosUseAccessibilityController
```

behind LEO's own protocol.

---

# 86. AX Compression

Never send full raw trees blindly to the model.

Pipeline:

```text
raw AX tree
↓
remove invisible nodes
↓
remove structural noise
↓
collapse redundant groups
↓
retain role/title/value/actions/state
↓
compact representation
```

Example:

```text
Safari — GitHub

Toolbar:
- Back
- Forward
- Address: github.com/...

Page:
- Heading: speech-swift
- Button: Star
- Link: Issues
```

---

# 87. Screen Capture

Not continuously active.

When needed:

```text
request needs visual context
↓
semantic context insufficient
↓
capture targeted window/region
↓
vision
```

Full-screen continuous history is out of scope.

---

# 88. Browser Adapter

Initial:

```swift
struct BrowserContext: Codable {
    let application: String
    let title: String?
    let url: URL?
}
```

Later:

* page text
* DOM
* tab search
* actions

---

# 89. MCP

MCP is an optional external-tool adapter.

```text
ToolBroker
├── NativeToolProvider
└── MCPToolProvider
```

Core Mac functions should remain native where possible.

---

# 90. UI Architecture

Primary surfaces:

```text
MenuBar
VoiceHUD
CommandPalette
Confirmation
Quarantine
Memory
Settings
DebugDiagnostics
```

---

# 91. Menu Bar

Minimum menu:

```text
LEO

Status: Ready

Open Command Palette
Recent Actions
Quarantine
Memory

Settings…
Quit LEO
```

---

# 92. Voice HUD

Should show:

* listening
* partial transcript
* thinking/reasoning summary
* action
* spoken response state
* confirmation
* errors

Use a lightweight floating `NSPanel`.

---

# 93. Text Palette

Should show:

* editable request
* reasoning summary
* action progress
* result
* optional speaker button
* confirmation UI if needed

It should remain compact.

---

# 94. Voice/Thinking Animation

State:

```text
idle
listening
thinking
acting
speaking
interrupted
confirming
```

Inputs:

```swift
struct AnimationSignal {
    let state: InteractionState

    let microphoneAmplitude: Float
    let outputAmplitude: Float

    let lowFrequencyEnergy: Float
    let highFrequencyEnergy: Float

    let transitionProgress: Float
    let timestamp: TimeInterval
}
```

---

# 95. Animation Renderer

Initial:

```text
SwiftUI Canvas
+
TimelineView
```

Later:

```text
SwiftUI Shader
or
Metal
```

The animation must not involve model inference.

---

# 96. Permissions

Request only when required.

Potential:

```text
Microphone
Accessibility
Calendar
Contacts
Screen Recording
Automation/Apple Events
```

Do not request all permissions during first launch.

---

# 97. Logging

Use:

```text
OSLog / Logger
```

Categories:

```text
app
ipc
voice
model
context
tools
policy
automation
storage
performance
```

Do not log secrets.

---

# 98. Request Trace

```swift
struct RequestTrace {
    let requestID: UUID
    let sessionID: UUID
    let source: RequestSource

    let startedAt: Date

    var sttCompletedAt: Date?
    var modelStartedAt: Date?
    var firstModelTokenAt: Date?

    var toolCalls: [ToolTrace]

    var firstTTSAudioAt: Date?
    var completedAt: Date?

    var peakResidentMemory: UInt64?
}
```

---

# 99. Performance Metrics

Track:

```text
hotkey → UI appearance
PTT → audio capture
audio → first STT partial
speech end → final STT
model TTFT
tokens/sec
context retrieval time
tool execution time
TTS first audio
barge-in latency
peak RSS
idle RSS
```

---

# 100. Memory Budget

Engineering target:

```text
Main model               ~1.8–2.3 GB
STT                      ~100–300 MB
TTS                       ~50–200 MB
AEC/VAD/speaker           ~20–100 MB
App/context/storage      ~100–200 MB
──────────────────────────────────
Target                  ~2.5–3.0 GB
```

These are budget allocations, not assumed measured values.

---

# 101. Typed/CLI Memory Behavior

For text-only interactions:

```text
STT unloaded where possible
TTS unloaded where possible
speaker verifier inactive
AEC inactive
```

This should make text/CLI mode materially lighter than voice mode.

---

# 102. Idle Behavior

Keep:

* menu-bar app
* IPC server
* Context Engine
* hotkeys
* lightweight event observers

Unload:

* main model after timeout
* TTS
* STT when unused
* optional vision model

Idle GPU usage should approach zero.

---

# 103. Memory Pressure

Monitor macOS pressure.

Response priority:

```text
1. discard unnecessary context caches
2. trim model KV/context
3. unload voice models
4. unload optional components
5. unload main LLM when idle
```

LEO should yield resources rather than aggressively competing with foreground work.

---

# 104. Cancellation

Use Swift structured concurrency.

Every long operation should be cancellable where safe.

PTT interruption may cancel:

* generation
* TTS
* non-effectful pending work

Do not blindly cancel external operations after side effects have occurred.

---

# 105. Error Types

```swift
enum LEOError: Error {
    case microphoneUnavailable
    case speechRecognitionFailed

    case modelUnavailable
    case modelOutOfMemory

    case permissionDenied(PermissionType)

    case contextUnavailable

    case invalidToolProposal
    case toolExecutionFailed(String)

    case automationTimeout

    case ipcUnavailable

    case speakerVerificationFailed
}
```

---

# 106. Error Presentation

Normal user errors should remain concise.

Examples:

```text
I couldn't find that file.

Calendar access isn't enabled.

That action needs Accessibility permission.

LEO isn't running.
```

Debug details remain in logs/diagnostics.

---

# 107. Testing

Required unit coverage:

* request/event Codable contracts
* SessionManager
* ContextRetriever
* EntityStore
* ReferentStore
* MemoryStore
* EventJournal
* PolicyEngine
* Quarantine
* tool schema validation
* IPC framing
* model lifecycle
* interruption state

---

# 108. Integration Tests

Examples:

```text
typed request → Core → model → apps.open

CLI → IPC → Core → response

Finder selection → ContextEngine → "open this"

file entity → move → referent path update

quarantine → restart → restore

voice request → session → typed follow-up

CLI request → GUI confirmation required
```

---

# 109. Voice Tests

Maintain recorded fixtures for:

* normal speech
* fast speech
* whisper
* background fan
* keyboard noise
* another speaker
* LEO TTS playing
* owner interruption

Track:

* STT accuracy
* self-transcription
* false barge-in
* missed barge-in
* speaker-match rates

---

# 110. Command Benchmark

Maintain approximately 50 supported requests.

Examples:

```text
Open Xcode.

Open this.

Move it into Downloads.

Rename it chapter-one.pdf.

What was that repo from earlier?

Open it again.

What's my next calendar event?

Create an event tomorrow at four.

Trash this.

Undo that.

Only show PDFs.

Wait, tomorrow.

Stop.
```

---

# 111. Cross-Modality Benchmark

A canonical workflow must test:

```text
Finder:
select file

Voice:
"find this"

Typed:
"move it into my school folder"

CLI:
leo "rename it chapter-one.pdf"

Voice:
"trash that"

Typed:
"undo that"
```

Every step must reference the same entity.

---

# 112. Reliability Target

Before broadening scope:

```text
~90% success
```

on supported workflows.

Absolute requirement:

```text
0 silent irreversible destructive actions
```

---

# 113. Project Layout

```text
LEO/
├── App/
│   ├── LEOApp.swift
│   ├── AppState.swift
│   └── HotkeyManager.swift
│
├── Core/
│   ├── AssistantRequest.swift
│   ├── AssistantEvent.swift
│   ├── InteractionOrchestrator.swift
│   ├── SessionManager.swift
│   ├── ConversationState.swift
│   └── TaskState.swift
│
├── Clients/
│   ├── Voice/
│   │   └── VoiceClient.swift
│   └── Text/
│       └── TextClientController.swift
│
├── Voice/
│   ├── VoiceEngine.swift
│   ├── AudioInput.swift
│   ├── SpeechRecognizer.swift
│   ├── SpeechSynthesizer.swift
│   ├── VoiceActivityDetector.swift
│   ├── EchoCanceller.swift
│   ├── SpeakerVerifier.swift
│   └── BargeInDetector.swift
│
├── Models/
│   ├── LanguageModel.swift
│   ├── ModelRequest.swift
│   ├── ModelEvent.swift
│   ├── ModelHost.swift
│   └── ModelLifecycleController.swift
│
├── Context/
│   ├── ContextEngine.swift
│   ├── LiveState.swift
│   ├── ContextRetriever.swift
│   ├── EventJournal.swift
│   ├── EntityStore.swift
│   ├── ReferentStore.swift
│   └── MemoryStore.swift
│
├── Tools/
│   ├── ToolBroker.swift
│   ├── ToolDefinition.swift
│   ├── ToolProposal.swift
│   ├── Apps/
│   ├── Files/
│   ├── Calendar/
│   ├── Shortcuts/
│   ├── Accessibility/
│   ├── Browser/
│   └── MCP/
│
├── Safety/
│   ├── PolicyEngine.swift
│   ├── ConfirmationRequest.swift
│   └── QuarantineService.swift
│
├── IPC/
│   ├── LocalIPCServer.swift
│   ├── IPCMessage.swift
│   └── IPCFraming.swift
│
├── Storage/
│   ├── Database.swift
│   └── Migrations.swift
│
├── Permissions/
│   └── PermissionManager.swift
│
├── Diagnostics/
│   ├── RequestTrace.swift
│   └── ResourceMonitor.swift
│
└── UI/
    ├── MenuBar/
    ├── VoiceHUD/
    ├── CommandPalette/
    ├── Confirmation/
    ├── Quarantine/
    ├── Memory/
    ├── Settings/
    └── Animation/

LEOCLI/
├── main.swift
├── CLIClient.swift
└── TerminalRenderer.swift
```

---

# 114. v0.1 Critical Path

Build in this conceptual order:

```text
Core request/session architecture

↓
Typed command palette

↓
Local IPC + CLI

↓
Local model

↓
ToolBroker + first tools

↓
Live context + referents

↓
Activity memory

↓
Quarantine + PolicyEngine

↓
Voice input/output

↓
Continuous STT / AEC / barge-in

↓
Native integrations

↓
Resource tuning

↓
Polish + reliability
```

Typed interaction comes before voice because it gives a fast way to validate the agent architecture independently from audio.

---

# 115. v0.1 Definition of Done

LEO v0.1 is technically complete when:

## Core

* [ ] one modality-independent AssistantRequest API
* [ ] shared SessionManager
* [ ] streamed AssistantEvents
* [ ] local model
* [ ] structured tools

## Typed

* [ ] separate typed hotkey
* [ ] compact command palette
* [ ] silent responses by default
* [ ] explicit speak-response control

## CLI

* [ ] `leo "request"` works
* [ ] interactive mode works
* [ ] Unix socket only
* [ ] no separate agent implementation
* [ ] silent output by default

## Voice

* [ ] separate PTT hotkey
* [ ] local streaming STT
* [ ] local TTS
* [ ] TTS cancellable
* [ ] STT active during TTS
* [ ] AEC
* [ ] speaker verification
* [ ] automatic barge-in
* [ ] PTT override
* [ ] spoken/unspoken tracking

## Context

* [ ] frontmost app
* [ ] Finder selection
* [ ] EventJournal
* [ ] EntityStore
* [ ] ReferentStore
* [ ] explicit long-term aliases
* [ ] cross-modality referents

## Tools

* [ ] apps
* [ ] files
* [ ] Calendar
* [ ] Shortcuts
* [ ] basic Accessibility if time permits

## Safety

* [ ] PolicyEngine
* [ ] LEO Quarantine
* [ ] no normal permanent-delete tool
* [ ] protected actions use GUI confirmation
* [ ] secure fields redacted

## UX

* [ ] natural reasoning/status summaries
* [ ] no raw chain-of-thought
* [ ] reasoning summaries not repetitive
* [ ] trivial actions avoid fake thinking
* [ ] voice animation
* [ ] typed interactions remain socially quiet

## Performance

* [ ] idle RAM <300 MB
* [ ] active voice RAM approximately ≤3 GB
* [ ] text/CLI use less RAM than voice mode
* [ ] idle GPU usage effectively zero

## Reliability

* [ ] repeatable benchmark exists
* [ ] supported workflows approach ≥90%
* [ ] zero silent irreversible destructive actions

---

# 116. Canonical End-to-End Test

The architecture is validated when this interaction works:

```text
User selects:
geometry.pdf

Voice:
"Leo, find this file."

LEO:
recognizes File #81

Typed palette:
"move it into my school folder"

LEO:
resolves File #81
resolves school folder
moves file

Terminal:
leo "rename it chapter-one.pdf"

LEO:
renames File #81

Voice:
"trash that"

LEO:
quarantines File #81

Typed:
"undo that"

LEO:
restores File #81

Later:

Voice:
"what was that PDF I was using earlier?"

LEO:
retrieves File #81 from recent activity/entity history
```

While LEO is explaining something:

```text
LEO:
"I found three matching files. The first one—"

User:
"Only PDFs."

LEO:
stops speaking
recognizes owner speech
preserves spoken state
updates active task
continues with filtered result
```

If those flows are fast, local, reliable, and remain within the resource target, the v0.1 technical architecture has succeeded.

---

# 117. Engineering Rule

For every new feature, ask:

```text
Can deterministic code solve it?
↓
Can structured context simplify it?
↓
Can a semantic tool solve it?
↓
Can Accessibility solve it?
↓
Only then consider vision/computer-use.
```

LEO should not become a collection of model calls solving problems that normal software can solve more reliably.

The model is an orchestrator inside the system.

It is not the system itself.
