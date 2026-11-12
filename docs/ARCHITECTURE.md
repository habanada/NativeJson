# Architecture

## Library

Production units live directly in `src/` with their `NativeJson.*` names. Consumers need one search path (`src`) and, for FPC, one include path (`src`).

| Family | Units |
| --- | --- |
| Facade | `NativeJson.Main` (`JsonConvert`) |
| Reading | `Core.Tokens`, `Core.Tokenizer` (strict JSON, opt-in JSON5), `Core.Reader` |
| DOM | `Dom.Value`, `Dom.Primitive`, `Dom.JsonObject`, `Dom.JsonArray`, `Dom.Io` (text to DOM and back without RTTI), `ExactNumber`, `Comparer`, `Linq` |
| Writing | `Serializer.Writer` (own UTF-8 byte buffer for streams), `Serializer.Core`, `Serializer.Converter` |
| Reading into objects | `Deserializer.Core`, `Deserializer.Activator`, `Deserializer.Generics`, `Sequence` (top-level arrays element by element) |
| Configuration | `Settings`, `Attributes`, `Fluent`, `NamingStrategy`, `Rtti.Cache`, `Dynamic` (duck-typed lists and maps) |
| Converters | `Converters.Standard`, `.System`, `.Classes`, `.DB`, `.Vcl`, `.Graphics`, `.Fmx` |
| Validation | `Validation` (runtime rules from attributes), `Schema.Attributes`, `Schema.Generator`, `Schema.Validator`, `Schema.Validation`, `Schema.Registry`, `Schema.Decimal` |
| Code generation | `CodeGen`, `CodeGen.Model`, `CodeGen.Parser`, `CodeGen.Repository`, `CodeGen.Names`, `CodeGen.Options`, `CodeGen.Delphi` |
| RFC tools | `Pointer` (RFC 6901), `Patch` (RFC 6902), `Diff` |
| Interop | `SystemJson` (optional; `System.JSON` values to the DOM, schema validation of `TJSONValue`), `Xml` (optional; XML text to the DOM and back, own parser), `Cbor` (optional; CBOR to the DOM and back, own reader and writer), `Cbor.Convert` (objects to and from CBOR through `JsonConvert`) |
| Platform layer | `Compat`, `FloatText` (exact `Double` text conversion), `NativeJson.inc` |

`NativeJson.SystemJson` is the only unit that uses `System.JSON`; no other unit depends on it, so `System.JSON` is linked only when an application uses that unit.

Numbers keep their raw text from the input in the DOM. Integer, Currency and UInt64 conversions work on that text, not on `Double`.

## Delphi and Free Pascal

Compiler differences are confined to `NativeJson.Compat` and `NativeJson.inc`. Every unit includes `NativeJson.inc` directly after `interface`; it sets `{$MODE DELPHIUNICODE}` and extended RTTI under FPC. Outside `uses` clauses, `{$IFDEF FPC}` appears only in `TJsonTypeConfig<T>`, `TJsonWriter.Emit(Char)` and `PatternMatches`. Details: [fpcReadme.md](fpcReadme.md).

## Programs

| Folder | Content |
| --- | --- |
| `examples/Demos` | `Demo01`..`Demo15`, shared `Demo.Assert` and `Demo.Model` |
| `examples/Showcase` | Self-checking program that runs the snippets of the README (objects, patch, queries, schema, code generation, sequence reading, validation, XML) |
| `examples/QuickStart`, `Fluent`, `Polymorphism`, `Schema` | Minimal examples |
| `Tests` | Feature and RFC test programs |
| `Tests/Package2` | Matrix tests (numbers, null, characters, accessors, schema validator, JSON5), using `Demo.Assert` |
| `Tests/Package3` | DUnitX test suite for the code generator |
| `Tests/MemoryTest` | Long-running memory growth test |
| `Tests/AttribInheritInterfacesStreamsTest` | Integration suite with its own model and runner |
| `Benchmarks` | `JsonDeathmatch`, `BigDataTest` |

Every entry point has its own Delphi project. `NativeJson.groupproj` references 42 projects. Projects resolve the library through relative unit search paths (`..\..\src`).

## Build output

Delphi projects write DCUs to `build/<project>/<platform>/<configuration>/` and executables to `bin/<project>/<platform>/<configuration>/`. `examples/Demos/Demos_FPC.bat` uses `build/FPC` and `bin/FPC`. These directories are ignored by Git.
