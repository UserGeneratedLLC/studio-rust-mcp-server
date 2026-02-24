--!strict
--!optimize 2
--!native

export type EncodedInstance = {
  Name: string,
  ClassName: string,
  DebugId: string,
  Shallow: boolean?,
  -- If Shallow=true, anything below this point will not be populated.
  Properties: { [string]: any }?,
  Attributes: { [string]: any }?,
  Tags: { string }?,
  Children: { EncodedInstance }?,
}

local function GetDebugId(inst: Instance): string
  return inst:GetDebugId(0) -- TODO: I notice some people remove the first char
end

local function UnescapeName(name: string): string
  name = string.gsub(name, "%%2F", "/")
  name = string.gsub(name, "%%7E", "~")
  name = string.gsub(name, "%%25", "%%")
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
  local pivot: Instance? = inst.Parent
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

local function EncodeNumber(v: number): any
  if not math.isfinite(v) then return { ["number"] = tostring(v) } end
  return v
end

local NilReference = newproxy()

local PropertyEncoders: { [string]: (any) -> any } = {
  ["nil"] = function(v: nil) return NilReference end,
  ["string"] = function(v: string) return v end,
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
    local data: any
    local sourceType = v.SourceType
    if sourceType == Enum.ContentSourceType.Uri then
      data = { Uri = v.Uri }
    elseif sourceType == Enum.ContentSourceType.Object then
      -- TODO(low): encode the EditableImage/Mesh/Capture/VideoContext etc.
      data = { Object = assert(v.Object).ClassName }
    elseif sourceType == Enum.ContentSourceType.Opaque then
      data = { Opaque = true }
    else
      data = {}
    end
    return { ["Content"] = data }
  end,
  ["BrickColor"] = function(v: BrickColor) return { ["BrickColor"] = v.Name } end,
  ["CFrame"] = function(v: CFrame)
    local comps = { v:GetComponents() }
    local encoded = table.create(12)
    for i = 1, 12 do
      encoded[i] = EncodeNumber(comps[i])
    end
    return { ["CFrame"] = encoded }
  end,
  ["NumberRange"] = function(v: NumberRange)
    return { ["NumberRange"] = { EncodeNumber(v.Min), EncodeNumber(v.Max) } }
  end,
  ["NumberSequence"] = function(v: NumberSequence)
    local keypoints = {}
    for _, kp in v.Keypoints do
      table.insert(keypoints, {
        EncodeNumber(kp.Time),
        EncodeNumber(kp.Value),
        EncodeNumber(kp.Envelope),
      })
    end
    return { ["NumberSequence"] = keypoints }
  end,
  ["ColorSequence"] = function(v: ColorSequence)
    local keypoints = {}
    for _, kp in v.Keypoints do
      table.insert(keypoints, {
        EncodeNumber(kp.Time),
        EncodeNumber(kp.Value.R),
        EncodeNumber(kp.Value.G),
        EncodeNumber(kp.Value.B),
      })
    end
    return { ["ColorSequence"] = keypoints }
  end,
  ["Rect"] = function(v: Rect)
    return {
      ["Rect"] = {
        EncodeNumber(v.Min.X),
        EncodeNumber(v.Min.Y),
        EncodeNumber(v.Max.X),
        EncodeNumber(v.Max.Y),
      },
    }
  end,
  ["Font"] = function(v: Font)
    local family = v.Family :: any
    return {
      ["Font"] = {
        family = if type(family) == "string"
          then family
          else family.Uri or tostring(family),
        weight = v.Weight.Name,
        style = v.Style.Name,
      },
    }
  end,
  ["PhysicalProperties"] = function(v: PhysicalProperties)
    return {
      ["PhysicalProperties"] = {
        EncodeNumber(v.Density),
        EncodeNumber(v.Friction),
        EncodeNumber(v.Elasticity),
        EncodeNumber(v.FrictionWeight),
        EncodeNumber(v.ElasticityWeight),
      },
    }
  end,
  ["Axes"] = function(v: Axes)
    return { ["Axes"] = { X = v.X, Y = v.Y, Z = v.Z } }
  end,
  ["Faces"] = function(v: Faces)
    return {
      ["Faces"] = {
        Top = v.Top,
        Bottom = v.Bottom,
        Left = v.Left,
        Right = v.Right,
        Front = v.Front,
        Back = v.Back,
      },
    }
  end,
  ["DateTime"] = function(v: DateTime)
    return { ["DateTime"] = v.UnixTimestampMillis }
  end,
  ["Ray"] = function(v: Ray)
    return {
      ["Ray"] = {
        EncodeNumber(v.Origin.X),
        EncodeNumber(v.Origin.Y),
        EncodeNumber(v.Origin.Z),
        EncodeNumber(v.Direction.X),
        EncodeNumber(v.Direction.Y),
        EncodeNumber(v.Direction.Z),
      },
    }
  end,
  ["Instance"] = function(v: Instance) return { ["Ref"] = GetDistinctPath(v) } end,
}
local function EncodeProperty(value: any): any
  local encoder = PropertyEncoders[typeof(value)]
  if not encoder then error(`UnknownType: {typeof(value)}`) end
  return encoder(value)
end

local AttributeEncoders: { [string]: (any) -> any } = {
  -- TODO: manually copy known supported attributes from PropertyEncoders, NOTE: there is no nil, and Instance uses the ref instead
}
local function EncodeAttribute(value: any): any
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
    for _, child in inst:GetChildren() do
      table.insert(children, EncodeInstance(child, childDepth))
    end
    if #children > 0 then result.Children = children end
    -- Properties
    local properties = {}
    for key, val in GetProperties(inst) do
      properties[key] = EncodeProperty(val)
    end
    if next(properties) then result.Properties = properties end
    -- Attributes
    local attributes = {}
    for key, val in inst:GetAttributes() do
      attributes[key] = EncodeAttribute(val)
    end
    if next(attributes) then result.Attributes = attributes end
    -- Tags
    local tags = inst:GetTags()
    if #tags > 0 then result.Tags = tags end
  else
    result.Shallow = true
  end
  return result
end

local module = {}

return table.freeze(module)
