# Exe Background Eviction Singleton Skill

A Codex skill for creating portable Windows background executables with [ExeWrap](https://github.com/AutoActuary/ExeWrap).

The default deployment is a windowed stamped executable containing its full PowerShell runtime: it evicts prior runs of the same canonical launcher path, forwards command-line arguments, writes `launcher.log`, and restarts a worker according to a chosen policy.

It is an eviction singleton, not a strict singleton. It intentionally avoids mutexes, PID files, lockfiles, services, and registry state.

## Use

Install or copy [`exe-background-eviction-singleton`](./exe-background-eviction-singleton) as a Codex skill. Ask Codex to wrap a Windows worker as a singleton background executable.

The skill's generator creates a config with these defaults:

- inline eviction implementation;
- path-scoped matching through `Win32_Process.ExecutablePath`;
- ExeWrap Job Object cleanup;
- forwarded launcher arguments;
- `on-failure` restart after a five-second delay.

Choose `never` for a one-shot worker or `always` only when every worker exit should restart it.

## Scope

Only processes started from the same canonical stamped-executable path are eligible for eviction. Identically named executables elsewhere are not matched. Concurrent starts can race by design.
