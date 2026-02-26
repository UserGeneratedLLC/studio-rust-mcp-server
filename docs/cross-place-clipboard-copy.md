# Cross-Place Clipboard Copy-Paste

## Goal

Copy instances from Studio Place A and paste them into Studio Place B, using the MCP server as a bridge and the OS clipboard as the transport layer. Both Studio instances connect to the same MCP server.

## Architecture

```
Studio A (plugin)                     Studio B (user)
     │                                      ▲
     │ Selection:Get() → serialize          │ Ctrl+V
     │ → MCP request                        │
     ▼                                      │
┌─────────────────────────────────────────────┐
│              MCP Server (Rust)              │
│                                             │
│  Receive instance data → build rbx-dom     │
│  tree → serialize to RBXM binary →         │
│  write to OS clipboard in Studio format    │
└─────────────────────────────────────────────┘
```

## Studio Plugin Clipboard API

### What Exists

| API | Security | Usable by Plugins? | Notes |
|-----|----------|--------------------|-------|
| `StudioService:CopyToClipboard(string)` | RobloxScriptSecurity | **No** | Text-only, locked to internal scripts |
| `StudioService:SerializeInstances(objects)` | RobloxScriptSecurity | **No** | Removed in engine v524 (April 2022) |
| `Selection:Get()` / `Selection:Set()` | PluginSecurity | **Yes** | Read/write Studio selection |
| `Plugin:StartDrag(data)` | PluginSecurity | **Yes** | Drag-and-drop between plugin GUIs only |
| `TextBox` copy workaround | N/A | **Partial** | Select text in a TextBox, user must Ctrl+C; 16K char limit |

### Key Takeaway

There is **no plugin-accessible API** for reading from or writing to the OS clipboard. The MCP server (running as a native Rust process) must handle all clipboard I/O.

## The Ref Property Problem

### What Breaks

When instances are serialized to RBXM (via `SerializationService`, file export, or clipboard copy), **Ref properties** pointing to instances outside the serialized set are lost.

RBXM files use internal referent IDs to link instances within the file. A `Sound.SoundGroup` pointing to a `SoundGroup` in `SoundService` won't survive serialization because that `SoundGroup` is not part of the serialized data.

### Affected Properties

Any property of type `Ref` (also called `Instance` in the property type system) that points outside the copied selection:

- `Sound.SoundGroup` → nil (target is typically in SoundService)
- `Model.PrimaryPart` → preserved **only if** the PrimaryPart is a descendant within the selection
- `ObjectValue.Value` → nil if target is external
- `Weld.Part0` / `Weld.Part1` → nil if either part is external
- Constraint references (`HingeConstraint.Attachment0`, etc.) → nil if attachment is external
- `Beam.Attachment0` / `Beam.Attachment1` → nil if external
- `Camera.CameraSubject` → nil if external

### Behavior Comparison

| Operation | Internal Refs | External Refs |
|-----------|--------------|---------------|
| `Instance:Clone()` | Remapped to clone | **Kept** (points to original, same DataModel) |
| RBXM serialize → same place | Remapped to deserialized copy | **Nil** (referent not found) |
| RBXM serialize → different place | Remapped to deserialized copy | **Nil** (target doesn't exist) |

`Clone()` is more forgiving because both the clone and the target still live in the same DataModel. Cross-place serialization has no such luxury.

## Resolution Strategy

### Phase 1: Record External Refs on Copy

When the plugin sends a "copy" request to the MCP server, it must walk the selection and identify all Ref properties that point **outside** the selection.

For each external ref, record:

1. The instance that owns the property (identified by its position in the serialized tree)
2. The property name (e.g. `"SoundGroup"`)
3. A **path** to the target instance (e.g. `SoundService/MySoundGroup`)

```luau
type ExternalRef = {
    ownerPath: string,    -- path within the copied tree, e.g. "Folder/MySound"
    property: string,     -- "SoundGroup"
    targetPath: string,   -- absolute path in the DataModel, e.g. "SoundService/MySoundGroup"
    targetClass: string,  -- "SoundGroup" (for validation on paste)
}
```

This metadata travels alongside the RBXM data as a sidecar (JSON or msgpack).

### Phase 2: Serialize and Transport

The MCP server receives:
1. The instance tree data (properties, hierarchy)
2. The external ref manifest (list of `ExternalRef` entries)

The server:
1. Builds the instance tree using `rbx-dom` crates
2. Serializes to RBXM binary
3. Writes to the OS clipboard in Studio's expected format
4. Stores the external ref manifest (in memory, keyed to the clipboard operation)

### Phase 3: Resolve External Refs on Paste

After the user pastes in Studio B (Ctrl+V), the plugin on that side:

1. Detects the new instances (via `DescendantAdded` or selection change)
2. Requests the external ref manifest from the MCP server
3. For each `ExternalRef`, resolves `targetPath` in Place B's DataModel
4. If the target exists and matches `targetClass`, sets the property
5. If the target doesn't exist, logs a warning

```luau
local function resolveExternalRefs(pastedRoot: Instance, refs: {ExternalRef})
    for _, ref in refs do
        local owner = resolvePath(pastedRoot, ref.ownerPath)
        local target = resolveAbsolutePath(ref.targetPath)

        if owner and target and target:IsA(ref.targetClass) then
            (owner :: any)[ref.property] = target
        else
            warn(`Could not resolve ref: {ref.ownerPath}.{ref.property} → {ref.targetPath}`)
        end
    end
end
```

### Alternative: Attribute-Based Sidecar

Instead of a separate manifest, embed the external ref data as attributes on the instances themselves before serialization (similar to Rojo `Rojo_Ref_*` attributes):

```luau
-- On copy: tag the instance
sound:SetAttribute("__ExtRef_SoundGroup", "SoundService/MySoundGroup")

-- On paste: resolve and clean up
local targetPath = sound:GetAttribute("__ExtRef_SoundGroup")
if targetPath then
    local target = resolveAbsolutePath(targetPath)
    if target then sound.SoundGroup = target end
    sound:SetAttribute("__ExtRef_SoundGroup", nil)
end
```

**Pros:** Self-contained, no separate manifest needed, survives even manual Ctrl+C/Ctrl+V.
**Cons:** Pollutes attribute space (must clean up), attribute values are strings only (no structured data), attribute name collisions possible.

## Rust Crate Dependencies

| Crate | Purpose |
|-------|---------|
| `rbx_binary` | Serialize/deserialize RBXM binary format |
| `rbx_dom_weak` | In-memory instance tree representation |
| `rbx_reflection` | Property type info and class hierarchy |
| `rbx_xml` | Serialize/deserialize RBXMX (XML model) as fallback |
| `arboard` or `clipboard-win` | OS clipboard read/write |

The clipboard format Studio uses on Windows is a registered clipboard format. Investigate `rbxclip` (Go, github.com/RobloxAPI/rbxclip) for the exact format name and data layout.

## Open Questions

1. **Clipboard format name** — What registered Windows clipboard format does Studio use? `rbxclip` source code is the best reference for this.
2. **Paste detection** — How does the plugin in Place B reliably detect that a paste just happened? `Selection.SelectionChanged` fires after paste, but distinguishing paste from other selection changes needs thought.
3. **Large selections** — OS clipboard has practical size limits. Need to test with large instance trees.
4. **Cross-platform** — macOS uses a different clipboard API (pasteboard). `arboard` abstracts this, but the Studio clipboard format may differ per platform.
5. **Ref property enumeration** — Need a reliable way to enumerate all Ref-type properties for any given class at runtime. The reflection database (`rbx_reflection`) covers this on the Rust side; on the Luau side, this requires a hardcoded list or API introspection.
