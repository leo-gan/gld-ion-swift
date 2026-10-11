# gld-ion-swift design

gld-ion-swift is a from-scratch Amazon Ion 1.0 and Ion 1.1 library for Swift 6.3.
The runtime never calls an Ion library written in another language. Python
`amazon-ion` may be used as a test oracle. It is not a build or run dependency.

## Goals

The library decodes every legal Ion 1.0 text and binary value and rejects the
inputs the ion-tests corpus marks as bad. Equivalence follows the Ion data
model: struct order does not matter, decimal scale does, and typed nulls stay
typed. Encoding is a semantic transcode. The caller chooses compact text or
length-prefixed binary, Ion 1.0 or the Ion 1.1 draft, and which shared symbol
tables the binary writer imports.

A second API generates Swift structs from a JSON Schema document or from an Ion
Schema `type` definition. Generated structs call the dynamic document API.
They expose `encodedLen`, `encode(to:options:)`, and `decode(from:)`.

## Document model

Values live in one `IonDoc` arena. A node is a small integer struct. Strings,
symbol text, integer limbs, float bits, timestamps, and blob bytes sit in
parallel arrays. Containers are singly linked edges, so a node never contains
another node.

| Kind | What the node stores |
| --- | --- |
| Null | The null's type, or `null.null` when the type is absent. |
| Int | Sign and little-endian `UInt32` limbs. Zero has no limbs. |
| Decimal | Sign, coefficient limbs, and the base-10 exponent. Negative zero is a sign with an empty coefficient. |
| Float | Width 0, 2, 4, or 8, and the IEEE bits. |
| Timestamp | Local calendar fields, offset minutes or unknown `-00:00`, and precision. |
| Symbol | Text when it is known. An unknown import stores the import name and the id inside that import. |
| Container | Head and tail edge indexes. Struct fields keep source order. |

Symbol tables are segments, not a dense array of every id. A shared import
with a huge `max_id` stores only the symbols the catalog actually defines.
The tail stays unknown. Lookup of an unknown local symbol compares equal to
symbol zero. Lookup of an unknown imported symbol compares the import name
and the import id.

## Ion 1.0

Text decoding accepts UTF-8 and transcodes a leading UTF-16 or UTF-32 body.
The parser keeps annotations, field order, decimal scale, and timestamp
precision. It drops comments and whitespace. A top-level
`$ion_symbol_table` struct updates the local table. A bare `$ion_1_0` or
`$ion_1_1` is a version marker.

Binary decoding requires a version marker on a non-empty stream. Integers,
decimals, and timestamps follow the big-endian Ion 1.0 layout. NOP padding is
skipped. A binary timestamp is UTC on the wire. The reader converts
minute-or-finer values to local time, including a date change when the offset
crosses midnight. Year, month, and day values force an unknown offset,
because the corpus treats a stored offset at that precision as superfluous.

The text writer emits `$ion_1_0` or `$ion_1_1`, then one value per line in
compact form. `EncodeOptions.pretty` inserts newlines and indentation. The
Ion 1.0 binary writer emits a local symbol table for symbols outside the
system set, then length-prefixed values. Field order, annotations, decimal
scale, and timestamp precision are preserved. The binary timestamp writer
converts local time back to UTC and shifts the calendar date when needed.

## Ion 1.1 draft

The Ion 1.1 specification is still a draft. This library implements the
binary opcode map and the text forms that the draft uses for the same ideas.

| Feature | Reader | Writer |
| --- | --- | --- |
| Version marker `E0 01 01 EA` and `$ion_1_1` | Yes | Yes |
| Little-endian ints, floats, decimals | Yes | Yes |
| Inline symbol text and symbol addresses | Yes | Inline text |
| Length-prefixed and delimited containers | Yes | Length-prefixed; structs use FlexSym |
| Short-form and long-form timestamps | Yes | Long form, local time |
| `set_symbols` and `add_symbols` | Yes | Not emitted; symbols are inline |
| `set_macros` and `add_macros` | Yes | Not emitted; writers may always use literals |
| Tagged e-expressions, defaults, absent `(:)` | Yes | Not emitted |
| Binary tagless primitive arguments | Yes | Not emitted |
| `use` of a catalog module | Yes | `EncodeOptions.addImport` on Ion 1.0; inline symbols on Ion 1.1 |
| `module`, `import`, and `encoding` | Consumed at the top level | Not emitted |

A macro template is an s-expression `(name body)` stored in the caller's
document. Placeholders are hole nodes. Expansion copies containers and shares
scalar nodes. An absent argument with no default drops that field or element.
An absent argument with a default copies the default. A template that is only
a placeholder is rejected. A template may not call another macro.

An Ion version marker resets the symbol table and the macro table. In a 1.1
stream, a top-level Ion 1.0 symbol-table struct is a no-op.

## Schema and code generation

`gld-iongen-swift --schema FILE --out DIR` reads one schema. JSON Schema is
legal Ion, so the same decoder reads both files.

The JSON Schema subset is `type`, `properties`, `required`, `items`,
`additionalProperties`, `title`, `$id`, `$ref`, and `$defs`. `ionType` adds
`decimal`, `timestamp`, `symbol`, `blob`, `clob`, and `sexp`. An Ion Schema
file is a datagram of `type::{ name, type: struct, fields, content }` values.
`occurs: optional` marks a field that may be missing. `content: closed` rejects
unknown fields, as `additionalProperties: false` does for JSON Schema.

Generated structs are value types. Integers that fit in `Int64` use `Int64`.
A wider integer raises `DecodeError.kindRange`. Decimals, timestamps, and
symbols are stored as their Ion text so scale and precision survive.
Blobs and clobs are `[UInt8]`. Nested structs are fields of the generated
type. Lists of scalars and of generated structs are `[T]`.

`encode(to:options:)` builds an `IonDoc` and calls the same encoders as the
dynamic API. `encodedLen` is the length of that encoding. `decode(from:)`
accepts text or binary and checks each field's type.

## Testing

`testdata/ion-tests` is a copy of the upstream ion-tests good, bad, equivs,
and non-equivs files, under the Apache-2.0 license in that directory. The
suite runs the corpus in one process and reports each failing path. A file
under `bad/` must fail. Equivalence groups must agree. Non-equivalence groups
must disagree. Local tests cover big integers, text and binary round trips,
Ion 1.1 spec examples, macros, and generated structs.

## Packaging

The Swift module is `Ion`. The generator binary is `gld-iongen-swift`.
The package version starts at `0.1.0` in `src/Version.swift`. There is no
conda publish workflow.
