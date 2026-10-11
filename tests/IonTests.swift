import Foundation
import Testing
import Ion

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

func bytes(_ hexIn: String) -> [UInt8] {
    var out: [UInt8] = []
    var i = hexIn.startIndex
    while i < hexIn.endIndex {
        let j = hexIn.index(i, offsetBy: 2)
        out.append(UInt8(hexIn[i..<j], radix: 16)!)
        i = j
    }
    return out
}

@Test func binaryIntZero() throws {
    let cat = Catalog()
    let doc = try decodeBinary(bytes("e00100ea20"), cat)
    #expect(doc.top.count == 1)
    #expect(doc.nodes[doc.top[0]].kind == kInt)
    #expect(doc.nodes[doc.top[0]].b == 0)
    let one = try decode(bytes("e00101ea60"), cat)
    #expect(one.nodes[one.top[0]].kind == kInt)
    #expect(ionEq(doc, doc.top[0], one, one.top[0]))
}

@Test func nullIntListAndSymbols() throws {
    let cat = Catalog()
    let n = try decodeText(Array("null.int".utf8), cat)
    #expect(n.nodes[n.top[0]].kind == kNull)
    #expect(n.nodes[n.top[0]].a == kInt)
    let list = try decode(bytes("e00101eab6610161026103"), cat)
    #expect(list.nodes[list.top[0]].kind == kList)
    #expect(list.nodes[list.top[0]].nchild == 3)
    let empty = try decode(bytes("e00101eaf0ef"), cat)
    #expect(empty.nodes[empty.top[0]].kind == kList)
    #expect(empty.nodes[empty.top[0]].nchild == 0)
    let sym = try decodeText(Array("$ion_1_0\n$ion_symbol_table::{symbols:[\"foo\"]}\n$10\n".utf8), cat)
    #expect(sym.top.count == 1)
    #expect(sym.symText(sym.nodes[sym.top[0]].a) == "foo")
    let inline = try decode(bytes("e00101eaa3626172"), cat)
    #expect(inline.symText(inline.nodes[inline.top[0]].a) == "bar")
}

@Test func textStructAndDecimal() throws {
    let cat = Catalog()
    let doc = try decodeText(Array("{a:1, b:[true, \"hi\"]}".utf8), cat)
    #expect(doc.nodes[doc.top[0]].kind == kStruct)
    #expect(doc.nodes[doc.childAt(doc.top[0], 0)].kind == kInt)
    let b = doc.childAt(doc.top[0], 1)
    #expect(doc.nodes[b].kind == kList)
    #expect(doc.nodes[doc.childAt(b, 0)].kind == kBool)
    #expect(doc.textAt(doc.childAt(b, 1)) == "hi")
    let ts = try decodeText(Array("2007-02-23T12:14:33.079-08:00".utf8), cat)
    let when = ts.times[ts.nodes[ts.top[0]].a]
    #expect(when.hour == 12)
    #expect(when.off == -480)
    #expect(when.unknown == false)
    let dec = try decodeText(Array("-0.00".utf8), cat)
    let dn = dec.nodes[dec.top[0]]
    #expect(dn.kind == kDecimal)
    #expect(dn.c == 1)
    #expect(dn.d == -2)
}

@Test func roundTripKinds() throws {
    let samples = [
        "true",
        "false",
        "null.int",
        "0",
        "-42",
        "100000000000000000000",
        "1.5e0",
        "-0e0",
        "nan",
        "+inf",
        "-0.00",
        "1.00",
        "2007-02-23T12:14:33.079-08:00",
        "2023T",
        "\"hi\"",
        "foo",
        "{{aGVsbG8=}}",
        "{{\"ab\"}}",
        "[true, 1, \"x\"]",
        "(a 1)",
        "{a:1, b:2}",
        "note::\"ada\"",
    ]
    let cat = Catalog()
    for src in samples {
        let doc = try decodeText(Array(src.utf8), cat)
        let text = try encodeText(doc, EncodeOptions(binary: false, pretty: false, version: 10))
        let again = try decodeText(Array(text.utf8), cat)
        #expect(docsEq(doc, again), "text \(src) -> \(text)")
        let bin = try encodeBinary(doc, EncodeOptions(binary: true, pretty: false, version: 10), cat)
        let back = try decodeBinary(bin, cat)
        #expect(docsEq(doc, back), "bin10 \(src) \(hex(bin))")
        let bin11 = try encodeBinary(doc, EncodeOptions(binary: true, pretty: false, version: 11), cat)
        let back11 = try decodeBinary(bin11, cat)
        #expect(docsEq(doc, back11), "bin11 \(src) \(hex(bin11))")
    }
}

@Test func ion11MacroAndDecimal() throws {
    let cat = Catalog()
    let doc = try decodeText(Array("$ion_1_1\n(:$ion set_macros (point {x: (:?), y: (:? 0)}))\n(:point 5 (:))\n".utf8), cat)
    #expect(doc.nodes[doc.top[0]].kind == kStruct)
    #expect(doc.nodes[doc.top[0]].nchild == 2)
    let y = doc.childAt(doc.top[0], 1)
    #expect(doc.nodes[y].kind == kInt)
    #expect(doc.nodes[y].b == 0)
    let dec = try decode(bytes("e00101ea720700"), cat)
    let node = dec.nodes[dec.top[0]]
    #expect(node.kind == kDecimal)
    #expect(node.c == 1)
    #expect(node.d == 3)
    let year = IonDoc()
    var t = IonTime()
    t.year = 1947
    t.prec = precYear
    t.unknown = true
    year.addTop(year.addTime(t))
    let raw = try encodeBinary(year, EncodeOptions(binary: true, pretty: false, version: 11), cat)
    #expect(hex(raw) == "e00101eaf7059b07")
}

@Test func structOrderAndDecimalScale() throws {
    let cat = Catalog()
    let a = try decodeText(Array("{b:1, a:2}".utf8), cat)
    let b = try decodeText(Array("{a:2, b:1}".utf8), cat)
    #expect(ionEq(a, a.top[0], b, b.top[0]))
    let d1 = try decodeText(Array("1.0".utf8), cat)
    let d2 = try decodeText(Array("1.00".utf8), cat)
    #expect(!ionEq(d1, d1.top[0], d2, d2.top[0]))
}

@Test func schemaAndGenerated() throws {
    let message = try parseSchemaFile("testdata/schema/message.json")
    #expect(message.find("Message") >= 0)
    let point = try parseSchemaFile("testdata/schema/point.ion")
    #expect(point.find("Point") >= 0)
    #expect(throws: DecodeError.self) {
        _ = try parseSchemaFile("testdata/invalid-schema/reject.ion")
    }
    var msg = Message()
    msg.id = 7
    msg.name = "ada"
    msg.has_ok = true
    msg.ok = true
    msg.has_weight = true
    msg.weight = 1.5
    msg.has_note = true
    msg.note = "hi"
    msg.has_tags = true
    msg.tags = ["a", "b"]
    msg.has_when = true
    msg.when = "2023T"
    msg.has_payload = true
    msg.payload = [1, 2]
    let opt = EncodeOptions(binary: true, pretty: false, version: 10)
    var buf: [UInt8] = []
    try msg.encode(to: &buf, opt)
    #expect(try msg.encodedLen(opt) == buf.count)
    let back = try Message.decode(from: buf)
    #expect(back.id == 7)
    #expect(back.name == "ada")
    #expect(back.ok)
    #expect(back.has_weight && back.weight == 1.5)
    #expect(back.note == "hi")
    #expect(back.tags == ["a", "b"])
    #expect(back.when == "2023T")
    #expect(back.payload == [1, 2])
    var p = Point()
    p.x = 3
    p.label = "foo"
    var raw: [UInt8] = []
    try p.encode(to: &raw, EncodeOptions(binary: true, pretty: false, version: 11))
    let got = try Point.decode(from: raw)
    #expect(got.x == 3)
    #expect(!got.has_y)
    #expect(got.label == "foo")
}

@Test func binaryStructFastPath() throws {
    let cat = Catalog()
    let src = "{a:true,b:false,c:-2,d:0,name:\"item\",name:\"item\"}"
    let doc = try decodeText(Array(src.utf8), cat)
    let bin = try encodeBinary(doc, EncodeOptions(binary: true, pretty: false, version: 10), cat)
    let back = try decodeBinary(bin, cat)
    #expect(docsEq(doc, back))
    let text = try encodeText(doc, EncodeOptions())
    let again = try decodeText(Array(text.utf8), cat)
    #expect(docsEq(doc, again))
}

@Test func emptySymbolAndAnnotation() throws {
    let cat = Catalog()
    let doc = try decodeText(Array("''\n{'':abc}\n''::abc\n{'':''::''}\n".utf8), cat)
    #expect(doc.top.count == 4)
    #expect(doc.symText(doc.nodes[doc.top[0]].a) == "")
    let back = try decodeText(Array((try encodeText(doc, EncodeOptions())).utf8), cat)
    #expect(docsEq(doc, back))
}

@Test func bigIntText() throws {
    let cat = Catalog()
    let doc = try decodeText(Array("100000000000000000000".utf8), cat)
    let text = try formatValue(doc, doc.top[0])
    #expect(text == "100000000000000000000")
    let neg = try decodeText(Array("-99".utf8), cat)
    #expect(try formatValue(neg, neg.top[0]) == "-99")
}
