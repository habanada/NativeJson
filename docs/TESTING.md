# Testing

## Policy

Use deterministic tests, explicit fault-injection boundaries, platform integration tests and measured performance tests where applicable. Keep existing regression tests. Never change an expected value only to make a test green.

## Self-checking programs

The demos and `Tests/Package2` use `examples/Demos/Demo.Assert.pas`. Every check prints `[OK]` or `[FAIL]` with expected and received value, the program ends with `RESULT: n passed, m failed` and returns exit code 0 only when all checks passed. Started with any parameter (`auto`), the program does not wait for Enter.

| Project | Purpose | Dependencies |
| --- | --- | --- |
| `examples/Demos/Demo01_Basics` .. `Demo15_WhatsNew` | Feature walk-through with checks | None |
| `Tests/Package2/Test2_NumberFormats` | Number limits and notations | None |
| `Tests/Package2/Test2_NullAndEmpty` | null vs. empty vs. missing | None |
| `Tests/Package2/Test2_Characters` | Escaping, Unicode, buffer chunk limits | None |
| `Tests/Package2/Test2_Accessors` | `[JsonGetter]`/`[JsonSetter]` | None |
| `Tests/Package2/Test2_SchemaValidator` | JSON Schema validation | None |
| `Tests/Package2/Test2_Json5` | JSON5 switch | None |

## Other programs

| Project | Purpose | Dependencies |
| --- | --- | --- |
| `Tests/NativeJson_Pointer`, `_Patch`, `_Diff`, `_DeepEquals`, `_ObjectPatch` | RFC 6901/6902, diff, semantic equality | None |
| `Tests/NativeJson_SystemJson` | `System.JSON` interop: conversion, exact numbers, schema validation, registered schemas, nil arguments; uses `Demo.Assert` (`RESULT` line) | Delphi (`System.JSON`, dotted unit names) |
| `Tests/NativeJson_Cbor` | CBOR: RFC 8949 Appendix A vectors (integers, floats, strings, containers, indefinite lengths, tags), preferred and deterministic encoding, exact decimals, byte and tag wrappers, malformed and hostile input, sequences, objects, 3000 random round trips, 4000 mutated inputs; uses `Demo.Assert` | None |
| `Tests/NativeJson_Xml` | XML to JSON and back: mapping, options, entities, CDATA, malformed and unsafe XML (DTD entities, depth), escaping, name encoding, round trips; uses `Demo.Assert` | None |
| `examples/Showcase/NativeJson_Showcase` | The README snippets as checks: object mapping, object patch, query chain with `Remove`/`Replace`, schema and exact numbers, code generation with external reference and OpenAPI, sequence reading, attribute validation, XML; uses `Demo.Assert` | None |
| `Tests/NativeJsonFinalTest` | Combined feature checks | None |
| `Tests/TestFeatures` | Feature checks | None |
| `Tests/AttribInheritInterfacesStreamsTest/NativeJson_Tests` | Integration suite | None |
| `Tests/Package3/Package3_CodeGen` | Code generator suite | DUnitX |
| `Tests/MemoryTest/NativeJson_MemoryTest` | Working set over many rounds, `ReportMemoryLeaksOnShutdown` | Windows (`Winapi.PsAPI`) |
| `Benchmarks/JsonDeathmatch` | String vs. stream, optional Neon | Neon only with `NATIVEJSON_WITH_NEON` |
| `Benchmarks/BigDataTest/NativeJson_Benchmark` | High-volume round trip | None |
| `Benchmarks/Speed/NativeJson_Speed` | Speed: DOM parse and write, object mapping; compares with `System.JSON` (Delphi) or `fpjson` (FPC) on record, number and string documents; best and median of 5 runs | None; build the Release configuration for meaningful numbers |

The programs without `RESULT` line print `[OK]`/`[FAIL]` or `-> OK`/`-> FAIL` lines; inspect the output, the exit code alone does not establish success.

## Commands

Free Pascal, all self-checking programs in one go (builds each with `-B`, runs it, prints the result line; `FPC` names the compiler, default `fpc`; programs can be passed as arguments):

```sh
FPC=/path/to/fpc sh tools/run-fpc-tests.sh
```

Delphi (editions with command-line compiler, from an initialized RAD Studio environment):

```powershell
./tools/build-delphi.ps1 -Project examples/Demos/Demo01_Basics.dproj -Platform Win32 -Config Debug
./bin/Demo01_Basics/Win32/Debug/Demo01_Basics.exe auto
```

```bat
examples\Demos\Demos_Build.bat Win64 Release
examples\Demos\Demos_Run.bat Win64 Release
```

Delphi Community Edition has no command-line compiler; build in the IDE (`NativeJson.groupproj`). `tools/set-delphi-platform.ps1` switches the default platform of all `.dproj` files.

Free Pascal:

```bat
examples\Demos\Demos_FPC.bat [path\fpc.exe]
```

Always build with `-B`; see [fpcReadme.md](fpcReadme.md).

## Interoperability checks

`Tests/Interop/Cbor` compares `NativeJson.Cbor` with an independent implementation (Python `cbor2`) and with published test data; see the README there. It is run by hand because it needs Python and a download.

| Check | Result (FPC, 2026-11-12) |
| --- | --- |
| 306 COSE examples of the cose-wg repository (Sign, Sign1, Encrypt, MAC, CWT, key sets): same value as `cbor2`, byte-identical round trip with `ckmInteger` and the byte and tag wrappers | 306 of 306 |
| 6000 decodes of random structures (bignums, floats, byte strings, tags, integer keys, 3-byte and 8-byte lengths) written by `cbor2` | 0 differences |
| 3000 documents written by `NativeJson.Cbor` and read by `cbor2` | 0 differences |
| 2957 canonical documents: decode, encode again, same bytes | 0 differences |
| 2953 documents with `Deterministic` and `ckoLengthFirst` against the canonical output of `cbor2` | byte-identical |
| 300 WebAuthn-shaped attestation objects (nested authenticator data, COSE key with integer labels, extension map as CBOR sequence); built from the specification layout, not captured from a device | 0 failures |

The comparison found one defect in the shared float printing (a 16-digit text was skipped and 17 digits printed, and subnormals printed more digits than needed); it is fixed and covered by `NativeJson_Cbor`.

## Known red results

None (FPC and Delphi 12 Win64 Debug, 2026-11-12, after the fixes listed below).

Last full FPC run: 2026-11-12, FPC 3.3.1 trunk Win64, 35 programs (the 33 above plus `NativeJson_Xml` and `NativeJson_Showcase`), results as listed above, everything else green. `NativeJson_Xml`: 59 passed; `NativeJson_Showcase`: 34 passed; both with `-gh` heap trace and 0 unfreed blocks.

Delphi 12 Win64 Debug, 2026-11-12, before the fixes below: `NativeJson_Showcase` 34/34, `NativeJson_Xml` 59/59, `NativeJson_SystemJson` 18/18, `Package3_CodeGen` 174 of 188, `Demo13_EdgeCases` 18/5, `Demo14_CodeGen` 29/3, `Test2_SchemaValidator` 113/1.

Fixes made after that run; rerun under Delphi 12 Win64 Debug the same day: `Package3_CodeGen` 188 of 188, `Demo13_EdgeCases` 23/0, `Demo14_CodeGen` 32/0, `Test2_SchemaValidator` 114/0, `NativeJson_Showcase` 34/0, `NativeJson_Xml` 59/0, `NativeJson_SystemJson` 18/0; the same programs pass under FPC:

- Generator: single-component OpenAPI root keeps the component name; `$ref` target names drop `.json`/`.schema.json`; type names taken from titles get the `T` prefix (a title `Thing` produced `Thing`, now `TThing`); `snake_case` and `SCREAMING_SNAKE` property names become PascalCase; nullable scalars honour `NullableKind` for alias declarations; closed `patternProperties` produce a dictionary, open ones a dictionary of the unknown type; merged `oneOf`/`anyOf` object unions no longer emit the unused option classes; `CG110` is reported when a default cannot be emitted; `items` schemas are indexed, so `$ref: "#"` inside `items` resolves and `CG112` is reported.
- Sets (`set of`) are written as JSON arrays of element names (or ordinals with `ByInteger`) and read back from arrays, ordinal numbers or the old string form `"[a,b]"`.
- `Double` to text and back no longer depends on the RTL: `NativeJson.FloatText` prints the shortest of 15 or 17 correctly rounded digits and parses with exact rounding. Delphi's `FloatToStrF` printed `0.30000000000000006` for `0.1 + 0.2` and the value did not come back bit-exact.
- Tests: `Package3.CodeGen.Helpers.TestDataFile` searches upward for `Tests\Package3\Data`; `Demo14` expects `TGUID`, `&Type` and a forward declaration instead of a declaration order; `Test2_SchemaValidator` uses `{"type":"number","minimum":5}` as second `oneOf` branch.

`NativeJson_Xml` with FPC on 2026-11-12 (`-gh` heap trace): 59 passed, 0 failed, 0 unfreed memory blocks.

Delphi 12 CE, Win64 Debug, 2026-11-12: `NativeJson_SystemJson` 18 passed, 0 failed; `NativeJson_Xml` 59 passed, 0 failed; both with `ReportMemoryLeaksOnShutdown`, no leak report. A trial build of the `NativeJson_SystemJson` checks with FPC (copy with short unit names): 14 passed, 4 failed; the 4 failures are number checks that FPC's `System.JSON` cannot pass because its parser keeps numbers as `Double`/`Int64` instead of their text.

CBOR, FPC 2026-11-12 (`-gh` heap trace): `NativeJson_Cbor` 219 passed, 0 failed, 0 unfreed memory blocks; `NativeJson_Showcase` (with the CBOR step) 39 passed, 0 failed. Delphi 12 Win64 Debug, same day: `NativeJson_Cbor` 219 passed, 0 failed; `NativeJson_Showcase` 39 passed, 0 failed; no leak report. After the `TJsonBytes` node and `WrapBytes` were added: FPC `NativeJson_Cbor` 231 passed, 0 failed, 0 unfreed blocks; Delphi 12 Win64 Debug rerun, same day: `NativeJson_Cbor` 231 passed, 0 failed; `NativeJson_Showcase` 39 passed, 0 failed; Demo01-15, `Test2_*`, `NativeJson_Xml` and `NativeJson_SystemJson` all 0 failed. `KeyMode := ckmInteger` (integer map keys) was added afterwards: then `KeyOrder`, the shortest-text fix in `NativeJson.FloatText` and their tests: FPC `NativeJson_Cbor` 245 passed, 0 failed, and every other FPC program green; Delphi 12 Win64 Debug rerun of the full set: `NativeJson_Cbor` 245 passed, 0 failed; `Test2_NumberFormats` 72, `NativeJson_Showcase` 39, `Package3_CodeGen` 188, Demo01-15, `Test2_*`, `NativeJson_Xml` and `NativeJson_SystemJson` all 0 failed.

## Speed (single machine, best of 5 runs)

`Benchmarks/Speed/NativeJson_Speed`, Delphi 12 Win64 Release, started outside the IDE, 2026-11-12. Text is parsed from a string in memory; MB/s is megabytes of JSON text per second.

| Document | Operation | NativeJson | System.JSON |
| --- | --- | --- | --- |
| Records, 11.7 MB | parse to DOM | 254 ms | 218 ms |
| | write DOM | 97 ms | 41 ms |
| Numbers, 7.7 MB (400000 doubles) | parse to DOM | 65 ms | 99 ms |
| | write DOM | 26 ms | 11 ms |
| Strings with escapes, 13.3 MB | parse to DOM | 77 ms | 88 ms |
| | write DOM | 54 ms | 68 ms |

Object mapping, 40000 records as classes (NativeJson only): deserialize 1188 ms (9.9 MB/s), serialize 776 ms (15.1 MB/s).

FPC 3.3.1 `-O3`, same program against `fpjson`: parse 193 ms (records), 57 ms (numbers), 93 ms (strings); mapping 1979 ms and 1427 ms.

