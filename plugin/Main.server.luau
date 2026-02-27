--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local StudioService = game:GetService("StudioService")

local ConsoleOutput = require(script.Parent.Utils.ConsoleOutput)
local DataModelType = require(script.Parent.Utils.DataModelType)
local GameStopUtil = require(script.Parent.Utils.GameStopUtil)
local MockWebSocketService = require(script.Parent.MockWebSocketService)
local PluginUtils = require(script.Parent.Utils.PluginUtils)
local ToolDispatcher = require(script.Parent.Utils.ToolDispatcher)

local URI = "http://localhost:44755"
local RECEIVE_ENDPOINT = "/request"
local SEND_ENDPOINT = "/response"
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

local function connectWebSocket()
  local client = MockWebSocketService:CreateClient(URI)
  client:SetReceiveEndpoint(RECEIVE_ENDPOINT)
  client:SetSendEndpoint(SEND_ENDPOINT)

  client.Opened:Once(function()
    log("[MCP] Connection opened")
  end)

  client.Closed:Once(function()
    log("[MCP] Connection closed")
  end)

  client.MessageReceived:Connect(function(message)
    log("[MCP] Message received")

    local body = HttpService:JSONDecode(message)
    assert(body and body.id and body.tool and body.args, "Invalid message received")

    local id: string = body.id
    local responseSent = false
    local function sendResponseOnce(success: boolean, response: string)
      if not responseSent then
        log("[MCP] Sending response:", response)
        responseSent = true
        client:Send({
          id = id,
          success = success,
          response = response,
        })
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

local function getButtonImage()
  local ok, response = pcall(function()
    return StudioService:GetClassIcon("PackageLink").Image
  end)
  return ok and response or "rbxasset://textures/ui/GuiImagePlaceholder.png"
end

local toolbar = plugin:CreateToolbar("MCP")
local toggleButton =
  toolbar:CreateButton("Toggle MCP", "Toggle connection to the server", getButtonImage())
toggleButton.ClickableWhenViewportHidden = true

local currentClient: MockWebSocketService.MockWebSocketClient?

if not plugin:GetSetting(PLUGIN_DISABLED_SETTING_KEY) then
  currentClient = connectWebSocket()
  print("The MCP Studio plugin is ready for prompts.")
end

toggleButton:SetActive(currentClient ~= nil)

toggleButton.Click:Connect(function()
  if not currentClient then
    currentClient = connectWebSocket()
    print("The MCP Studio plugin is ready for prompts.")
  else
    currentClient:Close()
    currentClient = nil
    print("The MCP Studio plugin is stopped.")
  end
  toggleButton:SetActive(currentClient ~= nil)
  plugin:SetSetting(PLUGIN_DISABLED_SETTING_KEY, currentClient == nil)
end)
