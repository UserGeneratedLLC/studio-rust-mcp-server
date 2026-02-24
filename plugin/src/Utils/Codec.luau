--!strict
--!optimize 2

local EncodingService = game:GetService("EncodingService")
local ReflectionService = game:GetService("ReflectionService")

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

export type ReflectionMemberFilter = {
  -- The security context to use; can be more expansive than the current script's security
  Security: SecurityCapabilities?, -- default: SecurityCapabilities.fromCurrent()
  -- Whether to exclude inherited properties from superclasses
  ExcludeInherited: boolean?, -- default: false
  -- Whether to exclude Studio display information about the properties
  ExcludeDisplay: boolean?, -- default: false
}
export type ReflectionType = {
  -- Engine's internal type name, e.g. "bool", "float", "int", "string",
  -- "Vector3", "CoordinateFrame", "Color3", "Color3uint8", "BrickColor",
  -- "Enum", "RefType", "PhysicalProperties", "Faces", "SecurityCapabilities"
  EngineType: string,
  -- Luau-facing type name, e.g. "boolean", "number", "string", "Vector3",
  -- "CFrame", "Color3", "BrickColor", "EnumItem", "Instance".
  -- Absent for non-scriptable engine types (e.g. Color3uint8, SystemAddress).
  ScriptType: string?,
  -- Enum type name when EngineType == "Enum", e.g. "PartType", "Material"
  EnumType: string?,
  -- Expected class when EngineType == "RefType", e.g. "BasePart", "Instance"
  InstanceType: string?,
}
export type ReflectedProperty = {
  -- The name of the property
  Name: string,
  -- The superclass from which the property is inherited, or the class name if not inherited
  Owner: string,
  -- Whether the property is serialized (able to be saved to disk or sent over the network)
  Serialized: boolean,
  -- The type of the property
  Type: ReflectionType,
  -- The content type of the property, if applicable
  ContentType: Enum.AssetType?,
  -- Studio display information
  Display: {
    -- The category under which the property is listed in Studio
    Category: string,
    -- A message indicating that the property is deprecated, if applicable
    DeprecationMessage: string?,
  }?,
  -- The security permissions required to access this property
  Permits: {
    -- The security context required to read this property
    Read: SecurityCapabilities?,
    -- The security context required to read this property while thread-safe
    ReadParallel: SecurityCapabilities?,
    -- The security context required to write to this property
    Write: SecurityCapabilities?,
    -- The security context required to write to this property while thread-safe
    WriteParallel: SecurityCapabilities?,
  },
}

local SkipProps: { [string]: boolean } = {
  Parent = true,
  Name = true,
  ClassName = true,
  className = true,
  Archivable = true,
  DataCost = true,
  RobloxLocked = true,
}

-- stylua: ignore
local ForceSerialize: { [string]: boolean } = {
  -- BasePart
  Size = true, Position = true, Orientation = true, CFrame = true,
  Color = true, BrickColor = true, Material = true, Transparency = true,
  Reflectance = true, CanCollide = true, Anchored = true, Shape = true,
  -- Content/asset IDs
  MeshId = true, TextureID = true, MeshType = true, SoundId = true,
  Image = true, Texture = true, Face = true, AnimationId = true,
  Video = true, Source = true, LinkedSource = true,
  -- Sky
  SkyboxBk = true, SkyboxDn = true, SkyboxFt = true,
  SkyboxLf = true, SkyboxRt = true, SkyboxUp = true,
  MoonTextureId = true, SunTextureId = true,
  -- Light / Lighting
  Brightness = true, Range = true, LightingStyle = true, Technology = true,
  -- SurfaceAppearance
  ColorMap = true, MetalnessMap = true, NormalMap = true, RoughnessMap = true,
  -- Welds / Constraints
  Part0 = true, Part1 = true, C0 = true, C1 = true,
  Attachment0 = true, Attachment1 = true,
  -- References
  PrimaryPart = true, Adornee = true, Value = true,
  HumanoidRootPart = true, RootPart = true, SeatPart = true, WalkToPart = true,
  CameraSubject = true, SoundGroup = true, Controller = true,
}

local PropertiesFilter: ReflectionMemberFilter = {
  Security = SecurityCapabilities.fromCurrent(),
  ExcludeInherited = false,
  ExcludeDisplay = false,
}

local function GetDebugId(inst: Instance): string return inst:GetDebugId(0) end

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
  TODO(high):
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

local function EncodeNumber(v: number): any
  if not math.isfinite(v) then return { ["number"] = tostring(v) } end
  return v
end
local function DecodeNumber(v: any): number
  if type(v) == "number" then return v end
  return assert(tonumber(v["number"]))
end

local function EncodeString(v: string): any
  if not utf8.len(v) then
    return {
      ["string"] = buffer.tostring(EncodingService:Base64Encode(buffer.fromstring(v))),
    }
  end
  return v
end
local function DecodeString(v: any): string
  if type(v) == "string" then return v end
  return buffer.tostring(EncodingService:Base64Decode(buffer.fromstring(v["string"])))
end

local function EncodeNil(_v: nil, nilReference: any): any return nilReference end

local function EncodeBoolean(v: boolean): any return v end
local function DecodeBoolean(v: any): boolean
  assert(type(v) == "boolean")
  return v
end

local function EncodeBuffer(v: buffer): any
  return { ["buffer"] = buffer.tostring(EncodingService:Base64Encode(v)) }
end
local function DecodeBuffer(v: any): buffer
  return EncodingService:Base64Decode(buffer.fromstring(v["buffer"]))
end

local function EncodeEnumItem(v: EnumItem): any
  return { ["EnumItem"] = { Type = tostring(v.EnumType), Name = v.Name } }
end
local function DecodeEnumItem(v: any): EnumItem
  local data = v["EnumItem"]
  return (Enum :: any)[data.Type][data.Name]
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

local function EncodeVector2int16(v: Vector2int16): any return { ["Vector2int16"] = { v.X, v.Y } } end
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
  return Vector3.new(DecodeNumber(data[1]), DecodeNumber(data[2]), DecodeNumber(data[3]))
end

local function EncodeColor3(v: Color3): any
  return {
    ["Color3"] = { EncodeNumber(v.R), EncodeNumber(v.G), EncodeNumber(v.B) },
  }
end
local function DecodeColor3(v: any): Color3
  local data = v["Color3"]
  return Color3.new(DecodeNumber(data[1]), DecodeNumber(data[2]), DecodeNumber(data[3]))
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
local function DecodeContent(v: any): Content return Content.fromUri(v["Content"]) end

local function EncodeBrickColor(v: BrickColor): any return { ["BrickColor"] = v.Name } end
local function DecodeBrickColor(v: any): BrickColor return BrickColor.new(v["BrickColor"]) end

local function EncodeCFrame(v: CFrame): any
  local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = v:GetComponents()
  return {
    ["CFrame"] = {
      EncodeNumber(x),
      EncodeNumber(y),
      EncodeNumber(z),
      EncodeNumber(r00),
      EncodeNumber(r01),
      EncodeNumber(r02),
      EncodeNumber(r10),
      EncodeNumber(r11),
      EncodeNumber(r12),
      EncodeNumber(r20),
      EncodeNumber(r21),
      EncodeNumber(r22),
    },
  }
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
    keypoints[i] =
      NumberSequenceKeypoint.new(DecodeNumber(kp[1]), DecodeNumber(kp[2]), DecodeNumber(kp[3]))
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
      family = if type(family) == "string" then family else family.Uri or tostring(family),
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

local function EncodeAxes(v: Axes): any return { ["Axes"] = { X = v.X, Y = v.Y, Z = v.Z } } end
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

local function EncodeDateTime(v: DateTime): any return { ["DateTime"] = v:ToIsoDate() } end
local function DecodeDateTime(v: any): DateTime return assert(DateTime.fromIsoDate(v["DateTime"])) end

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
    Vector3.new(DecodeNumber(data[1]), DecodeNumber(data[2]), DecodeNumber(data[3])),
    Vector3.new(DecodeNumber(data[4]), DecodeNumber(data[5]), DecodeNumber(data[6]))
  )
end

local function EncodeInstanceRef(v: Instance): any return { ["Instance"] = GetDistinctPath(v) } end
local function DecodeInstanceRef(v: any): Instance
  local path = v["Instance"]
  local inst = FromDistinctPath(path)
  if not inst then error(`UnknownRef: {path}`) end
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
    Vector3.new(DecodeNumber(data[1]), DecodeNumber(data[2]), DecodeNumber(data[3])),
    Vector3.new(DecodeNumber(data[4]), DecodeNumber(data[5]), DecodeNumber(data[6]))
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

local PropertyEncoders: { [string]: (any) -> any } = {
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
local function EncodeProperty(value: any, nilReference: any, reflectionType: ReflectionType): any
  local typeName = reflectionType.ScriptType or typeof(value)
  if value == nil then return {
    [typeName] = nilReference,
  } end
  local encoder = PropertyEncoders[typeName]
  if not encoder then error(`UnknownType: {typeName}`) end
  return encoder(value)
end

-- TODO(low): cache these
local function EncodeProperties(inst: Instance, nilReference: any): { [string]: any }
  local reflected: { ReflectedProperty }? =
    ReflectionService:GetPropertiesOfClass(inst.ClassName, PropertiesFilter) :: any
  if not reflected then return {} end
  local result: { [string]: any } = {}
  for _, prop in reflected do
    local name = prop.Name
    if SkipProps[name] then continue end
    if not prop.Permits.Read then continue end
    local forced = ForceSerialize[name] == true
    if not prop.Serialized and not forced then continue end
    if not forced then
      if prop.Display and prop.Display.DeprecationMessage then continue end
      if not prop.Permits.Write then continue end
    end
    local ok, value = pcall(function() return (inst :: any)[name] end)
    if ok then result[name] = EncodeProperty(value, nilReference, prop.Type) end
  end
  return result
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
  ["Instance"] = DecodeInstanceRef,
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
    if type(key) == "string" then
      local inner = value[key]
      if inner == nilReference then return nil end
      local decoder = PropertyDecoders[key]
      if not decoder then error(`UnknownType: {key}`) end
      return decoder(value)
    end
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
    if type(key) == "string" then
      local decoder = AttributeDecoders[key]
      if not decoder then error(`UnknownType: {key}`) end
      return decoder(value)
    end
  end
  error(`UnknownType: {typeof(value)}`)
end

--[[
  depth=0, this child specifically and then shallow view of it's children
]]
local function EncodeInstance(inst: Instance, depth: number, nilReference: any): EncodedInstance
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
    local properties = EncodeProperties(inst, nilReference)
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

local function DecodeInstance(data: EncodedInstance, nilReference: any, parent: Instance?): Instance
  local inst = Instance.new(data.ClassName)
  inst.Name = UnescapeName(data.Name)
  if not data.Shallow then
    if data.Properties then
      for key, value in data.Properties do
        (inst :: any)[key] = DecodeProperty(value, nilReference)
      end
    end
    if data.Attributes then
      for key, value in data.Attributes do
        inst:SetAttribute(key, DecodeAttribute(value))
      end
    end
    if data.Children then
      for _, childData in data.Children do
        DecodeInstance(childData, nilReference, inst)
      end
    end
    if data.Tags then
      for _, tag in data.Tags do
        inst:AddTag(tag)
      end
    end
  end
  if parent then inst.Parent = parent end
  return inst
end

local module = {}

return table.freeze(module)
