--!strict

local JestGlobals = require("../../DevPackages/JestGlobals")
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local msgpack = require("./msgpack")

local function hex(str: string): string
  local result = table.create(2 * #str - 1)

  for i = 1, #str do
    result[2 * (i - 1) + 1] = string.format("%02X", string.byte(str, i))

    if i ~= #str then
      result[2 * (i - 1) + 2] = " "
    end
  end

  return table.concat(result)
end

describe("decode", function()
  it("can decode nil value", function()
    local message = "\xC0"
    expect(msgpack.decode(message)).toEqual(msgpack.Null)
  end)

  it("can decode false value", function()
    local message = "\xC2"
    expect(msgpack.decode(message)).toEqual(false)
  end)

  it("can decode true value", function()
    local message = "\xC3"
    expect(msgpack.decode(message)).toEqual(true)
  end)

  it("can decode positive fixint value", function()
    expect(msgpack.decode("\x0C")).toEqual(12)
    expect(msgpack.decode("\x00")).toEqual(0)
    expect(msgpack.decode("\x7f")).toEqual(127)
  end)

  it("can decode negative fixint value", function()
    expect(msgpack.decode("\xE0")).toEqual(-32)
    expect(msgpack.decode("\xFF")).toEqual(-1)
    expect(msgpack.decode("\xE7")).toEqual(-25)
  end)

  it("can decode uint 8 value", function()
    expect(msgpack.decode("\xCC\x00")).toEqual(0)
    expect(msgpack.decode("\xCC\xFF")).toEqual(255)
    expect(msgpack.decode("\xCC\x0F")).toEqual(15)
  end)

  it("can decode uint 16 value", function()
    expect(msgpack.decode("\xCD\x00\x00")).toEqual(0)
    expect(msgpack.decode("\xCD\xFF\xFF")).toEqual(65535)
    expect(msgpack.decode("\xCD\x00\xFF")).toEqual(255)
  end)

  it("can decode uint 32 value", function()
    expect(msgpack.decode("\xCE\x00\x00\x00\x00")).toEqual(0)
    expect(msgpack.decode("\xCE\xFF\xFF\xFF\xFF")).toEqual(4294967295)
    expect(msgpack.decode("\xCE\x00\x00\xFF\xFF")).toEqual(65535)
  end)

  it("can decode uint 64 value", function()
    local zeroValue = msgpack.decode("\xCF\x00\x00\x00\x00\x00\x00\x00\x00")
    expect(zeroValue._msgpackType).toEqual(msgpack.UInt64)
    expect(zeroValue.mostSignificantPart).toEqual(0)
    expect(zeroValue.leastSignificantPart).toEqual(0)

    local maxValue = msgpack.decode("\xCF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF")
    expect(maxValue.mostSignificantPart).toEqual(4294967295)
    expect(maxValue.leastSignificantPart).toEqual(4294967295)

    local midValue = msgpack.decode("\xCF\x00\x00\x00\x00\xFF\xFF\xFF\xFF")
    expect(midValue.mostSignificantPart).toEqual(0)
    expect(midValue.leastSignificantPart).toEqual(4294967295)
  end)

  it("can decode int 8 value", function()
    expect(msgpack.decode("\xD0\x00")).toEqual(0)
    expect(msgpack.decode("\xD0\xFF")).toEqual(-1)
    expect(msgpack.decode("\xD0\x0F")).toEqual(15)
    expect(msgpack.decode("\xD0\x7F")).toEqual(127)
    expect(msgpack.decode("\xD0\x80")).toEqual(-128)
  end)

  it("can decode int 16 value", function()
    expect(msgpack.decode("\xD1\x00\x00")).toEqual(0)
    expect(msgpack.decode("\xD1\xFF\xFF")).toEqual(-1)
    expect(msgpack.decode("\xD1\x00\xFF")).toEqual(255)
    expect(msgpack.decode("\xD1\x7F\xFF")).toEqual(32767)
    expect(msgpack.decode("\xD1\x80\x00")).toEqual(-32768)
  end)

  it("can decode int 32 value", function()
    expect(msgpack.decode("\xD2\x00\x00\x00\x00")).toEqual(0)
    expect(msgpack.decode("\xD2\xFF\xFF\xFF\xFF")).toEqual(-1)
    expect(msgpack.decode("\xD2\x00\x00\xFF\xFF")).toEqual(65535)
    expect(msgpack.decode("\xD2\x7F\xFF\xFF\xFF")).toEqual(2147483647)
    expect(msgpack.decode("\xD2\x80\x00\x00\x00")).toEqual(-2147483648)
  end)

  it("can decode int 64 value", function()
    local zeroValue = msgpack.decode("\xD3\x00\x00\x00\x00\x00\x00\x00\x00")
    expect(zeroValue._msgpackType).toEqual(msgpack.Int64)
    expect(zeroValue.mostSignificantPart).toEqual(0)
    expect(zeroValue.leastSignificantPart).toEqual(0)

    local maxValue = msgpack.decode("\xD3\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF")
    expect(maxValue.mostSignificantPart).toEqual(4294967295)
    expect(maxValue.leastSignificantPart).toEqual(4294967295)

    local midValue = msgpack.decode("\xD3\x00\x00\x00\x00\xFF\xFF\xFF\xFF")
    expect(midValue.mostSignificantPart).toEqual(0)
    expect(midValue.leastSignificantPart).toEqual(4294967295)
  end)

  it("can decode float 32 value", function()
    expect(msgpack.decode("\xCA\x00\x00\x00\x00")).toEqual(0)
    expect(msgpack.decode("\xCA\x40\x00\x00\x00")).toEqual(2)
    expect(msgpack.decode("\xCA\xC0\x00\x00\x00")).toEqual(-2)
    expect(msgpack.decode("\xCA\x7F\x80\x00\x00")).toEqual(math.huge)
    expect(msgpack.decode("\xCA\xFF\x80\x00\x00")).toEqual(-math.huge)

    local nan = msgpack.decode("\xCA\xFF\x80\x00\x01")
    expect(nan ~= nan).toEqual(true)
  end)

  it("can decode float 64 value", function()
    expect(msgpack.decode("\xCB\x00\x00\x00\x00\x00\x00\x00\x00")).toEqual(0)
    expect(msgpack.decode("\xCB\x40\x00\x00\x00\x00\x00\x00\x00")).toEqual(2)
    expect(msgpack.decode("\xCB\xC0\x00\x00\x00\x00\x00\x00\x00")).toEqual(-2)
    expect(msgpack.decode("\xCB\x7F\xF0\x00\x00\x00\x00\x00\x00")).toEqual(math.huge)
    expect(msgpack.decode("\xCB\xFF\xF0\x00\x00\x00\x00\x00\x00")).toEqual(-math.huge)

    local nan = msgpack.decode("\xCB\xFF\xF0\x00\x00\x00\x00\x00\x01")
    expect(nan ~= nan).toEqual(true)
  end)

  it("can decode fixstr value", function()
    expect(msgpack.decode("\xA0")).toEqual("")
    expect(msgpack.decode("\xA1\x78")).toEqual("x")
    expect(msgpack.decode("\xAB\x68\x65\x6C\x6C\x6F\x20\x77\x6F\x72\x6C\x64")).toEqual(
      "hello world"
    )
    expect(
      msgpack.decode(
        "\xBF\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61\x61"
      )
    ).toEqual("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  end)

  it("can decode str 8 value", function()
    expect(msgpack.decode("\xD9\x00")).toEqual("")
    expect(msgpack.decode("\xD9\x01\x78")).toEqual("x")
    expect(msgpack.decode("\xD9\x0B\x68\x65\x6C\x6C\x6F\x20\x77\x6F\x72\x6C\x64")).toEqual(
      "hello world"
    )
  end)

  it("can decode str 16 value", function()
    expect(msgpack.decode("\xDA\x00\x00")).toEqual("")
    expect(msgpack.decode("\xDA\x00\x01\x78")).toEqual("x")
    expect(msgpack.decode("\xDA\x00\x0B\x68\x65\x6C\x6C\x6F\x20\x77\x6F\x72\x6C\x64")).toEqual(
      "hello world"
    )
  end)

  it("can decode str 32 value", function()
    expect(msgpack.decode("\xDB\x00\x00\x00\x00")).toEqual("")
    expect(msgpack.decode("\xDB\x00\x00\x00\x01\x78")).toEqual("x")
    expect(msgpack.decode("\xDB\x00\x00\x00\x0B\x68\x65\x6C\x6C\x6F\x20\x77\x6F\x72\x6C\x64")).toEqual(
      "hello world"
    )
  end)

  it("can decode bin 8 value", function()
    local emptyBinary = msgpack.decode("\xC4\x00")
    expect(typeof(emptyBinary)).toEqual("buffer")
    expect(buffer.tostring(emptyBinary)).toEqual("")

    local xBinary = msgpack.decode("\xC4\x01\x78")
    expect(buffer.tostring(xBinary)).toEqual("x")

    local helloBinary = msgpack.decode("\xC4\x0B\x68\x65\x6C\x6C\x6F\x20\x77\x6F\x72\x6C\x64")
    expect(buffer.tostring(helloBinary)).toEqual("hello world")
  end)

  it("can decode bin 16 value", function()
    local emptyBinary = msgpack.decode("\xC5\x00\x00")
    expect(typeof(emptyBinary)).toEqual("buffer")
    expect(buffer.tostring(emptyBinary)).toEqual("")

    local xBinary = msgpack.decode("\xC5\x00\x01\x78")
    expect(buffer.tostring(xBinary)).toEqual("x")

    local helloBinary = msgpack.decode("\xC5\x00\x0B\x68\x65\x6C\x6C\x6F\x20\x77\x6F\x72\x6C\x64")
    expect(buffer.tostring(helloBinary)).toEqual("hello world")
  end)

  it("can decode bin 32 value", function()
    local emptyBinary = msgpack.decode("\xC6\x00\x00\x00\x00")
    expect(typeof(emptyBinary)).toEqual("buffer")
    expect(buffer.tostring(emptyBinary)).toEqual("")

    local xBinary = msgpack.decode("\xC6\x00\x00\x00\x01\x78")
    expect(buffer.tostring(xBinary)).toEqual("x")

    local helloBinary =
      msgpack.decode("\xC6\x00\x00\x00\x0B\x68\x65\x6C\x6C\x6F\x20\x77\x6F\x72\x6C\x64")
    expect(buffer.tostring(helloBinary)).toEqual("hello world")
  end)

  it("can decode fixarray value", function()
    local emptyArray = msgpack.decode("\x90")
    expect(typeof(emptyArray)).toEqual("table")
    expect(#emptyArray).toEqual(0)
    expect((next(emptyArray))).toBeFalsy()

    local filledArray = msgpack.decode("\x93\xC0\xC2\xC3")
    expect(#filledArray).toEqual(3)
    expect(filledArray[1]).toEqual(msgpack.Null)
    expect(filledArray[2]).toEqual(false)
    expect(filledArray[3]).toEqual(true)

    local arrayWithString = msgpack.decode("\x93\xC2\xA5\x68\x65\x6C\x6C\x6F\xC3")
    expect(#arrayWithString).toEqual(3)
    expect(arrayWithString[1]).toEqual(false)
    expect(arrayWithString[2]).toEqual("hello")
    expect(arrayWithString[3]).toEqual(true)
  end)

  it("can decode array 16 value", function()
    local emptyArray = msgpack.decode("\xDC\x00\x00")
    expect(typeof(emptyArray)).toEqual("table")
    expect(#emptyArray).toEqual(0)
    expect((next(emptyArray))).toBeFalsy()

    local filledArray = msgpack.decode("\xDC\x00\x03\xC0\xC2\xC3")
    expect(#filledArray).toEqual(3)
    expect(filledArray[1]).toEqual(msgpack.Null)
    expect(filledArray[2]).toEqual(false)
    expect(filledArray[3]).toEqual(true)

    local arrayWithString = msgpack.decode("\xDC\x00\x03\xC2\xA5\x68\x65\x6C\x6C\x6F\xC3")
    expect(#arrayWithString).toEqual(3)
    expect(arrayWithString[1]).toEqual(false)
    expect(arrayWithString[2]).toEqual("hello")
    expect(arrayWithString[3]).toEqual(true)
  end)

  it("can decode array 32 value", function()
    local emptyArray = msgpack.decode("\xDD\x00\x00\x00\x00")
    expect(typeof(emptyArray)).toEqual("table")
    expect(#emptyArray).toEqual(0)
    expect((next(emptyArray))).toBeFalsy()

    local filledArray = msgpack.decode("\xDD\x00\x00\x00\x03\xC0\xC2\xC3")
    expect(#filledArray).toEqual(3)
    expect(filledArray[1]).toEqual(msgpack.Null)
    expect(filledArray[2]).toEqual(false)
    expect(filledArray[3]).toEqual(true)

    local arrayWithString = msgpack.decode("\xDD\x00\x00\x00\x03\xC2\xA5\x68\x65\x6C\x6C\x6F\xC3")
    expect(#arrayWithString).toEqual(3)
    expect(arrayWithString[1]).toEqual(false)
    expect(arrayWithString[2]).toEqual("hello")
    expect(arrayWithString[3]).toEqual(true)
  end)

  it("can decode fixmap value", function()
    local emptyMap = msgpack.decode("\x80")
    expect(typeof(emptyMap)).toEqual("table")
    expect(#emptyMap).toEqual(0)
    expect((next(emptyMap))).toBeFalsy()

    local filledMap = msgpack.decode("\x82\xA5\x68\x65\x6C\x6C\x6F\xA5\x77\x6F\x72\x6C\x64\x7B\xC3")
    expect(#filledMap).toEqual(0)
    expect((next(filledMap))).toBeTruthy()
    expect(filledMap["hello"]).toEqual("world")
    expect(filledMap[123]).toEqual(true)
  end)

  it("can decode map 16 value", function()
    local emptyMap = msgpack.decode("\xDE\x00\x00")
    expect(typeof(emptyMap)).toEqual("table")
    expect(#emptyMap).toEqual(0)
    expect((next(emptyMap))).toBeFalsy()

    local filledMap =
      msgpack.decode("\xDE\x00\x02\xA5\x68\x65\x6C\x6C\x6F\xA5\x77\x6F\x72\x6C\x64\x7B\xC3")
    expect(#filledMap).toEqual(0)
    expect((next(filledMap))).toBeTruthy()
    expect(filledMap["hello"]).toEqual("world")
    expect(filledMap[123]).toEqual(true)
  end)

  it("can decode map 32 value", function()
    local emptyMap = msgpack.decode("\xDF\x00\x00\x00\x00")
    expect(typeof(emptyMap)).toEqual("table")
    expect(#emptyMap).toEqual(0)
    expect((next(emptyMap))).toBeFalsy()

    local filledMap =
      msgpack.decode("\xDF\x00\x00\x00\x02\xA5\x68\x65\x6C\x6C\x6F\xA5\x77\x6F\x72\x6C\x64\x7B\xC3")
    expect(#filledMap).toEqual(0)
    expect((next(filledMap))).toBeTruthy()
    expect(filledMap["hello"]).toEqual("world")
    expect(filledMap[123]).toEqual(true)
  end)

  it("can decode fixext 1 value", function()
    local extension = msgpack.decode("\xD4\x7B\x78")
    expect(extension._msgpackType).toEqual(msgpack.Extension)
    expect(extension.type).toEqual(123)
    expect(buffer.tostring(extension.data)).toEqual("x")
  end)

  it("can decode fixext 2 value", function()
    local extension = msgpack.decode("\xD5\x7B\x78\x78")
    expect(extension._msgpackType).toEqual(msgpack.Extension)
    expect(extension.type).toEqual(123)
    expect(buffer.tostring(extension.data)).toEqual("xx")
  end)

  it("can decode fixext 4 value", function()
    local extension = msgpack.decode("\xD6\x7B\x78\x78\x78\x78")
    expect(extension._msgpackType).toEqual(msgpack.Extension)
    expect(extension.type).toEqual(123)
    expect(buffer.tostring(extension.data)).toEqual("xxxx")
  end)

  it("can decode fixext 8 value", function()
    local extension = msgpack.decode("\xD7\x7B\x78\x78\x78\x78\x78\x78\x78\x78")
    expect(extension._msgpackType).toEqual(msgpack.Extension)
    expect(extension.type).toEqual(123)
    expect(buffer.tostring(extension.data)).toEqual("xxxxxxxx")
  end)

  it("can decode fixext 16 value", function()
    local extension =
      msgpack.decode("\xD8\x7B\x78\x78\x78\x78\x78\x78\x78\x78\x78\x78\x78\x78\x78\x78\x78\x78")
    expect(extension._msgpackType).toEqual(msgpack.Extension)
    expect(extension.type).toEqual(123)
    expect(buffer.tostring(extension.data)).toEqual("xxxxxxxxxxxxxxxx")
  end)

  it("can decode ext 8 value", function()
    local emptyExtension = msgpack.decode("\xC7\x00\x7B")
    expect(emptyExtension._msgpackType).toEqual(msgpack.Extension)
    expect(emptyExtension.type).toEqual(123)
    expect(buffer.tostring(emptyExtension.data)).toEqual("")

    local extension = msgpack.decode("\xC7\x01\x7B\x78")
    expect(extension._msgpackType).toEqual(msgpack.Extension)
    expect(extension.type).toEqual(123)
    expect(buffer.tostring(extension.data)).toEqual("x")
  end)

  it("can decode ext 16 value", function()
    local emptyExtension = msgpack.decode("\xC8\x00\x00\x7B")
    expect(emptyExtension._msgpackType).toEqual(msgpack.Extension)
    expect(emptyExtension.type).toEqual(123)
    expect(buffer.tostring(emptyExtension.data)).toEqual("")

    local extension = msgpack.decode("\xC8\x00\x01\x7B\x78")
    expect(extension._msgpackType).toEqual(msgpack.Extension)
    expect(extension.type).toEqual(123)
    expect(buffer.tostring(extension.data)).toEqual("x")
  end)

  it("can decode ext 32 value", function()
    local emptyExtension = msgpack.decode("\xC9\x00\x00\x00\x00\x7B")
    expect(emptyExtension._msgpackType).toEqual(msgpack.Extension)
    expect(emptyExtension.type).toEqual(123)
    expect(buffer.tostring(emptyExtension.data)).toEqual("")

    local extension = msgpack.decode("\xC9\x00\x00\x00\x01\x7B\x78")
    expect(extension._msgpackType).toEqual(msgpack.Extension)
    expect(extension.type).toEqual(123)
    expect(buffer.tostring(extension.data)).toEqual("x")
  end)
end)

describe("encode", function()
  it("can encode nil value", function()
    expect(hex(msgpack.encode(nil))).toEqual("C0")
  end)

  it("can encode false value", function()
    expect(hex(msgpack.encode(false))).toEqual("C2")
  end)

  it("can encode true value", function()
    expect(hex(msgpack.encode(true))).toEqual("C3")
  end)

  it("can encode string value", function()
    expect(hex(msgpack.encode(""))).toEqual("A0")
    expect(hex(msgpack.encode("xyz"))).toEqual("A3 78 79 7A")

    local xs = string.rep("x", 0x20)
    expect(msgpack.encode(xs)).toEqual("\xD9\x20" .. xs)

    xs = string.rep("x", 0x100)
    expect(msgpack.encode(xs)).toEqual("\xDA\x01\x00" .. xs)

    xs = string.rep("x", 0x10000)
    expect(msgpack.encode(xs)).toEqual("\xDB\x00\x01\x00\x00" .. xs)
  end)

  it("can encode positive integers", function()
    expect(hex(msgpack.encode(0))).toEqual("00")
    expect(hex(msgpack.encode(1))).toEqual("01")
    expect(hex(msgpack.encode(127))).toEqual("7F")
    expect(hex(msgpack.encode(128))).toEqual("CC 80")
    expect(hex(msgpack.encode(255))).toEqual("CC FF")
    expect(hex(msgpack.encode(256))).toEqual("CD 01 00")
    expect(hex(msgpack.encode(65535))).toEqual("CD FF FF")
    expect(hex(msgpack.encode(65536))).toEqual("CE 00 01 00 00")
    expect(hex(msgpack.encode(4294967295))).toEqual("CE FF FF FF FF")
  end)

  it("can encode negative integers", function()
    expect(hex(msgpack.encode(-1))).toEqual("FF")
    expect(hex(msgpack.encode(-32))).toEqual("E0")
    expect(hex(msgpack.encode(-33))).toEqual("D0 DF")
    expect(hex(msgpack.encode(-128))).toEqual("D0 80")
    expect(hex(msgpack.encode(-129))).toEqual("D1 FF 7F")
    expect(hex(msgpack.encode(-32768))).toEqual("D1 80 00")
    expect(hex(msgpack.encode(-32769))).toEqual("D2 FF FF 7F FF")
    expect(hex(msgpack.encode(-2147483648))).toEqual("D2 80 00 00 00")
  end)

  it("can encode floating points", function()
    expect(hex(msgpack.encode(0 / 0))).toEqual("CA 7F 80 00 01")
    expect(hex(msgpack.encode(math.huge))).toEqual("CA 7F 80 00 00")
    expect(hex(msgpack.encode(-math.huge))).toEqual("CA FF 80 00 00")
    expect(hex(msgpack.encode(0.1))).toEqual("CB 3F B9 99 99 99 99 99 9A")
    expect(hex(msgpack.encode(-0.1))).toEqual("CB BF B9 99 99 99 99 99 9A")
    expect(hex(msgpack.encode(1234.56789))).toEqual("CB 40 93 4A 45 84 F4 C6 E7")
    expect(hex(msgpack.encode(1.7976931348623157e+308))).toEqual("CB 7F EF FF FF FF FF FF FF")
    expect(hex(msgpack.encode(-1.7976931348623157e+308))).toEqual("CB FF EF FF FF FF FF FF FF")
    expect(hex(msgpack.encode(2.2250738585072014e-308))).toEqual("CB 00 10 00 00 00 00 00 00")
    expect(hex(msgpack.encode(-2.2250738585072014e-308))).toEqual("CB 80 10 00 00 00 00 00 00")
  end)

  it("can encode Int64 and UInt64 representations", function()
    expect(hex(msgpack.encode(msgpack.Int64.new(0xFFFFFFFF, 0xFFFFFFFF)))).toEqual(
      "D3 FF FF FF FF FF FF FF FF"
    )
    expect(hex(msgpack.encode(msgpack.Int64.new(0xFAFBFCFD, 0xFEFDFCFB)))).toEqual(
      "D3 FA FB FC FD FE FD FC FB"
    )
    expect(hex(msgpack.encode(msgpack.UInt64.new(0xFFFFFFFF, 0xFFFFFFFF)))).toEqual(
      "CF FF FF FF FF FF FF FF FF"
    )
    expect(hex(msgpack.encode(msgpack.UInt64.new(0xFAFBFCFD, 0xFEFDFCFB)))).toEqual(
      "CF FA FB FC FD FE FD FC FB"
    )
  end)

  it("can encode buffer value", function()
    expect(hex(msgpack.encode(buffer.fromstring("")))).toEqual("C4 00")
    expect(hex(msgpack.encode(buffer.fromstring("xyz")))).toEqual("C4 03 78 79 7A")

    local xs = string.rep("x", 0x20)
    expect(msgpack.encode(buffer.fromstring(xs))).toEqual("\xC4\x20" .. xs)

    xs = string.rep("x", 0x100)
    expect(msgpack.encode(buffer.fromstring(xs))).toEqual("\xC5\x01\x00" .. xs)

    xs = string.rep("x", 0x10000)
    expect(msgpack.encode(buffer.fromstring(xs))).toEqual("\xC6\x00\x01\x00\x00" .. xs)
  end)

  it("can encode Extension value", function()
    expect(hex(msgpack.encode(msgpack.Extension.new(123, buffer.fromstring(""))))).toEqual(
      "C7 00 7B"
    )
    expect(hex(msgpack.encode(msgpack.Extension.new(123, buffer.fromstring("x"))))).toEqual(
      "D4 7B 78"
    )
    expect(hex(msgpack.encode(msgpack.Extension.new(123, buffer.fromstring("xy"))))).toEqual(
      "D5 7B 78 79"
    )
    expect(hex(msgpack.encode(msgpack.Extension.new(123, buffer.fromstring("wxyz"))))).toEqual(
      "D6 7B 77 78 79 7A"
    )
    expect(hex(msgpack.encode(msgpack.Extension.new(123, buffer.fromstring("wxyzwxyz"))))).toEqual(
      "D7 7B 77 78 79 7A 77 78 79 7A"
    )
    expect(hex(msgpack.encode(msgpack.Extension.new(123, buffer.fromstring("wxyzwxyzwxyzwxyz"))))).toEqual(
      "D8 7B 77 78 79 7A 77 78 79 7A 77 78 79 7A 77 78 79 7A"
    )

    local xs = string.rep("x", 0x20)
    expect(msgpack.encode(msgpack.Extension.new(123, buffer.fromstring(xs)))).toEqual(
      "\xC7\x20\x7B" .. xs
    )

    xs = string.rep("x", 0x100)
    expect(msgpack.encode(msgpack.Extension.new(123, buffer.fromstring(xs)))).toEqual(
      "\xC8\x01\x00\x7B" .. xs
    )

    xs = string.rep("x", 0x10000)
    expect(msgpack.encode(msgpack.Extension.new(123, buffer.fromstring(xs)))).toEqual(
      "\xC9\x00\x01\x00\x00\x7B" .. xs
    )
  end)

  it("can encode array-like tables", function()
    expect(hex(msgpack.encode({}))).toEqual("90")
    expect(hex(msgpack.encode({ 1, 2, 3 }))).toEqual("93 01 02 03")

    local t, s = table.create(15, 0), string.rep("\x00", 15)
    expect(msgpack.encode(t)).toEqual("\x9F" .. s)

    t, s = table.create(30, 0), string.rep("\x00", 30)
    expect(msgpack.encode(t)).toEqual("\xDC\x00\x1E" .. s)

    t, s = table.create(70000, 0), string.rep("\x00", 70000)
    expect(msgpack.encode(t)).toEqual("\xDD\x00\x01\x11\x70" .. s)
  end)

  it("can encode map-like tables", function()
    expect(hex(msgpack.encode({ a = 1 }))).toEqual("81 A1 61 01")
    -- selene: allow(mixed_table)
    expect(hex(msgpack.encode({ 1, a = 1 }))).toEqual("82 01 01 A1 61 01")

    local t, s = table.create(15, 0), string.rep("\x00", 15)
    expect(msgpack.encode(t)).toEqual("\x9F" .. s)

    t, s = table.create(30, 0), string.rep("\x00", 30)
    expect(msgpack.encode(t)).toEqual("\xDC\x00\x1E" .. s)

    t, s = table.create(70000, 0), string.rep("\x00", 70000)
    expect(msgpack.encode(t)).toEqual("\xDD\x00\x01\x11\x70" .. s)
  end)

  it("can handle cyclic tables", function()
    local cyclicTable: any = {}
    cyclicTable.self = cyclicTable
    expect(function()
      msgpack.encode(cyclicTable)
    end).toThrow("Can not serialize cyclic table")
  end)
end)

describe("utf8Encode", function()
  it("can encode a binary string as UTF-8", function()
    expect(msgpack.utf8Encode("")).toEqual("")

    local binary = string.char(0b11111111)
    local utf = string.char(0b01111111, 0b01000000)
    expect(hex(msgpack.utf8Encode(binary))).toEqual(hex(utf))

    binary = string.char(0b11110000, 0b00111100, 0b00001111)
    utf = string.char(0b01111000, 0b00001111, 0b00000001, 0b01110000)
    expect(hex(msgpack.utf8Encode(binary))).toEqual(hex(utf))

    binary = string.char(0b11111111):rep(8)
    utf = string.char(0b01111111):rep(9) .. string.char(0b01000000)
    expect(hex(msgpack.utf8Encode(binary))).toEqual(hex(utf))
  end)
end)

describe("utf8Decode", function()
  it("can decode a binary string encoded as UTF-8", function()
    expect(msgpack.utf8Decode("")).toEqual("")

    local utf = string.char(0b01111111, 0b01000000)
    local binary = string.char(0b11111111)
    expect(hex(msgpack.utf8Decode(utf))).toEqual(hex(binary))

    utf = string.char(0b01111000, 0b00001111, 0b00000001, 0b01110000)
    binary = string.char(0b11110000, 0b00111100, 0b00001111)
    expect(hex(msgpack.utf8Decode(utf))).toEqual(hex(binary))

    utf = string.char(0b01111111):rep(9) .. string.char(0b01000000)
    binary = string.char(0b11111111):rep(8)
    expect(hex(msgpack.utf8Decode(utf))).toEqual(hex(binary))
  end)
end)

describe("Null sentinel", function()
  it("encodes Null as msgpack nil (0xC0)", function()
    expect(hex(msgpack.encode(msgpack.Null))).toEqual("C0")
  end)

  it("decodes msgpack nil as Null sentinel (not Lua nil)", function()
    local result = msgpack.decode("\xC0")
    expect(result).toEqual(msgpack.Null)
    expect(result).never.toEqual(nil)
  end)

  it("preserves Null values in map keys during round-trip", function()
    -- fixmap {key: "hello", value: null}
    local encoded = msgpack.encode({ hello = msgpack.Null })
    local decoded = msgpack.decode(encoded)
    expect(decoded.hello).toEqual(msgpack.Null)
  end)

  it("preserves Null values in arrays during round-trip", function()
    local encoded = msgpack.encode({ msgpack.Null, false, true })
    local decoded = msgpack.decode(encoded)
    expect(#decoded).toEqual(3)
    expect(decoded[1]).toEqual(msgpack.Null)
    expect(decoded[2]).toEqual(false)
    expect(decoded[3]).toEqual(true)
  end)

  it("Null is not equal to nil", function()
    expect(msgpack.Null).never.toEqual(nil)
  end)

  it("Null is equal to itself", function()
    expect(msgpack.Null).toEqual(msgpack.Null)
  end)

  it("decodes null in map values as Null sentinel", function()
    -- fixmap with 1 entry: key="x", value=nil -> \x81\xA1\x78\xC0
    local decoded = msgpack.decode("\x81\xA1\x78\xC0")
    expect(decoded.x).toEqual(msgpack.Null)
  end)
end)

describe("encodeb64 / decodeb64", function()
  it("round-trips simple values", function()
    local values = { 42, "hello", true, false, { 1, 2, 3 }, { a = "b" } }
    for _, v in values do
      local encoded = msgpack.encodeb64(v)
      expect(typeof(encoded)).toEqual("string")
      local decoded = msgpack.decodeb64(encoded)
      if typeof(v) == "table" then
        for k, expected in v :: any do
          expect(decoded[k]).toEqual(expected)
        end
      else
        expect(decoded).toEqual(v)
      end
    end
  end)

  it("round-trips Null sentinel", function()
    local encoded = msgpack.encodeb64(msgpack.Null)
    local decoded = msgpack.decodeb64(encoded)
    expect(decoded).toEqual(msgpack.Null)
  end)

  it("round-trips tables with Null values", function()
    local original = { key = msgpack.Null, other = 123 }
    local encoded = msgpack.encodeb64(original)
    local decoded = msgpack.decodeb64(encoded)
    expect(decoded.key).toEqual(msgpack.Null)
    expect(decoded.other).toEqual(123)
  end)
end)
