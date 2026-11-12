# Test Package 2

Six programs, partly modeled on the structure of the Neon test suite. They add
axes to the demos that were not covered systematically there.

| Program | Neon model | What is checked |
|---|---|---|
| `Test2_NumberFormats` | `Types.Simple` | Every number type at its four corners, exponential notation, invalid notations, floating point round trip |
| `Test2_NullAndEmpty` | `Deserializer.Null` | `null` vs. empty string vs. missing field, `null` in lists, empty array and object |
| `Test2_Characters` | `Types.Strings`, `Types.Reference` | Escaping, control characters, Unicode, surrogate pairs across the buffer chunk limits, keys with special characters |
| `Test2_Accessors` | `Attributes.GetterSetter` | `[JsonGetter]`/`[JsonSetter]` redirection to fields and methods, wrong targets, validation through the same access |
| `Test2_SchemaValidator` | JSON Schema test suite layout | `type`, number limits without floating point loss, string length in code points, objects, arrays, `oneOf`/`anyOf`/`allOf`/`not`/`if`, `$ref` recursion, error paths, options, closed loop generator/serializer/validator |
| `Test2_Json5` | – | JSON5 switch: strict by default, JSON5 syntax, number normalization, strings, invalid input, deserializing into a class, Infinity/NaN |

## Why these

The demos show **capabilities** with one example each. This package walks through
**value ranges**. Both are needed: a demo shows that something works, a matrix test
shows where it stops working.

This is not theoretical. While designing `Test2_NumberFormats` it turned out that the
new range check rejected `{"Count":1e2}` - valid JSON meaning 100. A single example
would never have found that.

## Known red line

`Test2_SchemaValidator` reports 113 passed, 1 failed. The failing case expects
`"a"` to fail `{"oneOf":[{"type":"integer"},{"minimum":5}]}`; per specification
`minimum` ignores non-numbers, so `"a"` matches exactly one branch and is valid. The
test expectation is wrong, not the validator.

## Building

The programs use `Demo.Assert` from `examples\Demos`. The unit search path in the
`.dproj` files is `..\..\src;..\..\examples\Demos;.`; whoever moves the files has to
adjust it. With FPC: `examples\Demos\Demos_FPC.bat` builds and runs them together
with the demos.
