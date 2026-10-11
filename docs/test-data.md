# Test data

The tests are split into a vendored corpus and a few local schemas. Those files
live under `testdata/`.

## ion-tests

`testdata/ion-tests` is a copy of the upstream
[amazon-ion/ion-tests](https://github.com/amazon-ion/ion-tests) data files.
Those files keep their Apache-2.0 license. `testdata/ion-tests/LICENSE` and
`NOTICE` are the upstream texts. The library's own code stays MIT.

| Directory | What a passing run means |
| --- | --- |
| `iontestdata/good` | The file decodes. |
| `iontestdata/bad` | The file raises `DecodeError`. |
| `iontestdata/good/equivs` | Each top-level group contains equivalent values. `embedded_documents` groups are parsed again before the comparison. |
| `iontestdata/good/non-equivs` | Values in a group are pairwise not equivalent. |
| `catalog` | Shared symbol tables the suite loads before each file. |

`bash scripts/run-tests.sh` builds `ion-suite` once and runs that program on
every `.ion` and `.10n` file. The current copy has 785 files. The expected
result is zero failures.

The corpus covers Ion 1.0. Ion 1.1 behavior is checked by local tests for the
binary spec examples, directives and macros, and the 1.1 writer. Those include
binary int `0` as `E0 01 01 EA 60` and the Ion 1.0 form `E0 01 00 EA 20`,
`null.int`, a list, an empty delimited list, and a symbol table.

## Schemas

| File | What it generates |
| --- | --- |
| `testdata/schema/message.json` | `Message`, a closed JSON Schema object with Ion extensions for timestamp and blob. |
| `testdata/schema/point.ion` | `Point`, an Ion Schema struct with an optional int and a symbol. |

`bash scripts/check-generated.sh` writes those files again and diffs them
against `tests/generated`. A drift fails the check.

The unit tests fill a `Message` and a `Point`, encode them, and decode them
back. The timestamp `2023T` and the symbol `foo` must come back unchanged.
Round trips cover bool, int, float, decimal, timestamp, string, symbol, blob,
clob, list, sexp, struct, and annotations, in text and in both binary versions.
