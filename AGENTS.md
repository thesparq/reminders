# Reminders Assistant — Agent Development Hub

Welcome to the development hub for the **Reminders Assistant**, a stateful AI agent built using [roc-golem](https://github.com/thesparq/roc-golem) on [Golem Cloud](https://golem.cloud).

---

## 📚 Core Documentation Index

| Document | Description |
| :--- | :--- |
| **[Architecture Specification](docs/architecture.md)** | System topology, Golem Cloud durable worker model, native Telegram webhook, and execution flows. |
| **[Progress Tracker](docs/progress.md)** | Phase-by-phase roadmap, milestones, and real-time task status. |
| **[AI Guidelines & Principles](docs/ai_guidelines.md)** | Engineering standards: no band-aid fixes, durable state safety, Roc nightly conventions. |
| **[Platform Dogfooding Report](docs/roc_golem_dogfooding.md)** | In-depth analysis, discovered warnings, and feedback for the `roc-golem` platform. |
| **[LLM Wiki & Reminders Specification](docs/wiki_and_reminders_spec.md)** | Detailed specification of filesystem storage, exponential countdown ladder, and midnight organization. |

---

## 🗂️ Plans Directory

All operational plans are tracked in the [`plans/`](plans/) directory using sequential numbering:

* **[Plan 001: Master Development Plan](plans/001-master-development-plan.md)** — Master multi-phase blueprint covering toolchain setup, domain modeling, reminder ladder scheduling, midnight reorganization, and Telegram gateway.

---

## 🚀 Quick Reference Commands

### Building the Roc Agent Component
```bash
./tooling/build.sh assistant
```

### Local Testing with Golem Cloud CLI
```bash
# Start local Golem server
golem server run

# Deploy application to local environment
golem deploy -L

# Invoke agent method
golem agent invoke "reminders:assistant/user-1" 'processMessage' '"{\"text\":\"Remind me to call Mom at 7pm\"}"'
```

### Formatting Code
```bash
roc fmt main.roc RemindersAgent.roc Types.roc Wiki.roc Scheduler.roc Telegram.roc
```
