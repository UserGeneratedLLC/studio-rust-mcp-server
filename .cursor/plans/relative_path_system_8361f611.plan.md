---
name: Relative Path System
overview: Replace the DistinctPath system with a new relative path system (GetRelativePath / FromRelativePath) in Paths.luau, replicating Roblox require-by-string semantics with optional DebugId disambiguation.
todos:
  - id: escape
    content: Expand EscapeName/UnescapeName to handle '.' and '@'
    status: completed
  - id: get-relative
    content: Implement GetRelativePath(inst, relativeTo?) with require-by-string semantics and optional DebugId
    status: completed
  - id: from-relative
    content: Implement FromRelativePath(path, relativeTo?) with DebugIdMap fast path and traversal fallback
    status: completed
  - id: codec-update
    content: Update Codec.luau EncodeInstanceRef/DecodeInstanceRef to use new functions and fix relativeTo threading
    status: completed
  - id: exports
    content: Add new functions to the module export table
    status: completed
  - id: spec
    content: Create Paths.spec.luau with 100% scenario coverage using TestEZ (describe/it/expect)
    status: completed
isProject: false
---

# Relative Path System -- Final Implementation

## Files changed


| File                                                                   | Change                                                                                                                                                       |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `[plugin/src/Utils/Paths.luau](plugin/src/Utils/Paths.luau)`           | EscapeName/UnescapeName expanded; GetRelativePath and FromRelativePath added; exports updated                                                                |
| `[plugin/src/Utils/Codec.luau](plugin/src/Utils/Codec.luau)`           | EncodeInstanceRef/DecodeInstanceRef swapped to new functions; fixed missing `parent` arg in DecodeInstance general property path; removed 4 relativeTo TODOs |
| `[plugin/src/Utils/Paths.spec.luau](plugin/src/Utils/Paths.spec.luau)` | New file: ~120+ TestEZ tests                                                                                                                                 |


## Path Format (1:1 with Roblox require-by-string)

The path resolution semantics are a **1:1 match** of the Luau `require()` by-string behavior as documented in the [Roblox LuaGlobals reference](https://create.roblox.com/docs/reference/engine/globals/LuaGlobals#require) and the Luau language docs (`.cursor/rules/luau/`, `.cursor/rules/roblox/en-us/luau/`).

Given `GetRelativePath(inst, relativeTo?)` where `relativeTo` defaults to `game`:


| Relationship                          | Path format                | Example                |
| ------------------------------------- | -------------------------- | ---------------------- |
| `relativeTo == game`                  | `@game` / `@game/path`     | `@game/Workspace/Part` |
| `inst == relativeTo`                  | `@self`                    | `@self`                |
| inst is descendant of relativeTo      | `@self/path`               | `@self/Folder/Child`   |
| 1 level up (parent)                   | `.`                        | `.`                    |
| 1 level up + path down (sibling tree) | `./path`                   | `./Sibling`            |
| 2 levels up (grandparent)             | `..`                       | `..`                   |
| 2 levels up + path down               | `../path`                  | `../Uncle`             |
| N levels up (N >= 3)                  | `(N-1) ".." joined by "/"` | `../..` (3 up)         |
| N levels up + path down               | `prefix/path`              | `../../Cousin`         |
| No common ancestor (orphaned)         | bare `path` (no prefix)    | `OrphanRoot/Child`     |


The `~debugId` suffix is appended to the **last** name segment only when `IsAmbiguous(inst, relativeTo)` returns true.

**Important behavior of IsAmbiguous**: When `relativeTo` is NOT an ancestor of `inst` (sibling, cousin, etc.), `IsAmbiguous` always returns `true` because the walk from `inst` to `relativeTo` never reaches `relativeTo` (it hits `nil` parent first). This means `./`, `../`, `../../` paths always carry a debugId on their last segment. Paths with no name segments (`.`, `..`, `../..`) never carry a debugId since `segCount == 0` skips the check.

## EscapeName / UnescapeName

Escapes 5 characters that conflict with path syntax. Order matters: `%` must be encoded first (to avoid double-encoding) and decoded last.


| Character | Escaped | Purpose                     |
| --------- | ------- | --------------------------- |
| `%`       | `%25`   | Escape character itself     |
| `~`       | `%7E`   | DebugId separator           |
| `/`       | `%2F`   | Path separator              |
| `.`       | `%2E`   | Path prefix `.`/`..`        |
| `@`       | `%40`   | Path prefix `@game`/`@self` |


UnescapeName is case-insensitive on hex digits (`%2f` and `%2F` both unescape to `/`).

## GetRelativePath(inst, relativeTo?)

**Location**: `[plugin/src/Utils/Paths.luau](plugin/src/Utils/Paths.luau)` line 106

**Signature**: `(inst: Instance, _relativeTo: Instance?) -> string`

### Algorithm

1. Assert inputs. Default `relativeTo` to `game`.
2. **Early return**: if `inst == relativeTo`, return `"@game"` or `"@self"`.
3. **Build inst's ancestor chain** as an array `instChain` (child-to-root order) and a hash set `instSet: { [Instance]: number }` mapping each ancestor to its index. Single pass, O(depth).
4. **Find common ancestor**: check `instSet[relativeTo]` first (O(1)). If not found, walk up from `relativeTo.Parent`, incrementing `levelsUp`, checking `instSet` at each step. Exits as soon as a match is found.
5. **No common ancestor** (orphaned/disjoint): collect all names from `instChain`, reverse in-place, append debugId if ambiguous, return bare path.
6. **Collect segments down**: names from `instChain[1..commonIdx-1]` (child-to-root), reversed in-place.
7. **Append debugId** to last segment if `segCount > 0 and IsAmbiguous(inst, _relativeTo)`.
8. **Assemble path** based on `levelsUp`:
  - `levelsUp == 0`: `@game/segDown` or `@self/segDown`
  - `levelsUp == 1`: `./segDown` or `.`
  - `levelsUp >= 2`: `(levelsUp-1) ".." segments / segDown` or just the prefix

## FromRelativePath(path, relativeTo?)

**Location**: `[plugin/src/Utils/Paths.luau](plugin/src/Utils/Paths.luau)` line 194

**Signature**: `(path: string, _relativeTo: Instance?) -> Instance?`

### Parsing model

Resolution has two phases: **determine starting instance**, then **traverse segments**.

**Starting instance** by prefix:


| Prefix                                  | Start instance      | Remaining                                    |
| --------------------------------------- | ------------------- | -------------------------------------------- |
| `@game` (exact)                         | `game`              | (return immediately)                         |
| `@game/rest`                            | `game`              | `rest`                                       |
| `@self` (exact)                         | `relativeTo`        | (return immediately)                         |
| `@self/rest`                            | `relativeTo`        | `rest`                                       |
| First byte is `.` (0x2E)                | `relativeTo.Parent` | entire path (`.`/`..` processed as segments) |
| Bare (no prefix) + `relativeTo == game` | `game`              | entire path                                  |
| Bare + `relativeTo != game`             | `relativeTo.Parent` | entire path                                  |


**Segment-by-segment traversal**:


| Segment      | Action                                        |
| ------------ | --------------------------------------------- |
| `.`          | No-op (stay at current)                       |
| `..`         | Navigate to `.Parent`                         |
| `""` (empty) | No-op (handles double/trailing slashes)       |
| name         | `FindFirstChild(current, UnescapeName(name))` |


`..` is valid **anywhere** in the path, not just at the beginning.

### Algorithm

1. Assert inputs. Default `relativeTo` to `game`.
2. **Extract debugId**: find the last `~` that appears in the last segment (after the last `/`). Uses `string.find(path, "/[^/]*$")` to locate the last slash, then `string.find(path, "~", searchFrom, true)` for the tilde. Splits into `cleanPath` and `debugId`.
3. **DebugId fast path**: if `debugId` present, look up `DebugIdMap[debugId]`. If found, regenerate `GetRelativePath(foundInst, _relativeTo)` and compare with the original `path`. Return on match. This handles all ambiguity cases and ensures the path is canonical.
4. **Exact matches**: `cleanPath == "@game"` returns `game`; `cleanPath == "@self"` returns `relativeTo`.
5. **Determine start + rest** using prefix table above. Return `nil` if `start` is nil or `rest` is empty.
6. **Traverse segments**: split `rest` by `/`, iterate with the segment rules above. Return `nil` if any navigation fails.
7. **Validate debugId**: if present and traversal succeeded, check `GetDebugId(current) == debugId`. Return `nil` on mismatch.

## Codec.luau integration

**Location**: `[plugin/src/Utils/Codec.luau](plugin/src/Utils/Codec.luau)`

### relativeTo threading through the encode/decode pipeline

```
EncodeInstance(inst, depth, nilRef, _relativeTo?)
  relativeTo = _relativeTo or game
  EncodeProperties(inst, nilRef, relativeTo)       -- refs relative to parent context
    EncodeProperty(value, nilRef, scriptType, relativeTo)
      encoder(value, relativeTo)                    -- EncodeInstanceRef(v, relativeTo)
        Paths.GetRelativePath(v, relativeTo)
  for child: EncodeInstance(child, depth-1, nilRef, inst)  -- child uses parent as context
```

```
DecodeInstance(data, nilRef, parent?)
  DecodeProperty(encoded, nilRef, scriptType, parent)      -- refs relative to parent context
    decoder(value, relativeTo)                              -- DecodeInstanceRef(v, relativeTo)
      Paths.FromRelativePath(v, relativeTo)
  for child: DecodeInstance(childData, nilRef, inst)        -- child uses newly-created parent
```

### Bug fixed during implementation

`DecodeInstance`'s general property decode path (line 752) was missing the `parent` argument to `DecodeProperty`. The MeshPart special case (line 731) correctly passed it. This caused all non-MeshPart instance ref properties on non-root instances to decode relative to `game` instead of their parent context, breaking symmetry with the encoding side.

## Test spec

**Location**: `[plugin/src/Utils/Paths.spec.luau](plugin/src/Utils/Paths.spec.luau)`

~120+ TestEZ tests organized as:


| Section                      | Count | Coverage                                                                                                                                          |
| ---------------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| EscapeName                   | 14    | All 5 special chars, empty string, double-encoding, prefix lookalikes                                                                             |
| UnescapeName                 | 10    | All 5 chars, case-insensitive hex, double-decode prevention                                                                                       |
| Round-trip Escape            | 7     | All chars, mixed content, prefix lookalikes                                                                                                       |
| GetRelativePath @game        | 16    | game, service, deep, special chars, orphan                                                                                                        |
| GetRelativePath @self        | 7     | self, child, deep, escaped, service-to-deep                                                                                                       |
| GetRelativePath .            | 3     | Parent, root-from-child, no debugId                                                                                                               |
| GetRelativePath ./           | 2     | Sibling, sibling subtree (both with debugId)                                                                                                      |
| GetRelativePath .. and ../   | 10    | Grandparent, great-grandparent, cousin, deep cousin, cross-service, game-from-deep                                                                |
| GetRelativePath ambiguity    | 7     | Unambiguous, ambiguous twins, debugId placement, orphan debugId                                                                                   |
| FromRelativePath @game       | 12    | game, service, deep, nonexistent, all special char names                                                                                          |
| FromRelativePath @self       | 7     | self, child, deep, nonexistent, default-to-game, escaped                                                                                          |
| FromRelativePath ./          | 7     | Sibling, parent, deep, nonexistent, game-parent-nil, orphan-parent-nil                                                                            |
| FromRelativePath ../         | 8     | Grandparent, uncle, great-grandparent, cousin, deep chain, past-root, nonexistent                                                                 |
| FromRelativePath .. anywhere | 6     | @self mid-path, @game mid-path, multiple, mixed with ., back-to-start, service-loop                                                               |
| FromRelativePath . no-op     | 5     | @self, @game, consecutive, ./., chained                                                                                                           |
| FromRelativePath DebugId     | 7     | Fast path, both twins, no-debugId, mismatch, relative+debugId, traversal validate, @self ambig                                                    |
| FromRelativePath edge cases  | 13    | Empty, nonexistent, @game/.., double slash, trailing slash, all special chars, garbage                                                            |
| Round-trip                   | 20    | game, service, deep, @self, sibling, cousin, parent, grandparent, special chars, twins, orphan-nil, exhaustive all-pairs, all-instances-from-game |


The last two round-trip tests are combinatorial: one tests all pairs of 9 instances as inst/relativeTo (~72 sub-tests), the other tests all 20 tree instances from game.