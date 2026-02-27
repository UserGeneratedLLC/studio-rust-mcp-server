--!strict

local msgpack = require(script.Parent.Packages["msgpack-luau"])

-- Sentinel value representing msgpack null. Use this in tables instead of nil,
-- since Lua cannot store nil as a table value. Pass it as a direct value to
-- encode() and it serialises as the msgpack null type (0xC0).
-- Storing NULL as a table *value* requires manual pre-processing before encode.
local NULL: any = newproxy(false)

return {
  NULL = NULL,
  encode = msgpack.encode,
  decode = msgpack.decode,
}
