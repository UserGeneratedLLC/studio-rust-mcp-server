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
  Properties: { [string]: PropertyValue }?,
  Attributes: { [string]: AttributeValue }?,
  Tags: { string }?,
  Children: ({ [string]: EncodedInstance } | { string })?,
}

local function GetDebugId(inst: Instance): string
  return inst:GetDebugId(0) -- TODO: I notice some people remove the first char
end

local function GetFullName(inst: Instance): string
  local name = inst.Name
  name = string.gsub(name, "%%", "%%25")
  name = string.gsub(name, "~", "%%7E")
  name = string.gsub(name, "/", "%%2F")
  return `{name}~{GetDebugId(inst)}`
end

local function GetFullPath(inst: Instance): string
  local names = {}
  local pivot = inst
  while true do
    table.insert(names, GetFullName(pivot))
    local parent = pivot.Parent
    if not parent then
      break
    end
    pivot = parent
  end
  local n = #names
  local center = n // 2
  for i = 1, center do
    names[i], names[n - i - 1] = names[n - i - 1], names[i]
  end
  return table.concat(names, "/")
end

local function GetProperties(inst: Instance): { [string]: any }
  -- TODO: download and cache this:
  -- https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/refs/heads/roblox/Full-API-Dump.json
  return {}
end

local function EncodeNumber(v: number)
  if not math.isfinite(v) then
    return { ["number"] = tostring(v) }
  end
  return v
end

local PropertyEncoders: { [string]: (any) -> PropertyValue } = {
  ["nil"] = function(v: nil)
    return v
  end,
  ["string"] = function(v: number)
    return v
  end,
  ["boolean"] = function(v: boolean)
    return v
  end,
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
    if v.Uri then
      return {
        ["Content"] = v.Uri,
      }
    end
    -- TODO: encode other types as base64
  end,
}
local function EncodeProperty(value: any): AttributeValue
  local encoder = PropertyEncoders[typeof(value)]
  if not encoder then
    error(`UnknownType: {typeof(value)}`)
  end
  return encoder(value)
end

local AttributeEncoders: { [string]: (any) -> AttributeValue } = {
  -- TODO: manually copy known supported attributes from PropertyEncoders, NOTE: there is no nil, and Instance uses the ref instead
}
local function EncodeAttribute(value: any): AttributeValue
  local encoder = AttributeEncoders[typeof(value)]
  if not encoder then
    error(`UnknownType: {typeof(value)}`)
  end
  return encoder(value)
end

local function EncodeInstance(inst: Instance, depth: number): EncodedInstance
  -- Properties
  local properties = {}
  for key, val in pairs(GetProperties(inst)) do
    properties[key] = EncodeProperty(val)
  end
  -- Attributes
  local attributes = {}
  for key, val in pairs(inst:GetAttributes()) do
    attributes[key] = EncodeAttribute(val)
  end
  -- Tags
  local tags = inst:GetTags()
  -- Children
  local children: { [string]: EncodedInstance } | { string }
  if depth > 0 then
    local childrenTable = {}
    local childDepth = depth - 1
    for _, child in ipairs(inst:GetChildren()) do
      childrenTable[GetFullName(child)] = EncodeInstance(child, childDepth)
    end
    children = childrenTable
  else
    local childrenList = {}
    for _, child in ipairs(inst:GetChildren()) do
      table.insert(childrenList, GetFullName(child))
    end
    children = childrenList
  end
  return {
    Name = inst.Name,
    ClassName = inst.ClassName,
    DebugId = GetDebugId(inst),
    Properties = if next(properties) then properties else nil,
    Attributes = if next(attributes) then attributes else nil,
    Tags = if next(tags) then tags else nil,
    Children = if next(children) then children else nil,
  }
end

local module = {}

return table.freeze(module)
