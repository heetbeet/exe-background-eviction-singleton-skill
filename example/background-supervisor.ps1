$ErrorActionPreference = "Stop"

& "$PSScriptRoot\evict-prior-launchers.ps1" -OwnerExePath $env:SINGLETON_OWNER_EXE
& "$PSScriptRoot\heartbeat.bat"
