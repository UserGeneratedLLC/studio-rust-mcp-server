--!strict

local EncodingService = game:GetService("EncodingService")

local msgpack = require("../Packages/msgpack-luau")

-- Sentinel value representing msgpack null. Use this in tables instead of nil,
-- since Lua cannot store nil as a table value. Pass it as a direct value to
-- encode() and it serialises as the msgpack null type (0xC0).
-- Storing NULL as a table *value* requires manual pre-processing before encode.
local NULL: any = newproxy(false)

local function encodeb64(value: any): string
  local packed = msgpack.encode(value)
  local buf = buffer.fromstring(packed)
  local encoded = EncodingService:Base64Encode(buf)
  return buffer.tostring(encoded)
end

local function decodeb64(b64: string): any
  local buf = buffer.fromstring(b64)
  local decoded = EncodingService:Base64Decode(buf)
  return msgpack.decode(buffer.tostring(decoded))
end

return {
  NULL = NULL,
  encode = msgpack.encode,
  decode = msgpack.decode,
  encodeb64 = encodeb64,
  decodeb64 = decodeb64,
}
