local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestEZ = require(ReplicatedStorage.Packages:WaitForChild("TestEZ", 10))

require(ReplicatedStorage.MCPPlugin.runTests)(TestEZ)
