--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect
local beforeAll = JestGlobals.beforeAll
local afterAll = JestGlobals.afterAll

local Codec = require(script.Parent.Codec)
local DeepEquals = require(script.Parent.DeepEquals)
local Paths = require(script.Parent.Paths)

local RS = game:GetService("ReplicatedStorage")
local EncodeInstance = Codec.EncodeInstance
local NIL = "__NIL__"

local function id(inst)
  return Paths.GetDebugId(inst)
end
local function esc(name)
  return Paths.EscapeName(name)
end

local root: Folder
local emptyFolder: Folder
local namedFolder: Folder
local dotFolder: Folder
local allSpecialFolder: Folder
local parentFolder: Folder, childA: Folder, childB: Folder, grandchild: Folder, greatGrand: Folder
local tagFolder: Folder, multiTagFolder: Folder
local attrFolder: Folder
local part: Part
local physPart: Part
local objVal: ObjectValue
local weldPartA: Part, weldPartB: Part, weld: Weld
local pointLight: PointLight
local uiCorner: UICorner
local screenGui: ScreenGui, frame: Frame, textLabel: TextLabel
local sound: Sound
local specialMesh: SpecialMesh
local particleEmitter: ParticleEmitter
local refTarget: Part

beforeAll(function()
  root = Instance.new("Folder")
  root.Name = "__CodecTest__"

  -- Empty folder (structural tests)
  emptyFolder = Instance.new("Folder")
  emptyFolder.Name = "EmptyFolder"
  emptyFolder.Parent = root

  -- Named folder
  namedFolder = Instance.new("Folder")
  namedFolder.Name = "TestFolder"
  namedFolder.Parent = root

  -- Special character names
  dotFolder = Instance.new("Folder")
  dotFolder.Name = "Has.Dot"
  dotFolder.Parent = root

  allSpecialFolder = Instance.new("Folder")
  allSpecialFolder.Name = "%~/.@"
  allSpecialFolder.Parent = root

  -- Depth tree: parentFolder > childA > grandchild > greatGrand
  --                           > childB
  parentFolder = Instance.new("Folder")
  parentFolder.Name = "Parent"
  parentFolder.Parent = root

  childA = Instance.new("Folder")
  childA.Name = "ChildA"
  childA.Parent = parentFolder

  childB = Instance.new("Folder")
  childB.Name = "ChildB"
  childB.Parent = parentFolder

  grandchild = Instance.new("Folder")
  grandchild.Name = "Grandchild"
  grandchild.Parent = childA

  greatGrand = Instance.new("Folder")
  greatGrand.Name = "GreatGrand"
  greatGrand.Parent = grandchild

  -- Tags
  tagFolder = Instance.new("Folder")
  tagFolder.Name = "TagFolder"
  tagFolder.Parent = root
  tagFolder:AddTag("Solo")

  multiTagFolder = Instance.new("Folder")
  multiTagFolder.Name = "MultiTagFolder"
  multiTagFolder.Parent = root
  multiTagFolder:AddTag("Alpha")
  multiTagFolder:AddTag("Beta")
  multiTagFolder:AddTag("Gamma")

  -- Attributes folder (all 15 attribute types)
  attrFolder = Instance.new("Folder")
  attrFolder.Name = "AttrFolder"
  attrFolder.Parent = root
  attrFolder:SetAttribute("str", "hello")
  attrFolder:SetAttribute("num", 42)
  attrFolder:SetAttribute("bool", true)
  attrFolder:SetAttribute("udim", UDim.new(0.5, 10))
  attrFolder:SetAttribute("udim2", UDim2.new(0.5, 10, 0.25, 20))
  attrFolder:SetAttribute("vec2", Vector2.new(1.5, 2.5))
  attrFolder:SetAttribute("vec3", Vector3.new(1, 2, 3))
  attrFolder:SetAttribute("color3", Color3.new(1, 0, 0.5))
  attrFolder:SetAttribute("brick", BrickColor.new("Bright red"))
  attrFolder:SetAttribute("cframe", CFrame.new(10, 20, 30))
  attrFolder:SetAttribute("numrange", NumberRange.new(0, 10))
  attrFolder:SetAttribute(
    "numseq",
    NumberSequence.new({
      NumberSequenceKeypoint.new(0, 0, 0),
      NumberSequenceKeypoint.new(1, 1, 0),
    })
  )
  attrFolder:SetAttribute(
    "colseq",
    ColorSequence.new({
      ColorSequenceKeypoint.new(0, Color3.new(1, 0, 0)),
      ColorSequenceKeypoint.new(1, Color3.new(0, 1, 0)),
    })
  )
  attrFolder:SetAttribute("rect", Rect.new(0, 0, 100, 200))
  attrFolder:SetAttribute(
    "font",
    Font.new(
      "rbxasset://fonts/families/SourceSansPro.json",
      Enum.FontWeight.Bold,
      Enum.FontStyle.Italic
    )
  )

  -- Part (number, boolean, Vector3, Color3, CFrame, EnumItem)
  part = Instance.new("Part")
  part.Name = "TestPart"
  part.Size = Vector3.new(4, 2, 8)
  part.CFrame = CFrame.new(1, 2, 3)
  part.Color = Color3.new(1, 0, 0)
  part.Material = Enum.Material.Wood
  part.Transparency = 0.5
  part.Reflectance = 0.25
  part.CanCollide = false
  part.Anchored = true
  part.Shape = Enum.PartType.Block
  part.Parent = root

  -- Part with CustomPhysicalProperties
  physPart = Instance.new("Part")
  physPart.Name = "PhysPart"
  physPart.CustomPhysicalProperties = PhysicalProperties.new(2, 0.5, 0.25, 1, 1)
  physPart.Anchored = true
  physPart.Parent = root

  -- Reference target for ObjectValue
  refTarget = Instance.new("Part")
  refTarget.Name = "RefTarget"
  refTarget.Anchored = true
  refTarget.Parent = root

  -- ObjectValue (Instance ref)
  objVal = Instance.new("ObjectValue")
  objVal.Name = "ObjVal"
  objVal.Value = refTarget
  objVal.Parent = root

  -- Weld with Part0/Part1 refs
  weldPartA = Instance.new("Part")
  weldPartA.Name = "WeldPartA"
  weldPartA.Anchored = true
  weldPartA.Parent = root

  weldPartB = Instance.new("Part")
  weldPartB.Name = "WeldPartB"
  weldPartB.Anchored = true
  weldPartB.Parent = root

  weld = Instance.new("Weld")
  weld.Name = "TestWeld"
  weld.Part0 = weldPartA
  weld.Part1 = weldPartB
  weld.C0 = CFrame.new(1, 0, 0)
  weld.C1 = CFrame.new(0, 1, 0)
  weld.Parent = root

  -- PointLight (number: Brightness, Range)
  pointLight = Instance.new("PointLight")
  pointLight.Name = "TestLight"
  pointLight.Brightness = 2
  pointLight.Range = 16
  pointLight.Color = Color3.new(1, 1, 0)
  pointLight.Parent = root

  -- UICorner (UDim: CornerRadius)
  uiCorner = Instance.new("UICorner")
  uiCorner.Name = "TestCorner"
  uiCorner.CornerRadius = UDim.new(0.5, 10)
  uiCorner.Parent = root

  -- ScreenGui > Frame > TextLabel (UDim2, Font)
  screenGui = Instance.new("ScreenGui")
  screenGui.Name = "TestGui"
  screenGui.Parent = root

  frame = Instance.new("Frame")
  frame.Name = "TestFrame"
  frame.Size = UDim2.new(0.5, 10, 0.25, 20)
  frame.Parent = screenGui

  textLabel = Instance.new("TextLabel")
  textLabel.Name = "TestLabel"
  textLabel.FontFace = Font.new(
    "rbxasset://fonts/families/SourceSansPro.json",
    Enum.FontWeight.Bold,
    Enum.FontStyle.Italic
  )
  textLabel.Text = "Hello"
  textLabel.Parent = screenGui

  -- Sound (Content: SoundId)
  sound = Instance.new("Sound")
  sound.Name = "TestSound"
  sound.SoundId = "rbxassetid://123456"
  sound.Parent = root

  -- SpecialMesh (Content: MeshId, EnumItem: MeshType)
  specialMesh = Instance.new("SpecialMesh")
  specialMesh.Name = "TestMesh"
  specialMesh.MeshId = "rbxassetid://654321"
  specialMesh.MeshType = Enum.MeshType.FileMesh
  specialMesh.Parent = root

  -- ParticleEmitter (NumberSequence, ColorSequence, NumberRange)
  particleEmitter = Instance.new("ParticleEmitter")
  particleEmitter.Name = "TestParticles"
  particleEmitter.Size = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1, 0.5),
    NumberSequenceKeypoint.new(1, 3, 0),
  })
  particleEmitter.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.new(1, 0, 0)),
    ColorSequenceKeypoint.new(1, Color3.new(0, 0, 1)),
  })
  particleEmitter.Lifetime = NumberRange.new(1, 5)
  particleEmitter.Parent = root

  root.Parent = RS
end)

afterAll(function()
  root:Destroy()
end)

describe("input validation", function()
  it("should error for non-Instance first argument", function()
    expect(function()
      EncodeInstance("not an instance" :: any, 0, NIL)
    end).toThrow("InvalidInstance")
  end)

  it("should error for nil first argument", function()
    expect(function()
      EncodeInstance(nil :: any, 0, NIL)
    end).toThrow("InvalidInstance")
  end)

  it("should error for NaN depth", function()
    expect(function()
      EncodeInstance(emptyFolder, 0 / 0, NIL)
    end).toThrow("InvalidDepth")
  end)

  it("should error for non-integer depth (1.5)", function()
    expect(function()
      EncodeInstance(emptyFolder, 1.5, NIL)
    end).toThrow("InvalidDepth")
  end)

  it("should error for non-integer depth (-0.7)", function()
    expect(function()
      EncodeInstance(emptyFolder, -0.7, NIL)
    end).toThrow("InvalidDepth")
  end)

  it("should allow math.huge depth", function()
    expect(function()
      EncodeInstance(emptyFolder, math.huge, NIL)
    end).never.toThrow()
  end)

  it("should allow -math.huge depth", function()
    expect(function()
      EncodeInstance(emptyFolder, -math.huge, NIL)
    end).never.toThrow()
  end)

  it("should error for nil nilReference", function()
    expect(function()
      EncodeInstance(emptyFolder, 0, nil)
    end).toThrow("InvalidNilReference")
  end)

  it("should error for non-Instance relativeTo", function()
    expect(function()
      EncodeInstance(emptyFolder, 0, NIL, "not an instance" :: any)
    end).toThrow()
  end)

  it("should allow nil relativeTo", function()
    expect(function()
      EncodeInstance(emptyFolder, 0, NIL, nil)
    end).never.toThrow()
  end)
end)

describe("shallow encoding (depth < 0)", function()
  it("should return shallow result at depth=-1", function()
    local result = EncodeInstance(emptyFolder, -1, NIL)
    local expected = {
      Name = esc(emptyFolder.Name),
      ClassName = "Folder",
      DebugId = id(emptyFolder),
      Shallow = true,
    }
    expect(DeepEquals(result, expected)).toEqual(true)
  end)

  it("should return shallow result at depth=-100", function()
    local result = EncodeInstance(emptyFolder, -100, NIL)
    expect(result.Shallow).toEqual(true)
    expect(result.Properties).toEqual(nil)
    expect(result.Attributes).toEqual(nil)
    expect(result.Tags).toEqual(nil)
    expect(result.Children).toEqual(nil)
  end)

  it("should return shallow result at depth=-math.huge", function()
    local result = EncodeInstance(emptyFolder, -math.huge, NIL)
    expect(result.Shallow).toEqual(true)
    expect(result.Properties).toEqual(nil)
  end)

  it("should still include Name, ClassName, DebugId when shallow", function()
    local result = EncodeInstance(part, -1, NIL)
    expect(result.Name).toEqual(esc(part.Name))
    expect(result.ClassName).toEqual("Part")
    expect(result.DebugId).toEqual(id(part))
    expect(result.Shallow).toEqual(true)
  end)

  it("should not include properties on a Part when shallow", function()
    local result = EncodeInstance(part, -1, NIL)
    expect(result.Properties).toEqual(nil)
  end)

  it("should not include children when shallow even if instance has children", function()
    local result = EncodeInstance(parentFolder, -1, NIL)
    expect(result.Children).toEqual(nil)
  end)
end)

describe("structural encoding (Folder, depth=0)", function()
  it("should encode empty folder with correct structure", function()
    local result = EncodeInstance(emptyFolder, 0, NIL)
    local expected = {
      Name = esc(emptyFolder.Name),
      ClassName = "Folder",
      DebugId = id(emptyFolder),
    }
    expect(DeepEquals(result, expected)).toEqual(true)
  end)

  it("should not have Shallow field at depth=0", function()
    local result = EncodeInstance(emptyFolder, 0, NIL)
    expect(result.Shallow).toEqual(nil)
  end)

  it("should not have Properties field for Folder", function()
    local result = EncodeInstance(emptyFolder, 0, NIL)
    expect(result.Properties).toEqual(nil)
  end)

  it("should not have Attributes field when none set", function()
    local result = EncodeInstance(emptyFolder, 0, NIL)
    expect(result.Attributes).toEqual(nil)
  end)

  it("should not have Tags field when none set", function()
    local result = EncodeInstance(emptyFolder, 0, NIL)
    expect(result.Tags).toEqual(nil)
  end)

  it("should not have Children field when no children", function()
    local result = EncodeInstance(emptyFolder, 0, NIL)
    expect(result.Children).toEqual(nil)
  end)
end)

describe("depth recursion", function()
  it("depth=0, no children: full encoding, no Children", function()
    local result = EncodeInstance(emptyFolder, 0, NIL)
    expect(result.Children).toEqual(nil)
    expect(result.Shallow).toEqual(nil)
  end)

  it("depth=0, with children: children are shallow", function()
    local result = EncodeInstance(parentFolder, 0, NIL)
    expect(result.Shallow).toEqual(nil)
    expect(result.Children).toBeTruthy()
    assert(result.Children)
    expect(#result.Children).toEqual(2)
    for _, child in result.Children do
      expect(child.Shallow).toEqual(true)
      expect(child.Properties).toEqual(nil)
      expect(child.Children).toEqual(nil)
    end
  end)

  it("depth=1, children fully encoded, grandchildren shallow", function()
    local result = EncodeInstance(parentFolder, 1, NIL)
    expect(result.Shallow).toEqual(nil)
    expect(result.Children).toBeTruthy()
    assert(result.Children)

    local childAResult
    for _, child in result.Children do
      if child.Name == "ChildA" then
        childAResult = child
      end
    end
    expect(childAResult).toBeTruthy()
    assert(childAResult)
    expect(childAResult.Shallow).toEqual(nil)
    expect(childAResult.Children).toBeTruthy()
    assert(childAResult.Children)
    expect(#childAResult.Children).toEqual(1)
    expect(childAResult.Children[1].Name).toEqual("Grandchild")
    expect(childAResult.Children[1].Shallow).toEqual(true)
  end)

  it("depth=2, three levels encoded, great-grandchild shallow", function()
    local result = EncodeInstance(parentFolder, 2, NIL)
    assert(result.Children)

    local childAResult
    for _, child in result.Children do
      if child.Name == "ChildA" then
        childAResult = child
      end
    end
    expect(childAResult).toBeTruthy()
    assert(childAResult)
    expect(childAResult.Shallow).toEqual(nil)
    assert(childAResult.Children)
    local gcResult = childAResult.Children[1]
    expect(gcResult.Name).toEqual("Grandchild")
    expect(gcResult.Shallow).toEqual(nil)
    expect(gcResult.Children).toBeTruthy()
    assert(gcResult.Children)
    expect(#gcResult.Children).toEqual(1)
    expect(gcResult.Children[1].Name).toEqual("GreatGrand")
    expect(gcResult.Children[1].Shallow).toEqual(true)
  end)

  it("depth=0, children have their own children: inner children NOT encoded", function()
    local result = EncodeInstance(parentFolder, 0, NIL)
    assert(result.Children)
    local childAResult
    for _, child in result.Children do
      if child.Name == "ChildA" then
        childAResult = child
      end
    end
    expect(childAResult).toBeTruthy()
    assert(childAResult)
    expect(childAResult.Shallow).toEqual(true)
    expect(childAResult.Children).toEqual(nil)
  end)

  it("depth=math.huge encodes entire subtree fully, no shallow anywhere", function()
    local result = EncodeInstance(parentFolder, math.huge, NIL)

    local function assertNoShallow(encoded, path: string)
      if encoded.Shallow then
        error(`Found Shallow=true at {path}`)
      end
      if encoded.Children then
        for _, child in encoded.Children do
          assertNoShallow(child, path .. "/" .. child.Name)
        end
      end
    end
    assertNoShallow(result, result.Name)

    assert(result.Children)
    local childAResult
    for _, child in result.Children do
      if child.Name == "ChildA" then
        childAResult = child
      end
    end
    expect(childAResult).toBeTruthy()
    assert(childAResult)
    expect(childAResult.Children).toBeTruthy()
    assert(childAResult.Children)
    local gcResult = childAResult.Children[1]
    expect(gcResult.Name).toEqual("Grandchild")
    expect(gcResult.Children).toBeTruthy()
    assert(gcResult.Children)
    expect(gcResult.Children[1].Name).toEqual("GreatGrand")
    expect(gcResult.Children[1].Shallow).toEqual(nil)
    expect(gcResult.Children[1].Children).toEqual(nil)
  end)

  it("childB has no children at any depth", function()
    local result = EncodeInstance(parentFolder, math.huge, NIL)
    assert(result.Children)
    local childBResult
    for _, child in result.Children do
      if child.Name == "ChildB" then
        childBResult = child
      end
    end
    expect(childBResult).toBeTruthy()
    assert(childBResult)
    expect(childBResult.Children).toEqual(nil)
    expect(childBResult.Shallow).toEqual(nil)
  end)
end)

describe("property type encoding", function()
  describe("number", function()
    it("should encode Part.Transparency", function()
      local result = EncodeInstance(part, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      expect(result.Properties.Transparency).toEqual(0.5)
    end)

    it("should encode Part.Reflectance", function()
      local result = EncodeInstance(part, 0, NIL)
      assert(result.Properties)
      expect(result.Properties.Reflectance).toEqual(0.25)
    end)

    it("should encode PointLight.Brightness", function()
      local result = EncodeInstance(pointLight, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      expect(result.Properties.Brightness).toEqual(2)
    end)

    it("should encode PointLight.Range", function()
      local result = EncodeInstance(pointLight, 0, NIL)
      assert(result.Properties)
      expect(result.Properties.Range).toEqual(16)
    end)
  end)

  describe("boolean", function()
    it("should encode Part.Anchored as true", function()
      local result = EncodeInstance(part, 0, NIL)
      assert(result.Properties)
      expect(result.Properties.Anchored).toEqual(true)
    end)

    it("should encode Part.CanCollide as false", function()
      local result = EncodeInstance(part, 0, NIL)
      assert(result.Properties)
      expect(result.Properties.CanCollide).toEqual(false)
    end)
  end)

  describe("EnumItem", function()
    it("should encode Part.Material as table with Type and Name", function()
      local result = EncodeInstance(part, 0, NIL)
      assert(result.Properties)
      local mat = result.Properties.Material
      expect(mat).toBeTruthy()
      assert(mat)
      expect(mat.Type).toEqual("Material")
      expect(mat.Name).toEqual("Wood")
    end)

    it("should encode Part.Shape", function()
      local result = EncodeInstance(part, 0, NIL)
      assert(result.Properties)
      local shape = result.Properties.Shape
      expect(shape).toBeTruthy()
      assert(shape)
      expect(shape.Type).toEqual("PartType")
      expect(shape.Name).toEqual("Block")
    end)

    it("should encode SpecialMesh.MeshType", function()
      local result = EncodeInstance(specialMesh, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      local mt = result.Properties.MeshType
      expect(mt).toBeTruthy()
      assert(mt)
      expect(mt.Type).toEqual("MeshType")
      expect(mt.Name).toEqual("FileMesh")
    end)
  end)

  describe("Vector3", function()
    it("should encode Part.Size as array {x,y,z}", function()
      local result = EncodeInstance(part, 0, NIL)
      assert(result.Properties)
      local size = result.Properties.Size
      expect(size).toBeTruthy()
      expect(DeepEquals(size, { 4, 2, 8 })).toEqual(true)
    end)
  end)

  describe("Color3", function()
    it("should encode Part.Color as array {r,g,b}", function()
      local result = EncodeInstance(part, 0, NIL)
      assert(result.Properties)
      local color = result.Properties.Color
      expect(color).toBeTruthy()
      expect(DeepEquals(color, { 1, 0, 0 })).toEqual(true)
    end)

    it("should encode PointLight.Color", function()
      local result = EncodeInstance(pointLight, 0, NIL)
      assert(result.Properties)
      local color = result.Properties.Color
      expect(color).toBeTruthy()
      expect(DeepEquals(color, { 1, 1, 0 })).toEqual(true)
    end)
  end)

  describe("CFrame", function()
    it("should encode Part.CFrame as 12-component array", function()
      local result = EncodeInstance(part, 0, NIL)
      assert(result.Properties)
      local cf = result.Properties.CFrame
      expect(cf).toBeTruthy()
      assert(cf)
      expect(#cf).toEqual(12)
      expect(cf[1]).toEqual(1)
      expect(cf[2]).toEqual(2)
      expect(cf[3]).toEqual(3)
      expect(cf[4]).toEqual(1)
      expect(cf[5]).toEqual(0)
      expect(cf[6]).toEqual(0)
      expect(cf[7]).toEqual(0)
      expect(cf[8]).toEqual(1)
      expect(cf[9]).toEqual(0)
      expect(cf[10]).toEqual(0)
      expect(cf[11]).toEqual(0)
      expect(cf[12]).toEqual(1)
    end)

    it("should encode Weld.C0", function()
      local result = EncodeInstance(weld, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      local c0 = result.Properties.C0
      expect(c0).toBeTruthy()
      assert(c0)
      expect(#c0).toEqual(12)
      expect(c0[1]).toEqual(1)
      expect(c0[2]).toEqual(0)
      expect(c0[3]).toEqual(0)
    end)

    it("should encode Weld.C1", function()
      local result = EncodeInstance(weld, 0, NIL)
      assert(result.Properties)
      local c1 = result.Properties.C1
      expect(c1).toBeTruthy()
      assert(c1)
      expect(c1[1]).toEqual(0)
      expect(c1[2]).toEqual(1)
      expect(c1[3]).toEqual(0)
    end)
  end)

  describe("Content", function()
    it("should encode Sound.SoundId as URI string", function()
      local result = EncodeInstance(sound, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      expect(result.Properties.SoundId).toEqual("rbxassetid://123456")
    end)

    it("should encode SpecialMesh.MeshId as URI string", function()
      local result = EncodeInstance(specialMesh, 0, NIL)
      assert(result.Properties)
      expect(result.Properties.MeshId).toEqual("rbxassetid://654321")
    end)

    it("should encode empty Content as empty string", function()
      local emptySound = Instance.new("Sound")
      emptySound.Name = "EmptySound"
      emptySound.Parent = root
      local result = EncodeInstance(emptySound, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      expect(result.Properties.SoundId).toEqual("")
      emptySound:Destroy()
    end)
  end)

  describe("UDim", function()
    it("should encode UICorner.CornerRadius as {Scale, Offset}", function()
      local result = EncodeInstance(uiCorner, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      local cr = result.Properties.CornerRadius
      expect(cr).toBeTruthy()
      expect(DeepEquals(cr, { 0.5, 10 })).toEqual(true)
    end)
  end)

  describe("UDim2", function()
    it("should encode Frame.Size as {XScale,XOffset,YScale,YOffset}", function()
      local result = EncodeInstance(frame, 0, NIL, screenGui)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      local size = result.Properties.Size
      expect(size).toBeTruthy()
      expect(DeepEquals(size, { 0.5, 10, 0.25, 20 })).toEqual(true)
    end)
  end)

  describe("Font", function()
    it("should encode TextLabel.FontFace as table with family, weight, style", function()
      local result = EncodeInstance(textLabel, 0, NIL, screenGui)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      local fontFace = result.Properties.FontFace
      expect(fontFace).toBeTruthy()
      assert(fontFace)
      expect(fontFace.weight).toEqual("Bold")
      expect(fontFace.style).toEqual("Italic")
      expect(type(fontFace.family)).toEqual("string")
    end)
  end)

  describe("Instance ref", function()
    it("should encode ObjectValue.Value as relative path", function()
      local result = EncodeInstance(objVal, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      local val = result.Properties.Value
      expect(type(val)).toEqual("string")
      expect(val).toEqual(Paths.GetRelativePath(refTarget, game))
    end)

    it("should encode nil ObjectValue.Value as nilReference", function()
      local nilObjVal = Instance.new("ObjectValue")
      nilObjVal.Name = "NilObjVal"
      nilObjVal.Parent = root
      local result = EncodeInstance(nilObjVal, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      expect(result.Properties.Value).toEqual(NIL)
      nilObjVal:Destroy()
    end)

    it("should encode Weld.Part0 as relative path", function()
      local result = EncodeInstance(weld, 0, NIL)
      assert(result.Properties)
      expect(result.Properties.Part0).toEqual(Paths.GetRelativePath(weldPartA, game))
    end)

    it("should encode Weld.Part1 as relative path", function()
      local result = EncodeInstance(weld, 0, NIL)
      assert(result.Properties)
      expect(result.Properties.Part1).toEqual(Paths.GetRelativePath(weldPartB, game))
    end)
  end)

  describe("PhysicalProperties", function()
    it("should encode CustomPhysicalProperties as 5-element array", function()
      local result = EncodeInstance(physPart, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      local pp = result.Properties.CustomPhysicalProperties
      if pp ~= nil and pp ~= NIL then
        expect(DeepEquals(pp, { 2, 0.5, 0.25, 1, 1 })).toEqual(true)
      end
    end)
  end)

  describe("NumberSequence", function()
    it("should encode ParticleEmitter.Size as keypoint arrays", function()
      local result = EncodeInstance(particleEmitter, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      local size = result.Properties.Size
      if size then
        expect(#size).toEqual(2)
        expect(DeepEquals(size[1], { 0, 1, 0.5 })).toEqual(true)
        expect(DeepEquals(size[2], { 1, 3, 0 })).toEqual(true)
      end
    end)
  end)

  describe("ColorSequence", function()
    it("should encode ParticleEmitter.Color as keypoint arrays {time,r,g,b}", function()
      local result = EncodeInstance(particleEmitter, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      local color = result.Properties.Color
      if color then
        expect(#color).toEqual(2)
        expect(DeepEquals(color[1], { 0, 1, 0, 0 })).toEqual(true)
        expect(DeepEquals(color[2], { 1, 0, 0, 1 })).toEqual(true)
      end
    end)
  end)

  describe("NumberRange", function()
    it("should encode ParticleEmitter.Lifetime as {min, max}", function()
      local result = EncodeInstance(particleEmitter, 0, NIL)
      expect(result.Properties).toBeTruthy()
      assert(result.Properties)
      local lifetime = result.Properties.Lifetime
      if lifetime then
        expect(DeepEquals(lifetime, { 1, 5 })).toEqual(true)
      end
    end)
  end)
end)

describe("attribute encoding", function()
  it("should encode string attribute as pass-through", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    expect(result.Attributes).toBeTruthy()
    assert(result.Attributes)
    expect(result.Attributes.str).toEqual("hello")
  end)

  it("should encode number attribute as pass-through", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    expect(result.Attributes.num).toEqual(42)
  end)

  it("should encode boolean attribute as pass-through", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    expect(result.Attributes.bool).toEqual(true)
  end)

  it("should encode UDim attribute as wrapped table", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    local attr = result.Attributes.udim
    expect(attr).toBeTruthy()
    assert(attr)
    expect(DeepEquals(attr, { UDim = { 0.5, 10 } })).toEqual(true)
  end)

  it("should encode UDim2 attribute as wrapped table", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    local attr = result.Attributes.udim2
    expect(attr).toBeTruthy()
    assert(attr)
    expect(DeepEquals(attr, { UDim2 = { 0.5, 10, 0.25, 20 } })).toEqual(true)
  end)

  it("should encode Vector2 attribute as wrapped table", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    local attr = result.Attributes.vec2
    expect(attr).toBeTruthy()
    assert(attr)
    expect(DeepEquals(attr, { Vector2 = { 1.5, 2.5 } })).toEqual(true)
  end)

  it("should encode Vector3 attribute as wrapped table", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    local attr = result.Attributes.vec3
    expect(attr).toBeTruthy()
    assert(attr)
    expect(DeepEquals(attr, { Vector3 = { 1, 2, 3 } })).toEqual(true)
  end)

  it("should encode Color3 attribute as wrapped table", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    local attr = result.Attributes.color3
    expect(attr).toBeTruthy()
    assert(attr)
    expect(DeepEquals(attr, { Color3 = { 1, 0, 0.5 } })).toEqual(true)
  end)

  it("should encode BrickColor attribute as wrapped table", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    local attr = result.Attributes.brick
    expect(attr).toBeTruthy()
    assert(attr)
    expect(DeepEquals(attr, { BrickColor = "Bright red" })).toEqual(true)
  end)

  it("should encode CFrame attribute as wrapped table with 12 components", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    local attr = result.Attributes.cframe
    expect(attr).toBeTruthy()
    assert(attr)
    expect(attr.CFrame).toBeTruthy()
    assert(attr.CFrame)
    expect(#attr.CFrame).toEqual(12)
    expect(attr.CFrame[1]).toEqual(10)
    expect(attr.CFrame[2]).toEqual(20)
    expect(attr.CFrame[3]).toEqual(30)
  end)

  it("should encode NumberRange attribute as wrapped table", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    local attr = result.Attributes.numrange
    expect(attr).toBeTruthy()
    assert(attr)
    expect(DeepEquals(attr, { NumberRange = { 0, 10 } })).toEqual(true)
  end)

  it("should encode NumberSequence attribute as wrapped table", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    local attr = result.Attributes.numseq
    expect(attr).toBeTruthy()
    assert(attr)
    expect(attr.NumberSequence).toBeTruthy()
    assert(attr.NumberSequence)
    expect(#attr.NumberSequence).toEqual(2)
    expect(DeepEquals(attr.NumberSequence[1], { 0, 0, 0 })).toEqual(true)
    expect(DeepEquals(attr.NumberSequence[2], { 1, 1, 0 })).toEqual(true)
  end)

  it("should encode ColorSequence attribute as wrapped table", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    local attr = result.Attributes.colseq
    expect(attr).toBeTruthy()
    assert(attr)
    expect(attr.ColorSequence).toBeTruthy()
    assert(attr.ColorSequence)
    expect(#attr.ColorSequence).toEqual(2)
    expect(DeepEquals(attr.ColorSequence[1], { 0, 1, 0, 0 })).toEqual(true)
    expect(DeepEquals(attr.ColorSequence[2], { 1, 0, 1, 0 })).toEqual(true)
  end)

  it("should encode Rect attribute as wrapped table", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    local attr = result.Attributes.rect
    expect(attr).toBeTruthy()
    assert(attr)
    expect(DeepEquals(attr, { Rect = { 0, 0, 100, 200 } })).toEqual(true)
  end)

  it("should encode Font attribute as wrapped table", function()
    local result = EncodeInstance(attrFolder, 0, NIL)
    assert(result.Attributes)
    local attr = result.Attributes.font
    expect(attr).toBeTruthy()
    assert(attr)
    expect(attr.Font).toBeTruthy()
    assert(attr.Font)
    expect(attr.Font.weight).toEqual("Bold")
    expect(attr.Font.style).toEqual("Italic")
    expect(type(attr.Font.family)).toEqual("string")
  end)

  it("should not have Attributes field when no attributes set", function()
    local result = EncodeInstance(emptyFolder, 0, NIL)
    expect(result.Attributes).toEqual(nil)
  end)
end)

describe("tags encoding", function()
  it("should not have Tags field when no tags", function()
    local result = EncodeInstance(emptyFolder, 0, NIL)
    expect(result.Tags).toEqual(nil)
  end)

  it("should encode single tag", function()
    local result = EncodeInstance(tagFolder, 0, NIL)
    expect(result.Tags).toBeTruthy()
    assert(result.Tags)
    expect(#result.Tags).toEqual(1)
    expect(result.Tags[1]).toEqual("Solo")
  end)

  it("should encode multiple tags", function()
    local result = EncodeInstance(multiTagFolder, 0, NIL)
    expect(result.Tags).toBeTruthy()
    assert(result.Tags)
    expect(#result.Tags).toEqual(3)
    local sorted = table.clone(result.Tags)
    table.sort(sorted)
    expect(sorted[1]).toEqual("Alpha")
    expect(sorted[2]).toEqual("Beta")
    expect(sorted[3]).toEqual("Gamma")
  end)
end)

describe("name escaping", function()
  it("should pass through normal name unchanged", function()
    local result = EncodeInstance(namedFolder, 0, NIL)
    expect(result.Name).toEqual("TestFolder")
  end)

  it("should escape dot in name", function()
    local result = EncodeInstance(dotFolder, 0, NIL)
    expect(result.Name).toEqual("Has%2EDot")
  end)

  it("should escape all special characters in name", function()
    local result = EncodeInstance(allSpecialFolder, 0, NIL)
    expect(result.Name).toEqual("%25%7E%2F%2E%40")
  end)

  it("should use ClassName unescaped", function()
    local result = EncodeInstance(dotFolder, 0, NIL)
    expect(result.ClassName).toEqual("Folder")
  end)
end)

describe("instance references and relativeTo", function()
  it("should encode refs relative to game by default", function()
    local result = EncodeInstance(objVal, 0, NIL)
    assert(result.Properties)
    expect(result.Properties.Value).toEqual(Paths.GetRelativePath(refTarget, game))
  end)

  it("should encode refs relative to explicit relativeTo", function()
    local result = EncodeInstance(objVal, 0, NIL, root)
    assert(result.Properties)
    expect(result.Properties.Value).toEqual(Paths.GetRelativePath(refTarget, root))
  end)

  it("children get relativeTo=parent for their own instance refs", function()
    local childObjVal = Instance.new("ObjectValue")
    childObjVal.Name = "ChildRef"
    childObjVal.Value = refTarget
    childObjVal.Parent = parentFolder

    local result = EncodeInstance(parentFolder, 1, NIL)
    assert(result.Children)
    local childResult
    for _, child in result.Children do
      if child.Name == "ChildRef" then
        childResult = child
      end
    end
    expect(childResult).toBeTruthy()
    assert(childResult)
    expect(childResult.Properties).toBeTruthy()
    assert(childResult.Properties)
    expect(childResult.Properties.Value).toEqual(Paths.GetRelativePath(refTarget, parentFolder))
    childObjVal:Destroy()
  end)

  it("should encode Weld refs relative to game by default", function()
    local result = EncodeInstance(weld, 0, NIL)
    assert(result.Properties)
    expect(result.Properties.Part0).toEqual(Paths.GetRelativePath(weldPartA, game))
    expect(result.Properties.Part1).toEqual(Paths.GetRelativePath(weldPartB, game))
  end)

  it("should encode Weld refs relative to explicit relativeTo", function()
    local result = EncodeInstance(weld, 0, NIL, root)
    assert(result.Properties)
    expect(result.Properties.Part0).toEqual(Paths.GetRelativePath(weldPartA, root))
    expect(result.Properties.Part1).toEqual(Paths.GetRelativePath(weldPartB, root))
  end)
end)

describe("nilReference behavior", function()
  it("should use string nilReference for nil properties", function()
    local nilObjVal = Instance.new("ObjectValue")
    nilObjVal.Name = "NilObj"
    nilObjVal.Parent = root
    local result = EncodeInstance(nilObjVal, 0, "__NIL__")
    assert(result.Properties)
    expect(result.Properties.Value).toEqual("__NIL__")
    nilObjVal:Destroy()
  end)

  it("should use numeric nilReference for nil properties", function()
    local nilObjVal = Instance.new("ObjectValue")
    nilObjVal.Name = "NilObj2"
    nilObjVal.Parent = root
    local result = EncodeInstance(nilObjVal, 0, 0)
    assert(result.Properties)
    expect(result.Properties.Value).toEqual(0)
    nilObjVal:Destroy()
  end)

  it("should use false as nilReference for nil properties", function()
    local nilObjVal = Instance.new("ObjectValue")
    nilObjVal.Name = "NilObj3"
    nilObjVal.Parent = root
    local result = EncodeInstance(nilObjVal, 0, false)
    assert(result.Properties)
    expect(result.Properties.Value).toEqual(false)
    nilObjVal:Destroy()
  end)

  it("should use table as nilReference for nil properties", function()
    local sentinel = { "__NIL_TABLE__" }
    local nilObjVal = Instance.new("ObjectValue")
    nilObjVal.Name = "NilObj4"
    nilObjVal.Parent = root
    local result = EncodeInstance(nilObjVal, 0, sentinel)
    assert(result.Properties)
    expect(result.Properties.Value).toEqual(sentinel)
    nilObjVal:Destroy()
  end)

  it("non-nil properties should not produce nilReference", function()
    local result = EncodeInstance(objVal, 0, NIL)
    assert(result.Properties)
    expect(result.Properties.Value).never.toEqual(NIL)
  end)
end)

describe("edge cases", function()
  it("should handle instance with empty string name", function()
    local emptyName = Instance.new("Folder")
    emptyName.Name = ""
    emptyName.Parent = root
    local result = EncodeInstance(emptyName, 0, NIL)
    expect(result.Name).toEqual("")
    expect(result.ClassName).toEqual("Folder")
    emptyName:Destroy()
  end)

  it("should encode deeply nested tree at depth=0 with only shallow children", function()
    local d1 = Instance.new("Folder")
    d1.Name = "D1"
    d1.Parent = root
    local d2 = Instance.new("Folder")
    d2.Name = "D2"
    d2.Parent = d1
    local d3 = Instance.new("Folder")
    d3.Name = "D3"
    d3.Parent = d2
    local d4 = Instance.new("Folder")
    d4.Name = "D4"
    d4.Parent = d3

    local result = EncodeInstance(d1, 0, NIL)
    expect(result.Children).toBeTruthy()
    assert(result.Children)
    expect(#result.Children).toEqual(1)
    expect(result.Children[1].Shallow).toEqual(true)
    expect(result.Children[1].Children).toEqual(nil)

    d1:Destroy()
  end)

  it("should encode deeply nested tree at depth=3 fully", function()
    local d1 = Instance.new("Folder")
    d1.Name = "D1"
    d1.Parent = root
    local d2 = Instance.new("Folder")
    d2.Name = "D2"
    d2.Parent = d1
    local d3 = Instance.new("Folder")
    d3.Name = "D3"
    d3.Parent = d2
    local d4 = Instance.new("Folder")
    d4.Name = "D4"
    d4.Parent = d3

    local result = EncodeInstance(d1, 3, NIL)
    expect(result.Shallow).toEqual(nil)
    assert(result.Children)
    local rc1 = result.Children[1]
    expect(rc1.Shallow).toEqual(nil)
    assert(rc1.Children)
    local rc2 = rc1.Children[1]
    expect(rc2.Shallow).toEqual(nil)
    assert(rc2.Children)
    expect(rc2.Children[1].Shallow).toEqual(nil)
    expect(rc2.Children[1].Children).toEqual(nil)

    d1:Destroy()
  end)

  it("should encode instance with attributes, tags, and children simultaneously", function()
    local combo = Instance.new("Folder")
    combo.Name = "Combo"
    combo.Parent = root
    combo:SetAttribute("key", "value")
    combo:AddTag("tagged")

    local comboChild = Instance.new("Folder")
    comboChild.Name = "ComboChild"
    comboChild.Parent = combo

    local result = EncodeInstance(combo, 1, NIL)
    expect(result.Name).toEqual("Combo")
    expect(result.ClassName).toEqual("Folder")
    expect(result.Attributes).toBeTruthy()
    assert(result.Attributes)
    expect(result.Attributes.key).toEqual("value")
    expect(result.Tags).toBeTruthy()
    assert(result.Tags)
    expect(#result.Tags).toEqual(1)
    expect(result.Tags[1]).toEqual("tagged")
    expect(result.Children).toBeTruthy()
    assert(result.Children)
    expect(#result.Children).toEqual(1)
    expect(result.Children[1].Name).toEqual("ComboChild")
    expect(result.Children[1].Shallow).toEqual(nil)

    combo:Destroy()
  end)

  it("should produce consistent DebugId across multiple encodings", function()
    local r1 = EncodeInstance(emptyFolder, 0, NIL)
    local r2 = EncodeInstance(emptyFolder, 0, NIL)
    expect(r1.DebugId).toEqual(r2.DebugId)
  end)

  it("should encode with different nilReference values and get same structure", function()
    local nilObjVal = Instance.new("ObjectValue")
    nilObjVal.Name = "TestNilRef"
    nilObjVal.Parent = root

    local r1 = EncodeInstance(nilObjVal, 0, "__A__")
    local r2 = EncodeInstance(nilObjVal, 0, "__B__")
    assert(r1.Properties)
    assert(r2.Properties)
    expect(r1.Properties.Value).toEqual("__A__")
    expect(r2.Properties.Value).toEqual("__B__")
    expect(r1.Name).toEqual(r2.Name)
    expect(r1.ClassName).toEqual(r2.ClassName)
    expect(r1.DebugId).toEqual(r2.DebugId)

    nilObjVal:Destroy()
  end)

  it("should encode children in GetChildren order", function()
    local orderParent = Instance.new("Folder")
    orderParent.Name = "OrderParent"
    orderParent.Parent = root

    local first = Instance.new("Folder")
    first.Name = "First"
    first.Parent = orderParent
    local second = Instance.new("Folder")
    second.Name = "Second"
    second.Parent = orderParent
    local third = Instance.new("Folder")
    third.Name = "Third"
    third.Parent = orderParent

    local result = EncodeInstance(orderParent, 0, NIL)
    expect(result.Children).toBeTruthy()
    assert(result.Children)
    expect(#result.Children).toEqual(3)
    expect(result.Children[1].Name).toEqual("First")
    expect(result.Children[2].Name).toEqual("Second")
    expect(result.Children[3].Name).toEqual("Third")

    orderParent:Destroy()
  end)
end)
