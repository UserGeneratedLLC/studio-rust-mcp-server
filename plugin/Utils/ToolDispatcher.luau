--!strict

export type ToolFunction = (any) -> string?

local tools: { [string]: ToolFunction } = {}
for _, child in script.Parent.Parent.Tools:GetChildren() do
  if child:IsA("ModuleScript") and child:GetAttribute("Enabled") ~= false then
    local tool = require(child) :: any
    assert(type(tool) == "function", `{child.Name} must return a function`)
    tools[child.Name] = tool
  end
end
table.freeze(tools)

local function dispatchTool(toolName: string, args: any): string?
  local toolFunction: ToolFunction = tools[toolName]
  if not toolFunction then
    error(`Tool "{toolName}" not found`)
  end
  return toolFunction(args)
end

return {
  tools = tools,
  dispatchTool = dispatchTool,
}
