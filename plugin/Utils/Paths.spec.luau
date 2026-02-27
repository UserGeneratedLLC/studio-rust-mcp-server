--!nocheck

return function()
  local Paths = require(script.Parent.Paths)
  local RS = game:GetService("ReplicatedStorage")

  local root
  local alpha, beta, gamma, delta
  local epsilon, zeta
  local dotName, atName, slashName, tildeName, pctName, allSpecial
  local ambigParent, twin1, twin2, twin1Leaf, twin1Leaf2, twin2Leaf
  local deep1, deep2, deep3, deep4
  local orphan, orphanChild
  local basePath

  local function id(inst)
    return Paths.GetDebugId(inst)
  end
  local function esc(name)
    return Paths.EscapeName(name)
  end

  beforeAll(function()
    root = Instance.new("Folder")
    root.Name = "__PathsTest__"

    alpha = Instance.new("Folder")
    alpha.Name = "Alpha"
    alpha.Parent = root
    beta = Instance.new("Folder")
    beta.Name = "Beta"
    beta.Parent = alpha
    gamma = Instance.new("Folder")
    gamma.Name = "Gamma"
    gamma.Parent = beta
    delta = Instance.new("Folder")
    delta.Name = "Delta"
    delta.Parent = alpha

    epsilon = Instance.new("Folder")
    epsilon.Name = "Epsilon"
    epsilon.Parent = root
    zeta = Instance.new("Folder")
    zeta.Name = "Zeta"
    zeta.Parent = epsilon

    dotName = Instance.new("Folder")
    dotName.Name = "Has.Dot"
    dotName.Parent = root
    atName = Instance.new("Folder")
    atName.Name = "Has@At"
    atName.Parent = root
    slashName = Instance.new("Folder")
    slashName.Name = "Has/Slash"
    slashName.Parent = root
    tildeName = Instance.new("Folder")
    tildeName.Name = "Has~Tilde"
    tildeName.Parent = root
    pctName = Instance.new("Folder")
    pctName.Name = "Has%Pct"
    pctName.Parent = root
    allSpecial = Instance.new("Folder")
    allSpecial.Name = "%~/.@"
    allSpecial.Parent = root

    ambigParent = Instance.new("Folder")
    ambigParent.Name = "AmbigParent"
    ambigParent.Parent = root
    twin1 = Instance.new("Folder")
    twin1.Name = "Twin"
    twin1.Parent = ambigParent
    twin2 = Instance.new("Folder")
    twin2.Name = "Twin"
    twin2.Parent = ambigParent
    twin1Leaf = Instance.new("Folder")
    twin1Leaf.Name = "Leaf"
    twin1Leaf.Parent = twin1
    twin1Leaf2 = Instance.new("Folder")
    twin1Leaf2.Name = "Leaf"
    twin1Leaf2.Parent = twin1
    twin2Leaf = Instance.new("Folder")
    twin2Leaf.Name = "Leaf"
    twin2Leaf.Parent = twin2

    deep1 = Instance.new("Folder")
    deep1.Name = "Deep1"
    deep1.Parent = root
    deep2 = Instance.new("Folder")
    deep2.Name = "Deep2"
    deep2.Parent = deep1
    deep3 = Instance.new("Folder")
    deep3.Name = "Deep3"
    deep3.Parent = deep2
    deep4 = Instance.new("Folder")
    deep4.Name = "Deep4"
    deep4.Parent = deep3

    orphan = Instance.new("Folder")
    orphan.Name = "OrphanRoot"
    orphanChild = Instance.new("Folder")
    orphanChild.Name = "OrphanChild"
    orphanChild.Parent = orphan

    root.Parent = RS
    basePath = "@game/" .. esc(RS.Name) .. "/" .. esc(root.Name)
  end)

  afterAll(function()
    root:Destroy()
    orphan:Destroy()
  end)

  describe("EscapeName", function()
    it("should pass through normal names unchanged", function()
      expect(Paths.EscapeName("Hello")).to.equal("Hello")
      expect(Paths.EscapeName("MyFolder123")).to.equal("MyFolder123")
    end)

    it("should escape percent", function()
      expect(Paths.EscapeName("a%b")).to.equal("a%25b")
    end)

    it("should escape tilde", function()
      expect(Paths.EscapeName("a~b")).to.equal("a%7Eb")
    end)

    it("should escape forward slash", function()
      expect(Paths.EscapeName("a/b")).to.equal("a%2Fb")
    end)

    it("should escape dot", function()
      expect(Paths.EscapeName("a.b")).to.equal("a%2Eb")
    end)

    it("should escape at sign", function()
      expect(Paths.EscapeName("a@b")).to.equal("a%40b")
    end)

    it("should escape all special characters at once", function()
      expect(Paths.EscapeName("%~/.@")).to.equal("%25%7E%2F%2E%40")
    end)

    it("should handle empty string", function()
      expect(Paths.EscapeName("")).to.equal("")
    end)

    it("should escape a single dot", function()
      expect(Paths.EscapeName(".")).to.equal("%2E")
    end)

    it("should escape double dot", function()
      expect(Paths.EscapeName("..")).to.equal("%2E%2E")
    end)

    it("should escape name that looks like @game", function()
      expect(Paths.EscapeName("@game")).to.equal("%40game")
    end)

    it("should escape name that looks like @self", function()
      expect(Paths.EscapeName("@self")).to.equal("%40self")
    end)

    it("should escape multiple percent signs", function()
      expect(Paths.EscapeName("%%")).to.equal("%25%25")
    end)

    it("should escape percent before other chars to avoid double-encoding", function()
      expect(Paths.EscapeName("%2E")).to.equal("%252E")
    end)
  end)

  describe("UnescapeName", function()
    it("should pass through normal names unchanged", function()
      expect(Paths.UnescapeName("Hello")).to.equal("Hello")
    end)

    it("should unescape percent", function()
      expect(Paths.UnescapeName("a%25b")).to.equal("a%b")
    end)

    it("should unescape tilde", function()
      expect(Paths.UnescapeName("a%7Eb")).to.equal("a~b")
    end)

    it("should unescape forward slash", function()
      expect(Paths.UnescapeName("a%2Fb")).to.equal("a/b")
    end)

    it("should unescape dot", function()
      expect(Paths.UnescapeName("a%2Eb")).to.equal("a.b")
    end)

    it("should unescape at sign", function()
      expect(Paths.UnescapeName("a%40b")).to.equal("a@b")
    end)

    it("should unescape all special characters at once", function()
      expect(Paths.UnescapeName("%25%7E%2F%2E%40")).to.equal("%~/.@")
    end)

    it("should handle empty string", function()
      expect(Paths.UnescapeName("")).to.equal("")
    end)

    it("should be case insensitive for hex digits", function()
      expect(Paths.UnescapeName("%2f")).to.equal("/")
      expect(Paths.UnescapeName("%2F")).to.equal("/")
      expect(Paths.UnescapeName("%7e")).to.equal("~")
      expect(Paths.UnescapeName("%7E")).to.equal("~")
      expect(Paths.UnescapeName("%2e")).to.equal(".")
      expect(Paths.UnescapeName("%2E")).to.equal(".")
    end)

    it("should unescape %25 last to avoid double-decode", function()
      expect(Paths.UnescapeName("%252E")).to.equal("%2E")
    end)
  end)

  describe("EscapeName / UnescapeName round-trip", function()
    it("should round-trip all special characters", function()
      local original = "%~/.@"
      expect(Paths.UnescapeName(Paths.EscapeName(original))).to.equal(original)
    end)

    it("should round-trip normal text", function()
      local original = "NormalName123"
      expect(Paths.UnescapeName(Paths.EscapeName(original))).to.equal(original)
    end)

    it("should round-trip empty string", function()
      expect(Paths.UnescapeName(Paths.EscapeName(""))).to.equal("")
    end)

    it("should round-trip already-escaped-looking text", function()
      local original = "%25already"
      expect(Paths.UnescapeName(Paths.EscapeName(original))).to.equal(original)
    end)

    it("should round-trip complex mixed content", function()
      local original = "hello.world@test/path~id%done"
      expect(Paths.UnescapeName(Paths.EscapeName(original))).to.equal(original)
    end)

    it("should round-trip single special chars", function()
      for _, ch in { "%", "~", "/", ".", "@" } do
        expect(Paths.UnescapeName(Paths.EscapeName(ch))).to.equal(ch)
      end
    end)

    it("should round-trip path-prefix lookalikes", function()
      for _, name in { ".", "..", "@game", "@self", "@game/foo", "./bar" } do
        expect(Paths.UnescapeName(Paths.EscapeName(name))).to.equal(name)
      end
    end)
  end)

  describe("GetRelativePath", function()
    describe("with default relativeTo (game)", function()
      it("should return @game for game itself", function()
        expect(Paths.GetRelativePath(game)).to.equal("@game")
      end)

      it("should return @game for game with explicit nil", function()
        expect(Paths.GetRelativePath(game, nil)).to.equal("@game")
      end)

      it("should return @game/ServiceName for a service", function()
        expect(Paths.GetRelativePath(RS)).to.equal("@game/" .. esc(RS.Name))
      end)

      it("should return full path for direct child of test root", function()
        expect(Paths.GetRelativePath(alpha)).to.equal(basePath .. "/Alpha")
      end)

      it("should return full path for nested child", function()
        expect(Paths.GetRelativePath(beta)).to.equal(basePath .. "/Alpha/Beta")
      end)

      it("should return full path for deep descendant", function()
        expect(Paths.GetRelativePath(gamma)).to.equal(basePath .. "/Alpha/Beta/Gamma")
      end)

      it("should return full path for 4-level deep instance", function()
        expect(Paths.GetRelativePath(deep4)).to.equal(basePath .. "/Deep1/Deep2/Deep3/Deep4")
      end)

      it("should escape dot in instance name", function()
        expect(Paths.GetRelativePath(dotName)).to.equal(basePath .. "/" .. esc("Has.Dot"))
      end)

      it("should escape at sign in instance name", function()
        expect(Paths.GetRelativePath(atName)).to.equal(basePath .. "/" .. esc("Has@At"))
      end)

      it("should escape slash in instance name", function()
        expect(Paths.GetRelativePath(slashName)).to.equal(basePath .. "/" .. esc("Has/Slash"))
      end)

      it("should escape tilde in instance name", function()
        expect(Paths.GetRelativePath(tildeName)).to.equal(basePath .. "/" .. esc("Has~Tilde"))
      end)

      it("should escape percent in instance name", function()
        expect(Paths.GetRelativePath(pctName)).to.equal(basePath .. "/" .. esc("Has%Pct"))
      end)

      it("should escape all special characters in name", function()
        expect(Paths.GetRelativePath(allSpecial)).to.equal(basePath .. "/" .. esc("%~/.@"))
      end)

      it("should produce bare path with debugId for orphaned instance", function()
        local path = Paths.GetRelativePath(orphan)
        expect(path).to.equal(esc("OrphanRoot") .. "~" .. id(orphan))
      end)

      it("should produce bare multi-segment path for deep orphan", function()
        local path = Paths.GetRelativePath(orphanChild)
        expect(path).to.equal(
          esc("OrphanRoot") .. "/" .. esc("OrphanChild") .. "~" .. id(orphanChild)
        )
      end)
    end)

    describe("with @self (relativeTo is ancestor)", function()
      it("should return @self when inst equals relativeTo", function()
        expect(Paths.GetRelativePath(alpha, alpha)).to.equal("@self")
      end)

      it("should return @self/Child for direct child", function()
        expect(Paths.GetRelativePath(beta, alpha)).to.equal("@self/Beta")
      end)

      it("should return @self for deep descendant path", function()
        expect(Paths.GetRelativePath(gamma, alpha)).to.equal("@self/Beta/Gamma")
      end)

      it("should return @self with escaped name", function()
        expect(Paths.GetRelativePath(dotName, root)).to.equal("@self/" .. esc("Has.Dot"))
      end)

      it("should return @self path from service to deep child", function()
        expect(Paths.GetRelativePath(gamma, RS)).to.equal(
          "@self/" .. esc(root.Name) .. "/Alpha/Beta/Gamma"
        )
      end)

      it("should return @game when inst and relativeTo are both game", function()
        expect(Paths.GetRelativePath(game, game)).to.equal("@game")
      end)

      it("should not add debugId on unambiguous @self path", function()
        local path = Paths.GetRelativePath(beta, alpha)
        expect(string.find(path, "~")).to.equal(nil)
      end)
    end)

    describe("with . prefix (parent of relativeTo)", function()
      it("should return . for parent of relativeTo", function()
        expect(Paths.GetRelativePath(alpha, beta)).to.equal(".")
      end)

      it("should return . for root when relativeTo is direct child", function()
        expect(Paths.GetRelativePath(root, alpha)).to.equal(".")
      end)

      it("should not add debugId to bare . path", function()
        local path = Paths.GetRelativePath(alpha, beta)
        expect(string.find(path, "~")).to.equal(nil)
      end)
    end)

    describe("with ./ prefix (sibling paths)", function()
      it("should return ./Sibling with debugId", function()
        local path = Paths.GetRelativePath(delta, beta)
        expect(path).to.equal("./Delta~" .. id(delta))
      end)

      it("should return ./path with debugId for sibling subtree", function()
        local path = Paths.GetRelativePath(zeta, alpha)
        expect(path).to.equal("./Epsilon/Zeta~" .. id(zeta))
      end)
    end)

    describe("with .. prefix (grandparent and above)", function()
      it("should return .. for grandparent", function()
        expect(Paths.GetRelativePath(alpha, gamma)).to.equal("..")
      end)

      it("should return ../.. for great-grandparent", function()
        expect(Paths.GetRelativePath(root, gamma)).to.equal("../..")
      end)

      it("should return ../../.. for 4 levels up", function()
        expect(Paths.GetRelativePath(RS, gamma)).to.equal("../../..")
      end)

      it("should not add debugId to bare .. paths", function()
        expect(string.find(Paths.GetRelativePath(alpha, gamma), "~")).to.equal(nil)
        expect(string.find(Paths.GetRelativePath(root, gamma), "~")).to.equal(nil)
      end)
    end)

    describe("with ../ prefix (cousin paths)", function()
      it("should return cousin path with debugId", function()
        local path = Paths.GetRelativePath(epsilon, gamma)
        expect(path).to.equal("../../Epsilon~" .. id(epsilon))
      end)

      it("should handle deep cousin path", function()
        local path = Paths.GetRelativePath(zeta, deep4)
        expect(path).to.equal("../../.." .. "/Epsilon/Zeta~" .. id(zeta))
      end)

      it("should handle game from deep instance", function()
        expect(Paths.GetRelativePath(game, deep4)).to.equal("../../../../..")
      end)
    end)

    describe("ambiguity and DebugId", function()
      it("should not add debugId for unambiguous @game path", function()
        expect(string.find(Paths.GetRelativePath(alpha), "~")).to.equal(nil)
        expect(string.find(Paths.GetRelativePath(gamma), "~")).to.equal(nil)
        expect(string.find(Paths.GetRelativePath(deep4), "~")).to.equal(nil)
      end)

      it("should not add debugId for unambiguous @self path", function()
        expect(string.find(Paths.GetRelativePath(beta, alpha), "~")).to.equal(nil)
        expect(string.find(Paths.GetRelativePath(gamma, alpha), "~")).to.equal(nil)
      end)

      it("should not add debugId to @self with no segments", function()
        expect(string.find(Paths.GetRelativePath(alpha, alpha), "~")).to.equal(nil)
      end)

      it("should not add debugId to @game with no segments", function()
        expect(string.find(Paths.GetRelativePath(game), "~")).to.equal(nil)
      end)

      it("should not add debugId to bare . or .. paths (no name segments)", function()
        expect(string.find(Paths.GetRelativePath(alpha, beta), "~")).to.equal(nil)
        expect(string.find(Paths.GetRelativePath(alpha, gamma), "~")).to.equal(nil)
        expect(string.find(Paths.GetRelativePath(root, gamma), "~")).to.equal(nil)
      end)

      it("should add debugId for ambiguous @game path", function()
        expect(string.find(Paths.GetRelativePath(twin1), "~")).to.be.ok()
        expect(string.find(Paths.GetRelativePath(twin2), "~")).to.be.ok()
      end)

      it("should add debugId for ambiguous @self path", function()
        expect(string.find(Paths.GetRelativePath(twin1, ambigParent), "~")).to.be.ok()
        expect(string.find(Paths.GetRelativePath(twin2, ambigParent), "~")).to.be.ok()
      end)

      it("should add debugId for leaf under ambiguous parent", function()
        expect(string.find(Paths.GetRelativePath(twin1Leaf), "~")).to.be.ok()
        expect(string.find(Paths.GetRelativePath(twin2Leaf), "~")).to.be.ok()
      end)

      it("should add debugId for multi-level ambiguous leaf", function()
        expect(string.find(Paths.GetRelativePath(twin1Leaf2), "~")).to.be.ok()
      end)

      it("should produce distinct paths for ambiguous twins", function()
        local path1 = Paths.GetRelativePath(twin1)
        local path2 = Paths.GetRelativePath(twin2)
        expect(path1).never.to.equal(path2)
      end)

      it("should produce distinct paths for leaves under different twins", function()
        local path1 = Paths.GetRelativePath(twin1Leaf)
        local path2 = Paths.GetRelativePath(twin2Leaf)
        expect(path1).never.to.equal(path2)
      end)

      it("should produce distinct paths for leaves under same twin", function()
        local path1 = Paths.GetRelativePath(twin1Leaf)
        local path2 = Paths.GetRelativePath(twin1Leaf2)
        expect(path1).never.to.equal(path2)
      end)

      it("should place debugId only on last segment", function()
        local path = Paths.GetRelativePath(twin1Leaf)
        local lastSlash = string.find(path, "/[^/]*$")
        assert(lastSlash, "expected path with /")
        local lastSeg = string.sub(path, lastSlash + 1)
        local prefix = string.sub(path, 1, lastSlash - 1)
        expect(string.find(lastSeg, "~")).to.be.ok()
        expect(string.find(prefix, "~")).to.equal(nil)
      end)

      it("should always add debugId for orphaned instances", function()
        expect(string.find(Paths.GetRelativePath(orphan), "~")).to.be.ok()
        expect(string.find(Paths.GetRelativePath(orphanChild), "~")).to.be.ok()
      end)

      it("should add debugId for orphaned ambiguous instances", function()
        local orphanParent = Instance.new("Folder")
        orphanParent.Name = "OrphanParent"
        local oa = Instance.new("Folder")
        oa.Name = "Same"
        oa.Parent = orphanParent
        local ob = Instance.new("Folder")
        ob.Name = "Same"
        ob.Parent = orphanParent
        local pathA = Paths.GetRelativePath(oa)
        local pathB = Paths.GetRelativePath(ob)
        expect(string.find(pathA, "~")).to.be.ok()
        expect(string.find(pathB, "~")).to.be.ok()
        expect(pathA).never.to.equal(pathB)
        orphanParent:Destroy()
      end)
    end)
  end)

  describe("FromRelativePath", function()
    describe("@game prefix", function()
      it("should resolve @game to game", function()
        expect(Paths.FromRelativePath("@game")).to.equal(game)
      end)

      it("should resolve @game/ServiceName to service", function()
        expect(Paths.FromRelativePath("@game/" .. esc(RS.Name))).to.equal(RS)
      end)

      it("should resolve deep @game path", function()
        expect(Paths.FromRelativePath(basePath .. "/Alpha/Beta/Gamma")).to.equal(gamma)
      end)

      it("should resolve @game path to test root", function()
        expect(Paths.FromRelativePath(basePath)).to.equal(root)
      end)

      it("should error for @game/NonExistent", function()
        expect(function()
          Paths.FromRelativePath("@game/NonExistent")
        end).to.throw()
      end)

      it("should resolve @game/ to game (trailing slash ignored)", function()
        expect(Paths.FromRelativePath("@game/")).to.equal(game)
      end)

      it("should resolve path with escaped dot", function()
        expect(Paths.FromRelativePath(basePath .. "/" .. esc("Has.Dot"))).to.equal(dotName)
      end)

      it("should resolve path with escaped at-sign", function()
        expect(Paths.FromRelativePath(basePath .. "/" .. esc("Has@At"))).to.equal(atName)
      end)

      it("should resolve path with escaped slash", function()
        expect(Paths.FromRelativePath(basePath .. "/" .. esc("Has/Slash"))).to.equal(slashName)
      end)

      it("should resolve path with escaped tilde", function()
        expect(Paths.FromRelativePath(basePath .. "/" .. esc("Has~Tilde"))).to.equal(tildeName)
      end)

      it("should resolve path with escaped percent", function()
        expect(Paths.FromRelativePath(basePath .. "/" .. esc("Has%Pct"))).to.equal(pctName)
      end)

      it("should resolve path with all special chars escaped", function()
        expect(Paths.FromRelativePath(basePath .. "/" .. esc("%~/.@"))).to.equal(allSpecial)
      end)
    end)

    describe("@self prefix", function()
      it("should resolve @self to relativeTo", function()
        expect(Paths.FromRelativePath("@self", alpha)).to.equal(alpha)
      end)

      it("should resolve @self/Child", function()
        expect(Paths.FromRelativePath("@self/Beta", alpha)).to.equal(beta)
      end)

      it("should resolve deep @self path", function()
        expect(Paths.FromRelativePath("@self/Beta/Gamma", alpha)).to.equal(gamma)
      end)

      it("should error for @self/NonExistent", function()
        expect(function()
          Paths.FromRelativePath("@self/NonExistent", alpha)
        end).to.throw()
      end)

      it("should resolve @self to game when relativeTo defaults", function()
        expect(Paths.FromRelativePath("@self")).to.equal(game)
      end)

      it("should resolve @self/ to relativeTo (trailing slash ignored)", function()
        expect(Paths.FromRelativePath("@self/", alpha)).to.equal(alpha)
      end)

      it("should resolve @self with escaped child name", function()
        expect(Paths.FromRelativePath("@self/" .. esc("Has.Dot"), root)).to.equal(dotName)
      end)
    end)

    describe("./ prefix (1 level up)", function()
      it("should resolve ./Sibling", function()
        expect(Paths.FromRelativePath("./Delta", beta)).to.equal(delta)
      end)

      it("should resolve . to parent", function()
        expect(Paths.FromRelativePath(".", beta)).to.equal(alpha)
      end)

      it("should resolve ./A/B to deep sibling path", function()
        expect(Paths.FromRelativePath("./Epsilon/Zeta", alpha)).to.equal(zeta)
      end)

      it("should error for ./NonExistent", function()
        expect(function()
          Paths.FromRelativePath("./NonExistent", beta)
        end).to.throw()
      end)

      it("should error when relativeTo is game (game.Parent = nil)", function()
        expect(function()
          Paths.FromRelativePath("./Anything")
        end).to.throw()
      end)

      it("should error when relativeTo has no parent", function()
        expect(function()
          Paths.FromRelativePath("./Foo", orphan)
        end).to.throw()
      end)

      it("should resolve . to parent for deep instance", function()
        expect(Paths.FromRelativePath(".", gamma)).to.equal(beta)
      end)
    end)

    describe("../ prefix (2+ levels up)", function()
      it("should resolve .. to grandparent", function()
        expect(Paths.FromRelativePath("..", gamma)).to.equal(alpha)
      end)

      it("should resolve ../Uncle", function()
        expect(Paths.FromRelativePath("../Epsilon", beta)).to.equal(epsilon)
      end)

      it("should resolve ../.. to great-grandparent", function()
        expect(Paths.FromRelativePath("../..", gamma)).to.equal(root)
      end)

      it("should resolve ../../Cousin", function()
        expect(Paths.FromRelativePath("../../Epsilon/Zeta", gamma)).to.equal(zeta)
      end)

      it("should resolve deep .. chaining to root", function()
        expect(Paths.FromRelativePath("../../..", deep4)).to.equal(root)
      end)

      it("should resolve very deep .. chaining to game", function()
        expect(Paths.FromRelativePath("../../../../..", deep4)).to.equal(game)
      end)

      it("should error when .. goes past DataModel root", function()
        expect(function()
          Paths.FromRelativePath("../../../../../../../../../..", alpha)
        end).to.throw()
      end)

      it("should error for ../NonExistent", function()
        expect(function()
          Paths.FromRelativePath("../NonExistent", beta)
        end).to.throw()
      end)
    end)

    describe(".. anywhere in path", function()
      it("should resolve @self/Child/../OtherChild", function()
        expect(Paths.FromRelativePath("@self/Beta/../Delta", alpha)).to.equal(delta)
      end)

      it("should resolve @game path with mid-path ..", function()
        expect(Paths.FromRelativePath(basePath .. "/Alpha/Beta/../Delta")).to.equal(delta)
      end)

      it("should resolve multiple mid-path .. segments", function()
        expect(Paths.FromRelativePath("@self/Beta/Gamma/../../Delta", alpha)).to.equal(delta)
      end)

      it("should resolve . then .. in path", function()
        expect(Paths.FromRelativePath("@self/./Beta/../Delta", alpha)).to.equal(delta)
      end)

      it("should resolve .. back to start then descend", function()
        expect(Paths.FromRelativePath("@self/Beta/..", alpha)).to.equal(alpha)
      end)

      it("should resolve @game/Service/../Service back to service", function()
        expect(Paths.FromRelativePath("@game/" .. esc(RS.Name) .. "/../" .. esc(RS.Name))).to.equal(
          RS
        )
      end)
    end)

    describe(". segment (no-op)", function()
      it("should treat . as no-op in @self path", function()
        expect(Paths.FromRelativePath("@self/./Beta", alpha)).to.equal(beta)
      end)

      it("should treat . as no-op in @game path", function()
        expect(Paths.FromRelativePath("@game/./" .. esc(RS.Name))).to.equal(RS)
      end)

      it("should handle multiple consecutive . segments", function()
        expect(Paths.FromRelativePath("@self/./././Beta", alpha)).to.equal(beta)
      end)

      it("should resolve ./. to parent", function()
        expect(Paths.FromRelativePath("./.", beta)).to.equal(alpha)
      end)

      it("should resolve ./.  then child", function()
        expect(Paths.FromRelativePath("././Delta", beta)).to.equal(delta)
      end)
    end)

    describe("DebugId handling", function()
      it("should resolve ambiguous path with debugId", function()
        local path = Paths.GetRelativePath(twin1)
        expect(Paths.FromRelativePath(path)).to.equal(twin1)
      end)

      it("should resolve both ambiguous twins correctly", function()
        local path1 = Paths.GetRelativePath(twin1)
        local path2 = Paths.GetRelativePath(twin2)
        expect(Paths.FromRelativePath(path1)).to.equal(twin1)
        expect(Paths.FromRelativePath(path2)).to.equal(twin2)
      end)

      it("should resolve path without debugId normally", function()
        expect(Paths.FromRelativePath(basePath .. "/Alpha")).to.equal(alpha)
      end)

      it("should error for mismatched debugId", function()
        expect(function()
          Paths.FromRelativePath(basePath .. "/Alpha~INVALID")
        end).to.throw()
      end)

      it("should resolve relative path with debugId", function()
        local path = Paths.GetRelativePath(delta, beta)
        expect(Paths.FromRelativePath(path, beta)).to.equal(delta)
      end)

      it("should error for debugId mismatch after traversal", function()
        expect(function()
          Paths.FromRelativePath(basePath .. "/Alpha~" .. id(beta))
        end).to.throw()
      end)

      it("should resolve debugId on @self paths", function()
        local child = Instance.new("Folder")
        child.Name = "Twin"
        child.Parent = alpha
        local child2 = Instance.new("Folder")
        child2.Name = "Twin"
        child2.Parent = alpha
        local p1 = Paths.GetRelativePath(child, alpha)
        local p2 = Paths.GetRelativePath(child2, alpha)
        expect(Paths.FromRelativePath(p1, alpha)).to.equal(child)
        expect(Paths.FromRelativePath(p2, alpha)).to.equal(child2)
        child:Destroy()
        child2:Destroy()
      end)
    end)

    describe("ambiguity handling", function()
      -- Last segment ambiguity
      it("should error for ambiguous last segment without debugId", function()
        expect(function()
          Paths.FromRelativePath(basePath .. "/AmbigParent/Twin")
        end).to.throw()
      end)

      it("should resolve ambiguous last segment with correct debugId", function()
        expect(Paths.FromRelativePath(basePath .. "/AmbigParent/Twin~" .. id(twin1))).to.equal(
          twin1
        )
        expect(Paths.FromRelativePath(basePath .. "/AmbigParent/Twin~" .. id(twin2))).to.equal(
          twin2
        )
      end)

      it("should error for ambiguous last segment with bogus debugId", function()
        expect(function()
          Paths.FromRelativePath(basePath .. "/AmbigParent/Twin~BOGUS")
        end).to.throw()
      end)

      it("should error for ambiguous last segment with wrong valid debugId", function()
        expect(function()
          Paths.FromRelativePath(basePath .. "/AmbigParent/Twin~" .. id(alpha))
        end).to.throw()
      end)

      -- Intermediate ambiguity (one level)
      it("should error for ambiguous intermediate without debugId", function()
        expect(function()
          Paths.FromRelativePath(basePath .. "/AmbigParent/Twin/Leaf")
        end).to.throw()
      end)

      it("should resolve through ambiguous intermediate with debugId on leaf", function()
        expect(Paths.FromRelativePath(basePath .. "/AmbigParent/Twin/Leaf~" .. id(twin1Leaf))).to.equal(
          twin1Leaf
        )
        expect(Paths.FromRelativePath(basePath .. "/AmbigParent/Twin/Leaf~" .. id(twin2Leaf))).to.equal(
          twin2Leaf
        )
      end)

      -- Multi-level ambiguity (ambiguous Twin + ambiguous Leaf under twin1)
      it("should resolve multi-level ambiguity with debugId", function()
        expect(Paths.FromRelativePath(basePath .. "/AmbigParent/Twin/Leaf~" .. id(twin1Leaf))).to.equal(
          twin1Leaf
        )
        expect(Paths.FromRelativePath(basePath .. "/AmbigParent/Twin/Leaf~" .. id(twin1Leaf2))).to.equal(
          twin1Leaf2
        )
      end)

      it("should distinguish leaves under same ambiguous twin", function()
        local p1 = Paths.GetRelativePath(twin1Leaf)
        local p2 = Paths.GetRelativePath(twin1Leaf2)
        expect(Paths.FromRelativePath(p1)).to.equal(twin1Leaf)
        expect(Paths.FromRelativePath(p2)).to.equal(twin1Leaf2)
      end)

      -- Non-canonical paths through ambiguity
      it("should resolve non-canonical @game path through ambiguous segment", function()
        expect(Paths.FromRelativePath(basePath .. "/Alpha/../AmbigParent/Twin~" .. id(twin2))).to.equal(
          twin2
        )
      end)

      it("should resolve non-canonical @game path through ambiguous intermediate", function()
        expect(
          Paths.FromRelativePath(basePath .. "/Alpha/../AmbigParent/Twin/Leaf~" .. id(twin1Leaf))
        ).to.equal(twin1Leaf)
      end)

      -- @self paths through ambiguity
      it("should error for @self path into ambiguous children without debugId", function()
        expect(function()
          Paths.FromRelativePath("@self/Twin", ambigParent)
        end).to.throw()
      end)

      it("should resolve @self path into ambiguous children with debugId", function()
        expect(Paths.FromRelativePath("@self/Twin~" .. id(twin1), ambigParent)).to.equal(twin1)
        expect(Paths.FromRelativePath("@self/Twin~" .. id(twin2), ambigParent)).to.equal(twin2)
      end)

      it("should error for @self path through ambiguous to leaf without debugId", function()
        expect(function()
          Paths.FromRelativePath("@self/Twin/Leaf", ambigParent)
        end).to.throw()
      end)

      it("should resolve @self path through ambiguous intermediate with debugId", function()
        expect(Paths.FromRelativePath("@self/Twin/Leaf~" .. id(twin2Leaf), ambigParent)).to.equal(
          twin2Leaf
        )
      end)

      -- ./ paths through ambiguity
      it("should error for ./ path into ambiguous without debugId", function()
        expect(function()
          Paths.FromRelativePath("./Twin", twin1)
        end).to.throw()
      end)

      it("should resolve ./ path into ambiguous with debugId", function()
        expect(Paths.FromRelativePath("./Twin~" .. id(twin2), twin1)).to.equal(twin2)
      end)

      -- ../ paths through ambiguity
      it("should error for ../ path into ambiguous without debugId", function()
        expect(function()
          Paths.FromRelativePath("../Twin", twin1Leaf)
        end).to.throw()
      end)

      it("should resolve ../ path into ambiguous with debugId", function()
        expect(Paths.FromRelativePath("../Twin~" .. id(twin2), twin1Leaf)).to.equal(twin2)
      end)

      -- Unique paths still resolve without debugId
      it("should resolve unique sibling path through AmbigParent without debugId", function()
        expect(Paths.FromRelativePath(basePath .. "/AmbigParent")).to.equal(ambigParent)
      end)

      it("should resolve unique @self path without debugId", function()
        expect(Paths.FromRelativePath("@self/Beta", alpha)).to.equal(beta)
      end)

      -- Round-trips through all ambiguous instances
      it("should round-trip all ambiguous instances from game", function()
        for _, inst in { twin1, twin2, twin1Leaf, twin1Leaf2, twin2Leaf } do
          local path = Paths.GetRelativePath(inst)
          local resolved = Paths.FromRelativePath(path)
          if resolved ~= inst then
            error(`Failed round-trip for {inst:GetFullName()}: path={path}`)
          end
        end
      end)

      it("should round-trip ambiguous instances with @self relativeTo", function()
        for _, inst in { twin1, twin2 } do
          local path = Paths.GetRelativePath(inst, ambigParent)
          local resolved = Paths.FromRelativePath(path, ambigParent)
          if resolved ~= inst then
            error(`Failed round-trip for {inst:GetFullName()} relative to AmbigParent: path={path}`)
          end
        end
      end)

      -- Orphaned ambiguous instances
      it("should error for orphaned ambiguous instances (not in DebugIdMap)", function()
        local orphanP = Instance.new("Folder")
        orphanP.Name = "OP"
        local oa = Instance.new("Folder")
        oa.Name = "Same"
        oa.Parent = orphanP
        local ob = Instance.new("Folder")
        ob.Name = "Same"
        ob.Parent = orphanP
        local pathA = Paths.GetRelativePath(oa)
        local pathB = Paths.GetRelativePath(ob)
        expect(string.find(pathA, "~")).to.be.ok()
        expect(string.find(pathB, "~")).to.be.ok()
        expect(function()
          Paths.FromRelativePath(pathA)
        end).to.throw()
        expect(function()
          Paths.FromRelativePath(pathB)
        end).to.throw()
        orphanP:Destroy()
      end)

      -- Instances moved out of DataModel become unresolvable
      it("should error after ambiguous instance is removed from DataModel", function()
        local tempParent = Instance.new("Folder")
        tempParent.Name = "TempAmbig"
        tempParent.Parent = root
        local ta = Instance.new("Folder")
        ta.Name = "Dup"
        ta.Parent = tempParent
        local tb = Instance.new("Folder")
        tb.Name = "Dup"
        tb.Parent = tempParent
        local pathA = Paths.GetRelativePath(ta)
        local pathB = Paths.GetRelativePath(tb)
        expect(Paths.FromRelativePath(pathA)).to.equal(ta)
        expect(Paths.FromRelativePath(pathB)).to.equal(tb)
        tempParent.Parent = nil
        expect(function()
          Paths.FromRelativePath(pathA)
        end).to.throw()
        expect(function()
          Paths.FromRelativePath(pathB)
        end).to.throw()
        tempParent:Destroy()
      end)
    end)

    describe("edge cases", function()
      it("should error for empty string", function()
        expect(function()
          Paths.FromRelativePath("")
        end).to.throw()
      end)

      it("should error for path to nonexistent child", function()
        expect(function()
          Paths.FromRelativePath("@game/Nonexistent/Path")
        end).to.throw()
      end)

      it("should error when @game/.. goes past root", function()
        expect(function()
          Paths.FromRelativePath("@game/..")
        end).to.throw()
      end)

      it("should handle double slashes by skipping empty segments", function()
        expect(Paths.FromRelativePath(basePath .. "//Alpha")).to.equal(alpha)
      end)

      it("should handle trailing slash gracefully", function()
        expect(Paths.FromRelativePath(basePath .. "/Alpha/")).to.equal(alpha)
      end)

      it("should resolve escaped slash name", function()
        expect(Paths.FromRelativePath(basePath .. "/" .. esc("Has/Slash"))).to.equal(slashName)
      end)

      it("should resolve escaped tilde name (not confused with debugId)", function()
        expect(Paths.FromRelativePath(basePath .. "/" .. esc("Has~Tilde"))).to.equal(tildeName)
      end)

      it("should resolve escaped percent name", function()
        expect(Paths.FromRelativePath(basePath .. "/" .. esc("Has%Pct"))).to.equal(pctName)
      end)

      it("should resolve escaped dot name", function()
        expect(Paths.FromRelativePath(basePath .. "/" .. esc("Has.Dot"))).to.equal(dotName)
      end)

      it("should resolve escaped at-sign name", function()
        expect(Paths.FromRelativePath(basePath .. "/" .. esc("Has@At"))).to.equal(atName)
      end)

      it("should return game for bare @game with default relativeTo", function()
        expect(Paths.FromRelativePath("@game")).to.equal(game)
      end)

      it("should error for garbage input", function()
        expect(function()
          Paths.FromRelativePath("not_a_valid_path_probably")
        end).to.throw()
      end)

      it("should error for bare path when game is relativeTo", function()
        expect(function()
          Paths.FromRelativePath("CompletelyFake/Path")
        end).to.throw()
      end)
    end)
  end)

  describe("round-trip: GetRelativePath -> FromRelativePath", function()
    it("should round-trip game (default relativeTo)", function()
      local path = Paths.GetRelativePath(game)
      expect(Paths.FromRelativePath(path)).to.equal(game)
    end)

    it("should round-trip service", function()
      local path = Paths.GetRelativePath(RS)
      expect(Paths.FromRelativePath(path)).to.equal(RS)
    end)

    it("should round-trip test root", function()
      local path = Paths.GetRelativePath(root)
      expect(Paths.FromRelativePath(path)).to.equal(root)
    end)

    it("should round-trip deep instance from game", function()
      local path = Paths.GetRelativePath(gamma)
      expect(Paths.FromRelativePath(path)).to.equal(gamma)
    end)

    it("should round-trip 4-level deep instance", function()
      local path = Paths.GetRelativePath(deep4)
      expect(Paths.FromRelativePath(path)).to.equal(deep4)
    end)

    it("should round-trip @self path (direct child)", function()
      local path = Paths.GetRelativePath(beta, alpha)
      expect(Paths.FromRelativePath(path, alpha)).to.equal(beta)
    end)

    it("should round-trip @self deep path", function()
      local path = Paths.GetRelativePath(gamma, alpha)
      expect(Paths.FromRelativePath(path, alpha)).to.equal(gamma)
    end)

    it("should round-trip sibling (./ path)", function()
      local path = Paths.GetRelativePath(delta, beta)
      expect(Paths.FromRelativePath(path, beta)).to.equal(delta)
    end)

    it("should round-trip cousin (../ path)", function()
      local path = Paths.GetRelativePath(zeta, gamma)
      expect(Paths.FromRelativePath(path, gamma)).to.equal(zeta)
    end)

    it("should round-trip parent (. path)", function()
      local path = Paths.GetRelativePath(alpha, beta)
      expect(Paths.FromRelativePath(path, beta)).to.equal(alpha)
    end)

    it("should round-trip grandparent (.. path)", function()
      local path = Paths.GetRelativePath(alpha, gamma)
      expect(Paths.FromRelativePath(path, gamma)).to.equal(alpha)
    end)

    it("should round-trip great-grandparent (../.. path)", function()
      local path = Paths.GetRelativePath(root, gamma)
      expect(Paths.FromRelativePath(path, gamma)).to.equal(root)
    end)

    it("should round-trip 4 levels up (../../..)", function()
      local path = Paths.GetRelativePath(RS, gamma)
      expect(Paths.FromRelativePath(path, gamma)).to.equal(RS)
    end)

    it("should round-trip each special-char instance", function()
      for _, inst in { dotName, atName, slashName, tildeName, pctName, allSpecial } do
        local path = Paths.GetRelativePath(inst)
        expect(Paths.FromRelativePath(path)).to.equal(inst)
      end
    end)

    it("should round-trip ambiguous twin1", function()
      local path = Paths.GetRelativePath(twin1)
      expect(Paths.FromRelativePath(path)).to.equal(twin1)
    end)

    it("should round-trip ambiguous twin2", function()
      local path = Paths.GetRelativePath(twin2)
      expect(Paths.FromRelativePath(path)).to.equal(twin2)
    end)

    it("should round-trip game as inst with deep relativeTo", function()
      local path = Paths.GetRelativePath(game, deep4)
      expect(Paths.FromRelativePath(path, deep4)).to.equal(game)
    end)

    it("should NOT round-trip orphaned instance (not in DebugIdMap)", function()
      local path = Paths.GetRelativePath(orphanChild)
      expect(function()
        Paths.FromRelativePath(path)
      end).to.throw()
    end)

    it("should round-trip all pairs of test instances", function()
      local instances = { alpha, beta, gamma, delta, epsilon, zeta, root, deep1, deep4 }
      for _, inst in instances do
        for _, rel in instances do
          if inst ~= rel then
            local path = Paths.GetRelativePath(inst, rel)
            local resolved = Paths.FromRelativePath(path, rel)
            if resolved ~= inst then
              error(
                `Failed: GetRelativePath({inst.Name}, {rel.Name}) = {path}, resolved to {resolved and resolved.Name or "nil"}`
              )
            end
          end
        end
      end
    end)

    it("should round-trip all test instances from game", function()
      local instances = {
        alpha,
        beta,
        gamma,
        delta,
        epsilon,
        zeta,
        root,
        deep1,
        deep2,
        deep3,
        deep4,
        dotName,
        atName,
        slashName,
        tildeName,
        pctName,
        allSpecial,
        ambigParent,
        twin1,
        twin2,
        twin1Leaf,
        twin1Leaf2,
        twin2Leaf,
      }
      for _, inst in instances do
        local path = Paths.GetRelativePath(inst)
        local resolved = Paths.FromRelativePath(path)
        if resolved ~= inst then
          error(
            `Failed: GetRelativePath({inst.Name}) = {path}, resolved to {resolved and resolved.Name or "nil"}`
          )
        end
      end
    end)
  end)
end
