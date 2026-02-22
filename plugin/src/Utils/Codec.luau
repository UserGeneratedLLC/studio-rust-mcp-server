--!strict
--!optimize 2
--!native

export type EnumValue<T> = {}
export type PropertyValue = any
export type AttributeValue = any

export type EncodedInstance = {
  Name: string,
  ClassName: string,
  UniqueId: string,
  Properties: { [string]: PropertyValue }?,
  Attributes: { [string]: AttributeValue }?,
  Tags: { string }?,
  Children: { [string]: EncodedInstance }?,
}

local function GetUniqueId(inst: Instance): string
  return inst:GetUniqueId(0)
end

local function GetProperties(inst: Instance): { [string]: any }
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
    return {
      ["Content"] = tostring(v),
    }
  end,
}
local function EncodeProperty(value: any): AttributeValue
  local encoder = PropertyEncoders[typeof(value)]
  if not encoder then
    error(`UnknownType: {typeof(value)}`)
  end
  return encoder(value)
end

local AttributeEncoders: { [string]: (any) -> AttributeValue } = {}
local function EncodeAttribute(value: any): AttributeValue
  local encoder = AttributeEncoders[typeof(value)]
  if not encoder then
    error(`UnknownType: {typeof(value)}`)
  end
  return encoder(value)
end

local function EncodeInstance(inst: Instance): EncodedInstance
  local properties = {}
  for key, val in pairs(GetProperties(inst)) do
    properties[key] = EncodeProperty(val)
  end
  local attributes = {}
  for key, val in pairs(inst:GetAttributes()) do
    attributes[key] = EncodeAttribute(val)
  end
  local tags = inst:GetTags()
  local rawChildren = inst:GetChildren()
  local hasDuplicateChildren = false
  local children = {}
  for _, child in ipairs(inst:GetChildren()) do
    local key = `{child.Name}~{GetUniqueId(child)}`
    children[key] = EncodeInstance(child)
  end
  return {
    Name = inst.Name,
    ClassName = inst.ClassName,
    UniqueId = GetUniqueId(inst),
    Properties = if next(properties) then properties else nil,
    Attributes = if next(attributes) then attributes else nil,
    Tags = if next(tags) then tags else nil,
    Children = if next(children) then children else nil,
  }
end

local module = {}

return table.freeze(module)
