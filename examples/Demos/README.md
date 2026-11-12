# NativeJson Demos

Fifteen console programs that show the library step by step. Every step checks
itself and prints what was expected and what actually came out:

```
[OK]   ZipCode after round trip = 12345
[FAIL] City after round trip
       expected: Exampletown
       received: Bremen
```

Each program ends with a summary line (`RESULT: n passed, m failed`). The process
exit code is `0` when everything passed, so the demos can be used in a build job.

## Build and run

**IDE:** open `NativeJson.groupproj`; the demos are part of the project group.

**Command line (RAD Studio editions with command-line compiler):**

```bat
cd examples\Demos
Demos_Build.bat Win32 Release
Demos_Run.bat Win32 Release
```

Without parameters `Win32 Release` is used. Executables are written to
`bin\<Project>\<Platform>\<Config>` below the repository root. Delphi Community
Edition has no command-line compiler; build there in the IDE.

**Free Pascal:** `Demos_FPC.bat [path\fpc.exe]` builds and runs all demos and the
`Tests\Package2` programs with FPC. Output goes to `bin\FPC`, units to `build\FPC`.
See `docs/fpcReadme.md`.

Started without parameters, a demo waits for Enter at the end. With any parameter
(`Demo01_Basics.exe auto`) it runs through; `Demos_Run.bat` does that.

## Contents

| Demo | Topic | Covers |
|---|---|---|
| `Demo01_Basics` | Basics | Round trip, `[JsonProperty]`, `[JsonIgnore]`, null and default handling, indentation, naming strategies, single values |
| `Demo02_Collections` | Lists and maps | `TArray<T>`, `TList<T>`, `TObjectList<T>`, `TDictionary<K,V>`, custom list classes, `PopulateObject` on lists |
| `Demo03_DataTypes` | Values | `TDateTime` (ISO and custom format), enumerations, `TGUID`, `Currency`, `Int64`, records, `TStringList`, `TMemoryStream` as Base64, `Variant`, escaping |
| `Demo04_Polymorphism` | Inheritance and graphs | `$type`, round trip with subclasses, `$id`/`$ref` for cycles, unknown type |
| `Demo05_Configuration` | Fluent API | Rename, ignore, fixed order, value transformation, conditional writing, hooks, naming strategy per type, properties vs. fields |
| `Demo06_Practice` | ERP/EDI | Foreign JSON, reporting unknown fields, required fields, partial update, foreign field names and date formats, broken JSON, stream/file, 1000 records |
| `Demo07_Dom` | JSON without classes | Building a DOM, navigation, `SelectToken`, `FindAll` with wildcard and deep search, filtering, `EnsureObjectPath`, `Clone`, query chain `Q` |
| `Demo08_Schema` | JSON Schema | Schema from attributes, required fields, nested documents, `oneOf` + `discriminator`, effect of the fluent configuration |
| `Demo09_BinaryData` | Binary data | `TBytes` as Base64, stable field order, `[JsonRequired]` when reading and in the schema |
| `Demo10_Api` | API surface | File and stream in both directions, settings as anonymous method, `TryDeserialize`, `JsonConvert.DefaultSettings`, BOM handling, `TBytes` |
| `Demo11_MoneyAmounts` | Precision | `Currency` exact instead of via `Double`, type limits, identical output on Win32 and Win64 |
| `Demo12_ValidationRules` | Validation | Schema attributes enforced at runtime via `JsonConvert.Validate`, error list with JSON Pointer paths |
| `Demo13_EdgeCases` | Hardening probe | Integer limits, sets, interfaces, legacy string types, `Single`, `StrictTypes`, streamable classes. Exit code is always 0; red lines are open items |
| `Demo14_CodeGen` | Code generation | JSON Schema to Delphi types and units, formats, `$ref`, enums, reserved words, diagnostics |
| `Demo15_WhatsNew` | Additions | `.Q` query surface, sequence reader for large arrays, fluent polymorphism with a custom discriminator |

Shared files:

* `Demo.Assert.pas` – the small check harness (`Check`, `CheckContains`, `CheckError`, `Summary`, ...). No third-party library.
* `Demo.Model.pas` – the shared data model (customer, address, order, line items, supplier, ...).

## Behavior the demos pin down

These are not bugs but properties that come up in practice. Each one is recorded in one place.

1. **Classes rebuilt via `$type` belong in a unit.**
   `TRttiContext.FindType` only finds types from the `interface` section of a unit.
   Classes declared in a `.dpr` cannot be rebuilt. That is why the model lives in
   `Demo.Model.pas`. *(Demo 4)*

2. **Field order.** Members are sorted by `Order`, then by discovery index, so the
   order is stable between runs. A fixed layout for signatures or diffs is set with
   `Order` via fluent. The DOM always keeps insertion order. *(Demo 5, Demo 7, Demo 9)*

3. **Public fields are not written by default.**
   Classes serialize properties, records serialize fields. Switch with
   `Settings.MemberSelection` or `Fluent.Entity<T>.SelectMembers`. *(Demo 1, Demo 5)*

4. **Read-only properties are filled, not replaced.**
   An address or list created by the constructor gets its content written into it.
   For lists this means the existing content is **replaced** as soon as the list
   appears in the JSON. *(Demo 2, Demo 6)*

5. **`TObjectList<T>` comes back without ownership.**
   The activator finds the parameterless `TList<T>.Create`, so `OwnsObjects` is
   `False` afterwards. Set it to `True` before freeing the list yourself. *(Demo 2)*

6. **`TDictionary` as root can be written but not read.**
   It has no parameterless constructor. Wrap the dictionary in a class and expose it
   as a read-only property. *(Demo 2)*

7. **`Values['x']` raises when the key is missing.**
   For optional DOM fields use `TryGetValue`, `TrySelectToken` or the convenience
   getters with a default value (`GetStringPath`). *(Demo 7)*

8. **`AddPair` creates, `Values[...] :=` overwrites.**
   `AddPair` on an existing key raises `EJsonValueError`. To replace use
   `Values['x'] := TJsonString.Create(...)`; the old value is freed and the position
   in the order stays. *(Demo 7)*

9. **Nullable fields get a type vector in the schema.**
   `"type":"array"` becomes `"type":["array","null"]`, likewise for strings and
   objects. Required fields stay non-nullable. *(Demo 8, Demo 9)*

10. **The linker removes classes that are only named in an attribute.**
    `[JsonKnownType('TOrderLine')]` names the class as a string; for smart linking
    that is not a reference. If the program never creates the class, it is removed
    together with its RTTI and `FindType` no longer finds it: empty `oneOf` in the
    schema, `Unknown runtime type` when reading. One line in the `initialization`
    section of the model unit fixes it:

    ```pascal
    initialization
      JsonKeepTypes([TLineItem, TOrderLine, TTextLine]);
    ```

    The problem only appears in programs that do not instantiate the subclasses
    themselves; that is why Demo 4 always worked and Demo 8 did not.
    *(Demo.Model.pas, Demo 8)*

11. **The `required` block in the schema** is fed by `[JsonRequired]` and by the
    fluent configuration (`Map(...).Required(True)`). *(Demo 8, Demo 9)*

## Adding a demo

1. Create `Demo16_Topic.dpr`, use `Demo.Assert` and `Demo.Model`.
2. Copy an existing `.dproj` next to it, replace the project name in it and enter a
   new `ProjectGuid`.
3. Add the project to `NativeJson.groupproj`.

The unit search path of the demo projects is `..\..\src;.`: library units come from
`src`, the shared demo units from the same folder.
