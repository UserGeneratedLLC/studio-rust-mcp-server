---
name: inhouse msgpack shared buffer
overview: "In-house the msgpack-luau library into plugin/Tools/, apply PR #8 inflate encoding, add NULL sentinel support, shared encode buffer passed as parameter, and direct base64 middleware functions. Remove the wally msgpack dependency."
todos:
  - id: inhouse-msgpack
    content: "Create plugin/Tools/msgpack.luau: merge upstream main + PR#8 inflate + NULL sentinel + shared encode buffer + encodeb64/decodeb64 middleware + --!optimize 2 header"
    status: completed
  - id: jest-spec
    content: "Create plugin/Tools/msgpack.spec.luau: full Jest conversion of upstream TestEZ spec + new NULL sentinel tests"
    status: completed
  - id: delete-wrapper
    content: Delete plugin/msgpack.luau wrapper (no longer needed)
    status: completed
  - id: update-main
    content: "Update plugin/Main.server.luau: require from ./Tools/msgpack"
    status: completed
  - id: update-codec
    content: "Update plugin/Utils/Codec.luau: require from ../Tools/msgpack"
    status: completed
  - id: wally-toml
    content: Remove msgpack-luau from wally.toml [dependencies]
    status: completed
  - id: cleanup-packages
    content: Run wally install after removing the dependency (cleans up automatically)
    status: completed
  - id: verify-build
    content: Run cargo build to verify everything compiles
    status: completed
isProject: false
---

# In-house msgpack with NULL Sentinel and Shared Buffer

## 1. In-house msgpack library at `plugin/Tools/msgpack.luau`

Start from the [latest upstream main](https://github.com/cipharius/msgpack-luau/tree/main/src) `msgpack.lua`, then apply:

**A. PR #8 inflate approach** ([source](https://github.com/cipharius/msgpack-luau/pull/8)):

- Replace `computeLength` with `inflate` function (lazy buffer doubling)
- Inner `encode` signature: `(buf, offset, data, tableSet) -> (buffer, number)` -- buffer is passed as parameter, returned when replaced by inflate
- Public `msgpack.encode` passes the shared buffer in, gets back the (possibly grown) buffer and final offset

**B. Shared encode buffer** (encode-only, passed as parameter):

One module-level buffer used for encoding. Passed into `encode()` as a parameter (not referenced as a global upvalue). Size tracked via `buffer.len(buf)` -- no separate size variable.

```luau
local shared = buffer.create(1024)
```

`inflate` doubles by checking `buffer.len(buf)`:

```luau
local function inflate(buf: buffer, minSize: number): buffer
    local size = buffer.len(buf)
    if minSize <= size then return buf end
    while minSize > size do
        size *= 2
    end
    local temp = buffer.create(size)
    buffer.copy(temp, 0, buf)
    return temp
end
```

Inner `encode` receives and returns `buf`:

```luau
local function encode(buf: buffer, offset: number, data: any, tableSet: {[any]: boolean}): (buffer, number)
    -- inflate as needed: buf = inflate(buf, offset + N)
    -- write to buf
    -- return buf, newOffset
end
```

Public API:

```luau
function msgpack.encode(data: any): string
    local buf, offset = encode(shared, 0, data, {})
    shared = buf  -- keep grown buffer for next call
    return buffer.readstring(buf, 0, offset)
end
```

**C. Decode does NOT use the shared buffer**:

`parse()` calls `reverse()` which mutates the buffer in-place for endian byte-swapping. Using the shared buffer would corrupt data. Decode creates a fresh buffer per call via `buffer.fromstring(message)` -- same as upstream. This is correct.

**D. Direct base64 middleware** (`encodeb64`/`decodeb64`):

```luau
function msgpack.encodeb64(data: any): string
    local buf, offset = encode(shared, 0, data, {})
    shared = buf
    local region = buffer.create(offset)
    buffer.copy(region, 0, buf, 0, offset)
    return buffer.tostring(EncodingService:Base64Encode(region))
end

function msgpack.decodeb64(b64: string): any
    local decoded = EncodingService:Base64Decode(buffer.fromstring(b64))
    return (parse(decoded, 0))
end
```

- `encodeb64`: encodes into shared buffer, copies the used region, base64-encodes it. One fewer string allocation vs `encode()` then `fromstring()`.
- `decodeb64`: `Base64Decode` returns a buffer directly. Pass it straight to `parse`. No intermediate string at all.

**E. NULL sentinel support** (stored directly in this module):

- Define `msgpack.NULL = newproxy(false)` sentinel
- In inner `encode()`: add check at the very top -- if `data == msgpack.NULL`, write `0xC0` and return
- In `parse()` at the `0xC0` case: return `msgpack.NULL` instead of `nil`. Preserves map keys and array integrity.

**F. Headers**:

```luau
--!native
--!optimize 2
--!strict
```

**G. Preserve**: utf8Encode, utf8Decode, Int64, UInt64, Extension, MIT license.

## 2. Spec file at `plugin/Tools/msgpack.spec.luau` (Jest, not TestEZ)

Convert the [upstream TestEZ spec](https://github.com/cipharius/msgpack-luau/blob/main/src/msgpack.spec.lua) to **Jest** format matching the project convention in [plugin/Utils/Codec.spec.luau](plugin/Utils/Codec.spec.luau):

```luau
local JestGlobals = require("../../DevPackages/JestGlobals")
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect
```

Key conversions from TestEZ to Jest:

- `expect(x).to.equal(y)` becomes `expect(x).toEqual(y)`
- `expect(x).to.never.equal(y)` becomes `expect(x).never.toEqual(y)`
- `expect(fn).to.throw(msg)` becomes `expect(fn).toThrow(msg)`
- `expect(x).to.be.a("table")` becomes `expect(typeof(x)).toEqual("table")`
- `expect(x).to.be.ok()` becomes `expect(x).toBeTruthy()`
- `expect(x).never.to.be.ok()` becomes `expect(x).toBeFalsy()`

Full faithful conversion of all upstream encode/decode/utf8 tests, plus new tests:

- NULL sentinel encode: `expect(hex(msgpack.encode(msgpack.NULL))).toEqual("C0")`
- NULL sentinel decode in map: decode `{key: null}`, verify `result.key == msgpack.NULL`
- NULL sentinel decode in array: decode `[null, false, true]`, verify `result[1] == msgpack.NULL`
- NULL sentinel round-trip: `encode({a = msgpack.NULL})` then decode, verify key preserved
- NULL sentinel equality: `msgpack.NULL ~= nil`, `msgpack.NULL == msgpack.NULL`
- encodeb64/decodeb64 round-trip tests

## 3. Delete `plugin/msgpack.luau`

The wrapper is eliminated. The NULL sentinel and `encodeb64`/`decodeb64` now live directly in `plugin/Tools/msgpack.luau`.

## 4. Update `plugin/Main.server.luau`

- Change require from `require("./msgpack")` to `require("./Tools/msgpack")`
- `msgpack.encodeb64(...)` and `msgpack.decodeb64(...)` -- same API as before, no call-site changes needed

## 5. Update `plugin/Utils/Codec.luau`

- Change require from `require("../msgpack")` to `require("../Tools/msgpack")` (line 8)
- `msgpack.NULL` re-export on line 837 continues to work -- same API

## 6. Update `wally.toml`

Remove from `[dependencies]`:

```
msgpack-luau = "cipharius/msgpack-luau@0.3.0"
```

Keep the file, `[dev-dependencies]`, and `[package]` section intact.

## 7. Clean up old wally package files

Run `wally install` after removing the dependency from `wally.toml`. Wally handles cleanup automatically.

## No Rust changes

Base64 transport is unchanged. `ws_encode`/`ws_decode` in `src/rbx_studio_server.rs` stay as-is. `base64` remains a direct dependency in `Cargo.toml`.

## Files not touched (per user request)

- `plugin.project.json` -- unchanged
- `plugin-build.project.json` -- unchanged
- `build.rs` -- no changes needed (darklua will convert the new `./Tools/msgpack` require)
- `.darklua.json` -- unchanged
- `Cargo.toml` -- unchanged
- `src/` -- unchanged

