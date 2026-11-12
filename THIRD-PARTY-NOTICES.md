# Third-party notices

NativeJson is licensed under the MIT License (see [LICENSE](LICENSE)). Every source file carries an SPDX header with the copyright holder and license.

## Code and data included in this repository

No third-party source code, binary or data file is included. The algorithms the library implements (number conversion, UTF-8 validation, Base64, JSON Pointer, JSON Patch, JSON Schema, CBOR, XML mapping) come from public specifications and were written for this project; the specifications themselves are not reproduced.

Test data is authored for this project (`Tests/Package3/Data`) or taken from the examples printed in the specifications named below, which are short vectors needed to check conformance.

## Specifications implemented

| Specification | Used for |
| --- | --- |
| RFC 8259, ECMA-404 | JSON |
| JSON5 1.0 | optional relaxed input |
| RFC 6901, RFC 6902, RFC 7386 | JSON Pointer, JSON Patch, JSON Merge Patch |
| JSON Schema 2020-12 / OpenAPI 3.1 | schema validation and code generation |
| RFC 8949 (Appendix A vectors) | CBOR |
| RFC 7049 section 3.9 | length-first key order (`ckoLengthFirst`) |
| IEEE 754 | floating-point conversion |

## Tools used during development, not distributed

| Tool | License | Use |
| --- | --- | --- |
| `cbor2` (Python) | MIT | independent CBOR implementation for `Tests/Interop/Cbor` |
| cose-wg/Examples | Unlicense | COSE test messages, downloaded on demand by `Tests/Interop/Cbor/fetch_cose.py` into an ignored folder |
| Free Pascal and Delphi runtime libraries | FPC: LGPL with linking exception; Delphi: Embarcadero license | linked by the compiler into programs built from this repository; not part of it |

## If third-party code is added

Keep its original license text and copyright notice next to the code or in this file, record the origin and version here, and mark the files in the SPDX header with the license that applies to them.
