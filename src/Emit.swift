let swiftKeywords: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
    "init", "inout", "internal", "let", "operator", "private", "protocol", "public", "rethrows",
    "static", "struct", "subscript", "typealias", "var", "break", "case", "continue", "default",
    "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return",
    "switch", "where", "while", "as", "Any", "catch", "false", "is", "nil", "super", "self",
    "Self", "throw", "throws", "true", "try", "associativity", "convenience", "dynamic",
    "didSet", "final", "get", "infix", "indirect", "lazy", "left", "mutating", "none",
    "nonmutating", "optional", "override", "postfix", "precedence", "prefix", "Protocol",
    "required", "right", "set", "Type", "unowned", "weak", "willSet", "some", "any", "each",
    "macro", "package", "borrowing", "consuming", "isolated", "nonisolated",
]

public func sanitize(_ name: String) -> String {
    var out = ""
    let raw = utf8Bytes(name)
    for (i, b) in raw.enumerated() {
        let c = Int(b)
        var ok = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
        if i > 0 && c >= 48 && c <= 57 { ok = true }
        if ok, let scalar = UnicodeScalar(c) {
            out.append(Character(scalar))
        } else {
            out.append("_")
        }
    }
    if out.isEmpty { return "Value" }
    if let first = out.utf8.first, first >= 48 && first <= 57 { out = "T_" + out }
    if swiftKeywords.contains(out) { out += "_" }
    return out
}

public func emitAll(_ schema: Schema) throws -> [(String, String)] {
    var out: [(String, String)] = []
    for i in schema.typeName.indices where schema.typeKind[i] == tyStruct && !schema.typeName[i].isEmpty {
        let name = sanitize(schema.typeName[i])
        out.append((name, try emitStruct(schema, i, name)))
    }
    if out.isEmpty { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
    return out
}

func emitStruct(_ schema: Schema, _ idx: Int, _ name: String) throws -> String {
    var src = "import Ion\n\npublic struct \(name) {\n"
    var f = 0
    while f < schema.fieldN[idx] {
        let at = schema.fieldAt[idx] + f
        let ident = sanitize(schema.fieldName[at])
        let tid = schema.fieldType[at]
        if !schema.fieldReq[at] { src += "    public var has_\(ident): Bool\n" }
        src += "    public var \(ident): \(try mtype(schema, tid))\n"
        f += 1
    }
    src += "\n    public init() {\n"
    if schema.fieldN[idx] == 0 { src += "        _ = 0\n" }
    f = 0
    while f < schema.fieldN[idx] {
        let at = schema.fieldAt[idx] + f
        let ident = sanitize(schema.fieldName[at])
        let tid = schema.fieldType[at]
        if !schema.fieldReq[at] { src += "        has_\(ident) = false\n" }
        src += "        \(ident) = \(try defaultExpr(schema, tid))\n"
        f += 1
    }
    src += "    }\n\n"
    src += "    public func encodedLen(_ options: EncodeOptions) throws -> Int {\n"
    src += "        var buf: [UInt8] = []\n"
    src += "        try encode(to: &buf, options)\n"
    src += "        return buf.count\n"
    src += "    }\n\n"
    src += "    public func encode(to buf: inout [UInt8], _ options: EncodeOptions) throws {\n"
    src += "        let doc = try toDoc()\n"
    src += "        let cat = Catalog()\n"
    src += "        if options.binary {\n"
    src += "            buf.append(contentsOf: try encodeBinary(doc, options, cat))\n"
    src += "            return\n"
    src += "        }\n"
    src += "        buf.append(contentsOf: Array(try encodeText(doc, options).utf8))\n"
    src += "    }\n\n"
    src += "    public func toDoc() throws -> IonDoc {\n"
    src += "        let doc = IonDoc()\n"
    src += "        let st = try write(into: doc)\n"
    src += "        doc.addTop(st)\n"
    src += "        return doc\n"
    src += "    }\n\n"
    src += "    public func write(into doc: IonDoc) throws -> Int {\n"
    src += "        let st = doc.startContainer(kStruct)\n"
    f = 0
    while f < schema.fieldN[idx] {
        let at = schema.fieldAt[idx] + f
        src += try writeField(schema, schema.fieldName[at], schema.fieldType[at], schema.fieldReq[at])
        f += 1
    }
    src += "        return st\n"
    src += "    }\n\n"
    src += "    public static func decode(from raw: [UInt8]) throws -> \(name) {\n"
    src += "        let doc = try decodeAny(raw)\n"
    src += "        if doc.top.count != 1 { throw DecodeError(kind: DecodeError.kindType, offset: 0) }\n"
    src += "        return try fromDoc(doc, doc.top[0])\n"
    src += "    }\n\n"
    src += "    public static func fromDoc(_ doc: IonDoc, _ id: Int) throws -> \(name) {\n"
    src += "        if doc.nodes[id].kind != kStruct { throw DecodeError(kind: DecodeError.kindType, offset: 0) }\n"
    src += "        var out = \(name)()\n"
    f = 0
    while f < schema.fieldN[idx] {
        let at = schema.fieldAt[idx] + f
        if schema.fieldReq[at] {
            let ident = sanitize(schema.fieldName[at])
            src += "        var got_\(ident) = false\n"
        }
        f += 1
    }
    src += "        var i = 0\n"
    src += "        while i < doc.nodes[id].nchild {\n"
    src += "            let fname = fieldName(doc, id, i)\n"
    src += "            let child = doc.childAt(id, i)\n"
    f = 0
    while f < schema.fieldN[idx] {
        let at = schema.fieldAt[idx] + f
        let ionName = schema.fieldName[at]
        let ident = sanitize(schema.fieldName[at])
        let kw = f == 0 ? "if" : "else if"
        src += "            \(kw) fname == \(swiftLit(ionName)) {\n"
        src += try readField(schema, ident, schema.fieldType[at], schema.fieldReq[at])
        src += "            }\n"
        f += 1
    }
    if schema.fieldN[idx] == 0 {
        src += "            _ = fname\n            _ = child\n"
    } else {
        src += "            else {\n"
        if schema.typeClosed[idx] != 0 {
            src += "                throw DecodeError(kind: DecodeError.kindSchema, offset: 0)\n"
        } else {
            src += "                _ = child\n"
        }
        src += "            }\n"
    }
    src += "            i += 1\n"
    src += "        }\n"
    f = 0
    while f < schema.fieldN[idx] {
        let at = schema.fieldAt[idx] + f
        if schema.fieldReq[at] {
            let ident = sanitize(schema.fieldName[at])
            src += "        if !got_\(ident) { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }\n"
        }
        f += 1
    }
    src += "        return out\n"
    src += "    }\n}\n"
    return src
}

func mtype(_ schema: Schema, _ tid: Int) throws -> String {
    switch schema.typeKind[tid] {
    case tyInt: return "Int64"
    case tyBool: return "Bool"
    case tyString, tyIon: return "String"
    case tyFloat: return "Double"
    case tyBytes: return "[UInt8]"
    case tyStruct: return sanitize(schema.typeName[tid])
    case tyList: return "[\(try mtype(schema, schema.typeInner[tid]))]"
    default: throw DecodeError(kind: DecodeError.kindSchema, offset: 0)
    }
}

func defaultExpr(_ schema: Schema, _ tid: Int) throws -> String {
    switch schema.typeKind[tid] {
    case tyInt: return "0"
    case tyBool: return "false"
    case tyString, tyIon: return "\"\""
    case tyFloat: return "0"
    case tyBytes, tyList: return "[]"
    case tyStruct: return "\(sanitize(schema.typeName[tid]))()"
    default: throw DecodeError(kind: DecodeError.kindSchema, offset: 0)
    }
}

func writeField(_ schema: Schema, _ ionName: String, _ tid: Int, _ required: Bool) throws -> String {
    let ident = sanitize(ionName)
    var body = ""
    var pad = "        "
    if !required {
        body += pad + "if has_\(ident) {\n"
        pad = "            "
    }
    body += pad + "let sym_\(ident) = doc.addSymbolText(\(swiftLit(ionName)))\n"
    body += pad + "let slot_\(ident) = doc.nodes[sym_\(ident)].a\n"
    body += try writeValue(schema, tid, ident, "val_\(ident)", pad)
    body += pad + "doc.addChild(st, val_\(ident), slot_\(ident))\n"
    if !required { body += "        }\n" }
    return body
}

func writeValue(_ schema: Schema, _ tid: Int, _ expr: String, _ dest: String, _ pad: String) throws -> String {
    switch schema.typeKind[tid] {
    case tyInt:
        return pad + "let \(dest) = doc.addI64(\(expr))\n"
    case tyBool:
        return pad + "let \(dest) = doc.addBool(\(expr))\n"
    case tyString:
        return pad + "let \(dest) = doc.addString(\(expr))\n"
    case tyFloat:
        return pad + "let \(dest) = doc.addFloat(8, (\(expr)).bitPattern)\n"
    case tyIon:
        return pad + "let \(dest) = try parseIon(doc, \(expr), \(schema.typeExpect[tid]))\n"
    case tyBytes:
        return pad + "let \(dest) = doc.addBytes(\(schema.typeExpect[tid]), \(expr))\n"
    case tyStruct:
        return pad + "let \(dest) = try \(expr).write(into: doc)\n"
    case tyList:
        let inner = schema.typeInner[tid]
        var line = pad + "let \(dest) = doc.startContainer(kList)\n"
        line += pad + "for item_\(dest) in \(expr) {\n"
        line += try writeValue(schema, inner, "item_\(dest)", "el_\(dest)", pad + "    ")
        line += pad + "    doc.addChild(\(dest), el_\(dest), -1)\n"
        line += pad + "}\n"
        return line
    default:
        throw DecodeError(kind: DecodeError.kindSchema, offset: 0)
    }
}

func readField(_ schema: Schema, _ ident: String, _ tid: Int, _ required: Bool) throws -> String {
    var body = try readValue(schema, tid, "child", "out.\(ident)", "                ")
    if !required {
        body += "                out.has_\(ident) = true\n"
    } else {
        body += "                got_\(ident) = true\n"
    }
    return body
}

func readValue(_ schema: Schema, _ tid: Int, _ expr: String, _ dest: String, _ pad: String) throws -> String {
    switch schema.typeKind[tid] {
    case tyInt: return pad + "\(dest) = try asI64(doc, \(expr))\n"
    case tyBool: return pad + "\(dest) = try asBool(doc, \(expr))\n"
    case tyString: return pad + "\(dest) = try asString(doc, \(expr))\n"
    case tyFloat: return pad + "\(dest) = try asF64(doc, \(expr))\n"
    case tyIon: return pad + "\(dest) = try ionText(doc, \(expr), \(schema.typeExpect[tid]))\n"
    case tyBytes: return pad + "\(dest) = try asBytes(doc, \(expr), \(schema.typeExpect[tid]))\n"
    case tyStruct:
        let nm = sanitize(schema.typeName[tid])
        return pad + "\(dest) = try \(nm).fromDoc(doc, \(expr))\n"
    case tyList:
        let inner = schema.typeInner[tid]
        let item = "item_" + slug(dest)
        var line = pad + "if doc.nodes[\(expr)].kind != kList { throw DecodeError(kind: DecodeError.kindType, offset: 0) }\n"
        line += pad + "var \(item) = \(try defaultExpr(schema, inner))\n"
        line += pad + "var j_\(item) = 0\n"
        line += pad + "while j_\(item) < doc.nodes[\(expr)].nchild {\n"
        line += try readValue(schema, inner, "doc.childAt(\(expr), j_\(item))", item, pad + "    ")
        line += pad + "    \(dest).append(\(item))\n"
        line += pad + "    j_\(item) += 1\n"
        line += pad + "}\n"
        return line
    default:
        throw DecodeError(kind: DecodeError.kindSchema, offset: 0)
    }
}

func slug(_ text: String) -> String {
    var out = ""
    for b in utf8Bytes(text) {
        let c = Int(b)
        if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) {
            out.append(Character(UnicodeScalar(UInt8(c))))
        } else {
            out.append("_")
        }
    }
    return out
}

func swiftLit(_ text: String) -> String {
    var out = "\""
    for b in utf8Bytes(text) {
        if b == 34 || b == 92 { out.append("\\") }
        out.append(Character(UnicodeScalar(b)))
    }
    out.append("\"")
    return out
}
