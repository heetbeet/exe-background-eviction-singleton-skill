[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OwnerExePath
)

$ErrorActionPreference = "Stop"

function Get-CanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd("\\")
}

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        Stop-ProcessTree -ProcessId $child.ProcessId
    }

    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

$ownerPath = Get-CanonicalPath $OwnerExePath
$launcherPid = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId

$priorLaunchers = @(
    Get-CimInstance Win32_Process | Where-Object {
        if ($_.ProcessId -eq $PID -or $_.ProcessId -eq $launcherPid -or [string]::IsNullOrWhiteSpace($_.ExecutablePath)) {
            return $false
        }

        try {
            return [string]::Equals(
                (Get-CanonicalPath $_.ExecutablePath),
                $ownerPath,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        } catch {
            return $false
        }
    }
)

foreach ($priorLauncher in $priorLaunchers | Sort-Object ProcessId -Descending) {
    Write-Host "Evicting prior launcher PID $($priorLauncher.ProcessId): $ownerPath"
    Stop-ProcessTree -ProcessId $priorLauncher.ProcessId
}
