# MCP Tool Route Reference

## `#[doc]` vs `#[tool(description)]`

Both populate the identical `Tool.description` field in the MCP `tools/list` JSON-RPC response. The LLM reads the same field regardless of which approach is used.

How it works in rmcp:
- The `#[tool]` proc macro checks for an explicit `description = "..."` attribute first
- If absent, it falls back to `#[doc]` attributes on the function
- `#[doc = include_str!("file.md")]` preserves the macro expression in the token stream
- The Rust compiler expands `include_str!()` later, producing a `&'static str`
- The result is placed into `Tool { description: Some("...".into()), ... }`

We use `#[doc = include_str!("tool_name.md")]` so descriptions live in standalone `.md` files that are easy to read and edit. Never use `#[tool(description = "...")]` for new tools.

## MCP Description Best Practices

Sources: [MCP spec](https://modelcontextprotocol.io/docs/concepts/tools), [mcp-best-practice.github.io](https://mcp-best-practice.github.io/mcp-best-practice/best-practice/), [mcpbundles.com](https://www.mcpbundles.com/blog/2025/05/06/writing-great-tool-schemas), [Docker MCP blog](https://www.docker.com/blog/mcp-misconceptions-tools-agents-not-api/)

### Tool descriptions

The description is the most important field for LLM consumption. Write it like API documentation for a developer who has never seen your codebase.

- Communicate **affordances and intent**, not just "what it does"
- Define **preconditions** the model can check before calling (e.g. "Studio must be in stop mode")
- Define **postconditions** the model can verify after calling (e.g. "Datamodel resets to stop mode")
- Mention **error recovery** so the model can self-correct on failure
- Keep it concise — one paragraph summary, then details only if needed

### Parameter descriptions

- State purpose, valid values, and defaults
- Prefer **enums over free-text** for modes and statuses — reduces model guessing between "public", "Public", "PUBLIC"
- Add **constraints** (ranges, min/max length) where applicable
- Use `#[schemars(description = "...")]` on every field, no exceptions

### Tool outputs

- Keep outputs small — return stable IDs and short summaries
- Return **machine-checkable outcomes** the agent can evaluate programmatically
- For structured data, use `Json<T>` to generate `outputSchema` and `structuredContent`
- Make tools **idempotent** where possible — retries shouldn't create duplicates

## Annotations Deep-Dive

MCP tool annotations are behavioral hints for clients. Set all four explicitly on every tool.

### `read_only_hint`

Default: `false`. Set to `true` if the tool does not modify its environment.

Codebase examples where `true`: `get_console_output`, `get_studio_mode`, `get_studio`, `list_studios`

### `destructive_hint`

Default: `true`. Set to `false` if the tool cannot destroy or lose data. Only meaningful when `read_only_hint = false`.

Codebase example where `true`: `run_code` (arbitrary code execution can destroy anything)

### `idempotent_hint`

Default: `false`. Set to `true` if repeated calls with the same args have no additional effect. Only meaningful when `read_only_hint = false`.

Codebase examples where `true`: `start_stop_play` (starting when already started returns "Already in play mode"), `set_studio` (setting the same studio twice is a no-op)

### `open_world_hint`

Default: `true`. Set to `false` if the tool operates entirely within a closed system and does not reach external services.

Codebase example where `true`: `insert_model` (queries the Roblox marketplace)

## Error Handling Patterns

MCP distinguishes two error types. Choosing correctly determines whether the LLM can self-correct.

### Tool execution errors (recoverable)

Use when the LLM could fix the problem by adjusting args or calling another tool first.

```rust
Ok(CallToolResult::error(vec![Content::text(
    "No studio selected. Call `list_studios` to see available studios, then `set_studio` to select one."
)]))
```

The LLM sees these in the tool result and can retry or take corrective action.

### Protocol errors (unrecoverable)

Use only for structurally invalid requests the LLM cannot fix.

```rust
Err(ErrorData::invalid_params("studio_id must be a valid UUID", None))
```

### Anti-pattern

Returning `ErrorData` for recoverable situations like "no studio connected" — this should be a `CallToolResult::error()` with actionable guidance instead, because the LLM can fix it by calling `list_studios` + `set_studio`.

## Structured Output with `Json<T>`

For server-only tools that return structured data, use rmcp's `Json<T>` wrapper instead of manual `serde_json::to_string_pretty` + `Content::text`.

### Response struct

```rust
#[derive(Serialize, schemars::JsonSchema)]
pub struct StudioInfo {
    #[schemars(description = "Unique studio connection identifier")]
    pub studio_id: String,
    #[schemars(description = "Name of the Roblox place")]
    pub place_name: String,
    #[schemars(description = "Numeric place identifier")]
    pub place_id: u64,
}
```

### Tool function

```rust
async fn get_studio_info(&self) -> Result<Json<StudioInfo>, ErrorData> {
    Ok(Json(StudioInfo {
        studio_id: "abc-123".into(),
        place_name: "My Game".into(),
        place_id: 12345,
    }))
}
```

### What this produces

In `tools/list`, the tool definition includes an auto-generated `outputSchema`:
```json
{
  "name": "get_studio_info",
  "outputSchema": {
    "type": "object",
    "properties": {
      "studio_id": { "type": "string", "description": "Unique studio connection identifier" },
      "place_name": { "type": "string", "description": "Name of the Roblox place" },
      "place_id": { "type": "integer", "description": "Numeric place identifier" }
    },
    "required": ["studio_id", "place_name", "place_id"]
  }
}
```

In `tools/call`, the response includes both `content` (backward compat) and `structuredContent`:
```json
{
  "content": [{ "type": "text", "text": "{\"studio_id\":\"abc-123\",\"place_name\":\"My Game\",\"place_id\":12345}" }],
  "structuredContent": { "studio_id": "abc-123", "place_name": "My Game", "place_id": 12345 }
}
```

The `#[tool]` macro auto-detects `Json<T>` and `Result<Json<T>, E>` return types and generates the output schema automatically.

### When to use

- Server-only tools returning structured data — use `Json<T>`
- Dispatch tools returning opaque strings from the Luau plugin — use `CallToolResult::success(vec![Content::text(...)])` (existing pattern)
- Dispatch tools could be refactored to parse plugin responses into typed structs, but this is optional

## Modernization Guide

When auditing existing tools, apply fixes in this priority order:

### Priority 1: Error handling (agent effectiveness)

The biggest impact on agent experience. Check `src/server_state.rs` for `ErrorData` returns that should be `CallToolResult::error()`:

```rust
// BEFORE (anti-pattern): agent cannot self-correct
Err(ErrorData::internal_error("No studio connected", None))

// AFTER: agent sees actionable guidance and can fix it
Ok(CallToolResult::error(vec![Content::text(
    "No studio connected. Call `list_studios` to see available studios, then `set_studio` to select one."
)]))
```

Any error where the LLM could recover by calling another tool or adjusting args must use `CallToolResult::error()`.

### Priority 2: Description migration (maintainability)

Move inline `description = "..."` strings to `.md` files:

```rust
// BEFORE
#[tool(description = "Get the console output from Roblox Studio.")]

// AFTER
#[doc = include_str!("get_console_output.md")]
#[tool(annotations(...))]
```

### Priority 3: Structured output (agent intelligence)

Convert server-only tools that manually serialize JSON to use `Json<T>`:

```rust
// BEFORE (list_studios)
let result = serde_json::to_string_pretty(&studios).unwrap_or_else(|_| "[]".to_string());
Ok(CallToolResult::success(vec![Content::text(result)]))

// AFTER
Ok(Json(studios))
// where studios: Vec<StudioInfo> and StudioInfo derives Serialize + JsonSchema
```

This gives agents an `outputSchema` in `tools/list` so they know the exact shape of the response before calling.

### Priority 4: Annotations (client hints)

Ensure all four annotation hints are set explicitly and accurately. Read the plugin-side Luau handler to understand what the tool actually does before deciding values.
