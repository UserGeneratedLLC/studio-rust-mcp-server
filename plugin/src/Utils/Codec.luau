--!strict
--!optimize 2
--!native

local EncodingService = game:GetService("EncodingService")

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
  name = string.gsub(name, "%%2[Ff]", "/")
  name = string.gsub(name, "%%7[Ee]", "~")
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
  while pivot and pivot ~= game do
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

--[[
  TODO:
  * split
  * pull out DebugId [if present]
  * un-escape each component
  * start de-referencing one-by-one
  * root starts with game:FindService(name)
  * when we de-reference, check if there are duplicate named children and add that to search space
  * if we do not have a DebugId and there is a duplicately named children, warn & return nil
  * once we know the search space, start looking for the correct child given our DebugId
  * we could do a single-shot attempt at finding the child (fast-path) and check if it matches the DebugId, then actually build search space
  * NOTE: we really have to maintain a DebugId map of all instances, and then just do a table check & make sure path is still the same.
]]
local function FromDistinctPath(path: string): Instance? end

local function GetProperties(inst: Instance): { [string]: any }
  -- TODO: download and cache this:
  -- https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/refs/heads/roblox/Full-API-Dump.json
  return {}
end

local function EncodeNumber(v: number): any
  if not math.isfinite(v) then return { ["number"] = tostring(v) } end
  return v
end
local function DecodeNumber(v: any): number
  if type(v) == "number" then return v end
  if type(v) == "table" then
    local s = v["number"]
    if type(s) == "string" then
      local n = tonumber(s)
      if n ~= nil then return n end
      error(`Invalid encoded number: {s}`)
    end
  end
  error(`Expected number, got {typeof(v)}`)
end

local function EncodeString(v: string): any
  if not utf8.len(v) then
    return {
      ["string"] = buffer.tostring(
        EncodingService:Base64Encode(buffer.fromstring(v))
      ),
    }
  end
  return v
end
local function DecodeString(v: any): string
  if type(v) == "string" then return v end
  if type(v) == "table" then
    local s = v["string"]
    if type(s) == "string" then
      return buffer.tostring(EncodingService:Base64Decode(buffer.fromstring(s)))
    end
  end
  error(`Expected string, got {typeof(v)}`)
end

local function EncodeNil(_v: nil, nilReference: any): any return nilReference end

local function EncodeBoolean(v: boolean): any return v end
local function DecodeBoolean(v: any): boolean
  if type(v) == "boolean" then return v end
  error(`Expected boolean, got {typeof(v)}`)
end

local function EncodeBuffer(v: buffer): any
  return { ["buffer"] = buffer.tostring(EncodingService:Base64Encode(v)) }
end
local function DecodeBuffer(v: any): buffer
  return EncodingService:Base64Decode(buffer.fromstring(v["buffer"]))
end

local function EncodeEnumItem(v: EnumItem): any
  return { ["EnumItem"] = `{v.EnumType}.{v.Name}` }
end
local function DecodeEnumItem(v: any): EnumItem
  local data = v["EnumItem"]
  local dot = string.find(data, ".", 1, true)
  if not dot then error(`Invalid enum format: {data}`) end
  local enumTypeName = string.sub(data, 1, dot - 1)
  local enumValueName = string.sub(data, dot + 1)
  local enumType = (Enum :: any)[enumTypeName]
  if not enumType then error(`Unknown enum type: {enumTypeName}`) end
  local enumItem = (enumType :: any)[enumValueName]
  if not enumItem then error(`Unknown enum value: {data}`) end
  return enumItem
end

local function EncodeUDim(v: UDim): any
  return { ["UDim"] = { EncodeNumber(v.Scale), EncodeNumber(v.Offset) } }
end
local function DecodeUDim(v: any): UDim
  local data = v["UDim"]
  return UDim.new(DecodeNumber(data[1]), DecodeNumber(data[2]))
end

local function EncodeUDim2(v: UDim2): any
  return {
    ["UDim2"] = {
      EncodeNumber(v.X.Scale),
      EncodeNumber(v.X.Offset),
      EncodeNumber(v.Y.Scale),
      EncodeNumber(v.Y.Offset),
    },
  }
end
local function DecodeUDim2(v: any): UDim2
  local data = v["UDim2"]
  return UDim2.new(
    DecodeNumber(data[1]),
    DecodeNumber(data[2]),
    DecodeNumber(data[3]),
    DecodeNumber(data[4])
  )
end

local function EncodeVector2int16(v: Vector2int16): any
  return { ["Vector2int16"] = { v.X, v.Y } }
end
local function DecodeVector2int16(v: any): Vector2int16
  local data = v["Vector2int16"]
  return Vector2int16.new(data[1], data[2])
end

local function EncodeVector3int16(v: Vector3int16): any
  return { ["Vector3int16"] = { v.X, v.Y, v.Z } }
end
local function DecodeVector3int16(v: any): Vector3int16
  local data = v["Vector3int16"]
  return Vector3int16.new(data[1], data[2], data[3])
end

local function EncodeVector2(v: Vector2): any
  return { ["Vector2"] = { EncodeNumber(v.X), EncodeNumber(v.Y) } }
end
local function DecodeVector2(v: any): Vector2
  local data = v["Vector2"]
  return Vector2.new(DecodeNumber(data[1]), DecodeNumber(data[2]))
end

local function EncodeVector3(v: Vector3): any
  return {
    ["Vector3"] = { EncodeNumber(v.X), EncodeNumber(v.Y), EncodeNumber(v.Z) },
  }
end
local function DecodeVector3(v: any): Vector3
  local data = v["Vector3"]
  return Vector3.new(
    DecodeNumber(data[1]),
    DecodeNumber(data[2]),
    DecodeNumber(data[3])
  )
end

local function EncodeColor3(v: Color3): any
  return {
    ["Color3"] = { EncodeNumber(v.R), EncodeNumber(v.G), EncodeNumber(v.B) },
  }
end
local function DecodeColor3(v: any): Color3
  local data = v["Color3"]
  return Color3.new(
    DecodeNumber(data[1]),
    DecodeNumber(data[2]),
    DecodeNumber(data[3])
  )
end

local function EncodeContent(v: Content): any
  local data: any
  local sourceType = v.SourceType
  if sourceType == Enum.ContentSourceType.Uri then
    data = v.Uri
  elseif sourceType == Enum.ContentSourceType.Object then
    -- TODO(low): encode the EditableImage/Mesh/Capture/VideoContext etc.
    if v.Object then
      data = v.Object.ClassName
    else
      data = "Object"
    end
  elseif sourceType == Enum.ContentSourceType.Opaque then
    data = "Opaque"
  else
    data = sourceType.Name
  end
  return { ["Content"] = data }
end
local function DecodeContent(v: any): Content
  return Content.fromUri(v["Content"])
end

local function EncodeBrickColor(v: BrickColor): any
  return { ["BrickColor"] = v.Name }
end
local function DecodeBrickColor(v: any): BrickColor
  return BrickColor.new(v["BrickColor"])
end

local function EncodeCFrame(v: CFrame): any
  local comps = { v:GetComponents() }
  local encoded = table.create(12)
  for i = 1, 12 do
    encoded[i] = EncodeNumber(comps[i])
  end
  return { ["CFrame"] = encoded }
end
local function DecodeCFrame(v: any): CFrame
  local data = v["CFrame"]
  return CFrame.new(
    DecodeNumber(data[1]),
    DecodeNumber(data[2]),
    DecodeNumber(data[3]),
    DecodeNumber(data[4]),
    DecodeNumber(data[5]),
    DecodeNumber(data[6]),
    DecodeNumber(data[7]),
    DecodeNumber(data[8]),
    DecodeNumber(data[9]),
    DecodeNumber(data[10]),
    DecodeNumber(data[11]),
    DecodeNumber(data[12])
  )
end

local function EncodeNumberRange(v: NumberRange): any
  return { ["NumberRange"] = { EncodeNumber(v.Min), EncodeNumber(v.Max) } }
end
local function DecodeNumberRange(v: any): NumberRange
  local data = v["NumberRange"]
  return NumberRange.new(DecodeNumber(data[1]), DecodeNumber(data[2]))
end

local function EncodeNumberSequence(v: NumberSequence): any
  local raw = v.Keypoints
  local keypoints = table.create(#raw)
  for i, kp in raw do
    keypoints[i] = {
      EncodeNumber(kp.Time),
      EncodeNumber(kp.Value),
      EncodeNumber(kp.Envelope),
    }
  end
  return { ["NumberSequence"] = keypoints }
end
local function DecodeNumberSequence(v: any): NumberSequence
  local data = v["NumberSequence"]
  local keypoints = table.create(#data)
  for i, kp in data do
    keypoints[i] = NumberSequenceKeypoint.new(
      DecodeNumber(kp[1]),
      DecodeNumber(kp[2]),
      DecodeNumber(kp[3])
    )
  end
  return NumberSequence.new(keypoints)
end

local function EncodeColorSequence(v: ColorSequence): any
  local raw = v.Keypoints
  local keypoints = table.create(#raw)
  for i, kp in raw do
    keypoints[i] = {
      EncodeNumber(kp.Time),
      EncodeNumber(kp.Value.R),
      EncodeNumber(kp.Value.G),
      EncodeNumber(kp.Value.B),
    }
  end
  return { ["ColorSequence"] = keypoints }
end
local function DecodeColorSequence(v: any): ColorSequence
  local data = v["ColorSequence"]
  local keypoints = table.create(#data)
  for i, kp in data do
    keypoints[i] = ColorSequenceKeypoint.new(
      DecodeNumber(kp[1]),
      Color3.new(DecodeNumber(kp[2]), DecodeNumber(kp[3]), DecodeNumber(kp[4]))
    )
  end
  return ColorSequence.new(keypoints)
end

local function EncodeRect(v: Rect): any
  return {
    ["Rect"] = {
      EncodeNumber(v.Min.X),
      EncodeNumber(v.Min.Y),
      EncodeNumber(v.Max.X),
      EncodeNumber(v.Max.Y),
    },
  }
end
local function DecodeRect(v: any): Rect
  local data = v["Rect"]
  return Rect.new(
    DecodeNumber(data[1]),
    DecodeNumber(data[2]),
    DecodeNumber(data[3]),
    DecodeNumber(data[4])
  )
end

local function EncodeFont(v: Font): any
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
end
local function DecodeFont(v: any): Font
  local data = v["Font"]
  return Font.new(
    data.family,
    (Enum.FontWeight :: any)[data.weight],
    (Enum.FontStyle :: any)[data.style]
  )
end

local function EncodePhysicalProperties(v: PhysicalProperties): any
  return {
    ["PhysicalProperties"] = {
      EncodeNumber(v.Density),
      EncodeNumber(v.Friction),
      EncodeNumber(v.Elasticity),
      EncodeNumber(v.FrictionWeight),
      EncodeNumber(v.ElasticityWeight),
    },
  }
end
local function DecodePhysicalProperties(v: any): PhysicalProperties
  local data = v["PhysicalProperties"]
  return PhysicalProperties.new(
    DecodeNumber(data[1]),
    DecodeNumber(data[2]),
    DecodeNumber(data[3]),
    DecodeNumber(data[4]),
    DecodeNumber(data[5])
  )
end

local function EncodeAxes(v: Axes): any
  return { ["Axes"] = { X = v.X, Y = v.Y, Z = v.Z } }
end
local function DecodeAxes(v: any): Axes
  local data = v["Axes"]
  local axes = {}
  if data.X then table.insert(axes, Enum.Axis.X) end
  if data.Y then table.insert(axes, Enum.Axis.Y) end
  if data.Z then table.insert(axes, Enum.Axis.Z) end
  return Axes.new(unpack(axes))
end

local function EncodeFaces(v: Faces): any
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
end
local function DecodeFaces(v: any): Faces
  local data = v["Faces"]
  local faces = {}
  if data.Top then table.insert(faces, Enum.NormalId.Top) end
  if data.Bottom then table.insert(faces, Enum.NormalId.Bottom) end
  if data.Left then table.insert(faces, Enum.NormalId.Left) end
  if data.Right then table.insert(faces, Enum.NormalId.Right) end
  if data.Front then table.insert(faces, Enum.NormalId.Front) end
  if data.Back then table.insert(faces, Enum.NormalId.Back) end
  return Faces.new(unpack(faces))
end

local function EncodeDateTime(v: DateTime): any
  return { ["DateTime"] = v:ToIsoDate() }
end
local function DecodeDateTime(v: any): DateTime
  local data = v["DateTime"]
  local dt = DateTime.fromIsoDate(data)
  if not dt then error(`Invalid ISO date: {data}`) end
  return dt
end

local function EncodeRay(v: Ray): any
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
end
local function DecodeRay(v: any): Ray
  local data = v["Ray"]
  return Ray.new(
    Vector3.new(
      DecodeNumber(data[1]),
      DecodeNumber(data[2]),
      DecodeNumber(data[3])
    ),
    Vector3.new(
      DecodeNumber(data[4]),
      DecodeNumber(data[5]),
      DecodeNumber(data[6])
    )
  )
end

local function EncodeInstanceRef(v: Instance): any
  return { ["Ref"] = GetDistinctPath(v) }
end
local function DecodeInstanceRef(v: any): Instance
  local path = v["Ref"]
  local inst = FromDistinctPath(path)
  if not inst then error(`Could not resolve instance ref: {path}`) end
  return inst
end

local function EncodeRegion3(v: Region3): any
  local center = v.CFrame.Position
  local half = v.Size * 0.5
  local min = center - half
  local max = center + half
  return {
    ["Region3"] = {
      EncodeNumber(min.X),
      EncodeNumber(min.Y),
      EncodeNumber(min.Z),
      EncodeNumber(max.X),
      EncodeNumber(max.Y),
      EncodeNumber(max.Z),
    },
  }
end
local function DecodeRegion3(v: any): Region3
  local data = v["Region3"]
  return Region3.new(
    Vector3.new(
      DecodeNumber(data[1]),
      DecodeNumber(data[2]),
      DecodeNumber(data[3])
    ),
    Vector3.new(
      DecodeNumber(data[4]),
      DecodeNumber(data[5]),
      DecodeNumber(data[6])
    )
  )
end

local function EncodeRegion3int16(v: Region3int16): any
  return {
    ["Region3int16"] = {
      v.Min.X,
      v.Min.Y,
      v.Min.Z,
      v.Max.X,
      v.Max.Y,
      v.Max.Z,
    },
  }
end
local function DecodeRegion3int16(v: any): Region3int16
  local data = v["Region3int16"]
  return Region3int16.new(
    Vector3int16.new(data[1], data[2], data[3]),
    Vector3int16.new(data[4], data[5], data[6])
  )
end

local PropertyEncoders: { [string]: (any, any) -> any } = {
  ["nil"] = EncodeNil,
  ["string"] = EncodeString,
  ["boolean"] = EncodeBoolean,
  ["number"] = EncodeNumber,
  ["buffer"] = EncodeBuffer,
  ["EnumItem"] = EncodeEnumItem,
  ["UDim"] = EncodeUDim,
  ["UDim2"] = EncodeUDim2,
  ["Vector2int16"] = EncodeVector2int16,
  ["Vector3int16"] = EncodeVector3int16,
  ["Vector2"] = EncodeVector2,
  ["Vector3"] = EncodeVector3,
  ["Color3"] = EncodeColor3,
  ["Content"] = EncodeContent,
  ["BrickColor"] = EncodeBrickColor,
  ["CFrame"] = EncodeCFrame,
  ["NumberRange"] = EncodeNumberRange,
  ["NumberSequence"] = EncodeNumberSequence,
  ["ColorSequence"] = EncodeColorSequence,
  ["Rect"] = EncodeRect,
  ["Font"] = EncodeFont,
  ["PhysicalProperties"] = EncodePhysicalProperties,
  ["Axes"] = EncodeAxes,
  ["Faces"] = EncodeFaces,
  ["DateTime"] = EncodeDateTime,
  ["Ray"] = EncodeRay,
  ["Instance"] = EncodeInstanceRef,
  ["Region3"] = EncodeRegion3,
  ["Region3int16"] = EncodeRegion3int16,
}
local function EncodeProperty(value: any, nilReference: any): any
  local encoder = PropertyEncoders[typeof(value)]
  if not encoder then error(`UnknownType: {typeof(value)}`) end
  return encoder(value, nilReference)
end

local PropertyDecoders: { [string]: (any) -> any } = {
  ["number"] = DecodeNumber,
  ["string"] = DecodeString,
  ["buffer"] = DecodeBuffer,
  ["EnumItem"] = DecodeEnumItem,
  ["UDim"] = DecodeUDim,
  ["UDim2"] = DecodeUDim2,
  ["Vector2int16"] = DecodeVector2int16,
  ["Vector3int16"] = DecodeVector3int16,
  ["Vector2"] = DecodeVector2,
  ["Vector3"] = DecodeVector3,
  ["Color3"] = DecodeColor3,
  ["Content"] = DecodeContent,
  ["BrickColor"] = DecodeBrickColor,
  ["CFrame"] = DecodeCFrame,
  ["NumberRange"] = DecodeNumberRange,
  ["NumberSequence"] = DecodeNumberSequence,
  ["ColorSequence"] = DecodeColorSequence,
  ["Rect"] = DecodeRect,
  ["Font"] = DecodeFont,
  ["PhysicalProperties"] = DecodePhysicalProperties,
  ["Axes"] = DecodeAxes,
  ["Faces"] = DecodeFaces,
  ["DateTime"] = DecodeDateTime,
  ["Ray"] = DecodeRay,
  ["Ref"] = DecodeInstanceRef,
  ["Region3"] = DecodeRegion3,
  ["Region3int16"] = DecodeRegion3int16,
}
local function DecodeProperty(value: any, nilReference: any): any
  if value == nilReference then return nil end
  local t = type(value)
  if t == "boolean" then return value end
  if t == "number" then return value end
  if t == "string" then return value end
  if t == "table" then
    local key = next(value)
    if key == nil then error("Empty encoded property") end
    local decoder = PropertyDecoders[key]
    if not decoder then error(`UnknownType: {key}`) end
    return decoder(value)
  end
  error(`UnknownType: {typeof(value)}`)
end

local AttributeEncoders: { [string]: (any, any) -> any } = {
  ["string"] = EncodeString,
  ["boolean"] = EncodeBoolean,
  ["number"] = EncodeNumber,
  ["UDim"] = EncodeUDim,
  ["UDim2"] = EncodeUDim2,
  ["Vector2"] = EncodeVector2,
  ["Vector3"] = EncodeVector3,
  ["Color3"] = EncodeColor3,
  ["BrickColor"] = EncodeBrickColor,
  ["CFrame"] = EncodeCFrame,
  ["NumberRange"] = EncodeNumberRange,
  ["NumberSequence"] = EncodeNumberSequence,
  ["ColorSequence"] = EncodeColorSequence,
  ["Rect"] = EncodeRect,
  ["Font"] = EncodeFont,
}
local function EncodeAttribute(value: any, nilReference: any): any
  local encoder = AttributeEncoders[typeof(value)]
  if not encoder then error(`UnknownType: {typeof(value)}`) end
  return encoder(value, nilReference)
end

local AttributeDecoders: { [string]: (any) -> any } = {
  ["number"] = DecodeNumber,
  ["string"] = DecodeString,
  ["UDim"] = DecodeUDim,
  ["UDim2"] = DecodeUDim2,
  ["Vector2"] = DecodeVector2,
  ["Vector3"] = DecodeVector3,
  ["Color3"] = DecodeColor3,
  ["BrickColor"] = DecodeBrickColor,
  ["CFrame"] = DecodeCFrame,
  ["NumberRange"] = DecodeNumberRange,
  ["NumberSequence"] = DecodeNumberSequence,
  ["ColorSequence"] = DecodeColorSequence,
  ["Rect"] = DecodeRect,
  ["Font"] = DecodeFont,
}
local function DecodeAttribute(value: any): any
  local t = type(value)
  if t == "boolean" then return value end
  if t == "number" then return value end
  if t == "string" then return value end
  if t == "table" then
    local key = next(value)
    if key == nil then error("Empty encoded attribute") end
    local decoder = AttributeDecoders[key]
    if not decoder then error(`UnknownType: {key}`) end
    return decoder(value)
  end
  error(`UnknownType: {typeof(value)}`)
end

--[[
  depth=0, this child specifically and then shallow view of it's children
]]
local function EncodeInstance(
  inst: Instance,
  depth: number,
  nilReference: any
): EncodedInstance
  local result: EncodedInstance = {
    Name = EscapeName(inst.Name),
    ClassName = inst.ClassName,
    DebugId = GetDebugId(inst),
  }
  if depth >= 0 then
    -- Children
    local rawChildren = inst:GetChildren()
    local children = table.create(#rawChildren)
    local childDepth = depth - 1
    for i, child in rawChildren do
      children[i] = EncodeInstance(child, childDepth, nilReference)
    end
    if #children > 0 then result.Children = children end
    -- Properties
    local properties = {}
    for key, val in GetProperties(inst) do
      properties[key] = EncodeProperty(val, nilReference)
    end
    if next(properties) then result.Properties = properties end
    -- Attributes
    local attributes = {}
    for key, val in inst:GetAttributes() do
      attributes[key] = EncodeAttribute(val, nilReference)
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
