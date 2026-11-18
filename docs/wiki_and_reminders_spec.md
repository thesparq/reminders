# LLM Wiki & Reminders Specification

## 1. Overview

The Reminders Assistant combines durable autonomous execution (on Golem Cloud via `roc-golem`), an LLM-maintained digital garden / personal wiki on the persistent filesystem, an exponential countdown reminder schedule, and a strict single-user authentication model (limited to the owner's phone number).

---

## 2. User Authentication & Multi-Modal Ingestion

### 2.1. Phone Number Whitelist
* The bot is exclusively bound to the owner's phone number (configured via `ALLOWED_PHONE_NUMBER`).
* Inbound Telegram updates are checked against:
  1. `message.contact.phone_number` (initial verification handshake), OR
  2. Verified Telegram User ID mapped to the validated phone number.
* Unauthorized senders receive a polite rejection or are dropped silently to preserve privacy.

### 2.2. Multi-Modal Modalities
1. **Text Messages:** Direct ingestion, parsing intent, scheduling, or query answering.
2. **Voice Notes (Ogg/Opus):** Downloaded via Telegram Bot API `getFile`, transcribed via Speech-to-Text (Whisper / Gemini Audio), and passed into the processing pipeline as text with audio metadata.
3. **Images / Photos:** Downloaded via `getFile`, processed through multimodal vision LLM to extract text, receipts, whiteboard notes, or event flyers.

---

## 3. LLM Wiki Storage Architecture

The agent persists all information in a structured, searchable markdown wiki stored on Golem Cloud's durable filesystem.

### 3.1. Directory Structure & File Hierarchy
```text
wiki/
├── index.json               # Master registry of all notes, tags, and reminder references
├── agenda.md                # Rolling agenda for today, upcoming 7 days, and completed tasks
├── inbox/                   # Unprocessed / unacted incoming notes
│   ├── raw_20261116_180000_msg1.md
│   └── raw_20261116_191500_msg2.md
├── entities/                # Conceptual entities (people, projects, places, vendors)
│   ├── alex.md
│   └── golem_hackathon.md
├── topics/                  # Topical syntheses
│   └── travel_plans.md
└── reminders/               # Active & archived reminder definitions
    ├── active.json          # State of all active reminder ladders
    └── history.json         # Archive of completed reminders
```

### 3.2. Master Registry (`wiki/index.json`)
Because WASI filesystem in `roc-golem` currently supports file read/write but not directory traversal (`readDir`), the agent maintains an authoritative `wiki/index.json` tracking:
```json
{
  "updatedAt": 1794852000000,
  "inboxEntries": [
    { "id": "raw_20261116_180000", "path": "wiki/inbox/raw_20261116_180000.md", "status": "pending", "timestamp": 1794848400000 }
  ],
  "entities": ["alex", "golem_hackathon"],
  "reminders": [
    { "id": "rem_101", "title": "Team sync", "targetTime": 1794862800000, "status": "active" }
  ]
}
```

---

## 4. Exponential Reminder Scheduling Ladder

When the agent identifies an event requiring a reminder at time $T_{target}$, it schedules an exponential warning ladder leading up to the event.

### 4.1. Standard Countdown Milestones
For an event scheduled further out than 30 minutes:
* **T - 30 min:** Milestone 1 (30 minutes notice)
* **T - 20 min:** Milestone 2 (20 minutes notice)
* **T - 10 min:** Milestone 3 (10 minutes notice)
* **T - 5 min:** Milestone 4 (5 minutes notice)
* **T - 2 min:** Milestone 5 (2 minutes notice)
* **T - 1 min:** Milestone 6 (1 minute final warning)
* **T (0 min):** Event execution notice!

### 4.2. Dynamic Truncation for Near-Term Events
If an event is created only 12 minutes before $T_{target}$:
* Milestones $\ge 12$ min are discarded.
* Active ladder becomes: $10\text{ min} \to 5\text{ min} \to 2\text{ min} \to 1\text{ min} \to 0\text{ min}$.

### 4.3. Scheduling Mechanism
* The agent invokes `Golem.rpcSchedule(selfId, triggerReminder, payload, delayMillis)` on itself for each scheduled step, or schedules the immediate next step and records the remaining ladder in agent state / `reminders/active.json`.
* Each trigger fires an outbound Telegram message via `Golem.httpRequest` (`sendMessage`).

---

## 5. Midnight Periodic Reorganization

Every midnight (00:00 local time or 24h periodic timer):
1. **Trigger:** Scheduled self-invocation via `rpcSchedule` set for next midnight.
2. **Collection:** Inspects all items in `wiki/index.json` with status `"pending"` in `wiki/inbox/`.
3. **LLM Synthesis & Filing:**
   - Reads each pending note.
   - Extracts key entities, actions, and dates.
   - Creates or updates files in `wiki/entities/` and `wiki/topics/`.
   - Links cross-references with `[[wikilinks]]`.
   - Rewrites `wiki/agenda.md` for the new day.
   - Marks inbox entries as `"archived"`.
4. **Summary Dispatch:** Sends a morning briefing message to the user on Telegram with the organized agenda and highlights.

---

## 6. Question Answering & Agenda Queries

* Queries such as *"What is my agenda today?"*, *"When is my next meeting?"*, or *"What did I note about project X?"*:
  1. Agent loads `wiki/agenda.md` and reads `wiki/index.json`.
  2. For entity-specific questions, reads corresponding entity markdown files.
  3. Formulates a concise, conversational answer formatted in Telegram-compatible Markdown.
  4. Returns the response immediately to Telegram.
