# Features

Code in this document uses the unit names of the library. Programs that run these examples: `examples/Showcase`, `examples/Demos`, `Tests`.

## Contents

- [Coming from Newtonsoft.Json](#coming-from-newtonsoftjson)
- [Object mapping](#object-mapping)
- [DOM and queries](#dom-and-queries)
- [Diff and patch](#diff-and-patch)
- [JSON Schema](#json-schema)
- [Code generation](#code-generation)
- [Exact numbers](#exact-numbers)
- [Large documents](#large-documents)
- [Validation rules from attributes](#validation-rules-from-attributes)
- [JSON5](#json5)
- [XML](#xml)
- [CBOR](#cbor)
- [System.JSON interop](#systemjson-interop)
- [Delphi and Free Pascal](#delphi-and-free-pascal)

## Coming from Newtonsoft.Json

The names are deliberately close. Code written against Newtonsoft.Json usually translates line by line.

| Newtonsoft.Json | NativeJson |
| --- | --- |
| `JsonConvert.SerializeObject(x)` | `JsonConvert.SerializeObject(X)` |
| `JsonConvert.DeserializeObject<T>(json)` | `JsonConvert.DeserializeObject<T>(Json)` |
| `JsonConvert.PopulateObject(json, x)` | `JsonConvert.PopulateObject(X, Json)` |
| `JsonSerializerSettings` | `TJsonSettings`, or a callback: `JsonConvert.SerializeObject(X, procedure(S: TJsonSettings) begin ... end)` |
| `Formatting.Indented` | `TJsonFormatting.Indented` |
| `NullValueHandling`, `DefaultValueHandling`, `MissingMemberHandling` | same names on `TJsonSettings` |
| `TypeNameHandling.None / Objects / Auto` | `TJsonTypeNameHandling.None / Objects / Auto` |
| `PreserveReferencesHandling` (`$id`/`$ref`) | `TJsonSettings.PreserveReferences` |
| naming strategies (`CamelCase`, `SnakeCase`, `Kebab`) | `TCamelCaseNamingStrategy`, `TSnakeCaseNamingStrategy`, `TKebabCaseNamingStrategy`, also Pascal, lower, upper and screaming snake case |
| `[JsonProperty]`, `[JsonIgnore]`, `[JsonConstructor]`, `[JsonConverter]` | same attribute names |
| `JObject`, `JArray`, `JValue`, `JToken` | `TJsonObject`, `TJsonArray`, `TJsonString` / `TJsonNumber` / `TJsonBoolean` / `TJsonNull`, base `TJsonValue` |
| `token.SelectToken(path)`, `SelectTokens(path)` | `SelectToken(Path)`, `FindAll(Path)` |
| LINQ to JSON (`Children()`, `Descendants()`, `Where`, `OrderBy`) | `Value.Q.Children.Descendants.Where(...)`, see [DOM and queries](#dom-and-queries) |

Differences that matter in Delphi:

- **Ownership.** There is no garbage collector. `DeserializeObject<T>` returns an instance the caller frees. DOM values belong to their parent; only the root is freed. Methods that return a new object leave it to the caller (`CreatePatch`, `ApplyPatch`, `GenerateSchema`).
- **Settings are objects.** `TJsonSettings` is created and freed by the caller, or configured through a callback overload that needs no cleanup. `JsonConvert.DefaultSettings` sets a global configuration.
- **Names as declared.** Properties are written with their Delphi names unless an attribute, a fluent rule or a naming strategy says otherwise; explicit `[JsonProperty('x')]` names win over a naming strategy.
- **`$type` carries Delphi class names** (`Unit.TClass`). The class must be linked into the program; `JsonKeepTypes([...])` guarantees that, and under Free Pascal it is required.
- **Not provided:** `[JsonExtensionData]`, grouping operators (`GroupBy`) in the query chain.

## Object mapping

Classes, records, static and dynamic arrays, `TList<T>`, `TObjectList<T>`, dictionaries, interfaces with factories, duck-typed collections, `TBytes` as Base64, streams, `TStrings`, `Variant`, `TGUID`, enumerations by name or ordinal, `set of` as arrays of names, dates with invariant custom formats, `Currency`, full `Int64`/`UInt64` range.

Attributes: `JsonObject`, `JsonArray`, `JsonVisibility`, `JsonMemberSelection`, `JsonProperty`, `JsonGetter`, `JsonSetter`, `JsonIgnore`, `JsonConstructor`, `JsonShouldSerialize`, `JsonInclude`, `JsonConverter`, `JsonFormat`, `JsonRaw`, `JsonUnwrapped`, `JsonKnownType`.

Settings: `Formatting`, `DateFormat`, `EnumHandling`, `PreserveReferences`, `TypeNameHandling`, `NamingStrategy`, `CaseStyle`, `MemberSelection`, `NullValueHandling`, `DefaultValueHandling`, `MissingMemberHandling`, `StrictTypes`, `Json5`, plus factories, collection adapters, key serializers and value transformers per type.

Input and output: string, stream, file, `TBytes`; `TryDeserializeObject` returns the error text instead of raising.

### Fluent configuration for classes you cannot annotate

```pascal
Settings.Fluent.Entity<TLegacySystem>
  .Map('F_Internal_ID').Name('id').EndMember
  .Map('SecretKey').Ignore;
Json := JsonConvert.SerializeObject(Sys, Settings);
```

Rules set fluently take precedence over attributes on the same member.

### Polymorphism

With `$type`:

```pascal
Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
```

With a field your data already has, instead of `$type`:

```pascal
Settings.Fluent.Entity<TAnimal>
  .Discriminator('kind')
  .SubType('dog', TDog)
  .SubType('cat', TCat);
// {"Resident":{"kind":"dog","Name":"Rex","Breed":"Shepherd"}}
```

`PreserveReferences` writes `$id`/`$ref` for shared and cyclic references.

## DOM and queries

`DomFromText` (unit `NativeJson.Dom.Io`) parses without RTTI. Objects keep the insertion order. Numbers keep their text.

Path access on every value: `SelectToken`, `TrySelectToken`, `FindAll`, `Find(Path, Predicate)`, `EnsureObjectPath`; paths support properties, indexes, `*` and `..`.

`Value.Q` starts a query chain (unit `NativeJson.Linq`). A chain over an empty or missing selection is an empty sequence, not an error.

| Group | Operations |
| --- | --- |
| Navigation | `Children`, `Parents`, `Ancestors`, `Descendants`, `Siblings`, `Select(Path)` |
| Filter and projection | `Where`, `OfType`, `NotNull`, `Transform`, `TransformMany` |
| Sets | `Distinct`, `Union`, `Intersect`, `Exclude`, `Concat` |
| Order and paging | `OrderBy`, `OrderByDescending`, `ThenBy`, `ThenByDescending`, `Reverse`, `Skip`, `Take` |
| Single values | `First`, `FirstOrDefault`, `Last`, `LastOrDefault`, `Single`, `ElementAt`, `Min`, `Max` |
| Checks and aggregates | `Any`, `All`, `Contains`, `Count`, `Sum`, `Average`, `Aggregate<T>` |
| Result | `ToArray`, `ToJsonArray`, `Map<T>`, `Value<T>`, `Values<T>`, `ToJson`, `ForEach` |
| Change the document | `Remove`, `Replace` |

```pascal
Items := Dom.Q.Select('article').Children;

Items.Where(SoldOut).Remove;
Items.Where(IsSprocket).Select('price').Replace(NewPrice);
```

`Remove` takes the matches out of their parent object or array. `Replace` puts a copy of the new value at each match, keeping its position; the caller keeps ownership of the value passed in.

## Diff and patch

On Delphi objects:

```pascal
Patch := JsonConvert.CreatePatch<TCustomer>(OldCustomer, NewCustomer);
Updated := JsonConvert.ApplyPatch<TCustomer>(OldCustomer, Patch);
```

Both objects are serialized with the same settings, so the patch uses the JSON names. `ApplyPatch` patches that representation and reads a new instance; the source is not changed. State outside the JSON mapping (`[JsonIgnore]` members, serializer-only transformers) is not copied; it comes from the constructor or factory. For round-trip capable settings, `Serialize(ApplyPatch(A, CreatePatch(A, B)))` equals `Serialize(B)`.

On DOM values (no RTTI):

| Unit | Content |
| --- | --- |
| `NativeJson.Diff` | `TJsonDiff.Compare(Old, New)` returns an RFC 6902 patch array. Objects are compared recursively, changed arrays are replaced as a whole. |
| `NativeJson.Patch` | `TJsonPatch.Apply(Document, Patch)`, all RFC 6902 operations, errors name the operation index. |
| `NativeJson.Pointer` | RFC 6901 `Resolve`, `TryResolve`, `Escape`, `Unescape`. |
| `NativeJson.Comparer` | `TJsonComparer.DeepEquals`: member order ignored, array order kept, numbers compared by exact value. |

## JSON Schema

Generate from a class, validate any document:

```pascal
Schema := JsonConvert.GenerateSchema<TCustomer>;
try
  Outcome := JsonConvert.ValidateJsonSchema(Json, Schema.ToJson);
  if not Outcome.IsValid then
    Writeln(Outcome.Errors[0].InstancePath, ' ', Outcome.Errors[0].Keyword, ': ', Outcome.Errors[0].Message);
finally
  Schema.Free;
end;
```

- **Generator:** Draft 2020-12 from RTTI, driven by attributes (`JsonTitle`, `JsonDescription`, `JsonSchemaFormat`, `JsonRequired`, `JsonRange`, `JsonExclusiveRange`, `JsonMultipleOf`, `JsonPattern`, `JsonMinLength`, `JsonMaxLength`, `JsonArrayLength`, `JsonUniqueItems`, `JsonReadOnly`, `JsonWriteOnly`, `JsonDeprecated`, `JsonExample`, `JsonSchemaExtension`). Polymorphic types become `oneOf` with definitions.
- **Validator:** Draft 7, 2019-09 and 2020-12 (`TJsonSchemaDialect.Auto` reads `$schema`), `$ref` and `$dynamicRef`, anchors, registered schemas by URI, format assertion on request, options for first-error stop, error limit, depth limit and strict schema checking. Errors carry the instance path, the schema path and the keyword.
- **Registry:** `TJsonSchemaRegistry` resolves references between documents; schemas passed to the validator are copied, callers may free theirs.
- **Exact numbers:** comparisons, `multipleOf`, `minimum` and `maximum` are evaluated on the decimal text.

```pascal
JsonConvert.ValidateJsonSchema('19.99', '{"multipleOf":0.01}').IsValid;                       // True
JsonConvert.ValidateJsonSchema('9007199254740993', '{"maximum":9007199254740992}').IsValid;   // False
```

## Code generation

Delphi source from a JSON Schema or an OpenAPI document (3.0 and 3.1, `components/schemas`):

```pascal
Generator := TNativeJsonSchemaCodeGenerator.Create;
try
  Generator.RegisterSchema('https://example.org/address.json', AddressSchema);
  Generator.LoadSchema(OrderSchema, 'https://example.org/order.json');
  Code := Generator.GenerateUnit('Shop.Model');
  Generator.SaveUnitToFile('Shop.Model.pas', 'Shop.Model');
finally
  Generator.Free;
end;
```

- External `$ref` targets come from `RegisterSchema` / `RegisterSchemaFromFile`, relative references resolve against the base URI.
- `SchemaToTypes` and `SchemaToUnit` are one-call variants; `TJsonCodeGenOptions` holds the generation options, for example `SetFormatKind`.
- Anything the generator cannot express exactly is reported through `Generator.Diagnostics` with a stable code (`CG...`), a schema path and a message instead of silently producing wrong code.
- The generated classes carry `[JsonProperty]` names and the schema as a constant, so they can be used with `JsonConvert` directly.

The suite in `Tests/Package3` (DUnitX) covers collections, composition, references, naming, OpenAPI, diagnostics, output and ownership.

## Exact numbers

The DOM stores each number as the text that was read. Conversions to `Currency`, `Int64`, `UInt64` and `Double` start from that text, and writing a DOM value back keeps its notation (`1e2` stays `1e2`).

- `Currency` is read and written without a detour through `Extended`; the result does not depend on Win32 or Win64.
- `Int64` and `UInt64` keep their full range; values beyond `Double` precision (for example `9007199254740993`) survive a round trip.
- `TJsonExactNumber` (`NativeJson.ExactNumber`) parses a decimal text to sign, digits and exponent and provides `Compare`, `Equals`, `IsInteger` and `IsMultipleOf` without floating point. The schema validator and the DOM comparer use it.

## Large documents

```pascal
Count := JsonConvert.DeserializeSequence<TCustomer>(Json,
  procedure(Item: TCustomer)
  begin
    Process(Item);
    Item.Free;
  end);
```

For a top-level array the handler receives one finished element at a time and owns it. Memory use depends on the size of one element, not on the count. `DeserializeSequenceFromStream` and `DeserializeSequenceFromFile` take a stream or file name; `TJsonElementSequence` (`NativeJson.Sequence`) is the same reader without a callback.

The stream variants read the whole stream into memory first.

## Validation rules from attributes

The schema attributes are also checked at runtime:

```pascal
[JsonRange(18, 120)]
property Age: Integer read FAge write FAge;

Outcome := JsonConvert.Validate(Customer);
try
  for I := 0 to Outcome.Count - 1 do
    Writeln(Outcome[I].Path, ' ', Outcome[I].Rule, ' ', Outcome[I].Message);
finally
  Outcome.Free;
end;
```

Validation is separate from reading: reading returns the object, `Validate` returns all violations at once with path, member name, rule and message.

## JSON5

`TJsonSettings.Json5 := True` accepts comments, trailing commas, single-quoted and unquoted keys, hexadecimal numbers, `Infinity` and `NaN`. Strict JSON stays the default. Output is always strict JSON; numbers are normalized, and `Infinity`/`NaN` can be read into floating point fields but not written.

## XML

`NativeJson.Xml` converts between XML text and the DOM. Typical uses: reading XML from SOAP or legacy interfaces into the same code path as JSON, validating XML content with a JSON Schema, producing XML for a system that does not take JSON.

```pascal
uses
  NativeJson.Xml;

Json := XmlToJson('<price currency="EUR">12.50</price>');
Xml := JsonToXml('{"person":{"name":"Anna","age":42}}');
```

`XmlToDom` and `DomToXml` work on DOM values instead of text. All four functions take an optional `TJsonXmlOptions`.

XML and JSON have no one-to-one mapping. The conversion follows the convention known from Newtonsoft.Json:

| XML | JSON |
| --- | --- |
| `<doc>...</doc>` | `{"doc": ...}`; the document element is the single property of the result |
| `<a>text</a>` | `"a": "text"` |
| `<a/>`, `<a></a>` | `"a": null` |
| `<a x="1">t</a>` | `"a": {"@x": "1", "#text": "t"}` |
| `<l><i>1</i><i>2</i></l>` | `"l": {"i": ["1", "2"]}` |
| `<l><i>1</i></l>` | `"l": {"i": "1"}`, or `["1"]` when `i` or `l/i` is in `ForceArrays` |
| `<p>a<b/>c</p>` | `"p": {"#text": ["a", "c"], "b": null}` |
| `<ns:a xmlns:ns="u">` | `"ns:a": {"@xmlns:ns": "u"}`; prefixes are kept as part of the name |
| `<first_x0020_name>` | `"first name"`; JSON keys that are not valid XML names are written in this encoding and decoded when read |

| Option | Default | Effect |
| --- | --- | --- |
| `AttributePrefix` | `@` | Key prefix for attributes |
| `TextKey` | `#text` | Key for text next to attributes or child elements |
| `ForceArrays` | empty | Element names (`item`) or paths from the document element (`list/item`) that always become arrays |
| `InferTypes` | `False` | XML to JSON: `true`/`false` become booleans, text in JSON number syntax becomes a number (raw text kept, so `18446744073709551615` stays exact; `007` stays a string). Otherwise every value is a string |
| `RootName` | empty | JSON to XML: name of the document element that wraps the value. Empty: the value must be an object with exactly one property |
| `Indent` | `False` | Indented output, for `XmlToJson` and `JsonToXml` |
| `WriteDeclaration` | `False` | JSON to XML: write `<?xml version="1.0" encoding="UTF-8"?>` |
| `MaxDepth` | 256 | Maximum element nesting, both directions |

What is not preserved:

- XML to JSON: comments, processing instructions, the DOCTYPE, the order between different child element names and between text and elements in mixed content. Whitespace-only text is dropped in elements that have attributes or child elements; in leaf elements it is kept. Line ends become LF.
- JSON to XML: empty arrays write nothing, empty objects become `<a/>` and read back as `null`, `null` attributes are left out. Arrays directly inside arrays and arrays as document element have no XML form and raise `EJsonXmlError`.
- Values are kept as text unless `InferTypes` is set; `JsonToXml(XmlToJson(Xml))` reproduces documents that follow the convention above, `XmlToJson(JsonToXml(Json))` reproduces typed JSON only with `InferTypes`.

The parser handles elements, attributes, text, CDATA, comments, processing instructions, the five predefined entities and character references. A DOCTYPE is skipped, never evaluated: entities declared in it are not expanded, external entities are never loaded, and a reference to them raises `EJsonXmlError` (no XXE, no entity expansion attacks). Errors report line and column. Input is a `string`; for files, read them with the encoding from their XML declaration first.

## CBOR

`NativeJson.Cbor` converts between CBOR (RFC 8949) and the DOM; `NativeJson.Cbor.Convert` adds the object level. CBOR is the binary format behind WebAuthn/FIDO2, COSE/CWT and CoAP. The codec has its own reader and writer and no dependency on the serializer.

```pascal
Cbor := JsonToCbor('{"id":7,"temp":21.5,"ok":true}');       // TBytes
Json := CborToJson(Cbor);

Dom  := CborToDom(Cbor);                                      // caller frees
Cbor := DomToCbor(Dom);

Cbor := CborConvert.SerializeObject(Customer);                // Delphi object to CBOR
Back := CborConvert.DeserializeObject<TCustomer>(Cbor);
```

Mapping from CBOR to the DOM:

| CBOR | DOM |
| --- | --- |
| unsigned and negative integers, full range from -2^64 to 2^64-1 | number with exact text |
| bignum (tags 2 and 3) | number with exact text, any size |
| decimal fraction (tag 4), bigfloat (tag 5) | number with exact decimal text (`273.15`, `1E1000`) |
| half, single, double | number; the exact value of the float, printed as the shortest text that reads back to the same `Double` |
| text string | string; invalid UTF-8 is rejected |
| byte string | `TJsonBytes` node: a string for every consumer (Base64Url by default, RFC 8949 6.1; `BytesMode` selects Base64 or hex) that also keeps the bytes; `cbmWrapped` produces `{"@bytes":"..."}` for JSON text |
| array, map | array, object; integer, boolean, null, float and byte string keys become text (`KeyMode`, see Integer map keys) |
| `false`, `true`, `null`, `undefined` | boolean, null (`undefined` is an error with `UndefinedAsNull := False`) |
| NaN, Infinity | error; `NonFinite` selects `null` or the text `NaN`, `Infinity`, `-Infinity` |
| other tags | the tagged value; with `TagMode := ctmWrap` the object `{"@tag":n,"@value":...}` |
| indefinite-length strings, arrays, maps | supported; chunks are validated |

Mapping from the DOM to CBOR:

- Integers use the shortest head; integers beyond 64 bits become bignums.
- Floats use preferred serialization (RFC 8949 4.1): half, single or double, whichever holds the value exactly. A number written with a fraction or exponent stays a float, so `1` and `1.0` keep their types.
- `ExactDecimals` (default): a decimal whose digits a `Double` cannot hold is written as a decimal fraction (tag 4) instead of being rounded. `1.00000000000000000001` and a `Currency` like `1234567890123.4567` survive; `0.1` or `19.99` stay doubles because the double reads back to the same decimal.
- Object keys are written as text strings. With `KeyMode := ckmInteger` a key that is the canonical decimal form of an integer between -2^64 and 2^64-1 is written as a CBOR integer instead.
- `Deterministic := True` sorts map keys by their encoding (RFC 8949 4.2.1), for signatures and content addressing. Without it the member order of the DOM is kept. `KeyOrder := ckoLengthFirst` selects the older length-first order (RFC 7049 3.9) that CTAP2 and therefore WebAuthn authenticators use; the two orders differ as soon as keys of different types or lengths are mixed, for example the integer `256` against the text `"a"`.
- A `TJsonBytes` node is written as a byte string, whatever its text form. When the DOM comes from JSON text, an object with the single member `@bytes` is written as a byte string too; an object with `@tag` and `@value` becomes a tag (with `TagMode := ctmWrap`).

Integer map keys: COSE and CWT label their map entries with integers (`1` is the key type, `3` the algorithm, `-1` the curve). The DOM has text keys only, so reading such a map gives `{"1":2,"3":-7,"-1":1}`. With the default `KeyMode := ckmStringify` writing it back produces text keys, which is a different byte sequence and breaks a signature over the original bytes. Set `KeyMode := ckmInteger` on both sides and the map is reproduced exactly:

```pascal
Options.KeyMode := ckmInteger;
Json  := CborToJson(Cose, Options);
Again := JsonToCbor(Json, Options);
```

A key counts as an integer only in canonical form: `"1"` and `"-7"` do, `"01"`, `"-0"`, `"+1"`, `"1.0"` and numbers beyond the 64-bit range stay text. The option therefore assumes that a map does not mix the integer `1` and the text `"1"`; such a map reads with a duplicate key error anyway. `ckmText` is the opposite setting: it rejects every map key that is not a text string. Combined with `Deterministic`, integer keys are ordered by their encoded bytes (RFC 8949 4.2.1), so small non-negative integers come first, then negative integers, then text.

Floating-point numbers are converted by `NativeJson.FloatText`, so the printed text is the shortest one that reads back to the same `Double` (`0.1`, `5E-324`, `-8.584287591200702E-15`), the same digits other runtimes print.

Input from outside is checked: a declared length larger than the remaining data is rejected before anything is allocated, nesting is limited by `MaxDepth` (default 256, also for chains of tags), duplicate map keys are an error unless `DuplicateKeys` says otherwise, reserved additional information, stray breaks and trailing bytes are errors. `CborToDomAt` reads one item at a given position, for CBOR sequences (RFC 8742). All errors are `EJsonCborError` with the byte offset.

Object serialization goes through the JSON text: `CborConvert` serializes with `TJsonSettings.WrapBytes`, so `TBytes` members are written as `{"@bytes":...}` and become CBOR byte strings; on reading they are restored from the wrapper. `JsonConvert` itself still writes Base64 text unless `WrapBytes` is set, and reads the wrapper in addition to a Base64 string or a number array. Tags are not part of the object model: they are dropped on reading, or kept as `{"@tag":n,"@value":...}` with `TagMode := ctmWrap` when working with the DOM (COSE structures, for example).

## System.JSON interop

Applications that already hold data as `System.JSON.TJSONValue` - typically a REST client, where `TRESTResponse.JSONValue` returns one - can validate it directly, without writing it to text and parsing it again:

```pascal
uses
  System.JSON, NativeJson.Schema.Validation, NativeJson.SystemJson;

R := ValidateSystemJson(RESTResponse.JSONValue, Schema);
if not R.IsValid then
  raise Exception.Create(R.ToString);
```

For many instances, create the validator once and reuse it:

```pascal
Validator := CreateSchemaValidator(Schema);
try
  RegisterSystemJsonSchema(Validator, 'https://example.org/address.json', AddressSchema);
  for Item in Items do
    Report(ValidateSystemJson(Validator, Item));
finally
  Validator.Free;
end;
```

`NativeJsonFromSystemJson(Value)` converts any `TJSONValue` into a NativeJson DOM value owned by the caller. Numbers are taken from the text `System.JSON` holds, so large integers and decimals stay exact. Schemas are copied into the validator; the `System.JSON` objects stay owned by the caller and may be freed right after the call.

The unit is the only one in the library that uses `System.JSON`. Programs that do not list it in their `uses` clause do not link `System.JSON`. Under FPC it compiles, but FPC's own `System.JSON` stores numbers as `Double`/`Int64` and loses their text, so decimals beyond double precision and values above `High(Int64)` are not exact there.

## Delphi and Free Pascal

One code base for Delphi 12 and Free Pascal 3.3.1 (trunk). Compiler differences are confined to `NativeJson.Compat` and `NativeJson.inc`. What works, what does not and how to build: [fpcReadme.md](fpcReadme.md). Verified toolchains: [COMPATIBILITY.md](COMPATIBILITY.md).
