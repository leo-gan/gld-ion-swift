# gld-ion-swift

A from-scratch Amazon Ion implementation for Swift.
The runtime and the code generator are Swift. They do not wrap, link, or vendor
ion-c, ion-java, ion-swift, or any other C, C++, or Rust Ion library.

Python `amazon-ion` is a **test oracle** only. It is not required to encode or
decode at runtime.

This repository is a standalone library. It is not part of any other project.

Documentation: [Why Ion](https://leo-gan.github.io/gld-ion-swift/why-ion/),
[Instructions](https://leo-gan.github.io/gld-ion-swift/instructions/),
[Examples](https://leo-gan.github.io/gld-ion-swift/examples/),
[Techniques](https://leo-gan.github.io/gld-ion-swift/techniques/),
[Test data](https://leo-gan.github.io/gld-ion-swift/test-data/).

## Install

Swift Package Manager, Swift 6.3. The module is `Ion`. The generator binary is
`gld-iongen-swift`.

```swift
dependencies: [
    .package(url: "https://github.com/leo-gan/gld-ion-swift", from: "0.2.0"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "Ion", package: "gld-ion-swift"),
    ]),
]
```

Registration on the Swift Package Index: [docs/publishing.md](docs/publishing.md).

From a git checkout:

```bash
git clone https://github.com/leo-gan/gld-ion-swift.git
cd gld-ion-swift
bash scripts/run-tests.sh
```

## What it reads and writes

| Surface | Behavior |
| --- | --- |
| Ion 1.0 text and binary | Decode every legal value in the vendored ion-tests corpus. Encode compact text or length-prefixed binary. |
| Ion 1.1 draft | Little-endian values, inline symbols, delimited containers, directives, and template macros. |
| Numbers | Arbitrary-precision integers and decimals. Decimal scale is kept, so `1.0` and `1.00` stay distinct. |
| Timestamps | Instant, local offset, and precision from year through fractional seconds. |
| Schema | JSON Schema objects and Ion Schema `type` definitions. `gld-iongen-swift` emits structs with `encodedLen`, `encode(to:options:)`, and `decode(from:)`. |

The encoder drops comments and whitespace. Two encodes of the same value match
when the options match. A catalog supplies shared symbol tables. Unknown
imported symbols stay unknown and compare by import name and import id.

## Layout

`src/` is the `Ion` module: the document arena, the text parser, the Ion 1.0
and 1.1 readers and writers, schema parsing, and the code generator.
`src/codegen` is the `gld-iongen-swift` executable.

Requires **Swift 6.3**.
