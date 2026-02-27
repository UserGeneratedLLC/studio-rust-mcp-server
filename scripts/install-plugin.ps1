#Requires -Version 5.1

# Builds and installs the Roblox Studio plugin (MCPStudioPlugin.rbxm)
# Usage: .\scripts\install-plugin.ps1

Set-Location "$PSScriptRoot\.."

$PluginsDir = "$env:LOCALAPPDATA\Roblox\Plugins"

rojo sourcemap plugin.project.json -o sourcemap.json
if ($LASTEXITCODE -ne 0) {
  Write-Host "Failed to generate sourcemap" -ForegroundColor Red
  exit 1
}

if (Test-Path "plugin-build") { Remove-Item -Recurse -Force "plugin-build" }
darklua process --config .darklua.json plugin plugin-build
if ($LASTEXITCODE -ne 0) {
  Write-Host "Failed to process requires with darklua" -ForegroundColor Red
  exit 1
}

rojo build plugin-build.project.json -o MCPStudioPlugin.rbxm
if ($LASTEXITCODE -ne 0) {
  Write-Host "Failed to build plugin" -ForegroundColor Red
  exit 1
}

New-Item -ItemType Directory -Path $PluginsDir -Force | Out-Null
Copy-Item "MCPStudioPlugin.rbxm" "$PluginsDir\"

Write-Host "Installed MCPStudioPlugin.rbxm to $PluginsDir" -ForegroundColor Green
