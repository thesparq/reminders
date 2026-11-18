# System Architecture: Reminders Assistant

## 1. High-Level Topology

```mermaid
graph TD
    User([Telegram User]) -->|Text / Voice / Image| TG_API[Telegram Bot API]
    TG_API -->|Direct HTTPS Webhook POST| GW[Golem Cloud API Gateway / HTTP Mount]
    GW -->|/telegram/{worker_id}/webhook| GC[Golem Cloud Worker / roc-golem Agent]
    
    subgraph Golem Worker [Golem Cloud Durable Worker - 100% Native Roc]
        RA[RemindersAgent.roc]
        State[(Durable State)]
        FS[(Durable WASI Filesystem)]
        Sched[Durable Timer / rpcSchedule]
        
        RA <--> State
        RA <--> FS
        RA <--> Sched
    end
    
    RA -->|Outbound HTTP sendMessage| TG_API
    TG_API -->|Push Notification| User
```

---

## 2. Component Breakdown

### 2.1. Native Ingress: Golem Cloud HTTP Mount & Webhook
* **100% Native Roc & Golem Cloud:**
  - Configured directly in `RemindersAgent.roc` via `withHttpMount({ pathPrefix: "/telegram/{id}", corsOrigins: ["*"], webhookSuffix: "webhook" })`.
  - Telegram's webhook is pointed directly at `https://<golem-host>/telegram/<worker-id>/webhook` (or the `/api/reminders-assistant/process_message` endpoint).
  - Telegram POSTs updates directly to Golem Cloud's API Gateway, invoking the Roc worker without any intermediate server or Python bridge.
  - The incoming Telegram Update JSON is parsed directly in pure Roc (`Telegram.parseTelegramUpdate`), extracting sender identity, text, contact verification, voice notes, and images.

### 2.2. Golem Agent (`RemindersAgent.roc`)
* **Role:** The core stateful brain, running compiled WebAssembly via `roc-golem`.
* **Durable State:**
  - Active reminder schedules and current ladder indexes.
  - User profile and configuration.
  - Pointer to current agenda and inbox count.
* **WASI Filesystem:**
  - Hosts the entire LLM Wiki (`wiki/index.json`, `wiki/agenda.md`, `wiki/inbox/`, `wiki/entities/`, `wiki/topics/`).
  - Survives worker suspension, node migration, and restarts through Golem's durability.

### 2.3. Exponential Reminder Engine
* Uses `Golem.rpcSchedule(selfId, triggerReminder, payload, delayMillis)` to schedule execution points.
* Generates countdown ladders:
  $$\Delta t \in \{30, 20, 10, 5, 2, 1, 0\} \text{ minutes}$$
* Emits outbound `sendMessage` HTTP requests to Telegram at each milestone.

### 2.4. Midnight Organizer
* Scheduled 24-hour cycle.
* Sweeps all pending inbox markdown files, invokes LLM to structure them, updates wiki entity graphs, and publishes the fresh `agenda.md`.

---

## 3. Communication & Data Flow

1. **Message Ingestion:**
   User $\xrightarrow{\text{Telegram}}$ Gateway $\xrightarrow{\text{Invoke}}$ Golem Agent `processMessage(payload)`.
2. **Intent Parsing & Storage:**
   Agent calls LLM $\to$ classifies as reminder / note / question $\to$ writes note to `wiki/inbox/` $\to$ updates `wiki/index.json`.
3. **Schedule Trigger:**
   If reminder detected $\to$ calculates ladder timestamps $\to$ calls `rpcSchedule` for first milestone ($T - 30\text{m}$).
4. **Execution:**
   Timer fires $\to$ Golem wakes agent worker $\to$ invokes `triggerReminder` $\to$ agent calls Telegram API $\to$ schedules next ladder step ($T - 20\text{m}$).
5. **Agenda Query:**
   User asks *"what is my agenda today?"* $\to$ Agent reads `wiki/agenda.md` $\to$ formats Markdown $\to$ replies to user.
