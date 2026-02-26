---
name: Codec EncodeInstance test suite
overview: "Create a comprehensive TestEZ test suite in `plugin/Utils/Codec.spec.luau` covering every branch of `EncodeInstance`: all 25 property type encoders, attribute encoding for all 15 attribute types, depth/recursion semantics, children, tags, name escaping, instance references, nilReference behavior, and input validation assertions."
todos:
  - id: create-spec-file
    content: Create plugin/Utils/Codec.spec.luau with TestEZ boilerplate, beforeAll/afterAll setup and teardown
    status: completed
  - id: deep-equal-helper
    content: Use existing plugin/Utils/DeepEquals.luau for recursive table comparison
    status: completed
  - id: validation-tests
    content: Write assertion/validation tests for invalid EncodeInstance inputs
    status: completed
  - id: shallow-tests
    content: Write shallow encoding tests (depth < 0)
    status: completed
  - id: structural-tests
    content: Write structural tests for Folder with full expected table comparison
    status: completed
  - id: depth-recursion-tests
    content: Write depth recursion tests (depth=0,1,2 with children/grandchildren)
    status: completed
  - id: property-type-tests
    content: Write property encoding tests for all reachable types through real instances (Part, Weld, ObjectValue, UICorner, Sound, SpecialMesh, ParticleEmitter, TextLabel, PointLight)
    status: completed
  - id: attribute-tests
    content: Write attribute encoding tests for all 15 AttributeEncoder types (primitive pass-through + wrapped complex)
    status: completed
  - id: tag-tests
    content: Write tags encoding tests (none, single, multiple)
    status: completed
  - id: name-escaping-tests
    content: Write name escaping tests (normal, special chars)
    status: completed
  - id: instance-ref-tests
    content: Write instance reference encoding tests with various relativeTo scenarios
    status: completed
  - id: nil-reference-tests
    content: Write nilReference sentinel behavior tests
    status: completed
  - id: edge-case-tests
    content: Write edge case tests (empty names, deep nesting, combined attributes+tags+children)
    status: completed
  - id: run-tests
    content: Run test suite via scripts/test-plugin.ps1 and verify all pass
    status: completed
isProject: false
---

# Codec EncodeInstance Test Suite

## File

Create [plugin/Utils/Codec.spec.luau](plugin/Utils/Codec.spec.luau), following the same TestEZ pattern as [plugin/Utils/Paths.spec.luau](plugin/Utils/Paths.spec.luau).

## Pre-requisite Code Change

In [plugin/Utils/Codec.luau](plugin/Utils/Codec.luau) line 688, change the depth assertion from:

```luau
assert(math.isfinite(depth) and math.floor(depth) == depth, "InvalidDepth")
```

to:

```luau
assert(depth == depth and math.floor(depth) == depth, "InvalidDepth")
```

This allows `math.huge` / `-math.huge` (useful for "encode everything") while still rejecting `NaN` (`NaN ~= NaN`).

## Key Observations from the Source

- `EncodeInstance` is the **only export** from [plugin/Utils/Codec.luau](plugin/Utils/Codec.luau) (line 837-839)
- Property encoding depends on `GetCachedProperties` (line 489-535), which filters by: not in `SkipProps`, has `ScriptType`, has encoder, has read permission, and either in `SerializeOverride` or (serialized + not deprecated + writable)
- Children get `relativeTo = inst` (the parent), while root properties get `relativeTo = _relativeTo or game` (line 694, 707, 713)
- Attributes use a different encoder map that wraps complex types as `{ [typeof(value)] = encoded }` for non-primitives, and passes through string/number/boolean directly (line 633-642)
- nilReference is a sentinel value for nil properties (line 543-546)

## Test Instance Setup (`beforeAll`)

All instances parented into `ReplicatedStorage` under a test root folder for cleanup. Key instances:

- **Folder** (no properties) -- structural and depth tests
- **Part** -- covers: `Vector3` (Size), `CFrame`, `Color3` (Color), `number` (Transparency, Reflectance, Brightness, Range), `boolean` (Anchored, CanCollide), `EnumItem` (Material, Shape)
- **Part with CustomPhysicalProperties** -- covers: `PhysicalProperties`
- **ObjectValue** -- covers: `Instance` ref (Value property in SerializeOverride)
- **Weld** inside a Part subtree -- covers: `Instance` refs (Part0, Part1), `CFrame` (C0, C1)
- **PointLight** -- covers: `number` (Brightness, Range)
- **UICorner** -- covers: `UDim` (CornerRadius)
- **Frame/TextLabel inside ScreenGui** -- covers: `UDim2`, `Font` (FontFace)
- **Sound** -- covers: `Content` (SoundId)
- **SpecialMesh** -- covers: `Content` (MeshId), `EnumItem` (MeshType)
- **ParticleEmitter** -- covers: `NumberSequence`, `ColorSequence`, `NumberRange`
- **Folder with attributes** -- covers all 15 attribute encoder types (string, number, boolean, UDim, UDim2, Vector2, Vector3, Color3, BrickColor, CFrame, NumberRange, NumberSequence, ColorSequence, Rect, Font)
- **Folder with tags** -- covers tags encoding
- **Folder with special characters in name** -- covers name escaping
- **Nested folder tree** -- covers depth recursion

## Test Categories

### 1. Input Validation (assertions on lines 689-693)

- Passing non-Instance errors ("InvalidInstance")
- Non-integer depth errors ("InvalidDepth")
- NaN depth (0/0) errors ("InvalidDepth")
- Non-integer depth (1.5, -0.7) errors ("InvalidDepth")
- math.huge and -math.huge are now **allowed** (no error)
- `nilReference = nil` errors ("InvalidNilReference")
- Non-Instance relativeTo errors

### 2. Shallow Encoding (depth < 0)

- `depth = -1`: returns `{ Name, ClassName, DebugId, Shallow = true }` only
- `depth = -100`: same behavior
- No Properties, Attributes, Tags, or Children fields

### 3. Structural Encoding -- Folder (depth = 0)

Full expected table comparison since Folder has no serialized properties:

- `Name` matches `Paths.EscapeName(inst.Name)`
- `ClassName` matches `inst.ClassName`
- `DebugId` matches `Paths.GetDebugId(inst)`
- `Properties` absent (empty table from `EncodeProperties` produces no entry)
- `Attributes` absent when none set
- `Tags` absent when none set
- `Children` absent when no children

### 4. Depth Recursion

- **depth=0, no children**: full encoding, no Children field
- **depth=0, with children**: Children present, each child is `Shallow = true`
- **depth=1, with children+grandchildren**: children fully encoded, grandchildren shallow
- **depth=2**: three levels deep, bottom-most is shallow
- **depth=0, children have their own children**: inner children NOT encoded (depth exhausted at child level)
- **depth=math.huge**: encodes entire subtree fully, no shallow nodes anywhere

### 5. Property Type Encoding (25 types via PropertyEncoders)

For each type, set a known property value on a real instance, encode, and verify the specific property in the output:


| Type               | Instance.Property             | Input                                    | Expected Encoding                             |
| ------------------ | ----------------------------- | ---------------------------------------- | --------------------------------------------- |
| number             | Part.Transparency             | 0.5                                      | 0.5                                           |
| boolean            | Part.Anchored                 | true                                     | true                                          |
| string             | (if available)                | "test"                                   | "test"                                        |
| EnumItem           | Part.Material                 | Enum.Material.Wood                       | `{Type="Material", Name="Wood"}`              |
| Vector3            | Part.Size                     | Vector3.new(4,2,8)                       | `{4,2,8}`                                     |
| Color3             | Part.Color                    | Color3.new(1,0,0.5)                      | `{1,0,0.5}`                                   |
| CFrame             | Part.CFrame                   | CFrame.new(1,2,3)                        | 12-component array                            |
| Content            | Sound.SoundId                 | Content.fromUri("rbxassetid://123")      | "rbxassetid://123"                            |
| Content (None)     | Sound.SoundId                 | (default/empty)                          | ""                                            |
| UDim               | UICorner.CornerRadius         | UDim.new(0.5, 10)                        | `{0.5, 10}`                                   |
| UDim2              | (via Frame/UI)                | UDim2.new(0.5,10,0.3,20)                 | `{0.5,10,0.3,20}`                             |
| Font               | TextLabel.FontFace            | Font.new("rbxasset://...", Bold, Italic) | `{family=..., weight="Bold", style="Italic"}` |
| Instance           | ObjectValue.Value             | (ref to a Part)                          | relative path string                          |
| Instance (nil)     | ObjectValue.Value             | nil                                      | nilReference sentinel                         |
| PhysicalProperties | Part.CustomPhysicalProperties | PhysicalProperties.new(2,0.5,0.3,1,1)    | `{2,0.5,0.3,1,1}`                             |
| NumberSequence     | ParticleEmitter property      | 2 keypoints                              | array of `{time,value,envelope}`              |
| ColorSequence      | ParticleEmitter property      | 2 keypoints                              | array of `{time,r,g,b}`                       |
| NumberRange        | ParticleEmitter property      | NumberRange.new(1,5)                     | `{1,5}`                                       |


Types harder to reach via properties but should still have encoder tests via attribute encoding:

- **Vector2**, **BrickColor**, **Rect** -- tested through attributes

### 6. Attribute Encoding (all 15 types in AttributeEncoders)

Create a Folder, set known attributes, encode, verify `Attributes` field:

- **Primitives** (pass-through): string -> "hello", number -> 42, boolean -> true
- **Wrapped complex types** (each as `{[typeof] = encoded}`):
  - `UDim` -> `{ UDim = {0.5, 10} }`
  - `UDim2` -> `{ UDim2 = {0.5, 10, 0.3, 20} }`
  - `Vector2` -> `{ Vector2 = {1.5, 2.5} }`
  - `Vector3` -> `{ Vector3 = {1, 2, 3} }`
  - `Color3` -> `{ Color3 = {1, 0, 0.5} }`
  - `BrickColor` -> `{ BrickColor = "Bright red" }`
  - `CFrame` -> `{ CFrame = {12 components} }`
  - `NumberRange` -> `{ NumberRange = {0, 10} }`
  - `NumberSequence` -> `{ NumberSequence = {{0,0,0},{1,1,0}} }`
  - `ColorSequence` -> `{ ColorSequence = {{0,1,0,0},{1,0,1,0}} }`
  - `Rect` -> `{ Rect = {0, 0, 100, 200} }`
  - `Font` -> `{ Font = {family=..., weight=..., style=...} }`

### 7. Tags Encoding

- No tags -> Tags field absent
- Single tag "Foo" -> `Tags = {"Foo"}`
- Multiple tags -> `Tags = {"A", "B", "C"}` (order may vary -- test with table sort)

### 8. Name Escaping

- Normal name "TestPart" -> "TestPart"
- Name with dot "Has.Dot" -> "Has%2EDot"
- Name with all specials "%~/.@" -> "%25%7E%2F%2E%40"

### 9. Instance References and relativeTo

- ObjectValue.Value pointing to sibling -> encodes as relative path
- ObjectValue.Value = nil -> encodes as nilReference
- Weld.Part0/Part1 refs -> encode as relative paths from relativeTo
- Children get `relativeTo = parent instance` (verify child's instance refs are relative to parent)
- Explicit `_relativeTo` parameter changes ref encoding base

### 10. nilReference Behavior

- Use various sentinel values ("**NIL**", 0, false) to verify they appear for nil properties
- Verify non-nil properties never produce the nilReference value

### 11. Edge Cases

- Instance with empty string name
- Deeply nested tree (4+ levels) at depth=0 vs depth=3
- Instance with many attributes, tags, and children simultaneously
- Encoding `game:GetService("Lighting")` or other services (if accessible)

## Comparison Strategy

Use the existing [plugin/Utils/DeepEquals.luau](plugin/Utils/DeepEquals.luau) module (`require(script.Parent.DeepEquals)`) for recursive table comparison. It handles cycles, NaN, metatables, and bidirectional key checks. For tests where the full Properties table is unpredictable (depends on engine version), check specific expected property keys and values rather than the full table. For Folders (no properties), do full table equality.

## Running

```powershell
.\scripts\test-plugin.ps1
```

