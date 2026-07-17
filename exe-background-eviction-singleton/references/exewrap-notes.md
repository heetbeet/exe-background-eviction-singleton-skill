# ExeWrap Runtime Notes

Use a checksum-verified current ExeWrap release. Stamp `ExeWrap-windowed.exe` and set `kill_children_on_exit` to `true`; this puts the PowerShell command and its worker tree in a Windows Job Object.

The inline command recovers its own path with:

```powershell
$OwnerExePath = ConvertFrom-Json '"@{exe_path:json}"'
```

The extra quote layer is intentional. In an ExeWrap templated JSON string, the `json` transform provides escaped JSON-string content; `ConvertFrom-Json` needs the JSON quote delimiters supplied by the PowerShell source.

Forward all launch arguments using:

```powershell
$ForwardedArgs = ConvertFrom-Json '@{args_as_json}'
```

`args_as_json` is designed for single-quoted PowerShell source. For batch workers, call `cmd.exe` through a native PowerShell argument array rather than `Start-Process -ArgumentList`, whose string joining can change quoting.

The generated config can include fixed worker arguments before those forwarded at launch. This is useful for wrappers around interpreters, for example a sibling `..\venv\Scripts\python.exe` with `pilot-poller.py` as its fixed argument. Parent traversal in the worker path requires the generator's explicit `-AllowParentWorkerPath` switch.

The config file is consumed only by the stamper. The stamped executable contains the inline command and does not need the sidecar JSON at runtime.
