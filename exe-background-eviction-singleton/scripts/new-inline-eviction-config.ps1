[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputConfig,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkerRelativePath,

    [ValidateSet("auto", "batch", "executable")]
    [string]$WorkerKind = "auto",

    [string[]]$WorkerArguments = @(),

    [switch]$AllowParentWorkerPath,

    [switch]$DisableLauncherLog,

    [ValidateSet("never", "on-failure", "always")]
    [string]$RestartPolicy = "on-failure",

    [ValidateRange(1, 3600)]
    [int]$RestartDelaySeconds = 5
)

$ErrorActionPreference = "Stop"

function Test-WorkerRelativePath {
    param([string]$RelativePath)

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "WorkerRelativePath must be relative to the stamped executable."
    }

    $segments = @($RelativePath -split '[\\/]' | Where-Object { $_ })
    $invalidSegments = @($segments | Where-Object {
        $_ -eq '.' -or
        ($_ -eq '..' -and -not $AllowParentWorkerPath) -or
        ($_ -ne '..' -and $_ -match '[\\/:*?"<>|]')
    })
    if ($segments.Count -eq 0 -or $invalidSegments.Count -gt 0) {
        throw "WorkerRelativePath contains an invalid path segment."
    }

}

Test-WorkerRelativePath $WorkerRelativePath
$workerRelativePathJson = $WorkerRelativePath | ConvertTo-Json -Compress
$workerArgumentsJson = ConvertTo-Json -InputObject ([object[]]$WorkerArguments) -Compress
$workerArgumentsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($workerArgumentsJson))
if ($WorkerKind -eq "auto") {
    $extension = [System.IO.Path]::GetExtension($WorkerRelativePath)
    $WorkerKind = if ($extension -in @(".bat", ".cmd")) { "batch" } else { "executable" }
}

$workerInvocation = if ($WorkerKind -eq "batch") {
@'
$childArgs = @('/d', '/c', $WorkerPath) + @($WorkerArgs)
& $env:ComSpec @childArgs
'@
} else {
@'
& $WorkerPath @WorkerArgs
'@
}

if ($DisableLauncherLog) {
    $logSetup = ''
    $logEviction = ''
    $logStarting = ''
    $logFailure = ''
    $logExited = ''
    $logRestarting = ''
} else {
    $logSetup = @'
$LogPath = Join-Path (Split-Path -Parent $OwnerExePath) 'launcher.log'

function Write-LauncherLog {
    param([string]$Message)
    try {
        Add-Content -LiteralPath $LogPath -Value "[$([DateTime]::UtcNow.ToString('o'))] $Message" -ErrorAction Stop
    } catch {
    }
}
'@
    $logEviction = 'Write-LauncherLog "Evicting launcher PID $($priorLauncher.ProcessId)."'
    $logStarting = 'Write-LauncherLog "Starting worker."'
    $logFailure = 'Write-LauncherLog "Worker invocation failed: $($_.Exception.Message)"'
    $logExited = 'Write-LauncherLog "Worker exited with code $exitCode."'
    $logRestarting = 'Write-LauncherLog "Restarting worker after __RESTART_DELAY__ seconds."'
}

$restartCondition = switch ($RestartPolicy) {
    "never" { '$false' }
    "on-failure" { '$exitCode -ne 0' }
    "always" { '$true' }
}

$inline = @'
$ErrorActionPreference = 'Stop'
$OwnerExePath = ConvertFrom-Json '"__OWNER_PATH__"'
$WorkerRelativePath = ConvertFrom-Json '__WORKER_RELATIVE_PATH_JSON__'
$WorkerPath = Join-Path (Split-Path -Parent $OwnerExePath) $WorkerRelativePath
$DefaultArgs = @(ConvertFrom-Json ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__DEFAULT_ARGS_BASE64__'))))
$ForwardedArgs = ConvertFrom-Json '__FORWARDED_ARGS__'
$WorkerArgs = @($DefaultArgs) + @($ForwardedArgs)
__LOG_SETUP__

function Get-CanonicalPath {
    param([string]$Path)
    [System.IO.Path]::GetFullPath($Path).TrimEnd("\\")
}

function Stop-ProcessTree {
    param([int]$ProcessId, [System.Collections.Generic.HashSet[int]]$Visited)
    if (!$Visited.Add($ProcessId)) {
        return
    }

    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        Stop-ProcessTree -ProcessId $child.ProcessId -Visited $Visited
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

$ownerPath = Get-CanonicalPath $OwnerExePath
$launcherPid = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
$priorLaunchers = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    if ($_.ProcessId -eq $PID -or $_.ProcessId -eq $launcherPid -or [string]::IsNullOrWhiteSpace($_.ExecutablePath)) {
        return $false
    }
    try {
        [string]::Equals((Get-CanonicalPath $_.ExecutablePath), $ownerPath, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        $false
    }
})

$visited = [System.Collections.Generic.HashSet[int]]::new()
foreach ($priorLauncher in $priorLaunchers | Sort-Object ProcessId -Descending) {
    __LOG_EVICTION__
    Stop-ProcessTree -ProcessId $priorLauncher.ProcessId -Visited $visited
}

while ($true) {
    __LOG_STARTING__
    try {
__WORKER_INVOCATION__
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    } catch {
        $exitCode = 1
        __LOG_FAILURE__
    }

    __LOG_EXITED__
    if (!(__RESTART_CONDITION__)) {
        exit $exitCode
    }

    __LOG_RESTARTING__
    Start-Sleep -Seconds __RESTART_DELAY__
}
'@

$inline = $inline.Replace("__OWNER_PATH__", "@{exe_path:json}")
$inline = $inline.Replace("__WORKER_RELATIVE_PATH_JSON__", $workerRelativePathJson)
$inline = $inline.Replace("__DEFAULT_ARGS_BASE64__", $workerArgumentsBase64)
$inline = $inline.Replace("__FORWARDED_ARGS__", "@{args_as_json}")
$inline = $inline.Replace("__LOG_SETUP__", $logSetup.TrimEnd())
$inline = $inline.Replace("__LOG_EVICTION__", $logEviction)
$inline = $inline.Replace("__LOG_STARTING__", $logStarting)
$inline = $inline.Replace("__LOG_FAILURE__", $logFailure)
$inline = $inline.Replace("__LOG_EXITED__", $logExited)
$inline = $inline.Replace("__LOG_RESTARTING__", $logRestarting)
$inline = $inline.Replace("__WORKER_INVOCATION__", $workerInvocation.TrimEnd())
$inline = $inline.Replace("__RESTART_CONDITION__", $restartCondition)
$inline = $inline.Replace("__RESTART_DELAY__", $RestartDelaySeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture))

$config = [ordered]@{
    kill_children_on_exit = $true
    cwd = "@{exe_dir}"
    command = @(
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        $inline
    )
}

$directory = Split-Path -Parent $OutputConfig
if ($directory) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}
$config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputConfig -Encoding utf8
