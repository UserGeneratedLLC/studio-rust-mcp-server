--!strict

export type TestMode = "start_play" | "run_server"
export type StartStopPlayMode = TestMode | "stop"

export type GlobalVariables = {
  studioMode: StartStopPlayMode,
}

local GlobalVariables = {
  studioMode = "stop",
}

return GlobalVariables
