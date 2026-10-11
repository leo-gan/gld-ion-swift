import Ion

public struct Point {
    public var x: Int64
    public var has_y: Bool
    public var y: Int64
    public var label: String

    public init() {
        x = 0
        has_y = false
        y = 0
        label = ""
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
        let sym_x = doc.addSymbolText("x")
        let slot_x = doc.nodes[sym_x].a
        let val_x = doc.addI64(x)
        doc.addChild(st, val_x, slot_x)
        if has_y {
            let sym_y = doc.addSymbolText("y")
            let slot_y = doc.nodes[sym_y].a
            let val_y = doc.addI64(y)
            doc.addChild(st, val_y, slot_y)
        }
        let sym_label = doc.addSymbolText("label")
        let slot_label = doc.nodes[sym_label].a
        let val_label = try parseIon(doc, label, 8)
        doc.addChild(st, val_label, slot_label)
        return st
    }

    public static func decode(from raw: [UInt8]) throws -> Point {
        let doc = try decodeAny(raw)
        if doc.top.count != 1 { throw DecodeError(kind: DecodeError.kindType, offset: 0) }
        return try fromDoc(doc, doc.top[0])
    }

    public static func fromDoc(_ doc: IonDoc, _ id: Int) throws -> Point {
        if doc.nodes[id].kind != kStruct { throw DecodeError(kind: DecodeError.kindType, offset: 0) }
        var out = Point()
        var got_x = false
        var got_label = false
        var i = 0
        while i < doc.nodes[id].nchild {
            let fname = fieldName(doc, id, i)
            let child = doc.childAt(id, i)
            if fname == "x" {
                out.x = try asI64(doc, child)
                got_x = true
            }
            else if fname == "y" {
                out.y = try asI64(doc, child)
                out.has_y = true
            }
            else if fname == "label" {
                out.label = try ionText(doc, child, 8)
                got_label = true
            }
            else {
                throw DecodeError(kind: DecodeError.kindSchema, offset: 0)
            }
            i += 1
        }
        if !got_x { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
        if !got_label { throw DecodeError(kind: DecodeError.kindSchema, offset: 0) }
        return out
    }
}
