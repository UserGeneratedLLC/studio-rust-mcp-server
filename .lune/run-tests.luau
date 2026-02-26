local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local luau_execute = require("./opencloud-execute")

local API_KEY = process.env["RBX_API_KEY"]
local UNIVERSE_ID = process.env["RBX_UNIVERSE_ID"]
local PLACE_ID = process.env["RBX_PLACE_ID"]

assert(API_KEY, "RBX_API_KEY env var not set")
assert(UNIVERSE_ID, "RBX_UNIVERSE_ID env var not set")
assert(PLACE_ID, "RBX_PLACE_ID env var not set")

local rbxl_path = process.args[1]
assert(rbxl_path, "usage: lune run run-tests <path-to-rbxl>")
assert(fs.isFile(rbxl_path), `file not found: {rbxl_path}`)

print("Uploading test place...")
local rbxl_content = fs.readFile(rbxl_path)
local upload_url =
	`https://apis.roblox.com/universes/v1/{UNIVERSE_ID}/places/{PLACE_ID}/versions?versionType=Saved`

local result = net.request({
	method = "POST",
	url = upload_url,
	body = rbxl_content,
	headers = {
		["Content-Type"] = "application/xml",
		["x-api-key"] = API_KEY,
	},
})
if not result.ok then
	stdio.ewrite(`Failed to upload test place: {result.statusCode} {result.statusMessage}\n{result.body}\n`)
	process.exit(1)
end
print("Test place uploaded.")

local test_script = fs.readFile("run-tests.server.luau")

print("Creating test execution task...")
local task = luau_execute.create_task_latest(UNIVERSE_ID, PLACE_ID, test_script, 300)

print("Waiting for tests to finish...")
local success = luau_execute.await_finish(task)

print("\nTest output:")
for _, log in luau_execute.get_structured_logs(task) do
	if log.messageType == "ERROR" then
		stdio.write(stdio.color("red"))
	elseif log.messageType == "WARNING" then
		stdio.write(stdio.color("yellow"))
	end
	stdio.write(log.message .. "\n")
	stdio.write(stdio.color("reset"))
end

if not success then
	local err = luau_execute.get_error(task)
	if err then
		stdio.ewrite(`\nTest task failed: {err.code} - {err.message}\n`)
	end
	process.exit(1)
end

print("\nAll tests passed.")
