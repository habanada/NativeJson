# Compatibility

| Toolchain | Platform | Configuration | Verification |
| --- | --- | --- | --- |
| Delphi 12 Community Edition | Win32 | Debug | `NativeJson.groupproj` (38 projects) compiled in the IDE by the maintainer on 2026-11-12, after the English renaming. |
| Delphi 12 Community Edition | Win64 | Debug | Same as Win32. |
| FPC 3.3.1 trunk (build 62b8ab000e) | Win64 | default, `-B` | 33 programs built and run on 2026-11-11 after the English renaming; `Tests/NativeJson_Xml` on 2026-11-12; results in [TESTING.md](TESTING.md). |
| FPC | Win32 | – | Not run |
| FPC | Linux | – | Not run |

Not supported under FPC: `NativeJson.Converters.Vcl`, `.Graphics`, `.Fmx`, programs that use `Winapi.PsAPI`. See [fpcReadme.md](fpcReadme.md).

`NativeJson.SystemJson` and `NativeJson.Xml` were added after that build. Their test programs were compiled in the IDE (Win64 Debug) on 2026-11-12 and run: `Tests/NativeJson_SystemJson` 18/18, `Tests/NativeJson_Xml` 59/59, no leak report.

Update only after reproducible compiler/runtime tests. The matrix is not a support promise.
