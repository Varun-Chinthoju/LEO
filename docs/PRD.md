# LEO — Local Execution Orchestrator

## Product Requirements Document — v0.1

**Status:** Draft
**Platform:** macOS / Apple Silicon
**Application type:** Native Swift / SwiftUI menu-bar app
**Primary use:** Personal-use local assistant
**Target machine:** Apple Silicon Mac
**Active memory target:** approximately ≤3 GB
**Primary interaction modes:** Voice, typed command palette, local CLI

---

# 1. Product Summary

**LEO — Local Execution Orchestrator** is a local-first macOS assistant that understands natural-language requests, maintains useful awareness of the user's current and recent Mac activity, and performs actions across applications and the operating system.

LEO is not fundamentally a chatbot or purely a voice assistant.

It is a **local execution and context engine with multiple interfaces**:

```text
Voice
   \
Text Palette ───► LEO Core ───► Context / Reasoning / Tools
   /
CLI
```

The same assistant can therefore be accessed through:

* a push-to-talk hotkey
* a separate typed-command hotkey
* a local `leo` command-line client

All interfaces share:

* conversation state
* current Mac context
* recent activity
* entity memory
* conversational referents
* long-term aliases/preferences
* the same local model
* the same tool system
* the same safety policy

The goal is for LEO to become a lightweight system utility that is faster and more useful than manually navigating macOS for many everyday actions.

---

# 2. Product Vision

The ideal LEO interaction is:

```text
invoke
↓
say or type naturally
↓
LEO understands context
↓
LEO reasons only as much as needed
↓
LEO executes the appropriate tool
↓
LEO gives a concise result
```

Example:

The user selects `geometry.pdf` in Finder and continues working.

Several minutes later:

> “Move that PDF from earlier into my school folder.”

LEO should understand:

* which PDF is being referenced
* where the user means by “school folder”
* whether the file moved or was renamed since then
* what operation is requested

without requiring the user to restate paths or filenames.

LEO should support interactions such as:

> “Open that repo from earlier.”

> “Move this into Downloads.”

> “Actually put it in Geometry instead.”

> “Trash that.”

> “Undo that.”

> “What was I working on before this?”

> “Open the thing I downloaded a few minutes ago.”

---

# 3. Core Product Principles

## 3.1 Local first

Routine requests should remain entirely on-device.

This includes:

* speech recognition
* local reasoning
* context retrieval
* tool execution
* recent activity storage
* speech synthesis

A stronger cloud model may eventually be used for difficult tasks, but cloud access should not be required for normal operation.

---

## 3.2 Input modality is separate from intelligence

Voice, typed input, and CLI are simply clients of the same assistant.

They must not contain independent agent logic.

Canonical flow:

```text
Input Client
↓
AssistantRequest
↓
LEO Core
↓
AssistantEvents
↓
Client Presentation
```

A feature that works only through voice or only through the CLI indicates an architectural problem unless the feature is inherently modality-specific.

---

## 3.3 Execution over conversation

LEO primarily exists to **do things**.

Its main value should come from:

* opening
* finding
* moving
* renaming
* organizing
* retrieving
* launching
* inspecting
* creating
* controlling
* executing workflows

rather than producing long conversational answers.

---

## 3.4 Context over brute-force model size

LEO should make relatively small local models more capable by providing precise structured context.

Bad:

```text
User:
"Open that PDF."

Model:
guesses what "that" means
```

Good:

```text
Recent relevant entity:
File #81
~/Downloads/geometry.pdf

User:
"Open that PDF."
```

The model should receive a small amount of highly relevant context instead of massive raw histories.

---

## 3.5 Semantic automation first

LEO should prefer deterministic and structured system interfaces.

Preferred hierarchy:

```text
Native macOS API
↓
App-specific structured API
↓
Apple Events / AppleScript / JXA
↓
Browser semantics / DOM
↓
Accessibility APIs
↓
Vision
↓
Coordinate-based input
```

Visual computer use is a fallback, not the default.

---

## 3.6 Reversible by default

Potentially destructive actions should use reversible equivalents whenever possible.

Example:

```text
"Delete this file."
↓
LEO Quarantine
↓
recoverable
```

The language model should not have normal access to permanent deletion.

---

## 3.7 Human control for irreversible actions

High-impact or irreversible actions remain under explicit human control.

Examples:

* permanent deletion
* emptying LEO Quarantine
* bulk destructive operations
* purchases
* security-sensitive changes
* privileged operations

The model may propose these actions but cannot authorize them.

---

## 3.8 Continuous awareness does not mean continuous AI inference

LEO should understand what the user has been doing without continuously running the language model or continuously processing screenshots.

Background context gathering should be:

* structured
* event-driven
* lightweight
* mostly deterministic

The main model should only run when needed.

---

# 4. Application Form Factor

LEO is primarily a **menu-bar application**.

The menu-bar process remains running so it can:

* maintain context
* receive hotkeys
* expose the local CLI endpoint
* manage models
* execute tools
* retain shared sessions

Primary surfaces:

1. menu-bar item
2. voice HUD
3. typed command palette
4. confirmation UI
5. Quarantine UI
6. memory/history/settings UI

LEO should feel like a native utility rather than a full-size chat application.

---

# 5. Voice Interaction

## 5.1 Push-to-talk

v0.1 uses push-to-talk rather than a wake word.

Example default:

```text
⌥ Space
```

Behavior:

```text
hold
↓
begin listening
↓
speak
↓
release
↓
process request
↓
perform action / respond
```

The shortcut must remain configurable.

---

## 5.2 Voice responses

Voice-originated requests may produce:

* spoken response
* visible text response

Example:

> “Leo, open Xcode.”

LEO:

> “Opened.”

For trivial actions, responses should remain short.

---

# 6. Typed Command Palette

LEO must have a second hotkey dedicated to typing.

Example default:

```text
⌥⇧ Space
```

Pressing it opens a compact command palette.

Example:

```text
╭──────────────────────────────────────────────╮
│ LEO                                          │
│                                              │
│ move that PDF into my school folder         │
╰──────────────────────────────────────────────╯
```

After submission:

```text
╭──────────────────────────────────────────────╮
│ Moving geometry.pdf → ~/School/Geometry…    │
╰──────────────────────────────────────────────╯
```

Then:

```text
╭──────────────────────────────────────────────╮
│ Done                                    🔊   │
╰──────────────────────────────────────────────╯
```

---

# 7. Typed Mode Must Be Silent by Default

Typed requests must **never automatically speak**.

Assume the user may be:

* in class
* in a library
* around friends
* in a meeting
* in any other shared environment

Default:

```text
Typed request
↓
text response only
```

A small speaker/play button may allow the user to explicitly speak that individual response.

Example:

```text
Result:
Your next event is Geometry at 2:30 PM.   🔊
```

Pressing the button speaks that response once.

It does not permanently enable TTS for typed mode.

A future shortcut may support:

```text
⌘ Return
→ submit + explicitly speak response
```

but normal Return remains silent.

---

# 8. Local CLI

LEO should provide an optional local CLI executable:

```bash
leo "open Xcode"
```

Examples:

```bash
leo "what was that repo I was looking at earlier?"
```

```bash
leo "move it into Downloads"
```

Interactive mode:

```bash
leo
```

```text
LEO> what PDF did I download earlier?
geometry.pdf

LEO> open it
Opened.
```

The CLI is another client of the same LEO Core.

It must not independently implement:

* models
* tools
* memory
* context
* permissions
* safety

---

# 9. CLI Audio Policy

CLI output is **silent by default**.

```bash
leo "what's next on my calendar?"
```

prints text only.

A future explicit option may allow:

```bash
leo --speak "what's next on my calendar?"
```

but no CLI command should unexpectedly produce speech.

---

# 10. Shared Cross-Modality Sessions

Voice, typed UI, and CLI should normally share the same default session.

Example:

Voice:

> “Find my geometry PDF.”

LEO identifies `File #81`.

Typed palette:

> move it to Downloads

LEO moves `File #81`.

Terminal:

```bash
leo "open it"
```

LEO opens the same `File #81`.

This continuity is a major product feature.

---

# 11. Presentation Is Client-Specific

The Core produces semantic response events.

The client chooses presentation.

Example result:

```text
Tool result:
Xcode opened successfully.

User response:
"Opened."
```

Voice client:

```text
text + TTS
```

Typed client:

```text
text only
```

CLI:

```text
terminal text only
```

This keeps presentation concerns outside the assistant's reasoning layer.

---

# 12. Reasoning Status

When the main model performs non-trivial reasoning, LEO should communicate a short user-facing summary of what it is doing.

Examples:

> “Let me check which file you meant…”

> “I’m looking through your recent activity…”

> “One sec — I’m comparing those events…”

> “I’m tracing where that file moved…”

> “I found two likely matches — narrowing it down…”

> “Checking Finder…”

> “Looking at your calendar…”

> “I’m figuring out the safest way to do that…”

These messages should:

* be concise
* vary naturally
* not repeat the same opener constantly
* describe useful high-level progress
* never expose raw chain-of-thought

---

## 12.1 Do not fake thinking for trivial actions

For:

> “Open Xcode.”

LEO should simply show:

```text
Opening Xcode…
```

not:

> “Hmm, I’m carefully considering how to open Xcode…”

Reasoning status appears only when it genuinely improves perceived responsiveness or transparency.

---

## 12.2 Timing behavior

Suggested behavior:

```text
instant/deterministic task
→ action status only

model reasoning > ~300–500 ms
→ short visible reasoning summary

voice reasoning > ~1.5–2 s
→ optionally speak one short status message
```

Do not create a constant stream of verbal filler.

---

# 13. Context Architecture

LEO should maintain four main context systems.

```text
Live Context
Recent Activity
Entity Memory
Long-Term Memory
```

---

# 14. Live Context

Live Context describes the current environment.

Examples:

* frontmost application
* focused window
* window title
* selected Finder item
* active browser tab
* active URL
* active document
* focused Accessibility element
* current conversational referent

Live Context should be lightweight and primarily memory-resident.

---

# 15. Recent Activity

LEO should automatically record meaningful activity transitions.

Example:

```text
13:04 Safari activated
13:05 opened github.com/soniqo/speech-swift
13:08 Finder activated
13:09 selected ~/Downloads/model.gguf
13:11 Xcode activated
```

The language model should not process these events continuously.

When the user asks:

> “Open that repo from earlier.”

LEO retrieves only the relevant events.

---

# 16. Entity Memory

LEO should track actual objects rather than only paths or event strings.

Example:

```text
File Entity #81

Downloaded:
~/Downloads/report.pdf

Renamed:
physics-report.pdf

Moved:
~/School/Physics/physics-report.pdf
```

Then:

> “Open that PDF from earlier.”

still works after the file moved.

Potential entity types include:

* files
* folders
* applications
* browser tabs
* URLs
* windows
* projects
* contacts
* calendar events
* tool results

---

# 17. Conversational Referents

LEO should explicitly track references such as:

* it
* this
* that
* there
* him
* her
* that file
* that folder
* that repo
* the second one
* the PDF from earlier

Example:

```text
User:
Find my geometry PDF.

LEO finds:
File #381

User:
Open it.

User:
Actually move it into Downloads.
```

No global memory search should be required after `File #381` becomes the active referent.

---

# 18. Long-Term Memory

Long-term memory stores durable user-specific aliases and preferences.

Examples:

```text
"school folder" → ~/School
"coding folder" → ~/Developer
preferred browser → Zen
```

Ordinary recent activity does not require the user to say:

> “Remember this.”

Explicit remembering is mainly for durable semantic information.

---

# 19. Personal-Use Activity Collection

Because LEO is designed for personal use, its local context system may be relatively rich.

Reasonable passive activity metadata includes:

* application changes
* window/document identity
* browser URLs and titles
* selected files
* opened files
* downloads
* file moves
* file renames
* assistant actions
* tool results

Rich content should generally remain on-demand.

---

# 20. Data LEO Should Not Passively Store

Do not intentionally retain:

* passwords
* secure input contents
* raw keystrokes
* private keys
* recovery codes
* API keys
* authentication tokens
* session tokens
* continuous microphone recordings

Secure fields may be represented as:

```text
type: secureTextField
value: [REDACTED]
```

LEO may know authentication is required without learning the secret.

---

# 21. Screen Awareness

Do not continuously screenshot the desktop.

Progressive context strategy:

```text
frontmost app
↓
focused window
↓
Accessibility semantics
↓
browser/app-specific semantics
↓
targeted screenshot
↓
vision model
```

Examples requiring visual context:

> “What does this graph mean?”

> “What is this error?”

> “Which button should I press?”

Routine commands should not trigger visual inference.

---

# 22. Voice Pipeline

LEO's voice system should be modular.

```text
Mic
↓
AEC
↓
VAD
↓
speaker verification
↓
streaming STT
↓
LEO Core
↓
response
↓
local TTS
```

The audio stack should remain separate from reasoning/tool execution.

---

# 23. Continuous Listening During Speech

LEO should continue listening while speaking.

This enables natural interruption.

```text
TTS ─────────────► speakers
 │
 └───────────────► AEC reference

Mic
 ↓
AEC
 ↓
VAD
 ↓
speaker verification
 ↓
streaming STT
```

Example:

**LEO:**

> “Your first event tomorrow is biology at nine, followed by—”

**User:**

> “Only tell me school stuff.”

LEO should stop, understand the new constraint, and continue with the updated request.

---

# 24. Barge-In

When the owner interrupts LEO while it speaks:

1. TTS stops immediately.
2. Microphone remains active.
3. STT continues.
4. New speech is transcribed.
5. The active task remains available.
6. LEO updates or replans.
7. LEO responds again.

---

# 25. Spoken vs Generated Response State

LEO must distinguish:

```text
generated text
actually spoken text
unspoken remainder
```

If LEO generates:

> “Your next event is Geometry at 2:30, and then Robotics at 4.”

but is interrupted after:

> “Your next event is Geometry at 2:30…”

conversation history should only treat the spoken portion as user-visible.

---

# 26. Fast Voice Commands

Certain interruption commands should use deterministic low-latency handling where confidence is high:

```text
stop
cancel
never mind
pause
hold on
```

Do not wait for a complete reasoning pass to stop speaking.

---

# 27. Speaker Verification

LEO should support a local owner voice profile.

Purpose:

* prevent nearby speech from accidentally controlling LEO
* decide whether passive speech should interrupt LEO

Not purpose:

* strong authentication

Flow:

```text
speech detected
↓
speaker similarity
├─ owner → eligible for passive command/barge-in
└─ unknown → ignore for control
```

---

# 28. Push-to-Talk Overrides Speaker Verification

PTT represents explicit intent.

Therefore:

```text
PTT active
→ accept user's speech
```

even if speaker verification confidence is low due to:

* illness
* whispering
* unusual microphone
* distance
* background noise

---

# 29. Voice Verification Is Not Security Authentication

Voice matching must never replace:

* Touch ID
* secure password entry
* system authorization
* destructive-action confirmation

Voice can be replayed or synthesized.

---

# 30. Local Model

Target:

```text
approximately 2–4B-class capability
```

A sub-1B model should not be the primary reasoning model unless real testing unexpectedly proves it sufficient.

Candidate models should be judged on LEO-specific tasks:

* tool selection
* structured arguments
* follow-up handling
* referent resolution
* latency
* memory
* instruction following

---

# 31. Model Resource Strategy

Target total active RAM:

```text
~3 GB maximum
```

The majority of that budget should go to the main reasoning model.

Voice components should remain lightweight.

Typed/CLI mode should avoid loading STT/TTS unnecessarily.

---

# 32. Voice Models

Likely lightweight candidates:

### TTS

Preferred evaluation order:

1. Supertonic 3
2. Kokoro
3. macOS Premium system voices
4. other lightweight dedicated TTS engines

Do not use a very large TTS model merely for slightly better expressiveness.

The assistant voice should optimize for:

* naturalness
* clarity
* low latency
* low RAM
* low annoyance over repeated use

not dramatic emotional acting.

---

# 33. TTS Voice Selection

LEO should eventually include a simple Voice Lab.

Example:

```text
LEO Voice Lab

Test phrase:
[ Hey. I found the file you were looking for. ]

Engine:
[ Supertonic 3 ▾ ]

Voice:
[ Voice 6 ▾ ]

Speed:
[────●────]

[ ▶ Play ]
```

This allows direct comparison of available voices.

---

# 34. Reasoning Model Escalation

Future architecture may support:

```text
deterministic command
↓
main local model
↓
difficult request
↓
stronger local/cloud model
```

The stronger model still uses the same:

* Context Engine
* Policy Engine
* Tool Broker

It does not gain an independent unrestricted execution path.

---

# 35. Tool Architecture

LEO should expose typed semantic tools.

Initial families:

```text
apps
files
calendar
shortcuts
context
accessibility
browser
```

Examples:

```text
apps.open
apps.activate

files.find
files.open
files.move
files.rename
files.inspect
files.quarantine
files.restore

calendar.list
calendar.create

shortcuts.run
```

Avoid making generic shell execution the standard interface.

---

# 36. Native macOS Automation

Preferred technologies:

### Native APIs

For:

* EventKit
* Contacts
* NSWorkspace
* filesystem
* system state

### AppleScript / JXA / Apple Events

For applications with useful scripting interfaces.

### MacosUseSDK / Accessibility

For general UI inspection/control.

### Shortcuts

For existing personal workflows.

### MCP

For optional external integrations.

---

# 37. MacosUseSDK

LEO should investigate using MacosUseSDK directly from Swift.

Potential uses:

* AX tree traversal
* semantic UI actions
* element observation
* keyboard/mouse interaction where necessary
* UI highlighting

Do not route LEO's own core Mac automation through MCP when equivalent Swift functionality is directly available.

---

# 38. MCP

MCP is an extension mechanism, not the internal architecture.

Use it for things like:

* GitHub
* Home Assistant
* databases
* other personal services

Architecture:

```text
ToolBroker
├── native tools
└── MCP tools
```

---

# 39. LEO Quarantine

The language model should not receive a normal permanent-delete tool.

User:

> “Delete this.”

becomes:

```text
files.quarantine
```

Quarantine metadata should include:

* original path
* quarantine path
* timestamp
* initiating command
* entity ID
* source modality

---

# 40. Quarantine Policy

### Explicit single-file quarantine

Normally allowed.

### Model independently deciding to remove something

Confirmation required.

### Bulk quarantine

Confirmation required.

### Restore

Allowed.

### Permanent delete

Always explicit human confirmation.

### Empty Quarantine

Always explicit human confirmation.

---

# 41. Policy Engine

Tool execution passes through an independent policy system.

```text
LLM
↓
Tool Proposal
↓
Policy Engine
├─ allow
├─ confirm
└─ deny
↓
Tool Broker
```

The model cannot override policy.

---

# 42. Local CLI Architecture

For v0.1, `LEO.app` itself acts as the local server.

Do not create a separate full daemon initially.

Architecture:

```text
                 LEO.app
                    │
              ┌─────▼─────┐
              │  LEO Core │
              └─────┬─────┘
                    │
       ┌────────────┼─────────────┐
       ▼            ▼             ▼
     Voice        Text         IPC Server
                                  │
                                  ▼
                               leo CLI
```

Advantages:

* one model instance
* one permission boundary
* one Context Engine
* one session store
* less debugging complexity

---

# 43. CLI IPC

Use a user-only local Unix-domain socket.

Do not expose:

* TCP
* HTTP
* LAN access
* internet access

The CLI receives no extra privileges.

All requests still pass through:

```text
Orchestrator
↓
Policy Engine
↓
Tool Broker
```

---

# 44. Confirmation Surface

High-impact confirmation should happen through trusted GUI.

If CLI requests a protected operation:

```text
Confirmation required in LEO.app.
```

The CLI should not become an alternative way to bypass confirmation by typing `y`.

---

# 45. UI States

Core interaction states:

```text
Idle
Listening
Thinking
Acting
Speaking
Interrupted
Confirming
Error
```

LEO should clearly communicate what state it is in.

---

# 46. Voice Animation

LEO should have a lightweight animated identity.

Animation states:

```text
idle
listening
thinking
acting
speaking
interrupted
```

Inputs:

* microphone amplitude
* frequency energy
* TTS output amplitude
* assistant state
* time
* transition progress

Initial implementation:

```text
SwiftUI Canvas
+
TimelineView
```

Later:

```text
SwiftUI Shader / Metal
```

No AI inference is needed for the animation.

---

# 47. Reasoning Animation / Status

Thinking state may combine:

* subtle animation
* concise reasoning-status text

Example:

```text
◌

Let me check which file you meant…
```

Then:

```text
↗

Moving geometry.pdf…
```

This should feel informative, not theatrical.

---

# 48. Menu-Bar Interface

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

Optional debug information:

```text
RAM
model loaded/unloaded
STT latency
LLM latency
speaker match
current session
```

---

# 49. Resource Targets

## Idle

Target:

```text
<300 MB
```

Ideal:

```text
<200 MB
```

Idle GPU usage should be effectively zero.

---

## Voice-active

Target:

```text
approximately ≤3 GB total
```

Includes:

* main model
* STT
* TTS
* speaker verification
* VAD
* AEC
* application
* context system

---

## Typed/CLI active

Should consume less than voice-active mode.

STT and TTS should not remain loaded merely because a typed request is being processed.

---

# 50. Performance Targets

Initial goals:

| Metric                        |                  Goal |
| ----------------------------- | --------------------: |
| Text hotkey → palette         |   effectively instant |
| PTT → microphone capture      |               <100 ms |
| STT partial transcript        |        near real-time |
| Speech end → final transcript |     <500 ms desirable |
| Simple command completion     |      <1.5 s desirable |
| First voice response          |        <2 s desirable |
| Manual interruption           |               <100 ms |
| Automatic barge-in            | <300–500 ms desirable |
| Idle RAM                      |               <300 MB |
| Active RAM                    |         ~3 GB maximum |

---

# 51. Initial Required Tools

v0.1 should prioritize a small reliable set.

Required:

* open application
* activate application
* inspect frontmost application
* open file/folder
* inspect file
* move file
* rename file
* quarantine file
* restore file
* inspect Finder selection
* retrieve recent activity
* read Calendar
* create Calendar event
* run Shortcut

Optional:

* Contacts
* browser URL/title
* basic window control
* basic Accessibility action

---

# 52. Non-Goals for v0.1

Do not expand v0.1 into:

* wake-word operation
* general autonomous agent
* unrestricted shell
* root helper
* broad MCP ecosystem
* continuous screenshots
* huge VLM
* arbitrary computer-use system
* automatic purchases
* password automation
* multi-hour autonomous agents
* proactive monitoring
* dozens of app integrations

---

# 53. Core Reliability Requirement

LEO should have a fixed test suite of real user workflows.

Examples:

```text
Open Xcode.

Open this in Preview.

Move this into Downloads.

What was that repo from earlier?

Open it again.

What's my next calendar event?

Create an event tomorrow at four.

Trash this.

Undo that.

Only show PDFs.

Wait, I meant tomorrow.

Stop.
```

Track:

* transcription
* context retrieved
* model response
* tool proposal
* policy decision
* execution success
* entity resolution
* latency
* memory

---

# 54. Cross-Modality Reliability Test

The following interaction should work:

```text
Finder:
select geometry.pdf

Voice:
"Find this file."

Text:
"move it into my school folder"

CLI:
leo "rename it chapter-one.pdf"

Voice:
"trash that"

Text:
"undo that"
```

Every interaction must resolve to the same file entity.

---

# 55. Voice Interruption Reliability Test

Required:

```text
User:
"What's on my calendar today?"

LEO:
"You have Geometry at two thirty, followed by—"

User:
"Wait, tomorrow."

LEO:
stops speech
recognizes owner
retains task
understands correction
answers tomorrow's calendar
```

---

# 56. Success Threshold

Before expanding into broad computer-use capabilities:

```text
~90% success
```

on supported workflows.

Critical requirement:

```text
0 silent irreversible destructive actions
```

---

# 57. v0.1 Definition of Done

LEO v0.1 is successful when:

* [ ] runs continuously as a native menu-bar application
* [ ] has separate voice and text hotkeys
* [ ] typed command palette works
* [ ] typed interaction is silent by default
* [ ] voice interaction can speak responses
* [ ] typed responses can optionally be spoken via explicit button
* [ ] local `leo` CLI works
* [ ] CLI is silent by default
* [ ] all modalities share one session/context system
* [ ] local model performs structured tool calls
* [ ] current Finder/app context works
* [ ] recent activity is remembered locally
* [ ] conversational referents work across modalities
* [ ] aliases such as “school folder” work
* [ ] file move/rename/open work
* [ ] LEO Quarantine works
* [ ] restore works
* [ ] permanent deletion remains human-controlled
* [ ] Calendar and Shortcuts work
* [ ] STT remains active while LEO speaks
* [ ] TTS can be interrupted
* [ ] basic AEC works
* [ ] owner voice can be distinguished sufficiently for passive barge-in
* [ ] nearby speech normally does not control LEO
* [ ] secure fields are redacted
* [ ] reasoning/status summaries appear naturally for non-trivial work
* [ ] raw chain-of-thought is never exposed
* [ ] active RAM remains around the ~3 GB target
* [ ] idle RAM remains below 300 MB

---

# 58. Core Product Test

LEO should make this feel normal:

```text
User presses voice hotkey.

"Leo, find the PDF I downloaded earlier."

LEO identifies:
geometry.pdf

User opens typed palette.

"move it into my school folder"

LEO moves the same file.

User later opens Terminal.

leo "open it"

LEO opens the same file.

User asks by voice:

"trash that"

LEO moves it into Quarantine.

User opens typed palette:

"undo that"

LEO restores it.

Later:

"what was I working on before this?"

LEO searches recent local activity and gives a useful answer.
```

If that interaction is fast, contextual, reliable, mostly local, and stays within the resource target, LEO v0.1 has achieved its product goal.

---

# 59. Product Success Criterion

The primary success metric is:

> **How often does using LEO feel easier than performing the action manually?**

LEO should not optimize for:

* number of tools
* parameter count
* flashy autonomous behavior
* giant model support
* artificial personality complexity

It should optimize for:

```text
low friction
+
good context
+
fast execution
+
reliability
+
natural interaction
```

The end goal is a Mac utility the user actually reaches for repeatedly throughout the day.
