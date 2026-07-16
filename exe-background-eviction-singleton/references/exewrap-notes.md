# ExeWrap Notes

Use `ExeWrap-windowed.exe` for the stamped background launcher. The windowed subsystem avoids a console window; its child has no inherited standard streams.

Set `kill_children_on_exit` to `true`. ExeWrap creates a Windows Job Object and places its child in it, so killing the launcher terminates the child process tree.

Use `@{exe_path}` to pass the full stamped executable path to the supervisor via an environment value. `@{exe_dir}` follows the final executable location and keeps the bundle portable.

ExeWrap does not provide a cross-PID singleton API. The eviction helper owns that policy by querying Windows' `Win32_Process.ExecutablePath`; do not degrade this to command-line or filename matching.
