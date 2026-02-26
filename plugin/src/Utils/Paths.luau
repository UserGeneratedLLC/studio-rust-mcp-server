--!strict
--!optimize 2

local DebugIdMap: { [string]: Instance } = {}

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
})
