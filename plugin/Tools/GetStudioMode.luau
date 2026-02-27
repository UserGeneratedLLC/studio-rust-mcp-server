--!strict

local GlobalVariables = require(script.Parent.Parent.Utils.GlobalVariables)

local function handleGetStudioMode(): string?
  local result = GlobalVariables.studioMode
  return result
end

return handleGetStudioMode
