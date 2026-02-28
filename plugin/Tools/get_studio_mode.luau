--!strict

local StudioModeState = require("../Utils/StudioModeState")

local function handleGetStudioMode(): string?
  local result = StudioModeState.studioMode
  return result
end

return handleGetStudioMode
