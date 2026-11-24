import Testing
import Ion

private let message = IonTree.fields([
    ("f_bool", .bool(true)),
    ("f_int32", .int(7)),
    ("f_int64", .int(99)),
    ("f_float64", .float(1.25)),
    ("f_string", .string("ada")),
    ("f_bool_2", .bool(false)),
    ("f_int32_2", .int(-3)),
    ("f_string_2", .string("x")),
])

private let messageHex =
    "e00100eaeecf8183decb87bec886665f626f6f6c87665f696e74333287665f696e74363489665f666c6f6174363488665f737472696e6788665f626f6f6c5f3289665f696e7433325f328a665f737472696e675f32de9f8a118b21078c21638d483ff40000000000008e836164618f10903103918178"

@Test func treeHexFixtures() throws {
    let samples: [(IonTree, String)] = [
        (.bool(true), "e00100ea11"),
        (.int(0), "e00100ea20"),
        (.int(-3), "e00100ea3103"),
        (.int(Int64.min), "e00100ea388000000000000000"),
        (.float(-0.0), "e00100ea488000000000000000"),
        (.string("ada"), "e00100ea83616461"),
        (.list([.int(1), .string("z")]), "e00100eab42101817a"),
        (message, messageHex),
    ]
    for (value, want) in samples {
        let raw = encodeTree(value)
        #expect(hex(raw) == want)
        let back = try decodeTree(raw)
        if case .float(let got) = back, case .float(let exp) = value {
            #expect(got.bitPattern == exp.bitPattern)
        } else {
            #expect(back == value)
        }
        #expect(hex(encodeTree(back)) == want)
    }
}

@Test func treeScalarsAndContainers() throws {
    let samples: [(IonTree, String)] = [
        (.null, "e00100ea0f"),
        (.bool(false), "e00100ea10"),
        (.string(""), "e00100ea80"),
        (.list([]), "e00100eab0"),
        (.fields([]), "e00100ead0"),
        (.float(0), "e00100ea480000000000000000"),
        (.float(1.25), "e00100ea483ff4000000000000"),
        (.int(1), "e00100ea2101"),
        (.int(255), "e00100ea21ff"),
        (.int(256), "e00100ea220100"),
        (.int(-1), "e00100ea3101"),
        (.int(-256), "e00100ea320100"),
        (.int(65536), "e00100ea23010000"),
        (.int(16_777_216), "e00100ea2401000000"),
        (.int(4_294_967_296), "e00100ea250100000000"),
        (.int(Int64.max), "e00100ea287fffffffffffffff"),
        (.string("abcdefghijklmn"), "e00100ea8e8e6162636465666768696a6b6c6d6e"),
        (.fields([("b", .int(1)), ("a", .int(2))]), ""),
        (.fields([("a", .int(1)), ("a", .int(2))]), ""),
        (.fields([("symbols", .int(1))]), ""),
        (.string("héllo"), ""),
        (.list([
            .fields([("sku", .string("a")), ("qty", .int(2))]),
            .fields([("sku", .string("bb")), ("qty", .int(0)), ("price_minor", .int(-1))]),
        ]), ""),
    ]
    for (value, want) in samples {
        let raw = encodeTree(value)
        if !want.isEmpty { #expect(hex(raw) == want) }
        let back = try decodeTree(raw)
        #expect(back == value)
        #expect(try decodeTree(raw) == value)
    }
    let one = encodeTree(.fields([("n", .int(1))]))
    let two = encodeTree(.fields([("n", .int(256))]))
    #expect(try decodeTree(one) == .fields([("n", .int(1))]))
    #expect(try decodeTree(two) == .fields([("n", .int(256))]))
    #expect(try decodeTree(one) == .fields([("n", .int(1))]))
    let msg = encodeTree(message)
    #expect(try decodeTree(msg) == message)
    #expect(try decodeTree(bytes("e00100ea11")) == .bool(true))
    #expect(try decodeTree(msg) == message)
    let neg = try decodeTree(bytes("e00100ea488000000000000000"))
    if case .float(let d) = neg {
        #expect(d.bitPattern == UInt64(0x8000_0000_0000_0000))
    } else {
        Issue.record("expected -0")
    }
}

@Test func treeNopVersionAndShapes() throws {
    #expect(try decodeTree([]) == .null)
    #expect(try decodeTree(bytes("e00100ea")) == .null)
    #expect(try decodeTree(bytes("e00100ea00")) == .null)
    #expect(try decodeTree(bytes("e00100ea0f00")) == .null)
    #expect(try decodeTree(bytes("e00100ea000f")) == .null)
    #expect(try decodeTree(bytes("e00100ea000f00")) == .null)
    #expect(try decodeTree(bytes("e00100ea1110")) == .list([.bool(true), .bool(false)]))
    #expect(try decodeTree(bytes("e00100eae3818411")) == .bool(true))
    #expect(try decodeTree(bytes("e00100ea7104")) == .string("name"))
    #expect(try decodeTree(bytes("e00100ea40")) == .float(0))
    #expect(try decodeTree(bytes("e00100ea4480000000")).floatBits() == (-0.0).bitPattern)
    #expect(try decodeTree(bytes("e00100ead0")) == .fields([]))
    #expect(try decodeTree(bytes("e00100eadf")) == .null)
    #expect(try decodeTree(bytes("e00100ea1f")) == .null)
    #expect(try decodeTree(bytes("e00100ead28000")) == .fields([]))
    #expect(try decodeTree(bytes("e00100ead28400")) == .fields([]))
    #expect(try decodeTree(bytes("e00100ead480008411")) == .fields([("name", .bool(true))]))
    #expect(try decodeTree(bytes("e00100ead484118000")) == .fields([("name", .bool(true))]))
    #expect(try decodeTree(bytes("e00100ead186840f85108611")) == .fields([
        ("name", .null),
        ("version", .bool(false)),
        ("imports", .bool(true)),
    ]))
    #expect(try decodeTree(bytes("e00100ead6840f85108611")) == .fields([
        ("name", .null),
        ("version", .bool(false)),
        ("imports", .bool(true)),
    ]))
    #expect(try decodeTree(bytes("e00100eab8d186840f85108611")) == .list([
        .fields([
            ("name", .null),
            ("version", .bool(false)),
            ("imports", .bool(true)),
        ]),
    ]))
    #expect(try decodeTree(bytes("e00100eadd848b3132333435363738394142")) == .fields([
        ("name", .string("123456789AB")),
    ]))
    #expect(try decodeTree(bytes("e00100eade8e848c313233343536373839414243")) == .fields([
        ("name", .string("123456789ABC")),
    ]))
    do {
        _ = try decodeTree(bytes("e00101ea11"))
        Issue.record("expected version error")
    } catch let err as DecodeError {
        #expect(err.kind == DecodeError.kindVersion)
    }
    for bad in ["e00100ea50", "e00100ea60", "e00100eaa0", "e00100eac0"] {
        do {
            _ = try decodeTree(bytes(bad))
            Issue.record("expected type error \(bad)")
        } catch let err as DecodeError {
            #expect(err.kind == DecodeError.kindType)
        }
    }
    var deep: [UInt8] = [0xE0, 0x01, 0x00, 0xEA]
    var n = 0
    while n < 1026 {
        deep.append(0xB1)
        n += 1
    }
    deep.append(0x10)
    do {
        _ = try decodeTree(deep)
        Issue.record("expected depth error")
    } catch let err as DecodeError {
        #expect(err.kind == DecodeError.kindDepth)
    }
}

@Test func treeReadsWriter() throws {
    let cat = Catalog()
    let opt = EncodeOptions(binary: true, pretty: false, version: 10)
    let doc = IonDoc()
    let st = doc.startContainer(kStruct)
    func field(_ name: String, _ child: Int) {
        let sym = doc.addSymbolText(name)
        doc.addChild(st, child, doc.nodes[sym].a)
    }
    field("f_bool", doc.addBool(true))
    field("f_int32", doc.addI64(7))
    field("f_int64", doc.addI64(99))
    field("f_float64", doc.addFloat(8, 1.25.bitPattern))
    field("f_string", doc.addString("ada"))
    field("f_bool_2", doc.addBool(false))
    field("f_int32_2", doc.addI64(-3))
    field("f_string_2", doc.addString("x"))
    doc.addTop(st)
    let raw = try encodeBinary(doc, opt, cat)
    #expect(hex(raw) == messageHex)
    #expect(try decodeTree(raw) == message)

    let nested = IonTree.fields([
        ("id", .string("d1")),
        ("items", .list([
            .fields([("sku", .string("a")), ("qty", .int(2)), ("price_minor", .int(50))]),
            .fields([("sku", .string("bb")), ("qty", .int(0)), ("price_minor", .int(-1))]),
        ])),
    ])
    let built = try writerDoc(nested)
    let legacy = try encodeBinary(built, opt, cat)
    #expect(try decodeTree(legacy) == nested)
    #expect(try decodeTree(encodeTree(nested)) == nested)

    let symDoc = IonDoc()
    let symSt = symDoc.startContainer(kStruct)
    let sym = symDoc.addSymbolText("symbols")
    symDoc.addChild(symSt, symDoc.addI64(1), symDoc.nodes[sym].a)
    symDoc.addTop(symSt)
    let symRaw = try encodeBinary(symDoc, opt, cat)
    #expect(try decodeTree(symRaw) == .fields([("symbols", .int(1))]))

    let wide = IonDoc()
    wide.addTop(wide.addInt(BigInt(neg: false, limbs: [0, 0, 1])))
    let wideRaw = try encodeBinary(wide, opt, cat)
    do {
        _ = try decodeTree(wideRaw)
        Issue.record("expected range error")
    } catch let err as DecodeError {
        #expect(err.kind == DecodeError.kindRange)
    }
}

private func writerDoc(_ value: IonTree) throws -> IonDoc {
    let doc = IonDoc()
    doc.addTop(try put(doc, value, -1).0)
    return doc
}

private func put(_ doc: IonDoc, _ value: IonTree, _ field: Int) throws -> (Int, Int) {
    let id: Int
    switch value {
    case .null:
        id = doc.addNull(0)
    case .bool(let v):
        id = doc.addBool(v)
    case .int(let v):
        id = doc.addI64(v)
    case .float(let v):
        id = doc.addFloat(8, v.bitPattern)
    case .string(let text):
        id = doc.addString(text)
    case .list(let items):
        id = doc.startContainer(kList)
        for item in items {
            let child = try put(doc, item, -1).0
            doc.addChild(id, child, -1)
        }
    case .fields(let pairs):
        id = doc.startContainer(kStruct)
        for (name, item) in pairs {
            let sym = doc.addSymbolText(name)
            let child = try put(doc, item, doc.nodes[sym].a).0
            doc.addChild(id, child, doc.nodes[sym].a)
        }
    }
    _ = field
    return (id, field)
}

extension IonTree {
    fileprivate func floatBits() -> UInt64 {
        if case .float(let v) = self { return v.bitPattern }
        return 0
    }
}
