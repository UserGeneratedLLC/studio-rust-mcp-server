# /audit - MCP Server Production Audit

**IMMEDIATE ACTION:** Before reading any files, running any commands, or performing any analysis, you MUST call `SwitchMode` with `target_mode_id: "plan"`. Do not proceed with any other step until you are in Plan mode. This is non-negotiable.

**Mode:** This command runs in **Plan mode** (read-only). It does NOT directly apply code changes. The deliverable is a `.cursor/plans/*.plan.md` file containing every approved fix, ready to be executed in a subsequent Agent-mode session.

**Workflow:** Switch to Plan mode -> Analyze -> Report -> Quiz user on each fix -> Write plan file.

## Quality Standards

These standards govern every audit finding.

### Request/Response Integrity

> A tool call from the AI client must produce the **exact same result** whether processed directly (HTTP server mode) or via proxy (port-busy mode). The UUID correlation, serialization, and error handling must be identical in both paths. Any behavioral divergence between the two execution paths is a bug.

### Tool Definition Parity

> Rust-side tool schemas (struct definitions + `#[tool]` attributes in `rbx_studio_server.rs`) must **exactly match** the Luau-side type definitions (`Types.luau`) and dispatcher routing (`ToolDispatcher.luau`). The `ToolArgumentValues` enum variant names must match the Luau dispatcher keys. Any mismatch causes silent failures -- the plugin receives an unknown tool name and errors, or the Rust server serializes arguments the plugin cannot decode.

### Serialization Round-Trip

> Data crossing the JSON boundary (Rust `serde_json` <-> Luau `HttpService:JSONEncode/Decode`) must survive without loss. Enum variant names, field names, optional/required status, and value types must be consistent across the boundary. A value serialized by Rust and deserialized by Luau (or vice versa) must produce the identical logical value.

### Code Quality

> Watch for duplicated logic, dead code, fragile error handling (bare pcall with no error inspection), and state management issues (mutex held across awaits, map entries never cleaned up). Small refactors (2-3 call sites): include in the fix plan. Major rewrites: flag in a "Deferred Refactors" section.

---

## System Layout

The auditor MUST read the relevant files from each layer when tracing the request/response pipeline. This section maps every file in the system.

### MCP Server Layer (Rust)

```
Entry Point
└── src/main.rs                              CLI parsing (--stdio flag). Two modes:
                                              (1) --stdio: starts MCP server + HTTP server
                                              (2) no args: runs install flow.
                                              Binds Axum HTTP server on 127.0.0.1:44755.
                                              If port is busy, falls back to proxy mode
                                              (dud_proxy_loop). Creates RBXStudioServer,
                                              serves on stdio transport via rmcp.

MCP Server
├── src/rbx_studio_server.rs                 Core MCP server implementation.
│                                             RBXStudioServer: implements ServerHandler.
│                                             6 tools defined via #[tool] macro:
│                                               run_code, insert_model, get_console_output,
│                                               start_stop_play, run_script_in_play_mode,
│                                               get_studio_mode.
│                                             ToolArgumentValues enum: variants map 1:1 to
│                                               Luau dispatcher keys (RunCode, InsertModel,
│                                               GetConsoleOutput, StartStopPlay,
│                                               RunScriptInPlayMode, GetStudioMode).
│                                             ToolArguments: wraps ToolArgumentValues + UUID.
│                                             AppState: process_queue (VecDeque), output_map
│                                               (HashMap<Uuid, Sender>), watch channel for
│                                               wakeup notification.
│                                             generic_tool_run(): creates UUID, enqueues
│                                               command, waits for response via mpsc channel.
│                                             HTTP Handlers:
│                                               request_handler (GET /request): long-polls
│                                                 with 15s timeout, returns 423 on timeout.
│                                               response_handler (POST /response): receives
│                                                 RunCommandResponse, routes to output_map
│                                                 sender by UUID.
│                                               proxy_handler (POST /proxy): for multi-
│                                                 instance proxying when port is occupied.
│                                             dud_proxy_loop(): fallback when port is busy.
│                                               Forwards commands to primary instance via
│                                               reqwest POST to /proxy.
│
└── src/error.rs                             Error wrapper. Report type wraps color_eyre
                                              for Axum IntoResponse. Returns 500 with
                                              generic message (no leak of internal errors).

Installation
└── src/install.rs                           Auto-installation for MCP clients.
                                              install_internal(): embeds plugin .rbxm via
                                              include_bytes!, copies to Studio Plugins dir.
                                              Configures Claude Desktop, Cursor, Antigravity
                                              by writing to their JSON config files.
                                              Platform-specific: macOS dialog, Windows pause,
                                              Linux stdout. get_exe_path() handles macOS
                                              security translocation.

Build System
├── build.rs                                 Cargo build script. Uses librojo to build
│                                             plugin.project.json -> MCPStudioPlugin.rbxm
│                                             into OUT_DIR. Rerun trigger: plugin/ changes.
└── plugin.project.json                      Rojo project file for plugin build.
```

### Plugin Layer (Luau)

```
Entry Point
└── plugin/Main.server.luau                  Plugin bootstrap. Guards: exits if RunService
                                              is running (play mode). Spawns GameStopUtil
                                              monitor if Server context. Connects console
                                              output listener. Creates MockWebSocket client
                                              to URI http://localhost:44755. Toggle button
                                              on toolbar for enable/disable. Persists
                                              disabled state via plugin:SetSetting().
                                              toolCallHandler(): extracts tool name from
                                              args table (first key), dispatches via
                                              ToolDispatcher, wraps in ChangeHistoryService
                                              recording.

Type Definitions
└── plugin/Types.luau                        Shared types. InsertModelArgs, RunCodeArgs,
                                              StartStopPlayArgs, RunScriptInPlayModeArgs.
                                              ToolArgs union type. ToolFunction type alias.
                                              CRITICAL: These types must match the Rust
                                              ToolArgumentValues enum variant payloads.

Transport
└── plugin/MockWebSocketService.luau         HTTP long-polling WebSocket simulation.
                                              MockWebSocketClient: polls GET /request in a
                                              loop. On 200: fires MessageReceived. On 423
                                              (timeout): continues polling. On error: waits
                                              POLL_WAIT_TIME (1s) then retries. Send() does
                                              POST to /response endpoint. Close() cancels
                                              poll task, fires Closed event. Connection
                                              states: Connecting, Open, Closing, Closed.

Tool Dispatch
└── plugin/Utils/ToolDispatcher.luau         Routes tool name string to handler function.
                                              Static map of 6 tools. dispatchTool() looks
                                              up handler, errors if not found, calls handler
                                              with args. CRITICAL: Keys must match Rust
                                              ToolArgumentValues variant names exactly.

Tool Implementations
├── plugin/Tools/RunCode.luau                Executes arbitrary Luau via loadstring().
│                                             Overrides print/warn/error in chunk's fenv
│                                             to capture output. Serializes return values
│                                             via custom table serialization (handles
│                                             userdata -> tostring, nested tables -> JSON).
│                                             Uses getfenv/setfenv (deprecated but required
│                                             for output capture).
│
├── plugin/Tools/InsertModel.luau            Searches Creator Store via InsertService:
│                                             GetFreeModels(). Loads first result via
│                                             game:GetObjects(). Wraps multiple objects in
│                                             Model (if physical) or Folder. Names with
│                                             title-cased query, deduplicates against
│                                             workspace children. Positions at camera
│                                             center raycast hit.
│
├── plugin/Tools/GetConsoleOutput.luau       Returns accumulated ConsoleOutput.outputMessage
│                                             buffer. Simple read, no side effects.
│
├── plugin/Tools/GetStudioMode.luau          Returns GlobalVariables.studioMode string.
│                                             One of: "start_play", "run_server", "stop".
│
├── plugin/Tools/StartStopPlay.luau          Controls play mode via StudioTestService.
│                                             callWithTimeout() pattern: spawns callback +
│                                             timeout race using BindableEvent. startPlay()
│                                             calls ExecutePlayModeAsync with 0.1s timeout.
│                                             stop() uses GameStopUtil cross-datamodel
│                                             messaging via plugin settings. runServer()
│                                             calls ExecuteRunModeAsync with 0.1s timeout.
│                                             Updates GlobalVariables.studioMode.
│
└── plugin/Tools/RunScriptInPlayMode.luau    Injects test runner Script into
                                              ServerScriptService. buildTestRunnerSource()
                                              generates wrapper that captures logs via
                                              LogService.MessageOut, runs user code in
                                              pcall, calls StudioTestService:EndTest() with
                                              structured result (success, value, error, logs,
                                              errors, duration, isTimeout). Stops play mode
                                              first via StartStopPlay, waits 0.2s, then
                                              starts. Cleans up test script after execution.

Plugin Utilities
├── plugin/Utils/ConsoleOutput.luau          Accumulates LogService.MessageOut messages
│                                             into outputMessage string. Caps at 10000 chars.
│                                             startListener() returns connection for cleanup.
│
├── plugin/Utils/GlobalVariables.luau        Shared mutable state. studioMode tracks current
│                                             play mode ("stop" | "start_play" | "run_server").
│
├── plugin/Utils/GameStopUtil.luau           Cross-datamodel stop signaling. stopPlay() sets
│                                             plugin setting flag. monitorForStopPlay() polls
│                                             the flag every 1s in Server context, calls
│                                             StudioTestService:EndTest() when set.
│
├── plugin/Utils/PluginUtils.luau            Plugin reference holder. getSettings/setSettings
│                                             wrappers around plugin:GetSetting/SetSetting.
│
├── plugin/Utils/DataModelType.luau          Detects execution context via RunService:
│                                             IsEdit/IsServer/IsClient -> "Edit"|"Server"|
│                                             "Client"|"Unknown".
│
├── plugin/Utils/Paths.luau                  Instance path encoding/decoding (420 lines).
│                                             Encodes Instance hierarchy as path strings.
│                                             Handles name escaping, DebugId mapping.
│
└── plugin/Utils/Codec.luau                  Instance serialization/deserialization (914
                                              lines). Encodes Instance trees to structured
                                              tables (EncodedInstance). Handles properties,
                                              attributes, tags, children. Uses Reflection
                                              API for property discovery.

Tests
├── plugin/sanity.spec.luau                  Basic sanity tests for TestEZ setup.
└── plugin/Utils/Paths.spec.luau             Path encoding/decoding tests (1188 lines).
```

### Audit Reading Order

When auditing a feature, read files in this order to build understanding:

1. **Data flow overview:** `src/main.rs` (entry point, server setup, dual execution paths) -> `src/rbx_studio_server.rs` (MCP tools, AppState, HTTP handlers)
2. **Plugin entry:** `plugin/Main.server.luau` (bootstrap, message handling, tool dispatch flow)
3. **Transport layer:** `plugin/MockWebSocketService.luau` (long-poll implementation) -> `src/rbx_studio_server.rs` `request_handler`/`response_handler` (server side of long-poll)
4. **Type contracts:** `plugin/Types.luau` (Luau types) <-> `src/rbx_studio_server.rs` (Rust struct definitions + ToolArgumentValues enum) -> `plugin/Utils/ToolDispatcher.luau` (dispatcher key map)
5. **Tool implementations:** Read the specific `plugin/Tools/*.luau` file(s) affected by the feature
6. **Utility modules:** `plugin/Utils/Codec.luau` and `plugin/Utils/Paths.luau` if the feature touches serialization or instance paths
7. **Error handling:** `src/error.rs` (Rust error -> HTTP response), `plugin/Main.server.luau` `toolCallHandler` (pcall wrapping + ChangeHistory)
8. **Installation:** `src/install.rs` if the feature affects client configuration or plugin embedding
9. **Build system:** `build.rs` if plugin structure or Rojo project changed

---

## Instructions

### 0. Orientation

Read the workspace rules (`.cursor/rules/persona.mdc`, `.cursor/rules/luau.mdc`, `.cursor/rules/roblox.mdc`) for project conventions and code standards. These inform every audit finding.

### 1. Identify the Feature Scope

**Default behavior:** Audit all changes in the current workspace against `origin/main`. Run:

```bash
git log origin/main..HEAD --oneline
git diff origin/main --stat
git diff origin/main
```

Read the commit log (for intent) and the full diff (for code). If the user provides plan files (via `@` reference), read those for additional context. Do NOT search for or read plan files on your own -- plans may be stale.

**If the user specifies a feature or branch:** Scope the audit to that feature's changes only.

From the diff, identify:

- Which files were modified (Rust server, plugin Luau, tests, build config)
- What the feature does (new tool, bug fix, transport change, etc.)
- Which layers of the architecture are affected
- Which execution paths are affected (direct HTTP server, proxy mode, or both)

### 2. Trace the Request/Response Pipeline (MOST CRITICAL)

For each change the feature introduces, trace the **complete lifecycle** through the full pipeline:

#### 2a. Tool Call -> Plugin Execution -> Response

Pick a concrete example. Trace:

1. **MCP client sends tool call** -- Which `#[tool]` method in `RBXStudioServer` handles it? What are the parameter types?
2. **generic_tool_run() enqueues** -- Is the `ToolArgumentValues` variant constructed correctly? Is the UUID generated and inserted into `output_map`?
3. **Watch channel notification** -- Does `trigger.send(())` correctly wake the long-poll waiter?
4. **request_handler dequeues** -- Does the `ToolArguments` serialize to JSON correctly? Does the variant name match what the plugin expects?
5. **Plugin receives via MockWebSocket** -- Does `MessageReceived` fire with the correct body? Is `body.args` decoded correctly?
6. **toolCallHandler dispatches** -- Does `next(args)` extract the correct tool name key? Does `ToolDispatcher.dispatchTool` route to the right handler?
7. **Tool executes** -- Does the handler receive the correct argument table? Does it return the expected string result?
8. **Plugin sends response** -- Does `client:Send()` POST a valid `RunCommandResponse` with the correct UUID?
9. **response_handler receives** -- Does JSON deserialization produce the correct `RunCommandResponse`? Is `output_map` lookup by UUID correct?
10. **generic_tool_run returns** -- Does the mpsc channel receive the result? Is the `output_map` entry cleaned up? Is the `CallToolResult` constructed correctly?

**Verify:** After the full round-trip, does the AI client receive the exact output the tool produced? Is error information preserved or lost?

#### 2b. Proxy Mode Parity

Trace the same tool call through the proxy path (`dud_proxy_loop`):

1. **dud_proxy_loop dequeues** -- Same queue, same `ToolArguments` struct
2. **reqwest POST to /proxy** -- Is the JSON payload identical to what `request_handler` would have returned?
3. **proxy_handler receives** -- Does it correctly enqueue the command and wait for the response?
4. **Response flows back** -- Does the `RunCommandResponse` get correctly deserialized and forwarded back through the proxy chain?

**Verify:** The AI client must receive the **identical result** regardless of whether the direct or proxy path was used. Any difference in error handling, timeout behavior, or response format is a bug.

#### 2c. Error Path Round-Trip

Trace what happens when the tool execution fails:

- Plugin-side error (pcall returns false) -- Does `toolCallHandler` re-throw correctly? Does `sendResponseOnce` encode `success=false`?
- Server-side `response_handler` receives `success=false` -- Is the error message preserved in the `Err(Report)` path?
- `generic_tool_run` receives `Err` -- Does `CallToolResult::error()` include the error message?
- **Proxy path:** Does `dud_proxy_loop` propagate errors identically?

#### 2d. Timeout and Disconnection

Trace edge cases:

- **Long-poll timeout** (15s): Does `request_handler` return 423? Does `MockWebSocketService` handle 423 correctly (continue polling, no error)?
- **Plugin disconnects mid-request:** Is the `output_map` entry cleaned up? Does `generic_tool_run` hang forever or error?
- **Server shuts down mid-request:** Does graceful shutdown (`close_tx`) interrupt pending long-polls?
- **Multiple MCP instances:** Does proxy mode correctly handle concurrent tool calls?

### 3. Audit Tool Definition Parity

Cross-reference every tool definition across the Rust/Luau boundary:

#### 3a. Enum Variant <-> Dispatcher Key Mapping

For each tool, verify the chain is unbroken:

| Rust `#[tool]` method | `ToolArgumentValues` variant | Luau `ToolDispatcher` key | Luau handler |
|---|---|---|---|
| `run_code` | `RunCode(RunCode)` | `"RunCode"` | `RunCode.luau` |
| `insert_model` | `InsertModel(InsertModel)` | `"InsertModel"` | `InsertModel.luau` |
| `get_console_output` | `GetConsoleOutput(GetConsoleOutput)` | `"GetConsoleOutput"` | `GetConsoleOutput.luau` |
| `start_stop_play` | `StartStopPlay(StartStopPlay)` | `"StartStopPlay"` | `StartStopPlay.luau` |
| `run_script_in_play_mode` | `RunScriptInPlayMode(RunScriptInPlayMode)` | `"RunScriptInPlayMode"` | `RunScriptInPlayMode.luau` |
| `get_studio_mode` | `GetStudioMode(GetStudioMode)` | `"GetStudioMode"` | `GetStudioMode.luau` |

**The variant name is the JSON key.** Serde serializes `ToolArgumentValues::RunCode(...)` as `{"RunCode": {...}}`. The plugin does `local toolName = next(args)` to extract it. If a variant is renamed in Rust without updating the dispatcher key in Luau, the tool silently breaks.

#### 3b. Parameter Field Parity

For each tool, verify every field in the Rust struct has a matching field in the Luau type:

- **RunCode:** Rust `command: String` <-> Luau `command: string`
- **InsertModel:** Rust `query: String` <-> Luau `query: string`
- **StartStopPlay:** Rust `mode: String` <-> Luau `mode: StartStopPlayMode`
- **RunScriptInPlayMode:** Rust `code: String`, `timeout: Option<u32>`, `mode: String` <-> Luau `code: string`, `timeout: number?`, `mode: TestMode`
- **GetConsoleOutput / GetStudioMode:** No parameters

**Check:** Are there parameters in Rust not present in Luau, or vice versa? An extra field in Rust that Luau ignores is data loss. A field Luau expects that Rust doesn't send causes nil access.

#### 3c. All Callers of Modified Functions

If the feature modifies a tool handler's signature or adds a new tool, search for ALL callers of the modified function using grep. Verify:

- `ToolDispatcher.luau` includes the new tool key
- `ToolArgumentValues` enum has the new variant
- `#[tool_router]` impl block has the new `#[tool]` method
- `Types.luau` has the new args type
- `ToolArgs` union type includes the new variant

**CRITICAL -- Lua silent argument mismatch:** In Luau, calling `foo(a, b)` when the function signature is `function(a, b, c)` does NOT produce any error -- `c` is simply `nil`. Adding a new parameter to a tool handler produces **zero errors** at callers that weren't updated. Grep for every caller of any modified function and verify the argument count matches.

### 4. Audit Serialization Boundaries

#### 4a. Rust -> Luau (Tool Arguments)

`generic_tool_run()` creates `ToolArguments { args: ToolArgumentValues::Variant(...), id: Some(uuid) }`. This is serialized via `Json(task)` in `request_handler` (serde_json). The plugin receives it via `HttpService:JSONDecode`.

Verify:

- Serde's enum serialization format: externally tagged by default, producing `{"args": {"VariantName": {fields}}, "id": "uuid"}`. Is this what the plugin expects?
- Does `body.args` in `Main.server.luau` correctly extract the variant wrapper?
- `next(args)` returns the first key of the table. If serde produces multiple keys (it shouldn't for a single variant), `next()` is non-deterministic.

#### 4b. Luau -> Rust (Tool Response)

The plugin sends `{ id = id, success = success, response = response }` via `client:Send()` -> `doRequest()` -> POST to /response. The server deserializes via `Json(payload): Json<RunCommandResponse>`.

Verify:

- Does `HttpService:JSONEncode` produce the expected field names? (`id`, `success`, `response`)
- Does serde deserialization handle Luau's UUID format? (Luau receives UUID as string from JSON, sends it back as string)
- What happens if `response` is nil in Luau? Does `JSONEncode` produce `null`? Does Rust's `String` deserialization accept `null`?

#### 4c. Edge Values

- **Empty string response:** Does it round-trip as `""` or get lost?
- **Very large response:** Does the 10000-char ConsoleOutput cap interact with HTTP body limits?
- **Special characters in response:** Unicode, null bytes, control characters
- **nil tool result:** `toolCallHandler` returns `response or ""` -- but the tool function returns `string?`. Does `or ""` cover all nil cases?

### 5. Audit State Management

#### 5a. AppState Mutex

`AppState` is behind `Arc<Mutex<AppState>>` (tokio Mutex). Verify:

- **No lock held across awaits in request_handler:** The current code acquires the lock, pops from queue, and releases before awaiting. Is this pattern consistent?
- **No lock held across awaits in generic_tool_run:** Lock is acquired to push + insert, released immediately, then awaits on rx. Correct pattern?
- **dud_proxy_loop lock pattern:** Acquires lock to pop, releases, does HTTP call, acquires again to get sender. Is there a race where the sender is removed between the two lock acquisitions?

#### 5b. Output Map Cleanup

`output_map.insert(id, tx)` in `generic_tool_run()`. After receiving response, `output_map.remove_entry(&id)`. Verify:

- **Normal path:** Entry is always removed after `rx.recv()`
- **Error path:** If `rx.recv()` returns `None` (sender dropped), is the entry still removed? (Currently: no -- `Err(ErrorData)` is returned before cleanup)
- **response_handler:** Calls `output_map.remove(&payload.id)` -- this consumes the sender. If `response_handler` is called twice with the same ID, the second call gets `None` and returns an error. Is this the correct behavior?
- **Timeout:** If the plugin never responds, `rx.recv()` blocks forever. Is there a timeout? (Currently: no -- the MCP client may have its own timeout, but the server goroutine leaks the map entry)

#### 5c. Queue Ordering

`process_queue` is a `VecDeque`. Multiple MCP tool calls can arrive concurrently (from different MCP clients via proxy, or from concurrent tool calls). Verify:

- FIFO ordering is maintained
- No tool call can be lost (enqueue + trigger is atomic under the lock)
- No tool call can be delivered twice (pop_front under lock)

### 6. Audit HTTP Communication

#### 6a. Long-Poll Implementation

`request_handler` uses `tokio::time::timeout(15s, async { ... })`:

- **Timeout returns 423 (LOCKED):** Does the plugin handle this correctly? `MockWebSocketService` checks `response.StatusCode == 423` and continues. Correct.
- **Wakeup loop:** The inner loop clones the watch receiver, checks queue, awaits `waiter.changed()`. Verify no spurious wakeups cause issues (watch channel can fire even if queue is empty).
- **Multiple waiters:** If multiple plugin instances poll simultaneously, only one gets the command (pop_front under lock). Others loop back to wait. Correct?

#### 6b. Proxy Mode

When port 44755 is already bound:

- `dud_proxy_loop` starts instead of Axum server
- Commands are forwarded via `reqwest::Client` POST to the primary instance's `/proxy` endpoint
- **Error handling:** If the primary instance is unreachable, `res` is `Err`. Currently: logs error but does NOT notify the output_map sender. The mpsc channel will never receive a response, causing `generic_tool_run` to hang forever.
- **Exit condition:** `while exit.is_empty()` checks the oneshot channel. When MCP session ends, `close_tx.send(())` fires. But if `dud_proxy_loop` is blocked on `waiter.changed().await`, it won't check the exit condition until the next wakeup.

#### 6c. Connection Lifecycle

- **Plugin toggle button:** Connects/disconnects MockWebSocket. Verify `Close()` correctly cancels the poll task.
- **Server graceful shutdown:** `close_tx`/`close_rx` oneshot triggers Axum's graceful shutdown. Pending long-polls should be interrupted.
- **Plugin unloading:** `plugin.Unloading` disconnects console output listener. But does it close the MockWebSocket? (Currently: no explicit close in Unloading handler)

### 7. Audit Plugin Tool Execution

#### 7a. Error Handling Pattern

`toolCallHandler` in `Main.server.luau`:

```
local recording = ChangeHistoryService:TryBeginRecording("StudioMCP")
local success, response = pcall(ToolDispatcher.dispatchTool, toolName, toolArgs)
if recording then
  ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
```

Verify:

- **Error in tool -> FinishRecording still called:** Yes, because pcall catches the error. But the recording is committed even on failure. Should it be rolled back (`Enum.FinishRecordingOperation.Cancel`) on error?
- **TryBeginRecording returns nil:** Can happen if another recording is in progress. The `if recording` guard handles this correctly.
- **Re-throw behavior:** `error("Error handling request: " .. tostring(response))` re-throws after FinishRecording. This is caught by `connectWebSocket`'s pcall around `toolCallHandler`. Does `sendResponseOnce(success, response)` receive the re-thrown error message?

#### 7b. RunCode Safety

`RunCode.luau` uses `loadstring(command)` + `getfenv`/`setfenv`:

- **Arbitrary code execution:** By design -- this is the tool's purpose. But verify there are no unintended sandbox escapes beyond what Studio already permits.
- **Output capture:** `print`/`warn`/`error` are overridden in the chunk's fenv. Original functions are preserved. After execution, the overrides are discarded (fenv is local to the chunk).
- **Error override:** `chunkfenv.error = function(...) oldError(...) addToOutput("[ERROR]", ...) end` -- this calls the real `error()` which throws, so `addToOutput` is never reached after `oldError(...)`. The output capture for `error()` is dead code.
- **Table serialization:** `serializeTable` handles tables and userdata. Verify it doesn't infinite-loop on circular table references (`deepClone` has a cache, but `serializeTable` does not).

#### 7c. Play Mode State Machine

`GlobalVariables.studioMode` tracks the current mode. Verify state transitions are consistent:

- `startPlay()` sets mode to `"start_play"` before calling `ExecutePlayModeAsync`
- `stop()` calls `GameStopUtil.stopPlay()`, waits 1s, sets mode to `"stop"`
- `runServer()` sets mode to `"run_server"` before calling `ExecuteRunModeAsync`
- `RunScriptInPlayMode` calls `StartStopPlay({ mode = "stop" })` first, waits 0.2s, then starts

**Race condition:** If a tool call arrives while play mode is transitioning (e.g., `ExecutePlayModeAsync` is yielding), `studioMode` may not reflect reality. The 0.1s timeout in `callWithTimeout` means the function returns before `ExecutePlayModeAsync` completes.

#### 7d. GameStopUtil Cross-DataModel Messaging

`stopPlay()` writes a plugin setting, `monitorForStopPlay()` polls it every 1s. This is the only mechanism for Edit-mode code to signal Server-mode code to stop.

- **1s polling interval:** There's up to 1s latency before the stop signal is detected.
- **Race with EndTest:** If `StudioTestService:EndTest()` is called while `RunScriptInPlayMode` is still waiting on `ExecutePlayModeAsync`, the async call resolves and execution continues. Is this handled?

### 8. Audit Codec/Paths Utilities

If the feature touches `Codec.luau` (914 lines) or `Paths.luau` (420 lines):

#### 8a. Codec.luau

- **Property encoding/decoding:** Uses ReflectionService for property discovery. Verify new properties or types are handled.
- **Round-trip identity:** `encode(instance)` -> `decode(encoded)` should produce equivalent data. Test with edge cases: instances with no properties, deeply nested children, special attribute types.
- **Security filtering:** Does it filter out properties that shouldn't be exposed?

#### 8b. Paths.luau

- **Name escaping:** `UnescapeName`/`EscapeName` must be inverse operations. A name containing path separators or escape characters must survive the round-trip.
- **DebugId mapping:** `DebugIdMap` maps debug IDs to instances. Verify entries are cleaned up when instances are destroyed.
- **Edge cases:** Empty names, names with only special characters, very long names, names containing null bytes.

### 9. Audit Installation System

If the feature touches `install.rs`:

- **Config file discovery:** `get_claude_config()`, `get_cursor_config()`, `get_antigravity_config()` -- verify paths are correct for each OS.
- **Existing config preservation:** `install_to_config()` reads existing JSON, merges `mcpServers` key, writes back. Verify it doesn't clobber other MCP server entries.
- **Old key cleanup:** Removes `"Roblox Studio"` (space) key, writes `"Roblox_Studio"` (underscore). Verify both keys don't coexist after migration.
- **Plugin embedding:** `include_bytes!` embeds the Rojo-built .rbxm. Verify `build.rs` output path matches the include path.
- **Error resilience:** If one config fails, others should still be attempted (`results` collects all, `filter_map` separates successes from errors).

### 10. Check Project-Specific Patterns

#### 10a. Dual Execution Paths

Every tool call flows through one of two paths:

1. **Direct:** `generic_tool_run` -> `process_queue` -> `request_handler` (Axum) -> plugin
2. **Proxy:** `generic_tool_run` -> `process_queue` -> `dud_proxy_loop` -> reqwest POST /proxy -> `proxy_handler` (on primary instance) -> `process_queue` -> `request_handler` -> plugin

Both paths must produce identical results. Common divergence points:

- Error handling: `dud_proxy_loop` uses `reqwest` errors; direct path uses Axum/channel errors
- Timeout behavior: Direct path has 15s long-poll timeout; proxy path has no explicit timeout on the reqwest call
- Response format: Proxy path deserializes `RunCommandResponse` then re-maps success/error; direct path receives directly via mpsc channel

#### 10b. Enum Variant Naming

Serde's default enum serialization is externally tagged. `ToolArgumentValues::RunCode(RunCode { command: "..." })` becomes:

```json
{"RunCode": {"command": "..."}}
```

The plugin uses `next(body.args)` to get the key `"RunCode"`, then looks it up in `ToolDispatcher.tools`. If the Rust enum variant is renamed (e.g., `RunLuaCode`), the plugin silently fails because `tools["RunLuaCode"]` returns nil.

**Verify:** Every `ToolArgumentValues` variant name matches its `ToolDispatcher` key exactly.

#### 10c. Response ID Correlation

The UUID flows: Rust generates it in `ToolArguments::new()` -> JSON serialized to plugin -> plugin reads `body.id` -> plugin sends it back in response -> `response_handler` looks up `output_map[id]`.

- **Type consistency:** Rust UUID serializes as a hyphenated string (`"550e8400-e29b-41d4-a716-446655440000"`). Luau receives it as a string, sends it back as a string. Rust deserializes it back as `Uuid`. Does `serde_json` correctly round-trip UUID strings?
- **Null ID:** `ToolArguments.id` is `Option<Uuid>`. In `generic_tool_run`, `with_id()` always sets it to `Some`. But `proxy_handler` reads `command.id.ok_or_eyre("Got proxy command with no id")`. If the primary instance somehow sends a command with no ID, the proxy errors. Is this possible?

#### 10d. Console Output Buffer

`ConsoleOutput.outputMessage` accumulates messages up to 10000 chars. It is:

- **Never cleared by GetConsoleOutput:** Reading the buffer doesn't reset it. Subsequent calls return the same (growing) buffer.
- **Cleared by StartStopPlay.startPlay() and RunScriptInPlayMode:** Both set `outputMessage = ""` before starting play mode.
- **Potential stale data:** If a tool reads console output between two play sessions without an explicit clear, it gets output from the previous session.

#### 10e. ChangeHistoryService Lifecycle

`toolCallHandler` wraps every tool call in a ChangeHistory recording. Verify:

- **Commit on error:** Currently commits even when the tool errors. This means failed changes are recorded in undo history. Should it cancel instead?
- **Nested recordings:** If a tool calls another tool (e.g., `RunScriptInPlayMode` calls `StartStopPlay`), does `TryBeginRecording` return nil for the inner call? Is this handled?
- **Non-mutating tools:** `GetConsoleOutput` and `GetStudioMode` don't modify the datamodel. Creating a recording for them is unnecessary overhead.

#### 10f. Plugin Unloading Cleanup

`plugin.Unloading` only disconnects the console output listener. It does NOT:

- Close the MockWebSocket client
- Cancel any in-progress tool execution
- Clear the console output buffer
- Reset GlobalVariables.studioMode

Verify whether missing cleanup causes issues on plugin reload.

#### 10g. MockWebSocket Error Recovery

The polling loop in `_OpenImpl`:

```lua
while self.ConnectionState == EnumWebSocketState.Open do
  local response = doRequest(...)
  if response then
    if response.StatusCode == 200 and response.Success then
      self._MessageReceivedEvent:Fire(response.Body)
      continue
    elseif response.StatusCode == 423 then
      continue
    end
  end
  task.wait(POLL_WAIT_TIME)
end
```

- **Non-200/non-423 status codes:** Fall through to `task.wait(1)` then retry. No backoff, no error logging, no max retry limit. A server returning 500 causes infinite 1-second retries.
- **Network failure:** `doRequest` pcalls `RequestAsync`. On failure, returns nil. Falls through to wait + retry. Same infinite retry behavior.
- **Server restart:** If the Rust server restarts, the plugin silently reconnects after at most 1 second. This is likely desirable behavior.

#### 10h. Concurrent Tool Calls

Multiple MCP clients can send tool calls simultaneously (e.g., two Cursor windows, or Cursor + Claude Desktop). Each gets its own `generic_tool_run` goroutine with its own UUID and mpsc channel.

- **Queue ordering:** FIFO via VecDeque. First-enqueued is first-served to the plugin.
- **Single plugin consumer:** Only one plugin polls at a time. If the plugin is processing a tool call (blocking in `toolCallHandler`), the poll loop is blocked. Other commands queue up server-side.
- **UUID isolation:** Each command has a unique UUID. Responses are routed by UUID. No cross-contamination.

### 11. Run Static Analysis

Run `cargo clippy` and Selene on modified code:

```bash
cargo clippy --all-targets 2>&1
```

If plugin files were modified:

```bash
selene plugin/src
stylua --check plugin/
```

Focus on warnings in files modified by the feature.

### 12. Produce the Report

Structured report with:

- **Critical issues** -- data loss, incorrect tool routing, silent failures, response correlation bugs
- **Correctness concerns** -- edge cases, race conditions, timeout gaps
- **Missing test coverage** -- specific test cases needed, prioritized by risk
- **Code quality items** -- dead code, unnecessary operations, DRY violations
- **Deferred refactors** -- major structural improvements too large to do inline
- For each issue: **file path, line numbers, description, and suggested fix**

### 13. Quiz User on Each Planned Fix

**No code changes may be applied until the user explicitly approves each one.** After producing the report, present EVERY planned fix to the user for approval.

For each fix, use the **AskQuestion tool** to present:

1. **What the fix changes** -- which file(s), what code, what behavior changes
2. **Why it's needed** -- which audit finding it addresses
3. **Risk assessment** -- could this fix break anything else?
4. **Options:**
   - **Apply** -- proceed with this fix
   - **Skip** -- do not apply (document the reason)
   - **Modify** -- user wants a different approach (wait for their input)

**Rules:**

- Present fixes one at a time
- Group closely related fixes into a single question
- If the user selects "Modify," wait for revised instructions before continuing
- After all fixes are quizzed, summarize which were approved, skipped, and modified

### 14. Create the Fix Plan

Write a plan file to `.cursor/plans/`. This plan is the deliverable -- do NOT directly apply code changes.

**Filename:** `.cursor/plans/<descriptive_slug>.plan.md`

**Plan structure:**

```markdown
# <Title describing the audit scope>

> This plan was generated by `/audit` from a Plan-mode session.

## Standards

These standards govern every fix in this plan.

### Request/Response Integrity

A tool call from the AI client must produce the exact same result whether processed directly (HTTP server mode) or via proxy (port-busy mode). Any behavioral divergence is a bug.

### Tool Definition Parity

Rust-side tool schemas must exactly match Luau-side type definitions and dispatcher routing. Any mismatch causes silent failures.

### Serialization Round-Trip

Data crossing the JSON boundary must survive without loss. Enum variant names, field names, optional/required status, and value types must be consistent.

## Context

<Brief summary of what was audited, which branch/feature, and the audit findings.>

## Fixes

Each fix below was approved by the user during the audit quiz. Implement in order.

### Fix N: <Short title>

- **Status:** Approved | Modified
- **Finding:** <Which audit section identified this>
- **Files:** <List of files to modify>
- **Problem:** <What's wrong, with file paths and line numbers>
- **Solution:** <Exact description of what to change>
- **Risk:** <Blast radius, what else could break>
- **Tests required:**
  - <Specific test description, expected behavior>

## Skipped Fixes

### Skipped: <Short title>

- **Finding:** <Audit section>
- **Problem:** <What's wrong>
- **Reason skipped:** <User's stated reason>

## Deferred Refactors

- <Refactor description, affected files, estimated scope>

## Test Plan

Summary of ALL tests across every fix, organized by layer.

### Rust Unit Tests
- <test description> (Fix N)

### Lua Spec Tests (`.spec.luau` files)
- <test description> (Fix N)

## Test Rules

### For bugs found and fixed

Every bug fix MUST have a test that:
1. Would have FAILED before the fix
2. PASSES after the fix
3. Prevents the bug from regressing

### For missing coverage identified

1. Write the test
2. Verify it passes against the current implementation
3. If it fails, investigate -- it may have found another bug

## Final Step: Run CI

After ALL fixes and tests are implemented, run the `/ci` command to execute the full CI pipeline. Every fix must pass CI before the plan is considered complete.
```

**Rules for the plan file:**

- The plan must be self-contained: an implementer should execute it by reading only the plan file, without re-reading the audit chat
- Every fix must include exact file paths and line numbers (as of the current commit)
- For each fix, list the tests that must accompany it
- Skipped fixes are documented so future audits don't rediscover them
- The plan file is the single source of truth for post-audit work

### 15. Run CI After Plan Execution

After the plan has been fully executed in Agent mode, run the `/ci` command (`.cursor/commands/ci.md`) as the final step. The plan is not complete until CI passes clean.
