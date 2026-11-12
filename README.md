# NativeJson

**The JSON engineering toolkit for Delphi and Free Pascal.**
Serialize. Query. Validate. Generate. Diff. Patch.

NativeJson covers the whole life cycle of JSON data in one library: map Delphi objects to JSON, navigate and change documents with a LINQ-style query chain, describe and validate with JSON Schema, generate Delphi units from schemas and OpenAPI, and derive RFC 6902 patches from your own objects. All parts share one DOM and one number model, so the result of one step is the input of the next.

The API follows the naming of Newtonsoft.Json (`JsonConvert`, `[JsonProperty]`, `TypeNameHandling`, `SelectToken`), so existing habits carry over. See [Coming from Newtonsoft.Json](docs/FEATURES.md#coming-from-newtonsoftjson).

## Status

In development, no release. Compiler and test evidence is in [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) and [docs/TESTING.md](docs/TESTING.md).

## What sets it apart

- **Object diff and patch.** `CreatePatch` serializes two Delphi objects and returns the RFC 6902 patch between them; `ApplyPatch` returns a new, patched object instance.
- **A query chain that also edits.** `Where`, `OrderBy`, `Descendants`, `Ancestors`, `Sum`, set operations - and `Remove` and `Replace` on the matches, inside the document.
- **Schema in both directions.** Generate a JSON Schema from a class, validate documents against Draft 7, 2019-09 or 2020-12, and generate Delphi code back from a schema or an OpenAPI document, including external `$ref` targets.
- **Exact numbers.** The DOM keeps the number text. `Currency`, `Int64`, `UInt64`, `multipleOf` and bounds are decided on the decimal value, not on a `Double`.
- **Large arrays element by element.** Process a top-level array with memory use bound to one element.
- **No third-party dependencies.** The core does not use `System.JSON`; it compiles with Delphi and with Free Pascal.

## Quick start

Add `src` to the unit search path (FPC: also to the include path).

```pascal
uses
  NativeJson.Main, NativeJson.Attributes;

type
  TUser = class
  private
    FName: string;
    FAge: Integer;
  public
    [JsonProperty('full_name')]
    property Name: string read FName write FName;
    property Age: Integer read FAge write FAge;
  end;

Json := JsonConvert.SerializeObject(User);
Clone := JsonConvert.DeserializeObject<TUser>(Json);
```

Units with classes that are serialized include `{$I NativeJson.inc}` directly after `interface` (required for FPC, harmless for Delphi).

## Examples

The snippets are shortened from [examples/Showcase](examples/Showcase/NativeJson_Showcase.dpr), a self-checking program that runs them.

### Delphi object to patch to Delphi object

```pascal
Patch := JsonConvert.CreatePatch<TCustomer>(OldCustomer, NewCustomer);
// [{"op":"replace","path":"/Age","value":35},
//  {"op":"replace","path":"/Address/City","value":"Hamburg"}]
Updated := JsonConvert.ApplyPatch<TCustomer>(OldCustomer, Patch);
```

The paths use the JSON names (`[JsonProperty]`, naming strategy). The source object is not changed; the caller owns the patch and the returned object.

### Query and edit

```pascal
Items := Dom.Q.Select('article').Children;

Total := Items.Where(InStock).Transform(Field('price')).Sum;
Top2  := Items.OrderByDescending(Field('price')).Take(2).Transform(Field('name')).ToJsonArray;

Items.Where(SoldOut).Remove;
Items.Where(IsSprocket).Select('price').Replace(NewPrice);
```

### Schema and exact numbers

```pascal
Schema := JsonConvert.GenerateSchema<TCustomer>;
Outcome := JsonConvert.ValidateJsonSchema(Json, Schema.ToJson);
// Outcome.Errors[0]: InstancePath '/Age', Keyword 'minimum'

JsonConvert.ValidateJsonSchema('19.99', '{"multipleOf":0.01}').IsValid;               // True
JsonConvert.ValidateJsonSchema('9007199254740993', '{"maximum":9007199254740992}').IsValid;  // False
```

### Schema and OpenAPI to Delphi code

```pascal
Generator := TNativeJsonSchemaCodeGenerator.Create;
try
  Generator.RegisterSchema('https://example.org/address.json', AddressSchema);
  Generator.LoadSchema(OrderSchema, 'https://example.org/order.json');
  Code := Generator.GenerateUnit('Shop.Model');
finally
  Generator.Free;
end;
```

`TNativeJsonSchemaCodeGenerator.SchemaToTypes(OpenApiText)` generates one class per component schema. Problems are reported as diagnostics with stable codes (`CG...`) instead of silently wrong code.

### A large array, one element at a time

```pascal
Count := JsonConvert.DeserializeSequence<TCustomer>(Json,
  procedure(Item: TCustomer)
  begin
    Process(Item);
    Item.Free;
  end);
```

### Validation rules from attributes

```pascal
[JsonRange(18, 120)]
property Age: Integer read FAge write FAge;

Outcome := JsonConvert.Validate(Customer);   // Outcome[0].Path = '/Age', .Rule = 'minimum'
```

The same attributes feed the generated schema.

### CBOR

```pascal
Cbor := JsonToCbor('{"id":7,"temp":21.5}');          // a2 62 6964 07 64 74656d70 f94d60
Json := CborToJson(Cbor);
Cbor := CborConvert.SerializeObject(Customer);
```

Integers of any size, byte strings, tags, indefinite lengths and exact decimals (decimal fractions instead of a rounded `Double`) are handled; input is bounded and checked. See [CBOR](docs/FEATURES.md#cbor).

### XML and System.JSON

```pascal
Xml  := JsonToXml('{"customer":{"@id":"7","name":"Anna"}}');   // <customer id="7"><name>Anna</name></customer>
R    := ValidateSystemJson(RESTResponse.JSONValue, Schema);
```

## Features

| Area | Content | Units |
| --- | --- | --- |
| Object mapping | Classes, records, arrays, generics, dictionaries, interfaces with factories, polymorphism (`$type` or custom discriminator), references (`$id`/`$ref`), attributes, fluent configuration, naming strategies | `Main`, `Attributes`, `Fluent`, `Settings`, `NamingStrategy` |
| DOM and queries | Insertion-ordered DOM, `SelectToken`, wildcard and recursive paths, LINQ-style query chain | `Dom.*`, `Linq` |
| Diff and patch | Object diff/patch, DOM diff, RFC 6902 Patch, RFC 6901 Pointer, semantic equality | `Main`, `Diff`, `Patch`, `Pointer`, `Comparer` |
| Schema | Generator (2020-12), validator (Draft 7, 2019-09, 2020-12), registry, exact decimals | `Schema.*` |
| Code generation | JSON Schema and OpenAPI 3.0/3.1 to Delphi units, external references, diagnostics | `CodeGen.*` |
| Formats | JSON5 input, XML, CBOR, `System.JSON` interop | `Settings`, `Xml`, `Cbor`, `SystemJson` |
| Streams | Strings, streams, files, `TBytes`; sequence reader | `Main`, `Sequence` |

Details and code for each area: [docs/FEATURES.md](docs/FEATURES.md).

## Layout

- `src/`: library units and `NativeJson.inc`
- `examples/`: `Showcase` (the snippets above), `Demos` (15 walk-throughs, see `examples/Demos/README.md`), minimal examples
- `Tests/`: test programs, `Tests/Package2` matrix tests, `Tests/Package3` DUnitX suite for the code generator
- `Benchmarks/`: benchmark and comparison programs
- `docs/`: technical documents
- `tools/`: build and maintenance scripts
- `NativeJson.groupproj`: all 42 Delphi projects

## Build and test

Delphi: open `NativeJson.groupproj` in the IDE, or use `tools/build-delphi.ps1` / `examples/Demos/Demos_Build.bat` where a command-line compiler is available. Free Pascal: `examples/Demos/Demos_FPC.bat`, details in [docs/fpcReadme.md](docs/fpcReadme.md).

Self-checking programs print `RESULT: n passed, m failed` and set the exit code; started with any parameter (`auto`) they do not wait for Enter.

## Documentation

[docs/FEATURES.md](docs/FEATURES.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/TESTING.md](docs/TESTING.md), [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md), [docs/SECURITY.md](docs/SECURITY.md), [docs/fpcReadme.md](docs/fpcReadme.md), [examples/Demos/README.md](examples/Demos/README.md).

## License

No license selected. Add one before distribution.

## License

MIT, see [LICENSE](LICENSE). Third-party material and referenced specifications are listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
