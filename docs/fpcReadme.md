# NativeJson with Free Pascal

Tested with FPC 3.3.1 (trunk, build 62b8ab000e), target Win64.

## Building

No compiler switch is needed. Mode and RTTI come from `NativeJson.inc`.

```bat
fpc -B -FuE:\path\Nativejson2\src -FiE:\path\Nativejson2\src MyProgram.dpr
```

Always build with `-B`. Incremental builds with stale `.ppu` files crash FPC trunk on generic methods (`EListError: List index exceeds bounds (-2)`).

FPC searches the current directory for units first. If an older copy of the library is there, that copy is used.

Build and run all demos and test package 2:

```bat
examples\Demos\Demos_FPC.bat [path\fpc.exe]
```

Executables go to `bin\FPC`, units to `build\FPC`.

## Own units

Every unit with classes that are serialized needs this directly after `interface`:

```pascal
interface

{$I NativeJson.inc}
```

Without it FPC generates RTTI only for `published` members and every object becomes `{}`. The directive is not allowed before `interface`.

FPC does not know dotted Delphi unit names (`System.SysUtils`). In units:

```pascal
uses
  {$IFDEF FPC}
  SysUtils, Classes, Generics.Collections,
  {$ELSE}
  System.SysUtils, System.Classes, System.Generics.Collections,
  {$ENDIF}
  NativeJson.Main;
```

In `.dpr` files short names (`SysUtils`) are enough; Delphi resolves them through the unit scope names of the project.

`TProc`, `TFunc` and `TPredicate` do not exist in FPC. They are declared in `NativeJson.Compat`.

## Polymorphism

FPC cannot find classes by name (`TRttiContext.FindType` and `GetTypes` are missing). For `$type` and `[JsonKnownType('TName')]` the classes must be registered:

```pascal
initialization
  JsonKeepTypes([TLineItem, TOrderLine, TTextLine]);
```

Under Delphi the same line keeps the linker from removing the classes.

## What works

- Serializing and deserializing classes, records, arrays, lists, dictionaries
- Fluent API including `Entity<T>` and fluent polymorphism with a custom discriminator
- Polymorphism with `$type`, `$id`/`$ref`
- DOM, LINQ queries, `SelectToken`, `FindAll`, sequence reader
- JSON Schema generator, JSON Schema validator, code generator
- Validation rules from attributes, including `pattern`
- JSON Pointer, JSON Patch, diff, semantic equality
- JSON5 input (`TJsonSettings.Json5`)
- XML to JSON and back (`NativeJson.Xml`)
- Exact Currency, Int64/UInt64 over the full range, Single/Double round trip
- Unicode, surrogate pairs, emojis
- Input and output via string, stream, file, `TBytes`

Results of the 33 FPC-buildable programs (demos, examples, `Tests`, `Tests\Package2`): all build and run. Known red lines, identical to the state before the port:

| Program | Result | Reason |
|---|---|---|
| `Demo13_EdgeCases` | 20 passed, 3 failed, exit code 0 | Sets (`set of`) are not supported; the demo is a hardening probe |
| `Demo14_CodeGen` | 29 passed, 3 failed | Code generator open items: `format: uuid` does not map to `TGuid`, `$ref` target is declared after its user, reserved word `type` is not escaped |
| `Test2_SchemaValidator` | 113 passed, 1 failed | The test case `oneOf` with `"a"` contradicts the specification |

`Tests/NativeJson_Xml` (added after that run, 2026-11-12): 59 passed, 0 failed, no leaks with `-gh`.

## What does not work

| Part | Reason |
|---|---|
| `NativeJson.Converters.Vcl`, `.Graphics`, `.Fmx` | VCL and FMX do not exist under FPC |
| `Benchmarks\*`, `Tests\MemoryTest` | need `Winapi.PsAPI` |
| Exact numbers in `NativeJson.SystemJson` | The unit compiles and works, but FPC's `System.JSON` parser stores numbers as `Double`/`Int64` without their text. Decimals beyond double precision are rounded, values above `High(Int64)` arrive as -1. |

## Limitations

- `TJsonWriter.Create(Writer: TTextWriter)`: FPC's `TTextWriter` (unit `streamex`) works with AnsiString. Characters outside the code page are lost. Output via string or stream is not affected.
- `ToString` methods (`TJsonWriter`, `TJsonValidationResult`, etc.) return `RTLString` under FPC, i.e. AnsiString with the classic RTL. Use `TJsonWriter.ToJson` for the JSON itself.
- Error messages built with `Format` are AnsiString under FPC.
- `TJsonSchemaValidator` uses `System.RegularExpressions`. Under FPC that loads `libpcre2-8-0.dll` at runtime. The validation rules in `NativeJson.Validation` do not need it (they use `uregexpr`).
- Under FPC the RTTI cache locks with a critical section instead of `TLightweightMREW`. Concurrent readers wait for each other.
- `Converters.Standard` and `Converters.System` handle `TStringBuilder` from application code. Under FPC with the classic RTL that is `TAnsiStringBuilder`.

## Differences handled in `NativeJson.Compat`

Apart from `uses` clauses the library code contains `{$IFDEF FPC}` only at these places: `TJsonTypeConfig<T>` (constraint, `AsT`, `IsT`), `TJsonWriter.Emit(Char)`, `PatternMatches` in `NativeJson.Validation`.

| Delphi | FPC | in Compat |
|---|---|---|
| Boolean is `tkEnumeration`, UInt64 `tkInt64`, AnsiString `tkLString` | own kinds `tkBool`, `tkQWord`, `tkAString` | `JsonTypeKind` |
| `TStringBuilder` is UTF-16 | `TAnsiStringBuilder` with the classic RTL | `TJsonStringBuilder` |
| `TIStringComparer` | works with AnsiString | `TJsonIStringComparer` |
| `TValue.AsString` | returns AnsiString | `JsonValueAsString` |
| `GetHashCode: Integer` | `UInt32` | `TJsonHashCode` |
| `TObject.ToString: string` | `RTLString` | `TJsonToStringResult` |
| `elType2`, `CompType` as `PPTypeInfo` | `PTypeInfo` directly | `JsonDynArrayElementType`, `JsonSetElementType` |
| `TRttiContext.FindType`, `GetTypes` | missing | `JsonRttiFindType`, `JsonRttiGetTypes` (return nil under FPC) |
| `TProc`, `TFunc`, `TPredicate`, `TLightweightMREW`, `MaxComp` | missing | declared under FPC |
| UTF-8 encoding without BOM | different class layout | `JsonCreateUtf8NoBom` |
| extended RTTI always active | only with `GlobalUsePublishedOnly := False` | `initialization` of Compat |

Bugs in FPC's RTTI unit, worked around in `JsonPropertyGetValue`/`JsonPropertySetValue`:

- `TRttiProperty.GetValue`/`SetValue` round Currency through `Extended` (a `Double` on Win64). Currency properties are read and written directly via the field or the getter/setter.
- `TRttiProperty.GetValue` returns an empty value for WideString properties. They are read via `GetWideStrProp`.

## Language limits of FPC trunk

- No inline variables (`var X := ...`).
- Nested generics in expressions are not parsed: `TValue.From<TArray<string>>(A)`, `DeserializeObject<TObjectList<TFoo>>(S)`. Workaround: a type alias (`TTexts = TArray<string>;`).
- `TCustomAttribute.Create` is private. Attribute base classes without their own constructor need a public `constructor Create;`, otherwise parameterless attributes cannot be used.
- A generic method with a constraint (`Entity<T: class>`) must not return a type whose class also has a constraint. That is why the `class` constraint of `TJsonTypeConfig<T>` only exists under Delphi.
- `inherited` is reserved as a parameter name too.
