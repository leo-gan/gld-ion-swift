import Ion

public struct Message {
    public var id: Int64
    public var name: String
    public var has_ok: Bool
    public var ok: Bool
    public var has_weight: Bool
    public var weight: Double
    public var has_note: Bool
    public var note: String
    public var has_tags: Bool
    public var tags: [String]
    public var has_when: Bool
    public var when: String
    public var has_payload: Bool
    public var payload: [UInt8]

    public init() {
        id = 0
        name = ""
        has_ok = false
        ok = false
        has_weight = false
        weight = 0
        has_note = false
        note = ""
        has_tags = false
        tags = []
        has_when = false
        when = ""
        has_payload = false
        payload = []
    }

    public func encodedLen(_ options: EncodeOptions) throws -> Int {
        var buf: [UInt8] = []
        try encode(to: &buf, options)
        return buf.count
    }

    public func encode(to buf: inout [UInt8], _ options: EncodeOptions) throws {
        let doc = try toDoc()
        let cat = Catalog()
        if options.binary {
            buf.append(contentsOf: try encodeBinary(doc, options, cat))
            return
        }
        buf.append(contentsOf: Array(try encodeText(doc, options).utf8))
    }

    public func toDoc() throws -> IonDoc {
        let doc = IonDoc()
        let st = try write(into: doc)
        doc.addTop(st)
        return doc
    }

    public func write(into doc: IonDoc) throws -> Int {
        let st = doc.startContainer(kStruct)
        let sym_id = doc.addSymbolText("id")
        let slot_id = doc.nodes[sym_id].a
        let val_id = doc.addI64(id)
        doc.addChild(st, val_id, slot_id)
        let sym_name = doc.addSymbolText("name")
        let slot_name = doc.nodes[sym_name].a
        let val_name = doc.addString(name)
        doc.addChild(st, val_name, slot_name)
        if has_ok {
            let sym_ok = doc.addSymbolText("ok")
            let slot_ok = doc.nodes[sym_ok].a
            let val_ok = doc.addBool(ok)
            doc.addChild(st, val_ok, slot_ok)
        }
        if has_weight {
            let sym_weight = doc.addSymbolText("weight")
            let slot_weight = doc.nodes[sym_weight].a
            let val_weight = doc.addFloat(8, (weight).bitPattern)
            doc.addChild(st, val_weight, slot_weight)
        }
        if has_note {
            let sym_note = doc.addSymbolText("note")
            let slot_note = doc.nodes[sym_note].a
            let val_note = doc.addString(note)
            doc.addChild(st, val_note, slot_note)
        }
        if has_tags {
            let sym_tags = doc.addSymbolText("tags")
            let slot_tags = doc.nodes[sym_tags].a
            let val_tags = doc.startContainer(kList)
            for item_val_tags in tags {
                let el_val_tags = doc.addString(item_val_tags)
                doc.addChild(val_tags, el_val_tags, -1)
            }
            doc.addChild(st, val_tags, slot_tags)
        }
        if has_when {
            let sym_when = doc.addSymbolText("when")
            let slot_when = doc.nodes[sym_when].a
            let val_when = try parseIon(doc, when, 6)
            doc.addChild(st, val_when, slot_when)
        }
        if has_payload {
            let sym_payload = doc.addSymbolText("payload")
            let slot_payload = doc.nodes[sym_payload].a
            let val_payload = doc.addBytes(9, payload)
            doc.addChild(st, val_payload, slot_payload)
        }
        return st
    }

    public static func decode(from raw: [UInt8]) throws -> Message {
        let doc = try decodeAny(raw)
        if doc.top.count != 1 { throw DecodeError(kind: DecodeError.kindType, offset: 0) }
        return try fromDoc(doc, doc.top[0])
    }

    public static func fromDoc(_ doc: IonDoc, _ id: Int) throws -> Message {
        if doc.nodes[id].kind != kStruct { throw DecodeError(kind: DecodeError.kindType, offset: 0) }
        var out = Message()
        var got_id = false
        var got_name = false
        var i = 0
        while i < doc.nodes[id].nchild {
            let fname = fieldName(doc, id, i)
            let child = doc.childAt(id, i)
            if fname == "id" {
                out.id = try asI64(doc, child)
                got_id = true
            }
            else if fname == "name" {
                out.name = try asString(doc, child)
                got_name = true
            }
            else if fname == "ok" {
                out.ok = try asBool(doc, child)
                out.has_ok = true
            }
            else if fname == "weight" {
                out.weight = try asF64(doc, child)
                out.has_weight = true
            }
            else if fname == "note" {
                out.note = try asString(doc, child)
                out.has_note = true
            }
            else if fname == "tags" {
                if doc.nodes[child].kind != kList { throw DecodeError(kind: DecodeError.kindType, offset: 0) }
                var item_out_tags = ""
                var j_item_out_tags = 0
                while j_item_out_tags < doc.nodes[child].nchild {
                    item_out_tags = try asString(doc, doc.childAt(child, j_item_out_tags))
                    out.tags.append(item_out_tags)
                    j_item_out_tags += 1
                }
                out.has_tags = true
            }
            else if fname == "when" {
                out.when = try ionText(doc, child, 6)
                out.has_when = true
            }
            else if fname == "payload" {
                out.payload = try asBytes(doc, child, 9)
                out.has_payload = true
            }
            else {
                throw DecodeError(kind: DecodeError.kindSchema, offset: 0)
            }
            i += 1
        }
        if !got_id { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
        if !got_name { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
        return out
    }
}
