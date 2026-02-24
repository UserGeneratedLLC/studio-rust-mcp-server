--!strict
--!optimize 2
--!native

export type EnumValue<T> = {}
export type PropertyValue = any
export type AttributeValue = any

export type EncodedInstance = {
  Name: string,
  ClassName: string,
  DebugId: string,
  Shallow: boolean?,
  Properties: { [string]: PropertyValue }?,
  Attributes: { [string]: AttributeValue }?,
  Tags: { string }?,
  Children: { EncodedInstance }?,
}

local function GetDebugId(inst: Instance): string
  return inst:GetDebugId(0) -- TODO: I notice some people remove the first char
end

local function UnescapeName(name: string): string
  name = string.gsub(name, "%%2F", "/")
  name = string.gsub(name, "%%7E", "~")
  name = string.gsub(name, "%%%%", "%%")
  return name
end

local function EscapeName(name: string): string
  name = string.gsub(name, "%%", "%%25")
  name = string.gsub(name, "~", "%%7E")
  name = string.gsub(name, "/", "%%2F")
  return name
end

local function GetDistinctName(inst: Instance): string
  return `{EscapeName(inst.Name)}~{GetDebugId(inst)}`
end

local function GetDistinctPath(inst: Instance): string
  local names = { GetDistinctName(inst) }
  local pivot: Instance? = inst
  while pivot do
    table.insert(names, EscapeName(pivot.Name))
    pivot = pivot.Parent
  end
  local n = #names
  local center = n // 2
  for i = 1, center do
    names[i], names[n - i + 1] = names[n - i + 1], names[i]
  end
  return table.concat(names, "/")
end

local function GetProperties(inst: Instance): { [string]: any }
  -- TODO: download and cache this:
  -- https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/refs/heads/roblox/Full-API-Dump.json
  return {}
end

local function EncodeNumber(v: number)
  if not math.isfinite(v) then return { ["number"] = tostring(v) } end
  return v
end

local PropertyEncoders: { [string]: (any) -> PropertyValue } = {
  ["nil"] = function(v: nil) return v end,
  ["string"] = function(v: number) return v end,
  ["boolean"] = function(v: boolean) return v end,
  ["number"] = EncodeNumber,
  ["EnumItem"] = function(v: EnumItem)
    return { [`Enum.{v.EnumType}`] = v.Name }
  end,
  ["UDim"] = function(v: UDim)
    return { ["UDim"] = { EncodeNumber(v.Scale), EncodeNumber(v.Offset) } }
  end,
  ["UDim2"] = function(v: UDim2)
    return {
      ["UDim2"] = {
        EncodeNumber(v.X.Scale),
        EncodeNumber(v.X.Offset),
        EncodeNumber(v.Y.Scale),
        EncodeNumber(v.Y.Offset),
      },
    }
  end,
  ["Vector2int16"] = function(v: Vector2int16)
    return { ["Vector2int16"] = { EncodeNumber(v.X), EncodeNumber(v.Y) } }
  end,
  ["Vector3int16"] = function(v: Vector3int16)
    return {
      ["Vector3int16"] = {
        EncodeNumber(v.X),
        EncodeNumber(v.Y),
        EncodeNumber(v.Z),
      },
    }
  end,
  ["Vector2"] = function(v: Vector2)
    return { ["Vector2"] = { EncodeNumber(v.X), EncodeNumber(v.Y) } }
  end,
  ["Vector3"] = function(v: Vector3)
    return {
      ["Vector3"] = { EncodeNumber(v.X), EncodeNumber(v.Y), EncodeNumber(v.Z) },
    }
  end,
  ["Color3"] = function(v: Color3)
    return {
      ["Color3"] = { EncodeNumber(v.R), EncodeNumber(v.G), EncodeNumber(v.B) },
    }
  end,
  ["Content"] = function(v: Content)
    if v.Uri then return {
      ["Content"] = v.Uri,
    } end
    -- TODO: encode other types as base64
  end,
}
local function EncodeProperty(value: any): AttributeValue
  local encoder = PropertyEncoders[typeof(value)]
  if not encoder then error(`UnknownType: {typeof(value)}`) end
  return encoder(value)
end

local AttributeEncoders: { [string]: (any) -> AttributeValue } = {
  -- TODO: manually copy known supported attributes from PropertyEncoders, NOTE: there is no nil, and Instance uses the ref instead
}
local function EncodeAttribute(value: any): AttributeValue
  local encoder = AttributeEncoders[typeof(value)]
  if not encoder then error(`UnknownType: {typeof(value)}`) end
  return encoder(value)
end

--[[
  depth=0, this child specifically and then shallow view of it's children
]]
local function EncodeInstance(inst: Instance, depth: number): EncodedInstance
  local result: EncodedInstance = {
    Name = EscapeName(inst.Name),
    ClassName = inst.ClassName,
    DebugId = GetDebugId(inst),
  }
  if depth >= 0 then
    -- Children
    local children = {}
    local childDepth = depth - 1
    for _, child in ipairs(inst:GetChildren()) do
      table.insert(children, EncodeInstance(child, childDepth))
    end
    if #children > 0 then result.Children = result end
    -- Properties
    local properties = {}
    for key, val in pairs(GetProperties(inst)) do
      properties[key] = EncodeProperty(val)
    end
    if next(properties) then result.Properties = properties end
    -- Attributes
    local attributes = {}
    for key, val in pairs(inst:GetAttributes()) do
      attributes[key] = EncodeAttribute(val)
    end
    if next(attributes) then result.Attributes = attributes end
    -- Tags
    local tags = inst:GetTags()
    if #tags > 0 then result.Tags = tags end
  end
  return result
end

local module = {}

return table.freeze(module)
