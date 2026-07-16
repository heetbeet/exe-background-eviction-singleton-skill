---
name: exe-background-eviction-singleton
description: Wrap a Windows app as a portable, windowless ExeWrap background executable that evicts prior runs of the same stamped executable path and starts a fresh supervised run. Use when asked to create a background .exe, a best-effort singleton launcher, or an eviction-singleton wrapper for a Windows application; use only when forcefully stopping prior same-path runs is acceptable.
---

# Exe Background Eviction Singleton

Create a best-effort *eviction singleton*, not a strict singleton: a new launch finds and terminates older launcher processes whose `Win32_Process.ExecutablePath` is the same canonical full path as the stamped launcher, then starts the app.

Use this only for Windows and only when the app owner accepts forceful termination. It deliberately has no mutex, PID file, lock, service registration, or cross-install identity. Concurrent launches can race; the desired outcome is that a newly started launch evicts older same-path launches.

## Inputs To Establish

Get or infer:

- the target command and its required arguments;
- the portable bundle layout and working directory;
- whether the target needs a restart supervisor or is itself the long-running worker;
- the launcher filename and final output path;
- whether terminating the previous process tree is safe.

Do not add application dependency installation, Startup-folder registration, scheduled tasks, ports, or process-name matching unless the user separately asks for them.

## Build The Launcher

1. Obtain the current pinned ExeWrap release and verify its published checksum before using it.
2. Copy [`scripts/evict-prior-launchers.ps1`](scripts/evict-prior-launchers.ps1) into the target bundle next to the launcher or its supervisor script.
3. In the first lines of the supervisor, invoke it with the launcher's exact path injected through `SINGLETON_OWNER_EXE`:

   ```powershell
   & "$PSScriptRoot\evict-prior-launchers.ps1" -OwnerExePath $env:SINGLETON_OWNER_EXE
   ```

4. Stamp `ExeWrap-windowed.exe` with `kill_children_on_exit: true`. Set `SINGLETON_OWNER_EXE` to `@{exe_path}` and use only executable-relative paths.
5. Validate the stamped launcher from a path containing spaces. Launch it twice and confirm that the second run terminates the first process tree and leaves one active run.

Use [`assets/background-launcher.config.json.template`](assets/background-launcher.config.json.template) as the config shape. Replace the marked supervisor path and command; preserve the owner-path environment value and Job Object setting.

## Ownership Rule

Match candidates by `Win32_Process.ExecutablePath`, normalized to a full path and compared case-insensitively. Do not match by filename, PowerShell command line, port, module name, or a hand-written process list.

`@{exe_path}` identifies the currently stamped ExeWrap executable. ExeWrap does not enumerate other PIDs itself; it injects this path into its child environment. The PowerShell helper then reads the full executable path recorded by Windows for each candidate PID. This remains safe when two unrelated launchers happen to share a filename.

Avoid treating this as cryptographic proof of ownership: a process using the exact same launcher path is intentionally in scope, and a concurrent launch can race. That is the accepted trade-off for this lightweight pattern.

## Deliverables

Produce the stamped executable, its config/source files, the supervisor or target script, a stop instruction, and a short note naming the exact eviction scope: "same canonical stamped-executable path."
