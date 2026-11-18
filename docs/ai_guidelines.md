# AI Development Guidelines & Engineering Principles

## 1. Core Engineering Philosophy: No Band-Aid Fixes

1. **Zero Band-Aid Solutions:**
   Every fix, module, and feature must be implemented thoroughly and correctly from first principles. No mock stubs where production implementations belong, no hardcoded values replacing logic, and no temporary patch hacks.
2. **Durable State Safety:**
   Because the agent runs on Golem Cloud's durable execution engine, all state mutations and filesystem writes must be idempotent and resilient to worker reloads and checkpointing.
3. **Dogfooding Awareness:**
   The `roc-golem` platform is actively built by the user. Any anomalies, compiler diagnostics, or host-guest boundary limitations must be logged in `docs/roc_golem_dogfooding.md` and handled cleanly.

---

## 2. Roc Coding Standards & Best Practices

1. **Roc Nightly Compatibility:**
   - Adhere to the pinned Roc version (`nightly-2026-09-29-7f11a82`).
   - Format all Roc source files via `roc fmt <file.roc>` or editor integration.
   - Address compiler warnings proactively where possible.
2. **Module Architecture:**
   - Keep platform interactions contained within dedicated modules (`Telegram.roc`, `Wiki.roc`, `Scheduler.roc`).
   - Use explicit record types and type aliases for all payloads and state records.
   - Utilize `Result(a, Str)` for all operations capable of failing.
3. **JSON Handling:**
   - Use `pf.Json` (`encode`, `decode`, `decode_or`, `escape`) safely.
   - Validate and sanitize all string inputs before embedding them into JSON strings.

---

## 3. Storage & Filesystem Rules

1. **Authoritative Index:**
   Always update `wiki/index.json` concurrently with any filesystem addition or deletion to preserve lookup integrity without requiring directory listing.
2. **Path Sanitization:**
   Avoid leading slashes or parent traversals (`..`) that could trigger host path normalization errors. Store paths as clean relative strings like `wiki/inbox/item_1.md`.

---

## 4. Scheduling & Reminders Safety

1. **Monotonic Clocks & Timestamps:**
   Use epoch milliseconds (`U64`) from `Golem.now` for all time computations.
2. **Ladder Monotonicity:**
   Ensure each step in the exponential countdown ($30\text{m} \to 20\text{m} \to 10\text{m} \to 5\text{m} \to 2\text{m} \to 1\text{m} \to 0\text{m}$) is strictly in the future before passing `delayMillis` to `rpcSchedule`.
3. **Graceful Handling of Missed or Near-Term Milestones:**
   If a reminder is scheduled with less than 30 minutes notice, dynamically truncate the ladder to only remaining valid future points.
