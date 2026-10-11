public func decodeAny(_ raw: [UInt8]) throws -> IonDoc {
    let cat = Catalog()
    if raw.count >= 4 && raw[0] == 0xE0 && raw[1] == 0x01 && raw[3] == 0xEA {
        return try decodeBinary(raw, cat)
    }
    return try decodeText(raw, cat)
}

public func fieldName(_ doc: IonDoc, _ id: Int, _ index: Int) -> String {
    let sym = doc.fieldAt(id, index)
    if sym < 0 { return "" }
    return doc.symText(sym)
}

public func asI64(_ doc: IonDoc, _ id: Int) throws -> Int64 {
    let n = doc.nodes[id]
    if n.kind != kInt { throw DecodeError(kind: DecodeError.kindType, offset: 0) }
    if n.b > 2 { throw DecodeError(kind: DecodeError.kindRange, offset: 0) }
    if n.b == 0 { return 0 }
    var mag = UInt64(doc.limbs[n.a])
    if n.b == 2 { mag |= UInt64(doc.limbs[n.a + 1]) << 32 }
    if n.c != 0 {
        if mag > (UInt64(1) << 63) { throw DecodeError(kind: DecodeError.kindRange, offset: 0) }
        if mag == (UInt64(1) << 63) { return Int64.min }
        return -Int64(mag)
    }
    if mag > UInt64(Int64.max) { throw DecodeError(kind: DecodeError.kindRange, offset: 0) }
    return Int64(mag)
}

public func asBool(_ doc: IonDoc, _ id: Int) throws -> Bool {
    let n = doc.nodes[id]
    if n.kind != kBool { throw DecodeError(kind: DecodeError.kindType, offset: 0) }
    return n.a != 0
}

public func asString(_ doc: IonDoc, _ id: Int) throws -> String {
    if doc.nodes[id].kind != kString { throw DecodeError(kind: DecodeError.kindType, offset: 0) }
    return doc.textAt(id)
}

public func asF64(_ doc: IonDoc, _ id: Int) throws -> Double {
    let n = doc.nodes[id]
    if n.kind != kFloat { throw DecodeError(kind: DecodeError.kindType, offset: 0) }
    let bits = doc.floats[n.b]
    if n.a == 0 { return 0 }
    if n.a == 4 { return Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits))) }
    if n.a == 8 { return Double(bitPattern: bits) }
    if n.a == 2 { return f16ToF64(UInt16(truncatingIfNeeded: bits)) }
    throw DecodeError(kind: DecodeError.kindType, offset: 0)
}

public func asBytes(_ doc: IonDoc, _ id: Int, _ kind: Int) throws -> [UInt8] {
    let n = doc.nodes[id]
    if n.kind != kind { throw DecodeError(kind: DecodeError.kindType, offset: 0) }
    return doc.blobs[n.a]
}

public func ionText(_ doc: IonDoc, _ id: Int, _ expect: Int) throws -> String {
    if expect != 0 && doc.nodes[id].kind != expect {
        throw DecodeError(kind: DecodeError.kindType, offset: 0)
    }
    return try formatValue(doc, id)
}

@discardableResult
public func parseIon(_ doc: IonDoc, _ text: String, _ expect: Int) throws -> Int {
    let id = try adoptText(doc, text)
    if expect != 0 && doc.nodes[id].kind != expect {
        throw DecodeError(kind: DecodeError.kindType, offset: 0)
    }
    return id
}

public func decode(_ raw: [UInt8], _ cat: Catalog) throws -> IonDoc {
    if raw.count >= 4 && raw[0] == 0xE0 && raw[1] == 0x01 && raw[3] == 0xEA {
        return try decodeBinary(raw, cat)
    }
    return try decodeText(raw, cat)
}

public func encode(_ doc: IonDoc, _ options: EncodeOptions, _ cat: Catalog) throws -> [UInt8] {
    if options.binary { return try encodeBinary(doc, options, cat) }
    return utf8Bytes(try encodeText(doc, options))
}
