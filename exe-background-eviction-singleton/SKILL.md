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

Use [`scripts/new-inline-eviction-config.ps1`](scripts/new-inline-eviction-config.ps1) to produce the ExeWrap config. It validates a relative worker path, embeds the eviction implementation, forwards launcher arguments, writes a launcher log, and selects batch/executable invocation safely.

Example:

```powershell
& .\new-inline-eviction-config.ps1 `
  -OutputConfig .\worker.config.json `
  -WorkerRelativePath worker\service.exe `
  -WorkerKind executable `
  -RestartPolicy on-failure `
  -RestartDelaySeconds 5
```

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

## Boundaries

The ownership scope is exactly "same canonical stamped-executable path." It avoids clashes with another identically named `.exe` elsewhere, but it intentionally evicts any process actually launched from that same path. It is designed for normal same-user operation; process metadata can be unavailable across users or elevation boundaries.
