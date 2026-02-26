---
name: FromDistinctPath implementation
overview: Implement `FromDistinctPath` in `Codec.luau` with a DebugIdMap fast-path and a single-call QueryDescendants chain fallback for paths without a debugId.
todos:
  - id: debugid-map
    content: Add module-level DebugIdMap, DescendantAdded/Removing connections, and GetDescendants initialization loop
    status: completed
  - id: from-distinct-path
    content: "Implement FromDistinctPath: split/extract debugId, map fast-path with path verification, QueryDescendants chain fallback"
    status: completed
isProject: false
---

# Implement FromDistinctPath

All changes are in `[plugin/src/Utils/Codec.luau](plugin/src/Utils/Codec.luau)`.

## Path Format Recap

`GetDistinctPath` produces paths like:

```
ServiceName/IntermediateName/.../LeafName~debugId
```

- Only the **last** segment carries a `~debugId` suffix
- All segments are percent-escaped via `EscapeName` (`%` -> `%25`, `~` -> `%7E`, `/` -> `%2F`)
- `UnescapeName` reverses in the opposite order (`/` first, `~` second, `%` last) to avoid double-unescape
- A literal `~` in the output is therefore always the debugId delimiter
- `GetDistinctPath(game)` returns `""` and `FromDistinctPath("")` returns `game`

## 1 -- Module-Level DebugId Map

**Declaration** at line 121 (before `GetDebugId` wrapper):

```luau
local DebugIdMap: { [string]: Instance } = {}
```

**Initialization** at the bottom of the module (lines 842-847), after the `module` table but before `return`:

```luau
game.DescendantAdded:Connect(function(inst) DebugIdMap[GetDebugId(inst)] = inst end)
game.DescendantRemoving:Connect(function(inst) DebugIdMap[GetDebugId(inst)] = nil end)
for _, inst in game:GetDescendants() do
  DebugIdMap[GetDebugId(inst)] = inst
end
```

- `DescendantRemoving` fires **before** removal -- instance is still fully valid, `GetDebugId` is safe to call
- Subtree removal: event fires for the root first, then each descendant (per docs), so all entries are cleaned up
- `DescendantAdded` fires for every descendant individually when a subtree is parented in
- No forward map needed -- DebugId is stable for the instance's lifetime and the instance is intact at event time
- Placed at module bottom to avoid blocking module-level function definitions

## 2 -- FromDistinctPath Implementation (lines 159-201)

### 2a. Extract DebugId (lines 160-167)

- `string.find(path, "~")` on the raw path string to locate the debugId delimiter
- If found: `debugId = string.sub(path, pos + 1)`, `pathWithoutId = string.sub(path, 1, pos - 1)`
- If not found: `debugId = nil`, `pathWithoutId = path`

### 2b. DebugId fast-path (lines 170-172)

1. `DebugIdMap[debugId]` -- if nil, fall through to 2c
2. Verify: `path == GetDistinctPath(inst)` -- single string comparison
3. If match, return the instance. If mismatch, fall through to 2c.

O(1) map lookup + one string comparison. Never returns nil on its own -- always falls through on any miss or mismatch.

### 2b'. Empty path guard (lines 175-178)

If `pathWithoutId == ""`, the path refers to `game` itself. If a debugId was present but didn't match `game`'s debugId, return nil. Otherwise return `game`.

### 2c. QueryDescendants chain fallback (lines 180-200)

Split `pathWithoutId` by `/`, then build a single QueryDescendants selector:

```luau
-- For path "Workspace/Models/Part":
game:QueryDescendants('> [Name = "Workspace"] > [Name = "Models"] > [Name = "Part"]')
```

- `UnescapeName` each segment, then quote with `string.format("%q", name)` -- `%q` handles embedded `"`, `\`, and control chars. Do NOT use `#Name` syntax (no escaping, breaks on spaces/special chars).
- Chain all segments with `> [Name = ...]` combinators (direct-child at each level)
- Single native C++ call via `pcall` -- errors are warned and return nil
- No Luau-side step-by-step iteration

Result handling depends on whether we have a debugId:

**With debugId**: iterate all results, return the one whose `GetDebugId(0)` matches. If none match, return nil immediately -- even if there's exactly 1 result (it's the wrong instance).

**Without debugId**:

- `#results == 0` -> return nil
- `#results == 1` -> return it
- `#results > 1` -> ambiguous, warn and return nil

## 3 -- GetDistinctPath update (line 144)

Added `if inst == game then return "" end` at the top to produce `""` for `game`, symmetric with `FromDistinctPath`'s empty-path guard.

## Research Notes

### GetDebugId

- **Security**: `PluginSecurity` -- accessible from plugins only (not Scripts/LocalScripts)
- `**GetDebugId(0)`** returns just the base ID (e.g. `40701`), no scope prefix. This is what the codebase uses via the `GetDebugId` wrapper on line 121.
- **Session-stable**: unique per instance within a Studio session, not persisted across sessions
- **Not a property**: it's a method, tagged `NotBrowsable` -- invisible to QueryDescendants selectors
- Used internally by the engine as a GUID for physics replication (per NetworkSettings docs)

### Instance.UniqueId

- **Completely inaccessible**: Read = `RobloxScriptSecurity`, Write = `RobloxEngineSecurity`
- Serialized to file (can_load/can_save = true) but `NotReplicated`
- Type is the dedicated `UniqueId` datatype (added engine v553/2022)
- **Cannot be used by our plugin** -- only internal CoreScripts/engine can read it

### QueryDescendants Selector Syntax

From Instance.yaml lines 1817-1952 and CSS comparisons doc:

- `**[property = value]`**: Supports bool, number, string values. *"Letters, numbers, `_`, and `-` can be used without putting the value in quotation marks."* -- implies quotes are needed for other characters, but escaping rules within quotes are **undocumented**.
- `**#Name`**: No escaping mechanism documented. All official examples use simple alphanumeric names (`#RedTree`, `#ModalFrame`). Breaks on names with spaces, `.`, `#`, `[`, `>`, `,`, `:`.
- **Grammar**: Described as *"similar to the one used in `StyleRule` with only a few differences"*. CSS-inspired, so `\` backslash escaping within quoted values is a reasonable assumption.
- `**string.format("%q", name)`**: Produces properly quoted Luau strings with `"`, `\`, and control chars escaped. Best available approach for safe `[Name = ...]` values. Used by the [QueryBuilder](https://github.com/notpoiu/QueryBuilder) library's `FormatValue` for the same purpose.

