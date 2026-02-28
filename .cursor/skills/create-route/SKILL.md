---
name: create-route
description: Create or modernize MCP tool endpoints for the Roblox Studio MCP server. Use when creating a new tool, adding a route, building a new MCP endpoint, or auditing/fixing existing tools. Guides through creating the Rust route, Luau plugin handler, and .md description file.
---

# Create MCP Tool Route

## Tool Types

Determine which type up front — this decides which files are needed:

- **Dispatch tool** (e.g. `run_code`, `insert_model`) — forwards args to the Roblox Studio plugin via `dispatch_to_studio`. Needs 3 files: `.rs` + `.md` + `.luau`
- **Server-only tool** (e.g. `list_studios`, `get_studio`, `set_studio`) — handles logic inline in Rust. Needs 2 files: `.rs` + `.md`

## Workflow

```
Task Progress:
- [ ] Step 1: Gather requirements
- [ ] Step 2: Create src/tools/tool_name.md
- [ ] Step 3: Create src/tools/tool_name.rs
- [ ] Step 4: Create plugin-build/Tools/tool_name.luau (dispatch only)
- [ ] Step 5: Register in src/tools/mod.rs
- [ ] Step 6: cargo check
```

## Step 1: Gather Requirements

Before writing any code, determine:
- What the tool does and when an agent should use it
- Dispatch to Studio or server-only?
- What parameters it needs (types, valid values, defaults)
- What it returns (text, structured JSON, status message)
- Side effects, preconditions, error conditions

## Step 2: Description File (.md)

Create `src/tools/tool_name.md`. This becomes the `Tool.description` field that the LLM reads during `tools/list`.

Writing guide:
- Lead with a **one-sentence summary** of what the tool does
- Document **return format** if non-obvious (especially structured JSON)
- State **preconditions** (e.g. "call `start_stop_play` to stop first")
- State **side effects** (e.g. "resets datamodel to stop mode after execution")
- Include **error recovery** guidance (what to do when it fails)
- Use inline code for parameter names, enum values, and tool references
- Use proper markdown: paragraphs, lists, code blocks

Example (`src/tools/run_code.md`):
```markdown
Runs a command in Roblox Studio and returns the printed output.
Can be used to both make changes and retrieve information.

The code is executed via `loadstring` in the Studio command bar context.
Output from `print()`, `warn()`, and `error()` is captured and returned.
Return values from the code chunk are also included in the output.
```

## Step 3: Rust Route (.rs)

Create `src/tools/tool_name.rs`. One tool per file.

### Dispatch tool with args

```rust
use super::prelude::*;

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema)]
pub struct ToolNameArgs {
    #[schemars(description = "Purpose. Valid values: x, y, z")]
    pub param: String,
    #[schemars(description = "Purpose. Defaults to 10")]
    pub optional_param: Option<u32>,
}

#[tool_router(router = tool_name_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("tool_name.md")]
    #[tool(annotations(
        read_only_hint = false,
        destructive_hint = false,
        idempotent_hint = true,
        open_world_hint = false
    ))]
    async fn tool_name(
        &self,
        ctx: RequestContext<RoleServer>,
        Parameters(args): Parameters<ToolNameArgs>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "tool_name", &args).await
    }
}
```

### Dispatch tool without args

```rust
use super::prelude::*;

#[tool_router(router = tool_name_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("tool_name.md")]
    #[tool(annotations(
        read_only_hint = true,
        destructive_hint = false,
        idempotent_hint = true,
        open_world_hint = false
    ))]
    async fn tool_name(
        &self,
        ctx: RequestContext<RoleServer>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "tool_name", &()).await
    }
}
```

### Server-only tool with structured output (preferred for new server-only tools)

Use `Json<T>` to auto-generate `outputSchema` and populate `structuredContent`:

```rust
use super::prelude::*;
use rmcp::handler::server::wrapper::Json;

#[derive(Serialize, schemars::JsonSchema)]
pub struct ToolNameResponse {
    #[schemars(description = "Unique identifier")]
    pub id: String,
    #[schemars(description = "Human-readable name")]
    pub name: String,
}

#[tool_router(router = tool_name_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("tool_name.md")]
    #[tool(annotations(
        read_only_hint = true,
        destructive_hint = false,
        idempotent_hint = true,
        open_world_hint = false
    ))]
    async fn tool_name(&self) -> Result<Json<ToolNameResponse>, ErrorData> {
        Ok(Json(ToolNameResponse {
            id: "abc".into(),
            name: "example".into(),
        }))
    }
}
```

### Parameter descriptions

Every args field MUST have `#[schemars(description = "...")]`. Include:
- **Purpose** of the parameter
- **Valid values** — use schemars enums where possible instead of free-text `String`
- **Default** if `Option<T>` (e.g. "Defaults to 100 seconds")
- **Constraints** (ranges, min/max length) where applicable

### Annotations

Set all four explicitly. Decision guide:

| Hint | Question | `true` | `false` |
|------|----------|--------|---------|
| `read_only_hint` | Does it modify any state? | No modifications | Modifies state |
| `destructive_hint` | Can it destroy/lose data? | Yes, irreversible | Safe or additive only |
| `idempotent_hint` | Same result on repeated calls? | No additional effect | Cumulative effects |
| `open_world_hint` | Reaches external services? | External API calls | Closed system only |

`destructive_hint` and `idempotent_hint` are only meaningful when `read_only_hint = false`.

### Error handling

MCP has two error paths — choosing correctly determines whether the LLM can self-correct:

- **`CallToolResult::error()`** — for recoverable failures. The LLM sees these and can retry or call a different tool. Include actionable guidance in the message.
- **`ErrorData`** — for structurally invalid requests (malformed params, type mismatches). LLMs generally cannot recover from these.

Rule: if the LLM could fix the problem by adjusting args or calling another tool first, use `CallToolResult::error()`.

## Step 4: Luau Handler (dispatch tools only)

Create `plugin-build/Tools/tool_name.luau`. The filename MUST exactly match the Rust dispatch string.

```luau
--!strict

type Args = {
  param: string,
  optional_param: number?,
}

local function handleToolName(args: Args): string?
  assert(type(args.param) == "string", "Missing param in ToolName")

  -- implementation here

  return result
end

return handleToolName
```

Rules:
- Module returns a single function matching `(any) -> string?`
- Validate args with `assert(type(args.field) == "expected_type", "Missing field in ToolName")`
- Can require shared utilities from `Utils/` (ConsoleOutput, StudioModeState, GameStopUtil, DeepCopy)
- Can call other tool handlers directly via `require()` if needed

## Step 5: Register

In `src/tools/mod.rs`:
1. Add `mod tool_name;` to the module list
2. Add `+ Self::tool_name_route()` in `build_tool_router()`

## Step 6: Verify

Run `cargo check` to confirm compilation.

## Auditing Existing Tools

When asked to fix, modernize, or audit existing tools, check each tool against this list:

### Description
- [ ] Uses `#[doc = include_str!("tool_name.md")]` (not inline `description = "..."`)
- [ ] `.md` file exists adjacent to the `.rs` file
- [ ] Description leads with one-sentence summary
- [ ] Description documents return format, preconditions, side effects, error recovery

### Annotations
- [ ] All four hints set explicitly (`read_only_hint`, `destructive_hint`, `idempotent_hint`, `open_world_hint`)
- [ ] Values are correct for what the tool actually does (read the plugin-side Luau to verify)

### Parameters
- [ ] Every args field has `#[schemars(description = "...")]`
- [ ] Descriptions include purpose, valid values, and defaults
- [ ] Free-text `String` fields that accept a fixed set of values should use enums instead

### Error handling
- [ ] Recoverable errors use `CallToolResult::error()` with actionable guidance, not `ErrorData`
- [ ] `ErrorData` is only used for structurally invalid requests

### Known anti-patterns in the current codebase

**`ErrorData` for recoverable errors:** `src/server_state.rs` `resolve_studio_id` returns `ErrorData` when no studio is connected or multiple studios exist without a selection. The LLM can fix this by calling `list_studios` + `set_studio`. These should be `CallToolResult::error()` with that guidance.

**Manual JSON serialization:** `list_studios`, `get_studio`, and `set_studio` serialize JSON via `serde_json::to_string_pretty` + `Content::text`. These could return `Json<T>` to auto-generate `outputSchema` and populate `structuredContent`, giving agents typed schemas to work with.

**`#[tool(description = "...")]`:** Any tool still using inline description strings should be migrated to `#[doc = include_str!("tool_name.md")]` with a standalone `.md` file.

## Additional Resources

For deep reference on annotations, `#[doc]` internals, MCP best practices, and `Json<T>` structured output, see [reference.md](reference.md).
