# Security

## Untrusted input

- JSON Schema validation: `TJsonSchemaValidationOptions.MaxDepth` limits the validation depth.
- CBOR (`NativeJson.Cbor`): declared lengths are checked against the remaining input before allocation, nesting (including chains of tags) is limited by `MaxDepth`, text strings are validated as UTF-8 (overlong forms, surrogates and code points above U+10FFFF are rejected), duplicate map keys are an error by default, bignum and bigfloat exponents are bounded. Mutated and random input was fuzzed; the only exception it raises is `EJsonCborError`.
- XML (`NativeJson.Xml`): the DOCTYPE is skipped and never evaluated; entities declared in it are not expanded and external entities are never resolved, so XXE and entity expansion attacks do not apply. Element nesting is limited by `TJsonXmlOptions.MaxDepth` (default 256). Input size is not limited; the caller decides how much text it reads.
