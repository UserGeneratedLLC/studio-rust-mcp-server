--!strict
--!native
--!optimize 2

local EncodingService = game:GetService("EncodingService")

local Null = newproxy(false) :: any

local Extension = {}
export type ExtensionType = { _msgpackType: typeof(Extension), type: number, data: buffer }
local function newExtension(extensionType: number, blob: buffer): ExtensionType
  return {
    _msgpackType = Extension,
    type = extensionType,
    data = blob,
  }
end
Extension.new = newExtension
table.freeze(Extension)

local Int64 = {}
export type Int64Type = {
  _msgpackType: typeof(Int64),
  mostSignificantPart: number,
  leastSignificantPart: number,
}
local function newInt64(mostSignificantPart: number, leastSignificantPart: number): Int64Type
  return {
    _msgpackType = Int64,
    mostSignificantPart = mostSignificantPart,
    leastSignificantPart = leastSignificantPart,
  }
end
Int64.new = newInt64
table.freeze(Int64)

local UInt64 = {}
export type UInt64Type = {
  _msgpackType: typeof(UInt64),
  mostSignificantPart: number,
  leastSignificantPart: number,
}
local function newUInt64(mostSignificantPart: number, leastSignificantPart: number): UInt64Type
  return {
    _msgpackType = UInt64,
    mostSignificantPart = mostSignificantPart,
    leastSignificantPart = leastSignificantPart,
  }
end
UInt64.new = newUInt64
table.freeze(UInt64)

local function byteswap16(value: number): number
  local v = bit32.band(value, 0xFFFF)
  return bit32.bor(bit32.rshift(v, 8), bit32.band(bit32.lshift(v, 8), 0xFFFF))
end

local function writeu16be(b: buffer, offset: number, value: number): ()
  buffer.writeu16(b, offset, byteswap16(value))
end

local function writei16be(b: buffer, offset: number, value: number): ()
  buffer.writeu16(b, offset, byteswap16(value))
end

local function writeu32be(b: buffer, offset: number, value: number): ()
  buffer.writeu32(b, offset, bit32.byteswap(value))
end

local function writei32be(b: buffer, offset: number, value: number): ()
  buffer.writeu32(b, offset, bit32.byteswap(value))
end

-- selene: allow(unused_variable)
local function writef32be(b: buffer, offset: number, value: number): ()
  buffer.writef32(b, offset, value)
  buffer.writeu32(b, offset, bit32.byteswap(buffer.readu32(b, offset)))
end

local function writef64be(b: buffer, offset: number, value: number): ()
  buffer.writef64(b, offset, value)
  local lo = bit32.byteswap(buffer.readu32(b, offset))
  local hi = bit32.byteswap(buffer.readu32(b, offset + 4))
  buffer.writeu32(b, offset, hi)
  buffer.writeu32(b, offset + 4, lo)
end

local function readu16be(b: buffer, offset: number): number
  return byteswap16(buffer.readu16(b, offset))
end

local function readi16be(b: buffer, offset: number): number
  local swapped = byteswap16(buffer.readu16(b, offset))
  if swapped >= 0x8000 then
    return swapped - 0x10000
  end
  return swapped
end

local function readu32be(b: buffer, offset: number): number
  return bit32.byteswap(buffer.readu32(b, offset))
end

local function readi32be(b: buffer, offset: number): number
  local swapped = bit32.byteswap(buffer.readu32(b, offset))
  if swapped >= 0x80000000 then
    return swapped - 0x100000000
  end
  return swapped
end

local function readf32be(b: buffer, offset: number): number
  buffer.writeu32(b, offset, bit32.byteswap(buffer.readu32(b, offset)))
  return buffer.readf32(b, offset)
end

local function readf64be(b: buffer, offset: number): number
  local lo = bit32.byteswap(buffer.readu32(b, offset))
  local hi = bit32.byteswap(buffer.readu32(b, offset + 4))
  buffer.writeu32(b, offset, hi)
  buffer.writeu32(b, offset + 4, lo)
  return buffer.readf64(b, offset)
end

local function parse(message: buffer, offset: number): (any, number)
  local byte = buffer.readu8(message, offset)

  if byte == 0xC0 then -- nil
    return Null, offset + 1
  elseif byte == 0xC2 then -- false
    return false, offset + 1
  elseif byte == 0xC3 then -- true
    return true, offset + 1
  elseif byte == 0xC4 then -- bin 8
    local length = buffer.readu8(message, offset + 1)
    local newBuf = buffer.create(length)
    buffer.copy(newBuf, 0, message, offset + 2, length)
    return newBuf, offset + 2 + length
  elseif byte == 0xC5 then -- bin 16
    local length = readu16be(message, offset + 1)
    local newBuf = buffer.create(length)
    buffer.copy(newBuf, 0, message, offset + 3, length)
    return newBuf, offset + 3 + length
  elseif byte == 0xC6 then -- bin 32
    local length = readu32be(message, offset + 1)
    local newBuf = buffer.create(length)
    buffer.copy(newBuf, 0, message, offset + 5, length)
    return newBuf, offset + 5 + length
  elseif byte == 0xC7 then -- ext 8
    local length = buffer.readu8(message, offset + 1)
    local newBuf = buffer.create(length)
    buffer.copy(newBuf, 0, message, offset + 3, length)
    return newExtension(buffer.readu8(message, offset + 2), newBuf), offset + 3 + length
  elseif byte == 0xC8 then -- ext 16
    local length = readu16be(message, offset + 1)
    local newBuf = buffer.create(length)
    buffer.copy(newBuf, 0, message, offset + 4, length)
    return newExtension(buffer.readu8(message, offset + 3), newBuf), offset + 4 + length
  elseif byte == 0xC9 then -- ext 32
    local length = readu32be(message, offset + 1)
    local newBuf = buffer.create(length)
    buffer.copy(newBuf, 0, message, offset + 6, length)
    return newExtension(buffer.readu8(message, offset + 5), newBuf), offset + 6 + length
  elseif byte == 0xCA then -- float 32
    return readf32be(message, offset + 1), offset + 5
  elseif byte == 0xCB then -- float 64
    return readf64be(message, offset + 1), offset + 9
  elseif byte == 0xCC then -- uint 8
    return buffer.readu8(message, offset + 1), offset + 2
  elseif byte == 0xCD then -- uint 16
    return readu16be(message, offset + 1), offset + 3
  elseif byte == 0xCE then -- uint 32
    return readu32be(message, offset + 1), offset + 5
  elseif byte == 0xCF then -- uint 64
    return newUInt64(readu32be(message, offset + 1), readu32be(message, offset + 5)), offset + 9
  elseif byte == 0xD0 then -- int 8
    return buffer.readi8(message, offset + 1), offset + 2
  elseif byte == 0xD1 then -- int 16
    return readi16be(message, offset + 1), offset + 3
  elseif byte == 0xD2 then -- int 32
    return readi32be(message, offset + 1), offset + 5
  elseif byte == 0xD3 then -- int 64
    return newInt64(readu32be(message, offset + 1), readu32be(message, offset + 5)), offset + 9
  elseif byte == 0xD4 then -- fixext 1
    local newBuf = buffer.create(1)
    buffer.copy(newBuf, 0, message, offset + 2, 1)
    return newExtension(buffer.readu8(message, offset + 1), newBuf), offset + 3
  elseif byte == 0xD5 then -- fixext 2
    local newBuf = buffer.create(2)
    buffer.copy(newBuf, 0, message, offset + 2, 2)
    return newExtension(buffer.readu8(message, offset + 1), newBuf), offset + 4
  elseif byte == 0xD6 then -- fixext 4
    local newBuf = buffer.create(4)
    buffer.copy(newBuf, 0, message, offset + 2, 4)
    return newExtension(buffer.readu8(message, offset + 1), newBuf), offset + 6
  elseif byte == 0xD7 then -- fixext 8
    local newBuf = buffer.create(8)
    buffer.copy(newBuf, 0, message, offset + 2, 8)
    return newExtension(buffer.readu8(message, offset + 1), newBuf), offset + 10
  elseif byte == 0xD8 then -- fixext 16
    local newBuf = buffer.create(16)
    buffer.copy(newBuf, 0, message, offset + 2, 16)
    return newExtension(buffer.readu8(message, offset + 1), newBuf), offset + 18
  elseif byte == 0xD9 then -- str 8
    local length = buffer.readu8(message, offset + 1)
    return buffer.readstring(message, offset + 2, length), offset + 2 + length
  elseif byte == 0xDA then -- str 16
    local length = readu16be(message, offset + 1)
    return buffer.readstring(message, offset + 3, length), offset + 3 + length
  elseif byte == 0xDB then -- str 32
    local length = readu32be(message, offset + 1)
    return buffer.readstring(message, offset + 5, length), offset + 5 + length
  elseif byte == 0xDC then -- array 16
    local length = readu16be(message, offset + 1)
    local array = table.create(length)
    local newOffset = offset + 3
    for i = 1, length do
      array[i], newOffset = parse(message, newOffset)
    end
    return array, newOffset
  elseif byte == 0xDD then -- array 32
    local length = readu32be(message, offset + 1)
    local array = table.create(length)
    local newOffset = offset + 5
    for i = 1, length do
      array[i], newOffset = parse(message, newOffset)
    end
    return array, newOffset
  elseif byte == 0xDE then -- map 16
    local length = readu16be(message, offset + 1)
    local dictionary = {}
    local newOffset = offset + 3
    local key
    for _ = 1, length do
      key, newOffset = parse(message, newOffset)
      dictionary[key], newOffset = parse(message, newOffset)
    end
    return dictionary, newOffset
  elseif byte == 0xDF then -- map 32
    local length = readu32be(message, offset + 1)
    local dictionary = {}
    local newOffset = offset + 5
    local key
    for _ = 1, length do
      key, newOffset = parse(message, newOffset)
      dictionary[key], newOffset = parse(message, newOffset)
    end
    return dictionary, newOffset
  elseif byte >= 0xE0 then -- negative fixint
    return byte - 256, offset + 1
  elseif byte <= 0x7F then -- positive fixint
    return byte, offset + 1
  elseif byte - 0x80 <= 0x8F - 0x80 then -- fixmap
    local length = bit32.band(byte, 0xF)
    local dictionary = {}
    local newOffset = offset + 1
    local key
    for _ = 1, length do
      key, newOffset = parse(message, newOffset)
      dictionary[key], newOffset = parse(message, newOffset)
    end
    return dictionary, newOffset
  elseif byte - 0x90 <= 0x9F - 0x90 then -- fixarray
    local length = bit32.band(byte, 0xF)
    local array = table.create(length)
    local newOffset = offset + 1
    for i = 1, length do
      array[i], newOffset = parse(message, newOffset)
    end
    return array, newOffset
  elseif byte - 0xA0 <= 0xBF - 0xA0 then -- fixstr
    local length = byte - 0xA0
    return buffer.readstring(message, offset + 1, length), offset + 1 + length
  end

  error("Unknown type")
end

local function inflate(buf: buffer, minSize: number): buffer
  local size = buffer.len(buf)
  if minSize <= size then
    return buf
  end
  while minSize > size do
    size *= 2
  end
  local temp = buffer.create(size)
  buffer.copy(temp, 0, buf)
  return temp
end

local extensionTypeLUT = {
  [1] = 0xD4,
  [2] = 0xD5,
  [4] = 0xD6,
  [8] = 0xD7,
  [16] = 0xD8,
}

local function encode(
  buf: buffer,
  offset: number,
  data: any,
  tableSet: { [any]: boolean }
): (buffer, number)
  if data == Null then
    data = nil
  end

  local dtype = type(data)
  if data == nil then
    buf = inflate(buf, offset + 1)
    buffer.writestring(buf, offset, "\xC0")
    return buf, offset + 1
  elseif data == false then
    buf = inflate(buf, offset + 1)
    buffer.writestring(buf, offset, "\xC2")
    return buf, offset + 1
  elseif data == true then
    buf = inflate(buf, offset + 1)
    buffer.writestring(buf, offset, "\xC3")
    return buf, offset + 1
  elseif dtype == "string" then
    local length = #data

    if length <= 31 then
      buf = inflate(buf, offset + 1 + length)
      buffer.writeu8(buf, offset, bit32.bor(0xA0, length))
      buffer.writestring(buf, offset + 1, data)
      return buf, offset + 1 + length
    elseif length <= 0xFF then
      buf = inflate(buf, offset + 2 + length)
      buffer.writeu8(buf, offset, 0xD9)
      buffer.writeu8(buf, offset + 1, length)
      buffer.writestring(buf, offset + 2, data)
      return buf, offset + 2 + length
    elseif length <= 0xFFFF then
      buf = inflate(buf, offset + 3 + length)
      buffer.writeu8(buf, offset, 0xDA)
      writeu16be(buf, offset + 1, length)
      buffer.writestring(buf, offset + 3, data)
      return buf, offset + 3 + length
    elseif length <= 0xFFFFFFFF then
      buf = inflate(buf, offset + 5 + length)
      buffer.writeu8(buf, offset, 0xDB)
      writeu32be(buf, offset + 1, length)
      buffer.writestring(buf, offset + 5, data)
      return buf, offset + 5 + length
    end

    error("Could not encode - too long string")
  elseif dtype == "buffer" then
    local length = buffer.len(data)

    if length <= 0xFF then
      buf = inflate(buf, offset + 2 + length)
      buffer.writeu8(buf, offset, 0xC4)
      buffer.writeu8(buf, offset + 1, length)
      buffer.copy(buf, offset + 2, data)
      return buf, offset + 2 + length
    elseif length <= 0xFFFF then
      buf = inflate(buf, offset + 3 + length)
      buffer.writeu8(buf, offset, 0xC5)
      writeu16be(buf, offset + 1, length)
      buffer.copy(buf, offset + 3, data)
      return buf, offset + 3 + length
    elseif length <= 0xFFFFFFFF then
      buf = inflate(buf, offset + 5 + length)
      buffer.writeu8(buf, offset, 0xC6)
      writeu32be(buf, offset + 1, length)
      buffer.copy(buf, offset + 5, data)
      return buf, offset + 5 + length
    end

    error("Could not encode - too long binary buffer")
  elseif dtype == "number" then
    if data == 0 then
      buf = inflate(buf, offset + 1)
      buffer.writeu8(buf, offset, 0)
      return buf, offset + 1
    elseif data ~= data then -- NaN
      buf = inflate(buf, offset + 5)
      buffer.writestring(buf, offset, "\xCA\x7F\x80\x00\x01")
      return buf, offset + 5
    elseif data == math.huge then
      buf = inflate(buf, offset + 5)
      buffer.writestring(buf, offset, "\xCA\x7F\x80\x00\x00")
      return buf, offset + 5
    elseif data == -math.huge then
      buf = inflate(buf, offset + 5)
      buffer.writestring(buf, offset, "\xCA\xFF\x80\x00\x00")
      return buf, offset + 5
    end

    local integral, fractional = math.modf(data)
    local sign = math.sign(data)

    if fractional ~= 0 or integral > 0xFFFFFFFF or integral < -0x80000000 then
      buf = inflate(buf, offset + 9)
      buffer.writeu8(buf, offset, 0xCB)
      writef64be(buf, offset + 1, data)
      return buf, offset + 9
    end

    if sign > 0 then
      if integral <= 127 then -- positive fixint
        buf = inflate(buf, offset + 1)
        buffer.writeu8(buf, offset, integral)
        return buf, offset + 1
      elseif integral <= 0xFF then -- uint 8
        buf = inflate(buf, offset + 2)
        buffer.writeu8(buf, offset, 0xCC)
        buffer.writeu8(buf, offset + 1, integral)
        return buf, offset + 2
      elseif integral <= 0xFFFF then -- uint 16
        buf = inflate(buf, offset + 3)
        buffer.writeu8(buf, offset, 0xCD)
        writeu16be(buf, offset + 1, integral)
        return buf, offset + 3
      elseif integral <= 0xFFFFFFFF then -- uint 32
        buf = inflate(buf, offset + 5)
        buffer.writeu8(buf, offset, 0xCE)
        writeu32be(buf, offset + 1, integral)
        return buf, offset + 5
      end
    else
      if integral >= -0x20 then -- negative fixint
        buf = inflate(buf, offset + 1)
        buffer.writeu8(buf, offset, bit32.bor(0xE0, bit32.extract(integral, 0, 5)))
        return buf, offset + 1
      elseif integral >= -0x80 then -- int 8
        buf = inflate(buf, offset + 2)
        buffer.writeu8(buf, offset, 0xD0)
        buffer.writei8(buf, offset + 1, integral)
        return buf, offset + 2
      elseif integral >= -0x8000 then -- int 16
        buf = inflate(buf, offset + 3)
        buffer.writeu8(buf, offset, 0xD1)
        writei16be(buf, offset + 1, integral)
        return buf, offset + 3
      elseif integral >= -0x80000000 then -- int 32
        buf = inflate(buf, offset + 5)
        buffer.writeu8(buf, offset, 0xD2)
        writei32be(buf, offset + 1, integral)
        return buf, offset + 5
      end
    end

    error(string.format('Could not encode - unhandled number "%s"', typeof(data)))
  elseif dtype == "table" then
    local msgpackType = data._msgpackType

    if msgpackType then
      if msgpackType == Int64 or msgpackType == UInt64 then
        buf = inflate(buf, offset + 9)
        local intType = if msgpackType == UInt64 then 0xCF else 0xD3
        buffer.writeu8(buf, offset, intType)
        writeu32be(buf, offset + 1, data.mostSignificantPart)
        writeu32be(buf, offset + 5, data.leastSignificantPart)
        return buf, offset + 9
      elseif msgpackType == Extension then
        local length = buffer.len(data.data)
        local extType = extensionTypeLUT[length]

        if extType then
          buf = inflate(buf, offset + 2 + length)
          buffer.writeu8(buf, offset, extType)
          buffer.writeu8(buf, offset + 1, data.type)
          buffer.copy(buf, offset + 2, data.data)
          return buf, offset + 2 + length
        end

        if length <= 0xFF then
          buf = inflate(buf, offset + 3 + length)
          buffer.writeu8(buf, offset, 0xC7)
          buffer.writeu8(buf, offset + 1, length)
          buffer.writeu8(buf, offset + 2, data.type)
          buffer.copy(buf, offset + 3, data.data)
          return buf, offset + 3 + length
        elseif length <= 0xFFFF then
          buf = inflate(buf, offset + 4 + length)
          buffer.writeu8(buf, offset, 0xC8)
          writeu16be(buf, offset + 1, length)
          buffer.writeu8(buf, offset + 3, data.type)
          buffer.copy(buf, offset + 4, data.data)
          return buf, offset + 4 + length
        elseif length <= 0xFFFFFFFF then
          buf = inflate(buf, offset + 6 + length)
          buffer.writeu8(buf, offset, 0xC9)
          writeu32be(buf, offset + 1, length)
          buffer.writeu8(buf, offset + 5, data.type)
          buffer.copy(buf, offset + 6, data.data)
          return buf, offset + 6 + length
        end

        error("Could not encode - too long extension data")
      end
    end

    if tableSet[data] then
      error("Can not serialize cyclic table")
    else
      tableSet[data] = true
    end

    local length = #data
    local mapLength = 0

    for _, _ in pairs(data) do
      mapLength += 1
    end

    if length == mapLength then -- array
      local newOffset = offset
      if length <= 15 then
        buf = inflate(buf, offset + 1)
        buffer.writeu8(buf, offset, bit32.bor(0x90, mapLength))
        newOffset += 1
      elseif length <= 0xFFFF then
        buf = inflate(buf, offset + 3)
        buffer.writeu8(buf, offset, 0xDC)
        writeu16be(buf, offset + 1, length)
        newOffset += 3
      elseif length <= 0xFFFFFFFF then
        buf = inflate(buf, offset + 5)
        buffer.writeu8(buf, offset, 0xDD)
        writeu32be(buf, offset + 1, length)
        newOffset += 5
      else
        error("Could not encode - too long array")
      end

      for _, v in ipairs(data) do
        buf, newOffset = encode(buf, newOffset, v, tableSet)
      end

      return buf, newOffset
    else -- map
      local newOffset = offset
      if mapLength <= 15 then
        buf = inflate(buf, offset + 1)
        buffer.writeu8(buf, offset, bit32.bor(0x80, mapLength))
        newOffset += 1
      elseif mapLength <= 0xFFFF then
        buf = inflate(buf, offset + 3)
        buffer.writeu8(buf, offset, 0xDE)
        writeu16be(buf, offset + 1, mapLength)
        newOffset += 3
      elseif mapLength <= 0xFFFFFFFF then
        buf = inflate(buf, offset + 5)
        buffer.writeu8(buf, offset, 0xDF)
        writeu32be(buf, offset + 1, mapLength)
        newOffset += 5
      else
        error("Could not encode - too long map")
      end

      for k, v in pairs(data) do
        buf, newOffset = encode(buf, newOffset, k, tableSet)
        buf, newOffset = encode(buf, newOffset, v, tableSet)
      end

      return buf, newOffset
    end
  end

  error(string.format('Could not encode - unsupported datatype "%s"', typeof(data)))
end

local function utf8Encode(message: string): string
  local messageLength = #message
  local nBytes = math.ceil(messageLength * (8 / 7))
  local result = buffer.create(nBytes)
  local bitPointer = 0
  for i = 1, nBytes do
    local j = 1 + math.floor(bitPointer / 8)
    local bitRemainder = bitPointer % 8
    local byte = string.byte(message, j)
    if bitRemainder == 0 then
      buffer.writeu8(result, i - 1, bit32.extract(byte, 1, 7))
    elseif bitRemainder == 1 then
      buffer.writeu8(result, i - 1, bit32.extract(byte, 0, 7))
    else
      local nextByte = string.byte(message, j + 1) or 0
      buffer.writeu8(
        result,
        i - 1,
        bit32.bor(
          bit32.lshift(bit32.extract(byte, 0, 8 - bitRemainder), bitRemainder - 1),
          bit32.extract(nextByte, 9 - bitRemainder, bitRemainder - 1)
        )
      )
    end
    bitPointer += 7
  end
  return buffer.tostring(result)
end

local function utf8Decode(message: string): string
  local nBytes = math.floor(#message * 7 / 8)
  local result = buffer.create(nBytes)
  local bitPointer = 0
  for i = 1, nBytes do
    local bitRemainder = bitPointer % 7
    local byte = string.byte(message, 1 + math.floor(bitPointer / 7))
    local nextByte = string.byte(message, 2 + math.floor(bitPointer / 7))
    buffer.writeu8(
      result,
      i - 1,
      bit32.bor(
        bit32.lshift(bit32.extract(byte, 0, 7 - bitRemainder), bitRemainder + 1),
        bit32.extract(nextByte, 6 - bitRemainder, 1 + bitRemainder)
      )
    )
    bitPointer += 8
  end
  return buffer.tostring(result)
end

local function decodeData(message: string): any
  assert(type(message) == "string", "must be string")
  assert(#message > 0, "input too short")
  local messageBuf = buffer.fromstring(message)
  local result = parse(messageBuf, 0)
  return result
end

local encodeBuf = buffer.create(0x1000)

local function encodeData(data: any): string
  local buf, offset = encode(encodeBuf, 0, data, {})
  encodeBuf = buf
  return buffer.readstring(buf, 0, offset)
end

local function encodeb64(data: any): string
  local buf, offset = encode(encodeBuf, 0, data, {})
  encodeBuf = buf
  local region = buffer.create(offset)
  buffer.copy(region, 0, buf, 0, offset)
  return buffer.tostring(EncodingService:Base64Encode(region))
end

local function decodeb64(b64: string): any
  local decoded = EncodingService:Base64Decode(buffer.fromstring(b64))
  return parse(decoded, 0)
end

local function unpack64(x: number): (number, number)
  if x < 0 then
    local z = -1 - x
    return bit32.bnot(z // 0x100000000), bit32.bnot(z)
  end
  return bit32.bor(x // 0x100000000, 0), bit32.bor(x, 0)
end

local function uint64(n: number): UInt64Type
  local hi, lo = unpack64(n)
  return newUInt64(hi, lo)
end

local function int64(n: number): Int64Type
  local hi, lo = unpack64(n)
  return newInt64(hi, lo)
end

return table.freeze({
  Null = Null,
  Int64 = Int64,
  UInt64 = UInt64,
  Extension = Extension,
  uint64 = uint64,
  int64 = int64,
  utf8Encode = utf8Encode,
  utf8Decode = utf8Decode,
  decode = decodeData,
  encode = encodeData,
  encodeb64 = encodeb64,
  decodeb64 = decodeb64,
})

--[[
MIT License

Copyright (c) 2024 Valts Liepiņš

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]
