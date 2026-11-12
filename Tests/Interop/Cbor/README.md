# CBOR interoperability checks

These scripts compare `NativeJson.Cbor` with an independent implementation (Python `cbor2`) and with published COSE test vectors. They are not part of the regular test run because they need Python and network access once.

| Script | What it checks |
| --- | --- |
| `harness.py COUNT SEED` | random structures: decode `cbor2` output (plain and canonical), let `cbor2` read our output, and a byte-exact canonical round trip |
| `vectors.py` | all COSE examples of the cose-wg repository (`fetch_cose.py` downloads them): same value as `cbor2`, byte-identical round trip |
| `canon.py COUNT SEED` | deterministic encoding with `KeyOrder := ckoLengthFirst` against the canonical output of `cbor2` |
| `webauthn.py` | WebAuthn-shaped attestation objects: nested authenticator data, COSE keys with integer labels, CBOR sequences |

```
pip install cbor2
dcc64 CborInterop.dpr            (or: fpc -Mdelphi -Fu../../../src -Fi../../../src CborInterop.dpr)
python fetch_cose.py
python harness.py 3000 7
python vectors.py
python canon.py 4000 3
python webauthn.py
```

`CborInterop.exe` reads one command per line from standard input: `D <hex>` (CBOR to JSON), `E <json>` (JSON to CBOR hex), `S <hex>` (all items of a CBOR sequence). The first line selects options: `int` (`ckmInteger`), `wrap` (byte and tag wrappers), `det` (`Deterministic`), `len` (`ckoLengthFirst`), `nodec` (`ExactDecimals := False`).
