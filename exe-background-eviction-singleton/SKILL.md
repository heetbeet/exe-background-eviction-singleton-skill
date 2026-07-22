---
name: exe-background-eviction-singleton
description: Create Windows ExeWrap windowed background launchers that evict prior runs of the same canonical stamped-executable path. Use when asked to wrap a Windows worker, batch file, or service as a portable best-effort singleton background .exe with optional restart-on-failure and forwarded command-line arguments.
---

# Exe Background Eviction Singleton

Build an *eviction singleton*: a new launch forcefully terminates old runs of the same canonical stamped-executable path, then starts the worker. This is deliberately not a strict singleton: concurrent launches may race, and no mutex, PID file, lockfile, service, or registry state is created.

Use the inline pattern by default. The generated stamped executable carries the complete PowerShell eviction and restart implementation; the deployed bundle does not need an eviction or supervisor `.ps1` file.

## Establish Inputs

Determine the worker's relative path, whether it is a batch file or executable, its default arguments, and its restart policy:

- `on-failure` is the default for a background service: restart after a non-zero exit with a bounded delay.
- `always` restarts even after exit code zero; use only when zero means an unexpected service stop.
- `never` is for one-shot workers.

Do not add Startup integration, dependency installation, port ownership, process-name matching, or a persistent lock unless the user separately asks.

## Generate The Inline Config

Use [`scripts/new-inline-eviction-config.ps1`](scripts/new-inline-eviction-config.ps1) to produce the ExeWrap config. It validates a relative worker path, embeds the eviction implementation, combines configured default arguments with forwarded launcher arguments, optionally writes a launcher log, and selects batch/executable invocation safely.

Example:

```powershell
& .\new-inline-eviction-config.ps1 `
  -OutputConfig .\worker.config.json `
  -WorkerRelativePath worker\service.exe `
  -WorkerArguments @('--config', 'service.json') `
  -WorkerKind executable `
  -RestartPolicy on-failure `
  -RestartDelaySeconds 5
```

Use `-DisableLauncherLog` for a silent wrapper that creates no `launcher.log`. Use `-AllowParentWorkerPath` only when the worker intentionally lives outside the executable directory, such as `..\venv\Scripts\python.exe`. Parent traversal remains rejected by default.

Use `-FailureToastTitle 'Platform poller error'` when a long-running desktop worker should visibly report a non-zero exit. The embedded Windows Runtime notification does not depend on the worker or its environment, includes only the stamped executable name and exit code, and is best-effort: notification failure never changes supervision. Repeated errors are suppressed for five minutes by default; change this with `-FailureToastCooldownSeconds`. Set `-FailureToastAppId` when the notification should have a platform-specific sender name.

Stamp the result with a checksum-verified current ExeWrap release:

```powershell
& ExeWrap-stamper.exe `
  --launcher ExeWrap-windowed.exe `
  --config .\worker.config.json `
  --subsystem windowed `
  .\worker-background.exe
```

## Inline Runtime Contract

The generated command uses all of the following:

- `kill_children_on_exit: true`, so ExeWrap's Windows Job Object owns the worker tree.
- `Win32_Process.ExecutablePath`, normalized and compared case-insensitively, to select eviction targets. Never match filename or command-line text.
- `$OwnerExePath = ConvertFrom-Json '"@{exe_path:json}"'` to recover the full current stamped-executable path.
- `$ForwardedArgs = ConvertFrom-Json '@{args_as_json}'` to recover every user-supplied launcher argument.
- Configured `WorkerArguments` precede forwarded launcher arguments, so a Python interpreter can have a fixed entry script while still accepting CLI options.
- When failure toasts are enabled, a non-zero exit is reported before the restart/exit decision. Toasts contain no worker output, arguments, paths, or secrets, and an in-memory cooldown prevents a crash loop from creating a notification storm.

For a batch worker, the generated code builds a native command argument array and invokes `cmd.exe` directly:

```powershell
$childArgs = @('/d', '/c', $WorkerPath) + @($ForwardedArgs)
& $env:ComSpec @childArgs
```

Do not use `Start-Process -ArgumentList` for forwarded user arguments unless its quoting behaviour has been specifically tested for the target. The native invocation above preserves PowerShell's argument-array handling and waits for the batch process.

## Validate Before Hand-off

1. Parse the generated JSON and stamp a console launcher first when diagnosing errors.
2. Stamp the windowed launcher.
3. Run it from a path containing spaces.
4. Launch it twice. Confirm that only the second launcher PID has the stamped executable's `ExecutablePath` and that the first worker tree stopped.
5. Run it with arguments containing spaces and shell metacharacters; verify the worker receives them exactly.
6. Make the worker exit non-zero once; confirm the configured restart delay and `launcher.log` entry. Confirm a zero exit follows the selected policy.
7. If failure toasts are enabled, confirm the first non-zero exit produces a notification and repeated failures inside the cooldown do not. Also confirm a toast API failure does not change the worker's restart or exit behavior.

When launcher logging is disabled, instead confirm that no `launcher.log` is created and inspect the worker's own log or observable output. The config JSON is a stamping artifact, not a runtime dependency; do not deploy it when a clean bundle is wanted.

## Starting Through OpenSSH

A process started with `Start-Process` inside a short-lived OpenSSH command may be terminated when that SSH command ends. For a background launcher that must survive the session, create it with WMI/CIM and then verify it from a fresh SSH connection:

```powershell
$commandLine = '"' + $launcherPath + '"'
$result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $commandLine }
if ($result.ReturnValue -ne 0) { throw "Win32_Process.Create failed: $($result.ReturnValue)" }
```

Do not use `Pid` as a PowerShell parameter or loop variable name: variable names are case-insensitive and the automatic `$PID` variable is read-only. Prefer `ProcessId` or `ProcessIdentifier`.

## Boundaries

The ownership scope is exactly "same canonical stamped-executable path." It avoids clashes with another identically named `.exe` elsewhere, but it intentionally evicts any process actually launched from that same path. It is designed for normal same-user operation; process metadata can be unavailable across users or elevation boundaries.
