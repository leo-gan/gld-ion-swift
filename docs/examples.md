# Examples

The dynamic API and the generated API write the same Ion. Use the dynamic API
when the shape is not known ahead of time. Use a generated struct when a schema
already names the fields.

## Dynamic document

`examples/main.swift` decodes one struct and writes it twice. Run it with
`swift run encode-value`.

```swift
import Ion

let cat = Catalog()
let doc = try decode(Array("{a:1,b:\"hi\"}\n".utf8), cat)
let text = try encode(doc, EncodeOptions(binary: false, pretty: false, version: 10), cat)
let binary = try encode(doc, EncodeOptions(binary: true, pretty: false, version: 11), cat)
print("text bytes", text.count)
print("ion 1.1 binary bytes", binary.count)
```

Ion 1.0 text starts with `$ion_1_0`. Ion 1.1 binary starts with `E0 01 01 EA`
and stores the field name `a` as inline symbol text, so the stream has no
symbol table.

## Build a value without parsing

```swift
import Ion

let doc = IonDoc()
let st = doc.startContainer(kStruct)
let field = doc.addSymbolText("n")
doc.addChild(st, doc.addI64(150), doc.nodes[field].a)
doc.addTop(st)
```

`kStruct` is the struct kind. `addI64` accepts any `Int64`. Wider integers go
through `addInt` and a `BigInt`. `addDecimal` keeps the coefficient and the
exponent, including a negative zero. `addTime` keeps precision and offset.

## Generated struct

`testdata/schema/message.json` describes a closed object. After
`bash scripts/generate.sh`, `tests/generated/Message.swift` has the fields
below.

| Schema field | Swift field | Required |
| --- | --- | --- |
| `id` | `Int64` | yes |
| `name` | `String` | yes |
| `ok` | `Bool` | no |
| `weight` | `Double` | no |
| `tags` | `[String]` | no |
| `when` | `String` holding Ion timestamp text | no |
| `payload` | `[UInt8]` | no |

```swift
var msg = Message()
msg.id = 7
msg.name = "ada"
msg.has_when = true
msg.when = "2023T"
var buf: [UInt8] = []
try msg.encode(to: &buf, EncodeOptions(binary: true, pretty: false, version: 10))
let back = try Message.decode(from: buf)
```

Optional fields use a `has_` flag. A missing flag omits the field. A closed
schema raises `DecodeError.kindSchema` when a required field is absent or an
unknown field is present.

`testdata/schema/point.ion` is Ion Schema. `label` is a symbol, so the
generated `String` holds Ion symbol text such as `foo`, not a quoted string.
`encode` with version `11` writes an Ion 1.1 binary struct.
