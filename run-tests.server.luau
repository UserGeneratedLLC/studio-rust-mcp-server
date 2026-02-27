--!nocheck

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Jest = require(ReplicatedStorage.DevPackages.Jest)

local processServiceExists, ProcessService = pcall(function()
  return game:GetService("ProcessService")
end)

local testRoot = ReplicatedStorage.MCPPlugin

local status, result = Jest.runCLI(testRoot, {
  verbose = true,
  ci = true,
}, { testRoot }):awaitStatus()

if status == "Rejected" then
  print(result)
end

if
  status == "Resolved"
  and result.results.numFailedTestSuites == 0
  and result.results.numFailedTests == 0
then
  if processServiceExists then
    ProcessService:ExitAsync(0)
  end
  return nil
end

if processServiceExists then
  ProcessService:ExitAsync(1)
end

error("Tests failed")
