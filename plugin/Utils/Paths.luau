--!strict
--!optimize 2

local DebugIdMap: { [string]: Instance } = {}

local function GetDebugId(inst: Instance): string
  return inst:GetDebugId(0)
end

local function UnescapeName(name: string): string
  name = string.gsub(name, "%%40", "@")
  name = string.gsub(name, "%%2[Ee]", ".")
  name = string.gsub(name, "%%2[Ff]", "/")
  name = string.gsub(name, "%%7[Ee]", "~")
  name = string.gsub(name, "%%25", "%%")
  return name
end

local function EscapeName(name: string): string
  name = string.gsub(name, "%%", "%%25")
  name = string.gsub(name, "~", "%%7E")
  name = string.gsub(name, "/", "%%2F")
  name = string.gsub(name, "%.", "%%2E")
  name = string.gsub(name, "@", "%%40")
  return name
end

local function ReverseArray(arr: { any }, n: number)
  local center = n // 2
  for i = 1, center do
    arr[i], arr[n - i + 1] = arr[n - i + 1], arr[i]
  end
end

local function FindChildren(parent: Instance, name: string): { Instance }
  return parent:QueryDescendants(string.format("> [Name = %q]", name))
end

local function GetDistinctName(inst: Instance): string
  return `{EscapeName(inst.Name)}~{GetDebugId(inst)}`
end

local function GetDistinctPath(inst: Instance): string
  if inst == game then
    return ""
  end
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

local function FromDistinctPath(path: string): Instance?
  local tildePos = string.find(path, "~")
  local debugId: string?
  local pathWithoutId: string
  if tildePos then
    debugId = string.sub(path, tildePos + 1)
    pathWithoutId = string.sub(path, 1, tildePos - 1)
  else
    pathWithoutId = path
  end

  if debugId then
    local inst = DebugIdMap[debugId]
    if inst and path == GetDistinctPath(inst) then
      return inst
    end
  end

  if pathWithoutId == "" then
    if debugId and GetDebugId(game) ~= debugId then
      return nil
    end
    return game
  end

  local segments = string.split(pathWithoutId, "/")
  local parts = table.create(#segments)
  for i, seg in segments do
    parts[i] = string.format("> [Name = %s]", string.format("%q", UnescapeName(seg)))
  end
  local selector = table.concat(parts, " ")
  local ok, results = pcall(game.QueryDescendants, game, selector)
  if not ok then
    warn(`FromDistinctPath QueryDescendants: {results}`)
    return nil
  end
  if debugId then
    for _, inst in results do
      if GetDebugId(inst) == debugId then
        return inst
      end
    end
  elseif #results == 1 then
    return results[1]
  elseif #results > 1 then
    warn(`FromDistinctPath Ambiguous: {#results}`)
  end
  return nil
end

local function IsAmbiguous(inst: Instance, _relativeTo: Instance?): boolean
  assert(typeof(inst) == "Instance", "expected Instance")
  assert(_relativeTo == nil or typeof(_relativeTo) == "Instance", "expected Instance or nil")
  local relativeTo = _relativeTo or game
  local pivot = inst
  while true do
    if pivot == relativeTo then
      return false
    end
    local parent = pivot.Parent
    if not parent then
      return true
    end -- Not a descendant of root
    local ok, results =
      pcall(parent.QueryDescendants, parent, string.format("> [Name = %q]", pivot.Name))
    if not ok or #results > 1 then
      return true
    end
    pivot = parent
  end
end

local function GetRelativePath(inst: Instance, _relativeTo: Instance?): string
  assert(typeof(inst) == "Instance", "expected Instance")
  assert(_relativeTo == nil or typeof(_relativeTo) == "Instance", "expected Instance or nil")
  local relativeTo: Instance = _relativeTo or game

  if inst == relativeTo then
    if relativeTo == game then
      return "@game"
    end
    return "@self"
  end

  -- inst's ancestor chain [inst, parent, grandparent, ..., root] with O(1) lookup
  local instChain: { Instance } = {}
  local instSet: { [Instance]: number } = {}
  local chainLen = 0
  local pivot: Instance? = inst
  while pivot do
    chainLen += 1
    instChain[chainLen] = pivot
    instSet[pivot] = chainLen
    pivot = pivot.Parent
  end

  -- Walk up from relativeTo to find common ancestor
  local levelsUp = 0
  local commonIdx: number? = instSet[relativeTo]
  if not commonIdx then
    pivot = relativeTo.Parent
    while pivot do
      levelsUp += 1
      commonIdx = instSet[pivot :: Instance]
      if commonIdx then
        break
      end
      pivot = (pivot :: Instance).Parent
    end
  end

  -- No common ancestor: bare path (orphaned or disjoint trees)
  if not commonIdx then
    local result = table.create(chainLen)
    for i = 1, chainLen do
      result[i] = EscapeName(instChain[chainLen - i + 1].Name)
    end
    if IsAmbiguous(inst, relativeTo) then
      result[chainLen] = `{result[chainLen]}~{GetDebugId(inst)}`
    end
    return table.concat(result, "/")
  end

  -- Build single result array: prefix segments + name segments
  local segCount = commonIdx - 1
  local prefixCount: number
  if levelsUp <= 1 then
    prefixCount = 1
  else
    prefixCount = levelsUp - 1
  end

  local totalSegs = prefixCount + segCount
  local result = table.create(totalSegs)

  -- Fill prefix
  if levelsUp == 0 then
    if relativeTo == game then
      result[1] = "@game"
    else
      result[1] = "@self"
    end
  elseif levelsUp == 1 then
    result[1] = "."
  else
    for i = 1, prefixCount do
      result[i] = ".."
    end
  end

  -- Fill name segments (iterate instChain backwards = root-to-child order)
  for i = 1, segCount do
    result[prefixCount + i] = EscapeName(instChain[segCount - i + 1].Name)
  end

  -- Append debugId to last segment if ambiguous
  if segCount > 0 and IsAmbiguous(inst, relativeTo) then
    result[totalSegs] = `{result[totalSegs]}~{GetDebugId(inst)}`
  end

  return table.concat(result, "/")
end

local function FromRelativePath(path: string, _relativeTo: Instance?): Instance?
  assert(type(path) == "string", "expected string")
  assert(_relativeTo == nil or typeof(_relativeTo) == "Instance", "expected Instance or nil")
  local relativeTo: Instance = _relativeTo or game

  if path == "" then
    return nil
  end

  -- Extract debugId from last segment (last ~ after last /)
  local debugId: string?
  local cleanPath = path
  do
    local lastSlash = string.find(path, "/[^/]*$")
    local searchFrom = 1
    if lastSlash then
      searchFrom = lastSlash + 1
    end
    local tildePos = string.find(path, "~", searchFrom, true)
    if tildePos then
      debugId = string.sub(path, tildePos + 1)
      cleanPath = string.sub(path, 1, tildePos - 1)
    end
  end

  -- Build candidate ancestor set for debugId disambiguation
  if debugId then
    local candidate = DebugIdMap[debugId]
    if candidate and GetDebugId(candidate) == debugId then
      error("nyi")
      -- TODO(high): we now have a literal path of the instance. we can literally walk it like we do below without having to do expensive calls to FindChildren
      -- crappy solution: just regenerate the path and compare, ignoring DebugId the at the ends. if it matches, return the instance. otherwise, fall through.
    end
  end

  -- Split into segments and classify by first component (matches Luau navigateImpl)
  local segments = string.split(cleanPath, "/")
  local current: Instance?
  local startIdx = 1
  local first = segments[1]

  if first == "@game" then
    current = game
    startIdx = 2
  elseif first == "@self" then
    current = relativeTo
    startIdx = 2
  elseif first == "." or first == ".." then
    current = relativeTo.Parent
  else
    if relativeTo == game then
      current = game
    else
      current = relativeTo.Parent
    end
  end

  if not current then
    return nil
  end

  -- Walk segments step by step (matches Luau navigateThroughPath)
  for i = startIdx, #segments do
    if not current then
      return nil
    end
    local seg = segments[i]
    if seg == ".." then
      current = current.Parent
    elseif seg ~= "." and seg ~= "" then
      local results = FindChildren(current, UnescapeName(seg))
      if #results == 0 then
        return nil
      elseif #results == 1 then
        current = results[1]
      else
        warn(`FromRelativePath Ambiguous: {#results}`)
        return nil
      end
    end
  end

  if not current then
    return nil
  end
  if debugId and GetDebugId(current) ~= debugId then
    return nil
  end
  return current
end

-- Watcher
game.DescendantAdded:Connect(function(inst)
  DebugIdMap[GetDebugId(inst)] = inst
end)
game.DescendantRemoving:Connect(function(inst)
  DebugIdMap[GetDebugId(inst)] = nil
end)
for _, inst in game:GetDescendants() do
  DebugIdMap[GetDebugId(inst)] = inst
end

return table.freeze({
  GetDebugId = GetDebugId,
  UnescapeName = UnescapeName,
  EscapeName = EscapeName,
  GetDistinctName = GetDistinctName,
  GetDistinctPath = GetDistinctPath,
  FromDistinctPath = FromDistinctPath,
  IsAmbiguous = IsAmbiguous,
  ReverseArray = ReverseArray,
  FindChildren = FindChildren,
  GetRelativePath = GetRelativePath,
  FromRelativePath = FromRelativePath,
})
