import Foundation

public let tyInt = 1
public let tyBool = 2
public let tyString = 3
public let tyFloat = 4
public let tyIon = 5
public let tyBytes = 6
public let tyStruct = 7
public let tyList = 8

public struct Schema {
    public var typeName: [String] = []
    public var typeKind: [Int] = []
    public var typeExpect: [Int] = []
    public var typeInner: [Int] = []
    public var typeRef: [String] = []
    public var typeClosed: [Int] = []
    public var fieldAt: [Int] = []
    public var fieldN: [Int] = []
    public var fieldName: [String] = []
    public var fieldType: [Int] = []
    public var fieldReq: [Bool] = []
    public var fieldRef: [String] = []

    public init() {
        prim("int", tyInt, 0)
        prim("bool", tyBool, 0)
        prim("string", tyString, 0)
        prim("float", tyFloat, 0)
        prim("decimal", tyIon, kDecimal)
        prim("timestamp", tyIon, kTimestamp)
        prim("symbol", tyIon, kSymbol)
        prim("blob", tyBytes, kBlob)
        prim("clob", tyBytes, kClob)
        prim("sexp", tyIon, kSexp)
    }

    mutating func prim(_ name: String, _ kind: Int, _ expect: Int) {
        typeName.append(name)
        typeKind.append(kind)
        typeExpect.append(expect)
        typeInner.append(-1)
        typeRef.append("")
        typeClosed.append(0)
        fieldAt.append(0)
        fieldN.append(0)
    }

    public func find(_ name: String) -> Int {
        for i in typeName.indices where typeName[i] == name { return i }
        return -1
    }
}

public func parseSchemaFile(_ path: String) throws -> Schema {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let doc = try decodeText([UInt8](data), Catalog())
    return try schemaFromDoc(doc)
}

public func schemaFromDoc(_ doc: IonDoc) throws -> Schema {
    var schema = Schema()
    if doc.top.isEmpty { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
    let first = doc.top[0]
    if isJSON(doc, first) {
        try jsonRoot(doc, &schema, first, "Document")
    } else {
        for id in doc.top { try registerIon(doc, &schema, id) }
        for id in doc.top { try fillIon(doc, &schema, id) }
    }
    try resolve(&schema)
    return schema
}

func isJSON(_ doc: IonDoc, _ id: Int) -> Bool {
    if doc.nodes[id].kind != kStruct { return false }
    if doc.nodes[id].annN != 0 { return false }
    return findField(doc, id, "properties") >= 0 || findField(doc, id, "$defs") >= 0
        || findField(doc, id, "definitions") >= 0
}

func registerIon(_ doc: IonDoc, _ schema: inout Schema, _ id: Int) throws {
    if doc.nodes[id].kind != kStruct { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
    let name = typeNameOf(doc, id, "")
    if name.isEmpty { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
    if schema.find(name) < 0 { _ = alloc(&schema, name, tyStruct, 0, -1) }
}

func fillIon(_ doc: IonDoc, _ schema: inout Schema, _ id: Int) throws {
    let name = typeNameOf(doc, id, "")
    let idx = schema.find(name)
    if idx < 0 { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
    try fillStruct(doc, &schema, idx, id, name)
}

func jsonRoot(_ doc: IonDoc, _ schema: inout Schema, _ id: Int, _ fallback: String) throws {
    var defs = findField(doc, id, "$defs")
    if defs < 0 { defs = findField(doc, id, "definitions") }
    if defs >= 0 {
        var i = 0
        while i < doc.nodes[defs].nchild {
            let nm = fieldNameText(doc, defs, i)
            if schema.find(nm) < 0 { _ = alloc(&schema, nm, tyStruct, 0, -1) }
            i += 1
        }
        i = 0
        while i < doc.nodes[defs].nchild {
            let child = doc.childAt(defs, i)
            let nm = fieldNameText(doc, defs, i)
            let idx = schema.find(nm)
            try fillStruct(doc, &schema, idx, child, nm)
            i += 1
        }
    }
    let name = typeNameOf(doc, id, fallback)
    var idx = schema.find(name)
    if idx < 0 { idx = alloc(&schema, name, tyStruct, 0, -1) }
    try fillStruct(doc, &schema, idx, id, name)
}

func fillStruct(_ doc: IonDoc, _ schema: inout Schema, _ idx: Int, _ id: Int, _ parent: String) throws {
    if schema.fieldN[idx] != 0 { return }
    var closed = 0
    let addl = findField(doc, id, "additionalProperties")
    if addl >= 0 && doc.nodes[addl].kind == kBool && doc.nodes[addl].a == 0 { closed = 1 }
    let content = findField(doc, id, "content")
    if content >= 0 && nodeText(doc, content) == "closed" { closed = 1 }
    schema.typeClosed[idx] = closed
    var fields = findField(doc, id, "fields")
    if fields < 0 { fields = findField(doc, id, "properties") }
    let required = findField(doc, id, "required")
    let at = schema.fieldName.count
    var n = 0
    if fields >= 0 && doc.nodes[fields].kind == kStruct {
        var i = 0
        while i < doc.nodes[fields].nchild {
            let fname = fieldNameText(doc, fields, i)
            let child = doc.childAt(fields, i)
            var req = true
            if required >= 0 {
                req = listHas(doc, required, fname)
            } else if occursOptional(doc, child) {
                req = false
            }
            let tid = try valueType(doc, &schema, parent, fname, bareType(doc, child))
            schema.fieldName.append(fname)
            schema.fieldType.append(tid)
            schema.fieldReq.append(req)
            if tid < 0 {
                schema.fieldRef.append(refName(doc, child))
            } else {
                schema.fieldRef.append("")
            }
            n += 1
            i += 1
        }
    }
    schema.fieldAt[idx] = at
    schema.fieldN[idx] = n
}

func valueType(_ doc: IonDoc, _ schema: inout Schema, _ parent: String, _ hint: String, _ id: Int) throws -> Int {
    if id < 0 { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
    let kind = doc.nodes[id].kind
    if kind == kSymbol || kind == kString { return lookup(schema, nodeText(doc, id)) }
    if kind != kStruct { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
    let link = findField(doc, id, "$ref")
    if link >= 0 { return lookup(schema, lastPath(nodeText(doc, link))) }
    var label = ""
    let ionT = findField(doc, id, "ionType")
    if ionT >= 0 {
        label = nodeText(doc, ionT)
    } else {
        let ty = findField(doc, id, "type")
        if ty >= 0 { label = nodeText(doc, ty) }
    }
    if label == "object" || label == "struct" || findField(doc, id, "properties") >= 0
        || findField(doc, id, "fields") >= 0
    {
        let nm = typeNameOf(doc, id, parent + "_" + hint)
        var idx = schema.find(nm)
        if idx < 0 { idx = alloc(&schema, nm, tyStruct, 0, -1) }
        try fillStruct(doc, &schema, idx, id, nm)
        return idx
    }
    if label == "array" || label == "list" {
        var elem = findField(doc, id, "items")
        if elem < 0 { elem = findField(doc, id, "element") }
        if elem < 0 { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
        let inner = try valueType(doc, &schema, parent, hint + "_item", elem)
        let listId = alloc(&schema, "", tyList, 0, inner)
        if inner < 0 { schema.typeRef[listId] = refName(doc, elem) }
        return listId
    }
    if label == "sexp" { return 9 }
    if label.isEmpty { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
    return lookup(schema, label)
}

func lookup(_ schema: Schema, _ name: String) -> Int {
    if name == "integer" { return 0 }
    if name == "boolean" { return 1 }
    if name == "number" { return 3 }
    return schema.find(name)
}

func bareType(_ doc: IonDoc, _ id: Int) -> Int { id }

func refName(_ doc: IonDoc, _ id: Int) -> String {
    if doc.nodes[id].kind == kSymbol || doc.nodes[id].kind == kString { return nodeText(doc, id) }
    let link = findField(doc, id, "$ref")
    if link >= 0 { return lastPath(nodeText(doc, link)) }
    let ty = findField(doc, id, "type")
    if ty >= 0 { return nodeText(doc, ty) }
    var elem = findField(doc, id, "element")
    if elem < 0 { elem = findField(doc, id, "items") }
    if elem >= 0 { return refName(doc, elem) }
    return ""
}

func occursOptional(_ doc: IonDoc, _ id: Int) -> Bool {
    if doc.nodes[id].kind != kStruct { return false }
    let occ = findField(doc, id, "occurs")
    if occ < 0 { return false }
    return nodeText(doc, occ) == "optional"
}

func resolve(_ schema: inout Schema) throws {
    for i in schema.fieldName.indices where schema.fieldType[i] < 0 {
        let idx = schema.find(schema.fieldRef[i])
        if idx < 0 { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
        schema.fieldType[i] = idx
    }
    for i in schema.typeName.indices where schema.typeKind[i] == tyList && schema.typeInner[i] < 0 {
        let idx = schema.find(schema.typeRef[i])
        if idx < 0 { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
        schema.typeInner[i] = idx
    }
}

func alloc(_ schema: inout Schema, _ name: String, _ kind: Int, _ expect: Int, _ inner: Int) -> Int {
    schema.typeName.append(name)
    schema.typeKind.append(kind)
    schema.typeExpect.append(expect)
    schema.typeInner.append(inner)
    schema.typeRef.append("")
    schema.typeClosed.append(0)
    schema.fieldAt.append(0)
    schema.fieldN.append(0)
    return schema.typeName.count - 1
}

func typeNameOf(_ doc: IonDoc, _ id: Int, _ fallback: String) -> String {
    let title = findField(doc, id, "title")
    if title >= 0 {
        let text = nodeText(doc, title)
        if !text.isEmpty { return text }
    }
    let name = findField(doc, id, "name")
    if name >= 0 {
        let text = nodeText(doc, name)
        if !text.isEmpty { return text }
    }
    let idField = findField(doc, id, "$id")
    if idField >= 0 { return lastPath(nodeText(doc, idField)) }
    return fallback
}

func lastPath(_ text: String) -> String {
    let raw = utf8Bytes(text)
    var start = 0
    for i in raw.indices where raw[i] == 47 { start = i + 1 }
    return String(decoding: raw[start...], as: UTF8.self)
}

func findField(_ doc: IonDoc, _ id: Int, _ name: String) -> Int {
    if id < 0 || doc.nodes[id].kind != kStruct { return -1 }
    var i = 0
    while i < doc.nodes[id].nchild {
        if fieldNameText(doc, id, i) == name { return doc.childAt(id, i) }
        i += 1
    }
    return -1
}

func fieldNameText(_ doc: IonDoc, _ id: Int, _ index: Int) -> String {
    let sym = doc.fieldAt(id, index)
    if sym < 0 { return "" }
    return doc.symText(sym)
}

func nodeText(_ doc: IonDoc, _ id: Int) -> String {
    let kind = doc.nodes[id].kind
    if kind == kString { return doc.textAt(id) }
    if kind == kSymbol { return doc.symText(doc.nodes[id].a) }
    return ""
}

func listHas(_ doc: IonDoc, _ id: Int, _ name: String) -> Bool {
    if doc.nodes[id].kind != kList { return false }
    var i = 0
    while i < doc.nodes[id].nchild {
        if nodeText(doc, doc.childAt(id, i)) == name { return true }
        i += 1
    }
    return false
}
