--!strict

local ConsoleOutput = require("../Utils/ConsoleOutput")

local function handleGetConsoleOutput(): string?
  local result = ConsoleOutput.outputMessage or ""
  return result
end

return handleGetConsoleOutput
