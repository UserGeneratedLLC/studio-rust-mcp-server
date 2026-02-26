--!strict
--!optimize 2

local EncodingService = game:GetService("EncodingService")
local InsertService = game:GetService("InsertService")
local ReflectionService = game:GetService("ReflectionService")
local TouchInputService = game:GetService("TouchInputService")

local Paths = require("Paths")

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

-- TODO(high): make this hierarchical
-- stylua: ignore
local SerializeOverride: { [string]: boolean } = {
  -- BasePart
  Size = true, CFrame = true,
  Color = true, Material = true, Transparency = true,
  Reflectance = true, CanCollide = true, Anchored = true, Shape = true,
  -- TODO(high): we cannot support hiding these until we make this hierarchical...
  -- BrickColor = false, Orientation = false, Position = false,
  -- BackSurface = false, BottomSurface = false, FrontSurface = false,
  -- LeftSurface = false, RightSurface = false, TopSurface = false,
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

local function EncodeNumber(v: number): any return tostring(v) end
local function DecodeNumber(v: any): number return assert(tonumber(v)) end

local function EncodeString(v: any): string
  return buffer.tostring(EncodingService:Base64Encode(buffer.fromstring(v)))
end
local function DecodeString(v: any): string
  return buffer.tostring(EncodingService:Base64Decode(buffer.fromstring(v)))
end

local function EncodeBoolean(v: boolean): any return v end
local function DecodeBoolean(v: any): boolean
  assert(type(v) == "boolean")
  return v
end

local function EncodeBuffer(v: buffer): any return buffer.tostring(EncodingService:Base64Encode(v)) end
local function DecodeBuffer(v: any): buffer
  return EncodingService:Base64Decode(buffer.fromstring(v))
end

local function EncodeEnumItem(v: EnumItem): any
  return { Type = tostring(v.EnumType), Name = v.Name }
end
local function DecodeEnumItem(v: any): EnumItem return (Enum :: any)[v.Type][v.Name] end

local function EncodeUDim(v: UDim): any return { EncodeNumber(v.Scale), EncodeNumber(v.Offset) } end
local function DecodeUDim(v: any): UDim return UDim.new(DecodeNumber(v[1]), DecodeNumber(v[2])) end

local function EncodeUDim2(v: UDim2): any
  return {
    EncodeNumber(v.X.Scale),
    EncodeNumber(v.X.Offset),
    EncodeNumber(v.Y.Scale),
    EncodeNumber(v.Y.Offset),
  }
end
local function DecodeUDim2(v: any): UDim2
  return UDim2.new(DecodeNumber(v[1]), DecodeNumber(v[2]), DecodeNumber(v[3]), DecodeNumber(v[4]))
end

local function EncodeVector2int16(v: Vector2int16): any return { v.X, v.Y } end
local function DecodeVector2int16(v: any): Vector2int16 return Vector2int16.new(v[1], v[2]) end

local function EncodeVector3int16(v: Vector3int16): any return { v.X, v.Y, v.Z } end
local function DecodeVector3int16(v: any): Vector3int16 return Vector3int16.new(v[1], v[2], v[3]) end

local function EncodeVector2(v: Vector2): any return { EncodeNumber(v.X), EncodeNumber(v.Y) } end
local function DecodeVector2(v: any): Vector2
  return Vector2.new(DecodeNumber(v[1]), DecodeNumber(v[2]))
end

local function EncodeVector3(v: Vector3): any
  return { EncodeNumber(v.X), EncodeNumber(v.Y), EncodeNumber(v.Z) }
end
local function DecodeVector3(v: any): Vector3
  return Vector3.new(DecodeNumber(v[1]), DecodeNumber(v[2]), DecodeNumber(v[3]))
end

local function EncodeColor3(v: Color3): any
  return { EncodeNumber(v.R), EncodeNumber(v.G), EncodeNumber(v.B) }
end
local function DecodeColor3(v: any): Color3
  return Color3.new(DecodeNumber(v[1]), DecodeNumber(v[2]), DecodeNumber(v[3]))
end

-- TODO(low): EncodeContent silently produces garbage for non-URI Content
--  encode the EditableImage/Mesh/Capture/VideoContext etc.
local function EncodeContent(v: Content): any
  local data: any
  local sourceType = v.SourceType
  if sourceType == Enum.ContentSourceType.Uri then
    data = v.Uri
  elseif sourceType == Enum.ContentSourceType.None then
    data = ""
  elseif sourceType == Enum.ContentSourceType.Object then
    if v.Object then
      data = v.Object.ClassName
    else
      data = "Object"
    end
  elseif sourceType == Enum.ContentSourceType.Opaque then
    data = "Opaque"
  else
    error(`UnsupportedContent {sourceType}`)
  end
  return data
end
local function DecodeContent(v: string): Content return Content.fromUri(v) end

local function EncodeBrickColor(v: BrickColor): any return v.Name end
local function DecodeBrickColor(v: any): BrickColor return BrickColor.new(v) end

local function EncodeCFrame(v: CFrame): any
  local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = v:GetComponents()
  return {
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
  }
end
local function DecodeCFrame(v: any): CFrame
  return CFrame.new(
    DecodeNumber(v[1]),
    DecodeNumber(v[2]),
    DecodeNumber(v[3]),
    DecodeNumber(v[4]),
    DecodeNumber(v[5]),
    DecodeNumber(v[6]),
    DecodeNumber(v[7]),
    DecodeNumber(v[8]),
    DecodeNumber(v[9]),
    DecodeNumber(v[10]),
    DecodeNumber(v[11]),
    DecodeNumber(v[12])
  )
end

local function EncodeNumberRange(v: NumberRange): any
  return { EncodeNumber(v.Min), EncodeNumber(v.Max) }
end
local function DecodeNumberRange(v: any): NumberRange
  return NumberRange.new(DecodeNumber(v[1]), DecodeNumber(v[2]))
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
  return keypoints
end
local function DecodeNumberSequence(v: any): NumberSequence
  local keypoints = table.create(#v)
  for i, kp in v do
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
  return keypoints
end
local function DecodeColorSequence(v: any): ColorSequence
  local keypoints = table.create(#v)
  for i, kp in v do
    keypoints[i] = ColorSequenceKeypoint.new(
      DecodeNumber(kp[1]),
      Color3.new(DecodeNumber(kp[2]), DecodeNumber(kp[3]), DecodeNumber(kp[4]))
    )
  end
  return ColorSequence.new(keypoints)
end

local function EncodeRect(v: Rect): any
  return {
    EncodeNumber(v.Min.X),
    EncodeNumber(v.Min.Y),
    EncodeNumber(v.Max.X),
    EncodeNumber(v.Max.Y),
  }
end
local function DecodeRect(v: any): Rect
  return Rect.new(DecodeNumber(v[1]), DecodeNumber(v[2]), DecodeNumber(v[3]), DecodeNumber(v[4]))
end

local function EncodeFont(v: Font): any
  local family = v.Family :: any
  return {
    family = if type(family) == "string" then family else family.Uri or tostring(family),
    weight = v.Weight.Name,
    style = v.Style.Name,
  }
end
local function DecodeFont(v: any): Font
  return Font.new(v.family, (Enum.FontWeight :: any)[v.weight], (Enum.FontStyle :: any)[v.style])
end

local function EncodePhysicalProperties(v: PhysicalProperties): any
  return {
    EncodeNumber(v.Density),
    EncodeNumber(v.Friction),
    EncodeNumber(v.Elasticity),
    EncodeNumber(v.FrictionWeight),
    EncodeNumber(v.ElasticityWeight),
  }
end
local function DecodePhysicalProperties(v: any): PhysicalProperties
  return PhysicalProperties.new(
    DecodeNumber(v[1]),
    DecodeNumber(v[2]),
    DecodeNumber(v[3]),
    DecodeNumber(v[4]),
    DecodeNumber(v[5])
  )
end

local function EncodeAxes(v: Axes): any return { X = v.X, Y = v.Y, Z = v.Z } end
local function DecodeAxes(v: any): Axes
  local axes = {}
  if v.X then table.insert(axes, Enum.Axis.X) end
  if v.Y then table.insert(axes, Enum.Axis.Y) end
  if v.Z then table.insert(axes, Enum.Axis.Z) end
  return Axes.new(unpack(axes))
end

local function EncodeFaces(v: Faces): any
  return {
    Top = v.Top,
    Bottom = v.Bottom,
    Left = v.Left,
    Right = v.Right,
    Front = v.Front,
    Back = v.Back,
  }
end
local function DecodeFaces(v: any): Faces
  local faces = {}
  if v.Top then table.insert(faces, Enum.NormalId.Top) end
  if v.Bottom then table.insert(faces, Enum.NormalId.Bottom) end
  if v.Left then table.insert(faces, Enum.NormalId.Left) end
  if v.Right then table.insert(faces, Enum.NormalId.Right) end
  if v.Front then table.insert(faces, Enum.NormalId.Front) end
  if v.Back then table.insert(faces, Enum.NormalId.Back) end
  return Faces.new(unpack(faces))
end

local function EncodeDateTime(v: DateTime): any return v:ToIsoDate() end
local function DecodeDateTime(v: any): DateTime return assert(DateTime.fromIsoDate(v)) end

local function EncodeRay(v: Ray): any
  return {
    EncodeNumber(v.Origin.X),
    EncodeNumber(v.Origin.Y),
    EncodeNumber(v.Origin.Z),
    EncodeNumber(v.Direction.X),
    EncodeNumber(v.Direction.Y),
    EncodeNumber(v.Direction.Z),
  }
end
local function DecodeRay(v: any): Ray
  return Ray.new(
    Vector3.new(DecodeNumber(v[1]), DecodeNumber(v[2]), DecodeNumber(v[3])),
    Vector3.new(DecodeNumber(v[4]), DecodeNumber(v[5]), DecodeNumber(v[6]))
  )
end

local function EncodeInstanceRef(v: Instance): any return Paths.GetDistinctPath(v) end
local function DecodeInstanceRef(v: any): Instance
  local inst = Paths.FromDistinctPath(v)
  if not inst then error(`UnknownRef {v}`) end
  return inst
end

local function EncodeRegion3(v: Region3): any
  local center = v.CFrame.Position
  local half = v.Size * 0.5
  local min = center - half
  local max = center + half
  return {
    EncodeNumber(min.X),
    EncodeNumber(min.Y),
    EncodeNumber(min.Z),
    EncodeNumber(max.X),
    EncodeNumber(max.Y),
    EncodeNumber(max.Z),
  }
end
local function DecodeRegion3(v: any): Region3
  return Region3.new(
    Vector3.new(DecodeNumber(v[1]), DecodeNumber(v[2]), DecodeNumber(v[3])),
    Vector3.new(DecodeNumber(v[4]), DecodeNumber(v[5]), DecodeNumber(v[6]))
  )
end

local function EncodeRegion3int16(v: Region3int16): any
  return {
    v.Min.X,
    v.Min.Y,
    v.Min.Z,
    v.Max.X,
    v.Max.Y,
    v.Max.Z,
  }
end
local function DecodeRegion3int16(v: any): Region3int16
  return Region3int16.new(Vector3int16.new(v[1], v[2], v[3]), Vector3int16.new(v[4], v[5], v[6]))
end

local PropertyEncoders: { [string]: (any) -> any } = {
  ["string"] = EncodeString,
  ["number"] = EncodeNumber,
  ["boolean"] = EncodeBoolean,
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
local function EncodeProperty(value: any, nilReference: any, scriptType: string): any
  if value == nil then return {
    [scriptType] = nilReference,
  } end
  if scriptType == "string" then
    if utf8.len(value) then return value end
  elseif scriptType == "number" then
    if math.isfinite(value) then return value end
  elseif scriptType == "boolean" then
    return value
  end
  local encoder = PropertyEncoders[scriptType]
  if not encoder then error(`UnknownType {scriptType}`) end
  return {
    [scriptType] = encoder(value),
  }
end

local PropertiesCache: { [string]: { ReflectedProperty } } = {}

local function GetCachedProperties(className: string): { ReflectedProperty }
  local cached = PropertiesCache[className]
  if cached then return cached end
  local reflected: { ReflectedProperty }? =
    ReflectionService:GetPropertiesOfClass(className, PropertiesFilter) :: any
  if not reflected then
    PropertiesCache[className] = {}
    return PropertiesCache[className]
  end
  local filtered = {}
  for _, prop in reflected do
    local name = prop.Name
    if SkipProps[name] then continue end
    if not prop.Type.ScriptType then continue end
    if not PropertyEncoders[prop.Type.ScriptType] then continue end
    if not prop.Permits.Read then continue end
    local override = SerializeOverride[name]
    if override ~= nil then
      if not override then continue end
    else
      if not prop.Serialized then continue end
      if prop.Display and prop.Display.DeprecationMessage then continue end
      if not prop.Permits.Write then continue end
    end
    table.insert(filtered, prop)
  end
  PropertiesCache[className] = filtered
  return filtered
end

local function EncodeProperties(inst: Instance, nilReference: any): { [string]: any }
  local props = GetCachedProperties(inst.ClassName)
  local result: { [string]: any } = {}
  for _, prop in props do
    local success, value = pcall(function() return (inst :: any)[prop.Name] end)
    if success then
      result[prop.Name] = EncodeProperty(value, nilReference, assert(prop.Type.ScriptType))
    end
  end
  return result
end

local PropertyDecoders: { [string]: (any) -> any } = {
  ["number"] = DecodeNumber,
  ["string"] = DecodeString,
  ["boolean"] = DecodeBoolean,
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
local function DecodeProperty(value: any, nilReference: any, scriptType: string): any
  if value == nilReference then return nil end
  local t = typeof(value)
  if t == "boolean" or t == "number" or t == "string" then
    if t == scriptType then return value end
  elseif t == "table" then
    local inner = value[scriptType]
    if inner ~= nil then
      if inner == nilReference then return nil end
      value = inner
    end
  end
  return PropertyDecoders[scriptType](value)
end

local AttributeEncoders: { [string]: (any) -> any } = {
  ["string"] = EncodeString,
  ["number"] = EncodeNumber,
  ["boolean"] = EncodeBoolean,
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
local function EncodeAttribute(value: any): any
  local t = typeof(value)
  if t == "string" then
    if utf8.len(value) then return value end
  elseif t == "number" then
    if math.isfinite(value) then return value end
  elseif t == "boolean" then
    return value
  end
  return {
    [t] = AttributeEncoders[t](value),
  }
end

local AttributeDecoders: { [string]: (any) -> any } = {
  ["string"] = DecodeString,
  ["number"] = DecodeNumber,
  ["boolean"] = DecodeBoolean,
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
  local t = typeof(value)
  if t == "boolean" or t == "number" or t == "string" then return value end
  if t == "table" then
    local key = next(value)
    if type(key) == "string" then
      local decoder = AttributeDecoders[key]
      if not decoder then error(`UnknownType {key}`) end
      return decoder(value[key])
    end
  end
  error(`UnknownType {t}`)
end

--[[
  depth=0, this child specifically and then shallow view of it's children
]]
local function EncodeInstance(inst: Instance, depth: number, nilReference: any): EncodedInstance
  assert(typeof(inst) == "Instance", "InvalidInstance")
  assert(math.isfinite(depth) and math.floor(depth) == depth, "InvalidDepth")
  assert(nilReference ~= nil, "InvalidNilReference")

  local result: EncodedInstance = {
    Name = Paths.EscapeName(inst.Name),
    ClassName = inst.ClassName,
    DebugId = Paths.GetDebugId(inst),
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

-- TODO(low): handle CSG parts
local function DecodeInstance(data: EncodedInstance, nilReference: any, parent: Instance?): Instance
  assert(type(data) == "table", "InvalidData")
  assert(nilReference ~= nil, "InvalidNilReference")
  assert(parent == nil or typeof(parent) == "Instance", "InvalidParent")

  assert(type(data.ClassName) == "string", "MalformedClassName")
  assert(type(data.Name) == "string", "MalformedName")
  assert(type(data.DebugId) == "string", "MalformedDebugId") -- unused
  assert(data.Shallow == nil or data.Shallow == true, "MalformedShallow")
  assert(data.Properties == nil or type(data.Properties) == "table", "MalformedProperties")
  assert(data.Attributes == nil or type(data.Attributes) == "table", "MalformedAttributes")
  assert(data.Tags == nil or type(data.Tags) == "table", "MalformedTags")
  assert(data.Children == nil or type(data.Children) == "table", "MalformedChildren")

  local properties = data.Properties

  local inst: Instance
  if data.ClassName ~= "MeshPart" then
    inst = Instance.new(data.ClassName)
  else
    local meshId = ""
    local collisionFidelity = Enum.CollisionFidelity.Default
    local renderFidelity = Enum.RenderFidelity.Automatic
    if properties then
      properties = table.clone(properties)
      local function decodeProperty<T>(key: string, scriptType: string, defaultValue: T): T
        local encoded = properties[key]
        if encoded == nil then return defaultValue end
        properties[key] = nil
        local success, result = pcall(DecodeProperty, encoded, nilReference, scriptType)
        if not success then error(`MalformedProperty {key}: {result}`) end
        return result
      end
      meshId = decodeProperty("MeshId", "string", meshId)
      collisionFidelity = decodeProperty("CollisionFidelity", "EnumItem", collisionFidelity)
      renderFidelity = decodeProperty("RenderFidelity", "EnumItem", renderFidelity)
    end
    inst = InsertService:CreateMeshPartAsync(meshId, collisionFidelity, renderFidelity)
  end

  inst.Name = Paths.UnescapeName(data.Name)
  if not data.Shallow then
    if properties then
      local instAny = inst :: any
      local props = GetCachedProperties(data.ClassName)
      for _, prop in props do
        local key = prop.Name
        local encoded = properties[key]
        if encoded ~= nil then
          local success, result =
            pcall(DecodeProperty, encoded, nilReference, assert(prop.Type.ScriptType))
          if not success then error(`MalformedProperty {key}: {result}`) end
          instAny[key] = result
        end
      end
    end
    if data.Attributes then
      for key, value in data.Attributes do
        local success, result = pcall(DecodeAttribute, value)
        if not success then error(`MalformedAttribute {key}: {result}`) end
        inst:SetAttribute(key, result)
      end
    end
    if data.Children then
      for i, childData in data.Children do
        local success, result = pcall(DecodeInstance, childData, nilReference, inst)
        if not success then error(`MalformedChild {i}: {result}`) end
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

-- TODO(medium): UpdateInstance: service detection if parent==game, overwrite with defaults optionally (see: ResetPropertyToDefault)

return table.freeze({
  EncodeInstance = EncodeInstance,
})
