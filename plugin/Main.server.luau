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
local msgpack = require("./Utils/msgpack")

local WS_URI = "ws://localhost:44756/ws"
local PLUGIN_DISABLED_SETTING_KEY = "Disabled-MCP-plugin-setting"
local RECONNECT_INTERVAL = 5

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

local function connectToServer(): (any, BindableEvent, () -> boolean)
  local disconnectEvent = Instance.new("BindableEvent")
  local connected = false

  local client = HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
    Url = WS_URI,
    Compress = Enum.HttpCompression.Gzip,
  })

  client.Opened:Connect(function(_statusCode, _headers)
    connected = true
    log("[MCP] Connection opened, sending registration")
    client:Send(msgpack.encodeb64({
      type = "register",
      place_id = msgpack.uint64(game.PlaceId),
      place_name = game.Name,
      game_id = msgpack.uint64(game.GameId),
      job_id = game.JobId,
      place_version = msgpack.uint64(game.PlaceVersion),
      creator_id = msgpack.uint64(game.CreatorId),
      creator_type = game.CreatorType.Name,
    }))
    print("[MCP] Connected to server.")
  end)

  client.Closed:Connect(function()
    log("[MCP] Connection closed")
    disconnectEvent:Fire()
  end)

  client.Error:Connect(function(_statusCode, _errorMessage)
    disconnectEvent:Fire()
  end)

  client.MessageReceived:Connect(function(message: string)
    log("[MCP] Message received")

    local body = msgpack.decodeb64(message)

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
        client:Send(msgpack.encodeb64({
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

  return client, disconnectEvent, function()
    return connected
  end
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

local connectionLoop: thread? = nil
local currentClient: any = nil

local function startConnectionLoop()
  connectionLoop = task.spawn(function()
    while true do
      local client, disconnectEvent, wasConnected = connectToServer()
      currentClient = client
      disconnectEvent.Event:Wait()
      currentClient = nil
      if wasConnected() then
        warn("[MCP] Disconnected from server. Reconnecting in " .. RECONNECT_INTERVAL .. "s...")
      end
      pcall(function()
        client:Close()
      end)
      task.wait(RECONNECT_INTERVAL)
    end
  end)
end

local function stopConnectionLoop()
  if connectionLoop then
    task.cancel(connectionLoop)
    connectionLoop = nil
  end
  if currentClient then
    pcall(function()
      currentClient:Close()
    end)
    currentClient = nil
  end
end

if not plugin:GetSetting(PLUGIN_DISABLED_SETTING_KEY) then
  startConnectionLoop()
end

toggleButton:SetActive(connectionLoop ~= nil)

toggleButton.Click:Connect(function()
  if not connectionLoop then
    startConnectionLoop()
    print("The MCP Studio plugin is enabled.")
  else
    stopConnectionLoop()
    print("The MCP Studio plugin is stopped.")
  end
  toggleButton:SetActive(connectionLoop ~= nil)
  plugin:SetSetting(PLUGIN_DISABLED_SETTING_KEY, connectionLoop == nil)
end)
