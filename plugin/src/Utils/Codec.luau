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
  if pivot then
    repeat
      table.insert(names, EscapeName(pivot.Name))
      pivot = pivot.Parent
    until not pivot
  else
    table.insert(names, "")
  end
  local n = #names
  local center = n // 2
  for i = 1, center do
    names[i], names[n - i + 1] = names[n - i + 1], names[i]
  end
  return table.concat(names, "/")
end

--[[
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

local PropertyEncoders: { [string]: (any, any) -> any } = {
  ["nil"] = function(v: nil, nilReference: any) return nilReference end,
  ["string"] = EncodeString,
  ["boolean"] = function(v: boolean) return v end,
  ["number"] = EncodeNumber,
  ["buffer"] = function(v: buffer)
    return { ["buffer"] = buffer.tostring(EncodingService:Base64Encode(v)) }
  end,
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
  ["DateTime"] = function(v: DateTime) return { ["DateTime"] = v:ToIsoDate() } end,
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
  ["Region3"] = function(v: Region3)
    local center = v.CFrame.Position
    local half = v.Size / 2
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
  end,
  ["Region3int16"] = function(v: Region3int16)
    return {
      ["Region3int16"] = {
        EncodeNumber(v.Min.X),
        EncodeNumber(v.Min.Y),
        EncodeNumber(v.Min.Z),
        EncodeNumber(v.Max.X),
        EncodeNumber(v.Max.Y),
        EncodeNumber(v.Max.Z),
      },
    }
  end,
  ["ColorSequenceKeypoint"] = function(v: ColorSequenceKeypoint)
    return {
      ["ColorSequenceKeypoint"] = {
        EncodeNumber(v.Time),
        EncodeNumber(v.Value.R),
        EncodeNumber(v.Value.G),
        EncodeNumber(v.Value.B),
      },
    }
  end,
  ["NumberSequenceKeypoint"] = function(v: NumberSequenceKeypoint)
    return {
      ["NumberSequenceKeypoint"] = {
        EncodeNumber(v.Time),
        EncodeNumber(v.Value),
        EncodeNumber(v.Envelope),
      },
    }
  end,
  ["Path2DControlPoint"] = function(v: Path2DControlPoint)
    local pos = v.Position
    local lt = v.LeftTangent
    local rt = v.RightTangent
    return {
      ["Path2DControlPoint"] = {
        EncodeNumber(pos.X.Scale),
        EncodeNumber(pos.X.Offset),
        EncodeNumber(pos.Y.Scale),
        EncodeNumber(pos.Y.Offset),
        EncodeNumber(lt.X.Scale),
        EncodeNumber(lt.X.Offset),
        EncodeNumber(lt.Y.Scale),
        EncodeNumber(lt.Y.Offset),
        EncodeNumber(rt.X.Scale),
        EncodeNumber(rt.X.Offset),
        EncodeNumber(rt.Y.Scale),
        EncodeNumber(rt.Y.Offset),
      },
    }
  end,
  ["RotationCurveKey"] = function(v: RotationCurveKey)
    local comps = { v.Value:GetComponents() }
    local cframe = table.create(12)
    for i = 1, 12 do
      cframe[i] = EncodeNumber(comps[i])
    end
    return {
      ["RotationCurveKey"] = {
        time = EncodeNumber(v.Time),
        value = cframe,
        interpolation = v.Interpolation.Name,
        leftTangent = EncodeNumber(v.LeftTangent),
        rightTangent = EncodeNumber(v.RightTangent),
      },
    }
  end,
  ["ValueCurveKey"] = function(v: ValueCurveKey)
    return {
      ["ValueCurveKey"] = {
        time = EncodeNumber(v.Time),
        value = EncodeNumber(v.Value),
        interpolation = v.Interpolation.Name,
        leftTangent = EncodeNumber(v.LeftTangent),
        rightTangent = EncodeNumber(v.RightTangent),
      },
    }
  end,
  ["FloatCurveKey"] = function(v: FloatCurveKey)
    return {
      ["FloatCurveKey"] = {
        time = EncodeNumber(v.Time),
        value = EncodeNumber(v.Value),
        interpolation = v.Interpolation.Name,
        leftTangent = EncodeNumber(v.LeftTangent),
        rightTangent = EncodeNumber(v.RightTangent),
      },
    }
  end,
}
local function EncodeProperty(value: any, nilReference: any): any
  local encoder = PropertyEncoders[typeof(value)]
  if not encoder then error(`UnknownType: {typeof(value)}`) end
  return encoder(value, nilReference)
end

local AttributeEncoders: { [string]: (any, any) -> any } = {
  ["string"] = PropertyEncoders["string"],
  ["boolean"] = PropertyEncoders["boolean"],
  ["number"] = PropertyEncoders["number"],
  ["UDim"] = PropertyEncoders["UDim"],
  ["UDim2"] = PropertyEncoders["UDim2"],
  ["Vector2"] = PropertyEncoders["Vector2"],
  ["Vector3"] = PropertyEncoders["Vector3"],
  ["Color3"] = PropertyEncoders["Color3"],
  ["BrickColor"] = PropertyEncoders["BrickColor"],
  ["CFrame"] = PropertyEncoders["CFrame"],
  ["NumberRange"] = PropertyEncoders["NumberRange"],
  ["NumberSequence"] = PropertyEncoders["NumberSequence"],
  ["ColorSequence"] = PropertyEncoders["ColorSequence"],
  ["Rect"] = PropertyEncoders["Rect"],
  ["Font"] = PropertyEncoders["Font"],
}
local function EncodeAttribute(value: any, nilReference: any): any
  local encoder = AttributeEncoders[typeof(value)]
  if not encoder then error(`UnknownType: {typeof(value)}`) end
  return encoder(value, nilReference)
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
    local children = {}
    local childDepth = depth - 1
    for _, child in inst:GetChildren() do
      table.insert(children, EncodeInstance(child, childDepth, nilReference))
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
