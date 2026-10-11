func symUnknown() -> SymRef {
    SymRef(text: -1, sid: 0, impName: -1, impSid: 0)
}

func symFromSid(_ doc: IonDoc, _ tab: LocalTab, _ sid: Int, _ offset: Int) throws -> Int {
    if sid < 0 { throw DecodeError(kind: DecodeError.kindSymbol, offset: offset) }
    let got = try tab.lookup(sid, offset)
    if sid == 0 || (!got.known && got.imp.isEmpty) {
        return doc.addSymbolRef(symUnknown())
    }
    if got.known {
        let node = doc.addSymbolText(got.text)
        var s = doc.syms[doc.nodes[node].a]
        s.sid = sid
        doc.syms[doc.nodes[node].a] = s
        return node
    }
    let imp = doc.intern(got.imp)
    return doc.addSymbolRef(SymRef(text: -1, sid: sid, impName: imp, impSid: got.impSid))
}

func countField(_ doc: IonDoc, _ id: Int, _ name: String) -> Int {
    var n = 0
    var i = 0
    while i < doc.nodes[id].nchild {
        let sym = doc.fieldAt(id, i)
        let s = doc.syms[sym]
        if s.text >= 0 && doc.texts[s.text] == name { n += 1 }
        i += 1
    }
    return n
}

func fieldNode(_ doc: IonDoc, _ id: Int, _ name: String) -> Int {
    var i = 0
    let n = doc.nodes[id].nchild
    while i < n {
        let sym = doc.fieldAt(id, i)
        let s = doc.syms[sym]
        if s.text >= 0 && doc.texts[s.text] == name { return doc.childAt(id, i) }
        i += 1
    }
    return -1
}

func docI64(_ doc: IonDoc, _ id: Int, _ offset: Int) throws -> Int {
    let n = doc.nodes[id]
    if n.kind != kInt { throw DecodeError(kind: DecodeError.kindType, offset: offset) }
    if n.b > 2 { throw DecodeError(kind: DecodeError.kindRange, offset: offset) }
    var mag = UInt64(0)
    if n.b > 0 { mag = UInt64(doc.limbs[n.a]) }
    if n.b > 1 { mag |= UInt64(doc.limbs[n.a + 1]) << 32 }
    if n.c != 0 {
        if mag > 9_223_372_036_854_775_808 {
            throw DecodeError(kind: DecodeError.kindRange, offset: offset)
        }
        if mag == 9_223_372_036_854_775_808 { return Int.min }
        return -Int(mag)
    }
    if mag > 9_223_372_036_854_775_807 {
        throw DecodeError(kind: DecodeError.kindRange, offset: offset)
    }
    return Int(mag)
}

func isLocalTable(_ doc: IonDoc, _ id: Int) -> Bool {
    let n = doc.nodes[id]
    if n.annN == 0 { return false }
    let s = doc.syms[doc.anns[n.ann]]
    if s.text < 0 { return false }
    if doc.texts[s.text] != "$ion_symbol_table" { return false }
    if n.kind == kStruct { return true }
    return n.kind == kNull && n.a == kStruct
}

func symTextOf(_ doc: IonDoc, _ id: Int) -> String {
    let n = doc.nodes[id]
    if n.kind != kSymbol { return "" }
    return doc.symText(n.a)
}

func applyLst(_ doc: IonDoc, _ id: Int, _ tab: LocalTab, _ cat: Catalog, _ offset: Int) throws {
    let n = doc.nodes[id]
    if n.kind == kNull {
        tab.resetSystem()
        return
    }
    let imp = fieldNode(doc, id, "imports")
    if countField(doc, id, "imports") > 1 || countField(doc, id, "symbols") > 1 {
        throw DecodeError(kind: DecodeError.kindSymbol, offset: offset)
    }
    let extend = imp >= 0 && doc.nodes[imp].kind == kSymbol && symTextOf(doc, imp) == "$ion_symbol_table"
    if !extend {
        if imp >= 0 && doc.nodes[imp].kind == kList {
            tab.resetSystem()
            var i = 0
            while i < doc.nodes[imp].nchild {
                let el = doc.childAt(imp, i)
                if doc.nodes[el].kind == kStruct {
                    try importOne(doc, el, tab, cat, offset)
                }
                i += 1
            }
        } else if imp < 0 || doc.nodes[imp].kind == kNull {
            tab.resetSystem()
        } else {
            throw DecodeError(kind: DecodeError.kindSymbol, offset: offset)
        }
    }
    let syms = fieldNode(doc, id, "symbols")
    if syms >= 0 && doc.nodes[syms].kind == kList {
        var i = 0
        while i < doc.nodes[syms].nchild {
            let el = doc.childAt(syms, i)
            if doc.nodes[el].kind == kString {
                _ = tab.addText(doc.textAt(el))
            } else {
                _ = tab.addGap()
            }
            i += 1
        }
    }
}

func importOne(_ doc: IonDoc, _ id: Int, _ tab: LocalTab, _ cat: Catalog, _ offset: Int) throws {
    let nameId = fieldNode(doc, id, "name")
    if nameId < 0 || doc.nodes[nameId].kind != kString { return }
    let name = doc.textAt(nameId)
    if name.isEmpty || name == "$ion" { return }
    var version = 1
    let verId = fieldNode(doc, id, "version")
    if verId >= 0 && doc.nodes[verId].kind == kInt {
        let v = try docI64(doc, verId, offset)
        if v >= 1 { version = v }
    }
    var hasMax = false
    var maxId = 0
    let maxAt = fieldNode(doc, id, "max_id")
    if maxAt >= 0 && doc.nodes[maxAt].kind == kInt {
        let m = try docI64(doc, maxAt, offset)
        if m >= 0 {
            hasMax = true
            maxId = m
        }
    }
    if hasMax && maxId == 0 { return }
    var idx = cat.exact(name, version)
    if idx < 0 {
        if !hasMax { throw DecodeError(kind: DecodeError.kindSymbol, offset: offset) }
        idx = cat.greatest(name)
    }
    if idx < 0 {
        let dummy = SharedTable(name: name, version: version)
        try tab.importTable(dummy, maxId, offset)
        return
    }
    if !hasMax { maxId = cat.tables[idx].texts.count }
    try tab.importTable(cat.tables[idx], maxId, offset)
}
