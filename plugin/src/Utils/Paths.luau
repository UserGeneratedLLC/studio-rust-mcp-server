--!strict
--!optimize 2

local DebugIdMap: { [string]: Instance } = {}

local function GetDebugId(inst: Instance): string return inst:GetDebugId(0) end

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

local function GetDistinctName(inst: Instance): string
  return `{EscapeName(inst.Name)}~{GetDebugId(inst)}`
end

local function GetDistinctPath(inst: Instance): string
  if inst == game then return "" end
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
    if inst and path == GetDistinctPath(inst) then return inst end
  end

  if pathWithoutId == "" then
    if debugId and GetDebugId(game) ~= debugId then return nil end
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
      if GetDebugId(inst) == debugId then return inst end
    end
  elseif #results == 1 then
    return results[1]
  elseif #results > 1 then
    warn(`FromDistinctPath Ambiguous: {#results}`)
  end
  return nil
end

local function IsAmbiguous(inst: Instance, _relativeTo: Instance?): boolean
  assert(typeof(inst) == "Instance")
  assert(_relativeTo == nil or typeof(_relativeTo) == "Instance")
  local relativeTo = _relativeTo or game
  local pivot = inst
  while true do
    if pivot == relativeTo then return false end
    local parent = pivot.Parent
    if not parent then return true end -- Not a descendant of root
    local ok, results =
      pcall(parent.QueryDescendants, parent, string.format("> [Name = %q]", pivot.Name))
    if not ok or #results > 1 then return true end
    pivot = parent
  end
end

local function GetRelativePath(inst: Instance, _relativeTo: Instance?): string
  assert(typeof(inst) == "Instance")
  assert(_relativeTo == nil or typeof(_relativeTo) == "Instance")
  local relativeTo: Instance = _relativeTo or game

  if inst == relativeTo then return if relativeTo == game then "@game" else "@self" end

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
      if commonIdx then break end
      pivot = (pivot :: Instance).Parent
    end
  end

  -- No common ancestor: bare path (orphaned or disjoint trees)
  if not commonIdx then
    local names = table.create(chainLen)
    for i = 1, chainLen do
      names[i] = EscapeName(instChain[i].Name)
    end
    local n = chainLen
    local center = n // 2
    for i = 1, center do
      names[i], names[n - i + 1] = names[n - i + 1], names[i]
    end
    if IsAmbiguous(inst, relativeTo) then names[n] = `{names[n]}~{GetDebugId(inst)}` end
    return table.concat(names, "/")
  end

  -- Segments from common ancestor down to inst (collected child-to-root, then reversed)
  local segCount = commonIdx - 1
  local names = table.create(segCount)
  for i = 1, segCount do
    names[i] = EscapeName(instChain[i].Name)
  end
  local center = segCount // 2
  for i = 1, center do
    names[i], names[segCount - i + 1] = names[segCount - i + 1], names[i]
  end

  if segCount > 0 and IsAmbiguous(inst, relativeTo) then
    names[segCount] = `{names[segCount]}~{GetDebugId(inst)}`
  end

  local segDown: string? = if segCount > 0 then table.concat(names, "/") else nil

  if levelsUp == 0 then
    if relativeTo == game then return if segDown then `@game/{segDown}` else "@game" end
    return if segDown then `@self/{segDown}` else "@self"
  end

  if levelsUp == 1 then return if segDown then `./{segDown}` else "." end

  -- levelsUp >= 2: (levelsUp-1) ".." segments
  local prefixParts = table.create(levelsUp - 1)
  for i = 1, levelsUp - 1 do
    prefixParts[i] = ".."
  end
  local prefix = table.concat(prefixParts, "/")
  return if segDown then `{prefix}/{segDown}` else prefix
end

local function FromRelativePath(path: string, _relativeTo: Instance?): Instance?
  assert(type(path) == "string")
  assert(_relativeTo == nil or typeof(_relativeTo) == "Instance")
  local relativeTo: Instance = _relativeTo or game

  -- Extract debugId from last segment (last ~ after last /)
  local debugId: string?
  local cleanPath = path
  do
    local lastSlash = string.find(path, "/[^/]*$")
    local searchFrom = if lastSlash then lastSlash + 1 else 1
    local tildePos = string.find(path, "~", searchFrom, true)
    if tildePos then
      debugId = string.sub(path, tildePos + 1)
      cleanPath = string.sub(path, 1, tildePos - 1)
    end
  end

  -- DebugId fast path: O(1) lookup + canonical validation
  if debugId then
    local inst = DebugIdMap[debugId]
    if inst and GetRelativePath(inst, relativeTo) == path then return inst end
  end

  -- Exact matches (no traversal needed)
  if cleanPath == "@game" then return game end
  if cleanPath == "@self" then return relativeTo end

  -- Determine start instance and remaining path
  local start: Instance?
  local rest: string
  if string.sub(cleanPath, 1, 6) == "@game/" then
    start = game
    rest = string.sub(cleanPath, 7)
  elseif string.sub(cleanPath, 1, 6) == "@self/" then
    start = relativeTo
    rest = string.sub(cleanPath, 7)
  elseif string.byte(cleanPath, 1) == 0x2E then
    start = relativeTo.Parent
    rest = cleanPath
  else
    start = if relativeTo == game then game else relativeTo.Parent
    rest = cleanPath
  end

  if not start or rest == "" then return nil end

  -- Segment-by-segment traversal (1:1 with require-by-string resolution)
  local segments = string.split(rest, "/")
  local current: Instance? = start
  for _, seg in segments do
    if not current then return nil end
    if seg == ".." then
      current = current.Parent
    elseif seg ~= "." and seg ~= "" then
      current = current:FindFirstChild(UnescapeName(seg))
    end
  end

  if not current then return nil end
  if debugId and GetDebugId(current) ~= debugId then return nil end
  return current
end

-- Watcher
game.DescendantAdded:Connect(function(inst) DebugIdMap[GetDebugId(inst)] = inst end)
game.DescendantRemoving:Connect(function(inst) DebugIdMap[GetDebugId(inst)] = nil end)
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
  GetRelativePath = GetRelativePath,
  FromRelativePath = FromRelativePath,
})
