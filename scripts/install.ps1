#Requires -Version 5.1

param([string]$Mode = "release")

$InstallDir = "C:\Program Files\Atlas"

Set-Location "$PSScriptRoot\.."
if ($Mode -eq "release") {
  cargo build --release --config "profile.release.debug=true"
} else {
  cargo build "--$Mode"
}

$Exe = ".\target\$Mode\rbx-studio-mcp.exe"

gsudo Stop-Process -Name "rbx-studio-mcp" -Force -ErrorAction SilentlyContinue
gsudo New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
gsudo Copy-Item "$Exe" "$InstallDir\"
gsudo Copy-Item ".\target\$Mode\rbx-studio-mcp.pdb" "$InstallDir\"

$MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($MachinePath -notlike "*$InstallDir*") {
  gsudo [Environment]::SetEnvironmentVariable "Path" "$MachinePath;$InstallDir" "Machine"
  Write-Host "Added '$InstallDir' to system PATH"
}
