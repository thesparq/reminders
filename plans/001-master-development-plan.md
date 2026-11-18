# Plan 001: Master Development Plan — Reminders Assistant

## 1. Executive Summary & Goals

This plan establishes the complete blueprint for building the Reminders Assistant: a stateful, durable AI agent running on Golem Cloud via the `roc-golem` platform v1.4.1, connected to a single-user Telegram bot.

The agent delivers three core capabilities:
1. **Intelligent Ingestion & LLM Wiki Storage:** Ingests text, voice notes, and images from the authorized user's phone, stores them in an LLM Wiki on the durable filesystem, and maintains an authoritative index.
2. **Exponential Countdown Reminder Engine:** Dynamically calculates an exponential reminder ladder (30m $\to$ 20m $\to$ 10m $\to$ 5m $\to$ 2m $\to$ 1m $\to$ 0m), schedules future invocations via `Golem.rpcSchedule`, and emits timely Telegram alerts.
3. **Midnight Autonomous Organization & Agenda QA:** Sweeps unacted inbox notes every midnight, synthesizes entities and topics, generates the rolling daily agenda, and answers user questions (e.g., *"What is my agenda today?"*).

---

## 2. Phase Breakdown & Units

### Phase 1: Toolchain, Build Pipeline & Project Manifest
* **Unit 1.1: Golem Manifest Configuration (`golem.yaml`)**
  - Define application `reminders` with component `reminders:assistant`.
  - Bind build command `./tooling/build.sh assistant`.
  - Configure environments (`local` and `cloud`).
* **Unit 1.2: Build Tooling Script (`tooling/build.sh`)**
  - Automate 3-step build pipeline:
    1. Pre-compilation check for `targets/wasm32/libroc_golem_host.a`.
    2. `roc build --target=wasm32 main.roc --output=build/reminders_core.wasm`.
    3. `wasm-tools component new build/reminders_core.wasm -o build/reminders_agent.wasm`.
    4. `wasm-tools validate build/reminders_agent.wasm`.
* **Unit 1.3: Agent Scaffold (`main.roc` and `RemindersAgent.roc`)**
  - Point to platform release v1.4.1 (or local fallback).
  - Define agent lifecycle hooks and method registrations.
* **Verification:** `./tooling/build.sh assistant` builds and validates the WASM component without errors.

---

### Phase 2: Domain Data Modeling & LLM Wiki Engine
* **Unit 2.1: Domain Type System (`Types.roc`)**
  - Define `Message`, `ReminderItem`, `ReminderLadder`, `WikiIndex`, `InboxEntry`, `EntityNote`, `AgendaDay`.
  - Serialization / deserialization functions for JSON payloads.
* **Unit 2.2: Authoritative Wiki Registry (`Wiki.roc`)**
  - Manage `wiki/index.json` state.
  - Implement functions to save new inbox items (`wiki/inbox/<timestamp>.md`).
  - Implement read and update operations for `wiki/agenda.md` and `wiki/entities/<name>.md`.
* **Unit 2.3: Durable Filesystem Integration**
  - Chain `Golem.readFile` and `Golem.writeFile` effects.
  - Handle path formatting and JSON metadata synchronization.
* **Verification:** Unit tests confirming valid JSON roundtrips and accurate file content formatting.

---

### Phase 3: Exponential Reminder Scheduler
* **Unit 3.1: Ladder Calculation Algorithm (`Scheduler.roc`)**
  - Given target epoch time $T_{target}$ and current epoch time $T_{now}$:
    - Offsets: $[30, 20, 10, 5, 2, 1, 0]$ minutes.
    - Compute milestone timestamps: $t_i = T_{target} - (\text{offset}_i \times 60 \times 1000)$.
    - Filter to strictly future milestones: $\{t_i \mid t_i > T_{now}\}$.
    - Return sorted sequence of milestones with relative delays.
* **Unit 3.2: Self-Scheduling via Golem RPC**
  - Implement `scheduleNextReminder` invoking `Golem.rpcSchedule(selfId, triggerReminder, payload, delayMillis)`.
  - Store pending reminder state in agent state and `wiki/reminders/active.json`.
* **Unit 3.3: Reminder Execution & Telegram Dispatch (`Telegram.roc`)**
  - When `triggerReminder` fires:
    - Build Telegram Markdown message (e.g., 🔔 *Reminder: [Title] in 10 minutes!*).
    - Dispatch outbound HTTP request to Telegram Bot API `sendMessage`.
    - Recursively schedule the next milestone in the ladder until reaching milestone 0 (Event Start).
* **Verification:** Simulated ladder test verifying correct interval calculation and trigger progression.

---

### Phase 4: Midnight Autonomous Reorganization
* **Unit 4.1: Midnight Trigger Scheduling**
  - Calculate milliseconds until upcoming midnight (00:00:00) using `Golem.now`.
  - Register recurrent self-invocation via `rpcSchedule`.
* **Unit 4.2: Inbox Sweep & Entity Extraction**
  - Filter `wiki/index.json` for pending entries in `wiki/inbox/`.
  - Read note contents and synthesize them into entities and projects.
  - Move/archive processed inbox entries and write entity files.
* **Unit 4.3: Daily Agenda Generation**
  - Compile upcoming reminders and pending tasks into `wiki/agenda.md`.
  - Send Telegram morning digest to the user.
* **Verification:** Test sweep function processing sample inbox entries and generating valid `agenda.md`.

---

### Phase 5: Agenda & Question Answering Query Engine
* **Unit 5.1: Agenda Query Handler (`queryAgenda`)**
  - Inspects `wiki/agenda.md` and active reminders in agent state.
  - Formats immediate, clear response for today's agenda.
* **Unit 5.2: Knowledge Wiki Retrieval (`queryWiki`)**
  - Searches entity notes and indexes for relevant keywords/topics.
  - Returns concise answers citing sources.
* **Verification:** Agent method returns formatted agenda string matching user query.

---

### Phase 6: Telegram Bridge & Multi-Modal Ingestion
* **Unit 6.1: Gateway Service (`bridge/bot.py` or Node service)**
  - Authenticates with Telegram Bot API.
  - Enforces `ALLOWED_PHONE_NUMBER` whitelist check.
  - Dispatches requests to Golem Cloud worker.
* **Unit 6.2: Multi-Modal Media Handlers**
  - Download voice notes and transcribe via Whisper API.
  - Download images and analyze via multimodal LLM.
  - Pass structured text to Golem agent worker.
* **Verification:** Sending a test Telegram message invokes the agent and returns a verified reply.

---

### Phase 7: End-to-End Integration & Dogfooding Wrap-up
* **Unit 7.1: Local Server Deployment**
  - Launch `golem server run`.
  - Deploy component using `golem deploy -L`.
  - Invoke worker and verify state persistence across restarts.
* **Unit 7.2: Final Dogfooding Review**
  - Update `docs/roc_golem_dogfooding.md` with full project feedback.
