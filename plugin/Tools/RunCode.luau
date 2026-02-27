--!strict

local DeepCopy = require("../Utils/DeepCopy")

type Args = {
  command: string,
}

-- Converts any Lua value to a human-readable string safe for display output.
-- Handles NaN, Inf, and nil (represented as "null") without relying on
-- HttpService:JSONEncode, which rejects those values.
local function valueToString(value: any): string
  local t = type(value)
  if t == "number" then
    if value ~= value then
      return "NaN"
    elseif value == math.huge then
      return "Infinity"
    elseif value == -math.huge then
      return "-Infinity"
    end
    return tostring(value)
  elseif t == "nil" then
    return "null"
  elseif t == "string" then
    return string.format("%q", value)
  elseif t == "boolean" then
    return tostring(value)
  elseif t == "table" then
    local parts: { string } = {}
    local isArray = #value > 0
    if isArray then
      for _, v in value :: { any } do
        table.insert(parts, valueToString(v))
      end
      return "[" .. table.concat(parts, ", ") .. "]"
    else
      for k, v in value :: { [any]: any } do
        table.insert(parts, valueToString(k) .. ": " .. valueToString(v))
      end
      return "{" .. table.concat(parts, ", ") .. "}"
    end
  end
  return tostring(value)
end

local function runCodeWithOutput(command: string): string
  local output = ""

  local function getTableType(arg)
    local hasArray = false
    local hasTable = false
    for key, _value in arg do
      if typeof(key) == "number" then
        hasArray = true
      else
        hasTable = true
      end
      if hasArray and hasTable then
        break
      end
    end
    return hasArray, hasTable
  end

  local function serializeTable(arg): any
    if typeof(arg) == "table" then
      local _, isTable = getTableType(arg)

      local newArg = {}
      for key, value in arg do
        local newKey = serializeTable(key)
        newArg[if isTable then tostring(newKey) else newKey] = serializeTable(value)
      end
      return newArg
    elseif type(arg) == "userdata" then
      return tostring(arg) or "UNABLE_TO_SERIALIZE"
    end
    return arg
  end

  local function toStrTable(t: { any }): { string }
    local clonedTable = DeepCopy(t)
    local strTable = table.create(#clonedTable)
    for i, arg in clonedTable do
      local serializedArg = serializeTable(arg)
      strTable[i] = valueToString(serializedArg)
    end
    return strTable
  end

  local function addToOutput(header: string, ...)
    local strResults = toStrTable(table.pack(...))
    output ..= header .. " " .. table.concat(strResults, "\t") .. "\n"
  end

  local function executeCode()
    local chunk = loadstring(command) :: any
    local chunkfenv = getfenv(chunk)

    local oldPrint = print
    chunkfenv.print = function(...)
      oldPrint(...)
      addToOutput("[OUTPUT]", ...)
    end

    local oldWarn = warn
    chunkfenv.warn = function(...)
      oldWarn(...)
      addToOutput("[WARNING]", ...)
    end

    local oldError = error
    chunkfenv.error = function(...)
      oldError(...)
      addToOutput("[ERROR]", ...)
    end

    local results = table.pack(chunk())
    if #results > 0 then
      addToOutput("[RETURNED RESULTS]", table.unpack(results))
    end

    return results
  end

  local ok, errorMessage = pcall(executeCode)
  if not ok then
    addToOutput("[UNEXPECTED ERROR]", errorMessage)
  end

  return output
end

local function handleRunCode(args: Args): string?
  assert(type(args.command) == "string", "Missing command in RunCode")

  return runCodeWithOutput(args.command)
end

return handleRunCode
