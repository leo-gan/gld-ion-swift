# Instructions

These steps assume a Linux machine and Swift 6.3. The Swift module is `Ion`.
The command-line generator is `gld-iongen-swift`.

## Add the package

```swift
dependencies: [
    .package(url: "https://github.com/leo-gan/gld-ion-swift", from: "0.1.0"),
]
```

Depend on the `Ion` product. `import Ion` then resolves `decode` and `encode`.

## Build this repository

```bash
git clone https://github.com/leo-gan/gld-ion-swift.git
cd gld-ion-swift
bash scripts/run-tests.sh
```

Swift 6.3 must be on `PATH`. A checkout that uses swiftly can rely on
`scripts/run-tests.sh`, which prepends `~/.local/share/swiftly/bin` when that
toolchain is installed.

| Script | What it runs |
| --- | --- |
| `bash scripts/run-tests.sh` | Unit tests, then every file in the vendored ion-tests corpus. |
| `bash scripts/generate.sh` | Writes `tests/generated` from `testdata/schema`. |
| `bash scripts/check-generated.sh` | Regenerates into a temp directory and diffs. |
| `bash scripts/run-microbench.sh` | Prints nanoseconds per encode and decode of a 32-struct document. |

## Decode and encode

```swift
import Ion

let cat = Catalog()
let doc = try decode(Array("{a:1}\n".utf8), cat)
let raw = try encode(doc, EncodeOptions(binary: true, pretty: false, version: 10), cat)
print(raw.count)
```

`EncodeOptions` fields:

| Field | Meaning |
| --- | --- |
| `binary` | When true, `encode` writes binary Ion. Otherwise it writes UTF-8 text. |
| `pretty` | Indent text. Binary ignores it. |
| `version` | `10` for Ion 1.0, `11` for the Ion 1.1 draft. |
| `addImport(name, version)` | Shared table the Ion 1.0 binary writer imports. |

A leading `E0 01` version marker selects the binary decoder. Any other byte
string is text. The text decoder accepts UTF-8 and transcodes UTF-16 or UTF-32
when a wide encoding is obvious from the first bytes.

## Generate Swift

A JSON Schema file:

```bash
swift run gld-iongen-swift -- --schema testdata/schema/message.json --out tests/generated
```

An Ion Schema file is Ion text:

```bash
swift run gld-iongen-swift -- --schema testdata/schema/point.ion --out tests/generated
```

The generator writes one `.swift` file per struct. Compile generated code in a
target that depends on `Ion`. Structs in the same module can name each other
without an extra import.

## Document the package

```bash
pip install -r requirements-docs.txt
mkdocs build --strict
```

The site is Material for MkDocs with an indigo primary color and a teal accent.
