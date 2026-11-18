# Roc Golem Platform Dogfooding Report & Findings

**Platform Under Test:** `thesparq/roc-golem`  
**Version Tested:** `v1.4.1` (Latest release)  
**Host Target:** `wasm32-wasip2` / Golem Component Model  
**Golem Cloud Version:** `v1.6.3`  
**Roc Compiler Version:** `nightly-2026-09-29-7f11a82`  

---

## 1. Summary of Dogfooding Assessment

The `roc-golem` platform v1.4.1 is functional and correctly compiles Roc code into Wasm32 core modules that componentize with `wasm-tools component new` for Golem Cloud. The effect bindings for RPC (`rpcSchedule`, `rpcInvoke`, `rpcFireAndForget`), HTTP (`httpRequest`, `httpStreamOpen`), and state persistence align with Golem's Agent model.

During our live testing, compilation, and source inspection of `thesparq/roc-golem`, several actionable issues, compiler warnings, and API enhancement opportunities were identified.

---

## 2. Issues & Warnings Discovered

### 2.1. Duplicate Definition Warning in `platform/main.roc` (Line 95)
* **Observed Warning:**
  ```text
  ── ● duplicate definition ──────────────── platform/main.roc:95:1
  The name Json is being redeclared here:
  import Json exposing [encode, decode, decode_or, escape]
  In this scope, Json was already defined in platform/main.roc:1:1:
  platform "golem"
  ```
* **Root Cause:** In `platform/main.roc`, the platform exposes `Json` in its module list, while line 95 attempts an `import Json exposing [...]` inside the platform main module itself.
* **Suggested Fix:** In `platform/main.roc`, use qualified `PlatformJson` or drop redundant import to eliminate compiler warning.

### 2.2. Deprecated Module Header Syntax in Roc Nightly
* **Observed Warning:**
  ```text
  ── ● module header deprecated ──────────── platform/Golem.roc:1:1
  The module header is deprecated.
  Type modules (headerless files with a top-level type matching the filename) are
  now the preferred way to define modules.
  ```
* **Impact:** Emitted on `Golem.roc`, `Json.roc`, `Parse.roc`, and `Types.roc`. While the compiler still emits code (`0 errors and 5 warnings`), future Roc nightlies will make this a hard error.
* **Suggested Fix:** Transition platform modules to headerless type modules as recommended by upstream Roc.

### 2.3. Parent Directory Auto-Creation in WASI Filesystem (`fs_write_bytes_wasm32`)
* **Observed Code in `host/src/lib.rs` (Lines 203–205):**
  ```rust
  #[cfg(target_arch = "wasm32")]
  fn fs_write_bytes_wasm32(path: &str, bytes: &[u8]) -> Result<(), String> {
      std::fs::write(path, bytes).map_err(|e| e.to_string())
  }
  ```
* **Issue:** In Rust, `std::fs::write("wiki/inbox/entry.md", ...)` returns `NotFound (os error 2)` if `wiki/inbox` does not already exist. Because `roc-golem` does not expose `createDir`, writing to nested paths fails unless the directory already exists.
* **Suggested Fix:** In `host/src/lib.rs`, add parent directory creation before `std::fs::write` and `OpenOptions::new().append(true)`:
  ```rust
  if let Some(parent) = std::path::Path::new(path).parent() {
      let _ = std::fs::create_dir_all(parent);
  }
  ```

### 2.4. Lack of Directory Listing (`listDir` / `readDir`) and File Existence Check
* **Issue:** `roc-golem` currently provides `readFile`, `writeFile`, `appendFileBytes`, `readFileBytes`, and `writeFileBytes`. It does not provide:
  - `readDir` / `listDir`
  - `removeFile` / `deleteFile`
  - `fileExists` / `stat`
* **Impact on LLM Wiki & Storage:**
  - The agent cannot scan a directory (e.g., `wiki/inbox/`) at midnight to discover unacted files directly from the filesystem.
  - **Workaround in Consumer Agent:** Maintain a structured index file (e.g., `wiki_index.json` or `manifest.json`) stored in the filesystem or in agent state tracking all file paths and metadata.
* **Suggested Platform Feature:** Add `rocFxListDir! : Str => Result(List(Str), Str)` and `rocFxRemoveFile! : Str => Result({}, Str)` to `Effect.roc` and host WASI bindings.

### 2.6. Critical Bug: HTTP Headers Serialization Mismatch (`encodeHttpRequest` vs Host Rust)
* **Bug Discovery:** `encodeHttpRequest` in `Golem.roc` serialized headers as an array of objects:
  ```json
  "headers": [{"name": "Content-Type", "value": "application/json"}]
  ```
  However, in `host/src/lib.rs` (`perform_wasi_http_request`), the host expected `headers` to be a JSON map/object:
  ```rust
  if let Some(headers_obj) = val.get("headers").and_then(|h| h.as_object()) {
      for (k, v) in headers_obj {
          if let Some(s) = v.as_str() {
              builder = builder.header(k.as_str(), s);
          }
      }
  }
  ```
* **Impact:** `val.get("headers").and_then(|h| h.as_object())` silently returned `None` when given a JSON array! As a result, critical headers such as `Authorization: Bearer <API_KEY>` and `Content-Type: application/json` were omitted from outbound HTTP requests.
* **Fix Applied:** Updated `encodeHttpRequest` in `platform/Golem.roc` to serialize headers into a JSON map:
  ```roc
  headersObj =
      req.headers
          |> List.map(|h| "\"${escape(h.name)}\":\"${escape(h.value)}\"")
          |> Str.join_with(",")
  "{\"url\":\"${escape(req.url)}\",\"method\":\"${escape(req.method)}\",\"headers\":{${headersObj}},...}"
  ```
* **Platform Recommendation:** `host/src/lib.rs` should also support both formats defensively (`as_object()` and `as_array()`).

### 2.7. Golem Cloud LLM Architecture Clarification
* **Docs Verification:** Golem Cloud does *not* provide an ambient or proprietary LLM inference daemon inside the runtime kernel.
* **Standard WASI-HTTP:** All outbound LLM requests (to OpenAI, Anthropic Claude, OpenRouter, Groq, Bedrock, or local Ollama) run via standard WebAssembly `wasi:http/outgoing-handler@0.2.0`.
* **First-Party Crates:** Even Golem's first-party Rust crates (`golemcloud/golem-ai`) are standard client SDKs built on top of `golem-wasi-http` (`reqwest` over `wasi:http`). For all non-Rust languages (TypeScript, Scala, MoonBit, Go, Roc), the official Golem docs mandate making direct HTTP/REST calls to providers.
* **Durable HTTP Guarantee:** Golem's runtime automatically intercepts and checkpoints `wasi:http` requests and responses into the durable worker oplog. Mid-generation failures or worker crashes resume from memory without issuing duplicate HTTP calls to the LLM provider.

---

## 3. Platform Strengths Verified
1. **Compilation Speed & Quality:** Clean compilation with `roc build --target=wasm32` in ~13 seconds, producing valid core WASM.
2. **Golem Component Model Compatibility:** Flawless packaging via `wasm-tools component new` without interface mismatch errors.
3. **RPC Scheduling Primitive:** `rpcSchedule` seamlessly handles future worker invocations via Golem's durable scheduler, ideal for the reminder ladder.
4. **WASI HTTP Integration:** Outbound HTTP request dispatch through `golem_rust::http` allows the worker to contact Telegram and LLM APIs directly.

---

## 4. Verification with Platform Release `v1.4.2`
* **Release Verified:** `thesparq/roc-golem@v1.4.2` (`dd92ab6649600ff6aaf0b0570b56bbb37b9bf48b`).
* **Fix Confirmed:** `encodeHttpRequest` in `Golem.roc` serializes HTTP headers directly into a JSON map (`"headers":{"<name>":"<value>"}`), matching `host/src/lib.rs` expectations.
* **App Compilation:** `main.roc` compiles cleanly against the `v1.4.2` platform archive, componentizing into a 1.1MB validated WebAssembly component at `build/reminders_agent.wasm` (`wasi:http/outgoing-handler@0.2.0` and `golem:agent/guest@2.0.0`).
* **Test Suite:** All 17 unit tests pass in ~600ms via `test_suite.roc`.

