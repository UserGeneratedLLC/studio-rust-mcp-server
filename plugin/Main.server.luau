--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local StudioService = game:GetService("StudioService")

local ConsoleOutput = require("./Utils/ConsoleOutput")
local DataModelType = require("./Utils/DataModelType")
local GameStopUtil = require("./Utils/GameStopUtil")
local PluginUtils = require("./Utils/PluginUtils")
local ToolDispatcher = require("./Utils/ToolDispatcher")
local msgpack = require("./msgpack")

local WS_URI = "ws://localhost:44755/ws"
local PLUGIN_DISABLED_SETTING_KEY = "Disabled-MCP-plugin-setting"

PluginUtils.plugin = plugin

local datamodelType = DataModelType.getDataModelType()

if datamodelType == "Server" then
  task.spawn(GameStopUtil.monitorForStopPlay)
end

if RunService:IsRunning() then
  return
end

local connMessageOut = ConsoleOutput.startListener()
plugin.Unloading:Connect(function()
  connMessageOut:Disconnect()
end)

local old_warn = warn
local function log(...)
  if false then
    old_warn(...)
  end
end

local function connectToServer(): any
  local client = HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
    Url = WS_URI,
  })

  client.Opened:Connect(function(_statusCode, _headers)
    log("[MCP] Connection opened, sending registration")
    client:Send(msgpack.encode({
      type = "register",
      place_id = game.PlaceId,
      place_name = game.Name,
      game_id = game.GameId,
      job_id = game.JobId,
      place_version = game.PlaceVersion,
      creator_id = game.CreatorId,
      creator_type = tostring(game.CreatorType),
    }))
  end)

  client.Closed:Connect(function()
    log("[MCP] Connection closed")
  end)

  client.Error:Connect(function(statusCode, errorMessage)
    warn("[MCP] Connection error:", statusCode, errorMessage)
  end)

  client.MessageReceived:Connect(function(message: string)
    log("[MCP] Message received")

    local body = msgpack.decode(message)

    if body and body.type == "registered" then
      log("[MCP] Registered with studio_id:", body.studio_id)
      return
    end

    assert(body and body.id and body.tool and body.args, "Invalid message received")

    local id: string = body.id
    local responseSent = false
    local function sendResponseOnce(success: boolean, response: string)
      if not responseSent then
        log("[MCP] Sending response:", response)
        responseSent = true
        client:Send(msgpack.encode({
          id = id,
          success = success,
          response = response,
        }))
      end
    end

    local recording = ChangeHistoryService:TryBeginRecording("StudioMCP")
    local success, response = pcall(ToolDispatcher.dispatchTool, body.tool, body.args)
    if recording then
      ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
    end
    sendResponseOnce(success, response or "")

    log("[MCP] Successfully handled request")
  end)

  return client
end

local function getButtonImage(): string
  local ok, response = pcall(function()
    return StudioService:GetClassIcon("PackageLink").Image
  end)
  return ok and response or "rbxasset://textures/ui/GuiImagePlaceholder.png"
end

local toolbar = plugin:CreateToolbar("MCP")
local toggleButton =
  toolbar:CreateButton("Toggle MCP", "Toggle connection to the server", getButtonImage())
toggleButton.ClickableWhenViewportHidden = true

local currentClient: any = nil

if not plugin:GetSetting(PLUGIN_DISABLED_SETTING_KEY) then
  currentClient = connectToServer()
  print("The MCP Studio plugin is ready for prompts.")
end

toggleButton:SetActive(currentClient ~= nil)

toggleButton.Click:Connect(function()
  if not currentClient then
    currentClient = connectToServer()
    print("The MCP Studio plugin is ready for prompts.")
  else
    currentClient:Close()
    currentClient = nil
    print("The MCP Studio plugin is stopped.")
  end
  toggleButton:SetActive(currentClient ~= nil)
  plugin:SetSetting(PLUGIN_DISABLED_SETTING_KEY, currentClient == nil)
end)
