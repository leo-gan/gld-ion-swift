func isIdent(_ c: Int) -> Bool {
    if c >= 48 && c <= 57 { return true }
    if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) { return true }
    return c == 95 || c == 36
}

func isOp(_ c: Int) -> Bool {
    if c == 33 || c == 35 || c == 37 || c == 38 || c == 42 || c == 43 { return true }
    if c == 45 || c == 46 || c == 47 || c == 59 || c == 60 || c == 61 || c == 62 { return true }
    return c == 63 || c == 64 || c == 94 || c == 96 || c == 124 || c == 126
}

func isStop(_ c: Int) -> Bool {
    if c == 32 || c == 9 || c == 10 || c == 13 || c == 11 || c == 12 { return true }
    if c == 123 || c == 125 || c == 91 || c == 93 || c == 40 || c == 41 || c == 44 { return true }
    return c == 92 || c == 34 || c == 39
}

func isWs(_ c: Int) -> Bool {
    c == 32 || c == 9 || c == 10 || c == 13 || c == 11 || c == 12
}

func hexVal(_ c: Int) -> Int {
    if c >= 48 && c <= 57 { return c - 48 }
    if c >= 65 && c <= 70 { return c - 55 }
    if c >= 97 && c <= 102 { return c - 87 }
    return -1
}

final class TextParser {
    let raw: [UInt8]
    var i: Int
    let n: Int
    var depth = 0
    var sexp = 0
    var ver = 10
    var bareIVM = 0
    var templ = false
    var curParam0 = 0
    var macroName: [String] = []
    var macroRoot: [Int] = []
    var macroParamAt: [Int] = []
    var macroNParam: [Int] = []
    var paramKind: [Int] = []
    var paramDefault: [Int] = []
    var ident0 = ""
    var ident0At = 0
    var ident0Len = 0
    var identNode0 = -1
    var ident1 = ""
    var ident1At = 0
    var ident1Len = 0
    var identNode1 = -1
    var identHit = -1
    var strCache = ""
    var strAt = 0
    var strLen = 0
    var strValid = false
    var strId = -1

    init(_ raw: [UInt8]) {
        self.raw = raw
        i = 0
        n = raw.count
    }

    @inline(__always)
    func at(_ k: Int) -> Int { Int(raw[k]) }

    @inline(__always)
    func b() -> Int { Int(raw[i]) }

    @inline(__always)
    func skipWs() throws {
        while i < n {
            let c = b()
            if isWs(c) {
                i += 1
                continue
            }
            if c == 47 && i + 1 < n {
                let nxt = at(i + 1)
                if nxt == 47 {
                    i += 2
                    while i < n && b() != 10 && b() != 13 { i += 1 }
                    continue
                }
                if nxt == 42 {
                    i += 2
                    var ok = false
                    while i + 1 < n {
                        if b() == 42 && at(i + 1) == 47 {
                            i += 2
                            ok = true
                            break
                        }
                        i += 1
                    }
                    if !ok { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                    continue
                }
            }
            return
        }
    }

    func expect(_ c: Int) throws {
        if i >= n || b() != c { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        i += 1
    }

    func readAll(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws {
        while true {
            try skipWs()
            if i >= n { return }
            bareIVM = 0
            let id = try parseValue(doc, tab, cat)
            if id < 0 { continue }
            if bareIVM == 10 {
                tab.resetSystem()
                clearMacros()
                ver = 10
                continue
            }
            if bareIVM == 11 {
                tab.resetSystem()
                clearMacros()
                ver = 11
                continue
            }
            if ivmNop(doc, id) { continue }
            if ver == 10 && isLocalTable(doc, id) {
                try applyLst(doc, id, tab, cat, i)
                continue
            }
            if ver == 11 && isLocalTable(doc, id) { continue }
            doc.addTop(id)
        }
    }

    func ivmNop(_ doc: IonDoc, _ id: Int) -> Bool {
        let node = doc.nodes[id]
        if node.annN != 0 || node.kind != kSymbol { return false }
        let s = doc.syms[node.a]
        if s.text < 0 { return false }
        let t = doc.texts[s.text]
        if t == "$ion_1_0" { return true }
        return ver == 11 && t == "$ion_1_1"
    }

    func parseValue(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws -> Int {
        try skipWs()
        if depth == 0 && i < n {
            let c0 = b()
            if c0 == 36 || c0 == 95 || (c0 >= 65 && c0 <= 90) || (c0 >= 97 && c0 <= 122) {
                let iv = try bareIvm(doc)
                if iv != 0 {
                    bareIVM = iv
                    if iv == 10 { return doc.addSymbolText("$ion_1_0") }
                    return doc.addSymbolText("$ion_1_1")
                }
            }
        }
        if i < n {
            let c = b()
            if c == 123 && !(i + 1 < n && at(i + 1) == 123) { return try struct_(doc, tab, cat) }
            if c == 91 { return try list(doc, tab, cat) }
            if c == 40 && !(ver == 11 && i + 1 < n && at(i + 1) == 58) { return try sexp_(doc, tab, cat) }
        }
        if !annAhead() { return try one(doc, tab, cat) }
        var anns: [Int] = []
        while annAhead() {
            let quoted = b() == 39
            let sym = try parseSymbol(doc, tab, quoted)
            try skipWs()
            try expect(58)
            try expect(58)
            anns.append(sym)
            try skipWs()
        }
        let id = try one(doc, tab, cat)
        if id < 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        doc.setAnns(id, anns)
        return id
    }

    func bareIvm(_ doc: IonDoc) throws -> Int {
        _ = doc
        if i >= n || !isIdent(b()) || (b() >= 48 && b() <= 57) { return 0 }
        var j = i
        while j < n && isIdent(at(j)) { j += 1 }
        let word = copy(i, j)
        var k = j
        while k < n && isWs(at(k)) { k += 1 }
        if k + 1 < n && at(k) == 58 && at(k + 1) == 58 { return 0 }
        let which = try ivmWord(word)
        if which == 0 { return 0 }
        i = j
        return which
    }

    func ivmWord(_ word: String) throws -> Int {
        let bts = utf8Bytes(word)
        if bts.count < 8 || bts[0] != 36 { return 0 }
        let prefix = Array("$ion_".utf8)
        if bts.count <= prefix.count { return 0 }
        for k in prefix.indices where bts[k] != prefix[k] { return 0 }
        var k = prefix.count
        var major = 0
        var saw = false
        while k < bts.count && bts[k] >= 48 && bts[k] <= 57 {
            saw = true
            major = major * 10 + Int(bts[k]) - 48
            k += 1
        }
        if !saw || k >= bts.count || bts[k] != 95 { return 0 }
        k += 1
        var minor = 0
        saw = false
        while k < bts.count && bts[k] >= 48 && bts[k] <= 57 {
            saw = true
            minor = minor * 10 + Int(bts[k]) - 48
            k += 1
        }
        if !saw || k != bts.count { return 0 }
        if major == 1 && minor == 0 { return 10 }
        if major == 1 && minor == 1 { return 11 }
        throw DecodeError(kind: DecodeError.kindVersion, offset: i)
    }

    func annAhead() -> Bool {
        if i >= n { return false }
        let c = b()
        if c != 39 && c != 36 && !(c >= 65 && c <= 90) && !(c >= 97 && c <= 122) && c != 95 {
            return false
        }
        var j = i
        if c == 39 {
            j += 1
            while j < n {
                if at(j) == 92 {
                    j += 2
                    continue
                }
                if at(j) == 39 {
                    j += 1
                    break
                }
                j += 1
            }
        } else {
            while j < n && isIdent(at(j)) { j += 1 }
            let word = copy(i, j)
            if word == "null" || word == "true" || word == "false" || word == "nan" { return false }
        }
        var k = j
        while k < n && isWs(at(k)) { k += 1 }
        return k + 1 < n && at(k) == 58 && at(k + 1) == 58
    }

    func one(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws -> Int {
        if i >= n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        let c = b()
        if ver == 11 && c == 40 && i + 1 < n && at(i + 1) == 58 {
            return try colon(doc, tab, cat)
        }
        if c == 91 { return try list(doc, tab, cat) }
        if c == 40 { return try sexp_(doc, tab, cat) }
        if c == 123 {
            if i + 1 < n && at(i + 1) == 123 { return try lob(doc) }
            return try struct_(doc, tab, cat)
        }
        if c == 34 { return try string_(doc, false) }
        if c == 39 {
            if i + 2 < n && at(i + 1) == 39 && at(i + 2) == 39 {
                return try string_(doc, true)
            }
            let sym = try parseSymbol(doc, tab, true)
            return doc.wrapSym(sym)
        }
        if c == 43 || c == 45 || (c >= 48 && c <= 57) { return try number(doc) }
        if isIdent(c) { return try keywordOrSymbol(doc, tab) }
        if sexp > 0 && isOp(c) { return doc.addSymbolText(try readOperator()) }
        throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
    }

    func copy(_ a: Int, _ b: Int) -> String {
        if a >= b { return "" }
        return String(decoding: raw[a..<b], as: UTF8.self)
    }

    func enter() throws {
        if depth >= maxDepth { throw DecodeError(kind: DecodeError.kindDepth, offset: i) }
        depth += 1
    }

    func list(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws -> Int {
        try enter()
        i += 1
        let id = doc.startContainer(kList)
        try skipWs()
        if i < n && b() == 93 {
            i += 1
            depth -= 1
            return id
        }
        while true {
            let child = try parseValue(doc, tab, cat)
            if child >= 0 { doc.addChild(id, child, -1) }
            try skipWs()
            if i < n && b() == 44 {
                i += 1
                try skipWs()
                if i < n && b() == 93 {
                    i += 1
                    break
                }
                continue
            }
            if i < n && b() == 93 {
                i += 1
                break
            }
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        depth -= 1
        return id
    }

    func sexp_(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws -> Int {
        try enter()
        i += 1
        sexp += 1
        let id = doc.startContainer(kSexp)
        while true {
            try skipWs()
            if i < n && b() == 41 {
                i += 1
                break
            }
            if i >= n { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            let child = try parseValue(doc, tab, cat)
            if child >= 0 { doc.addChild(id, child, -1) }
        }
        sexp -= 1
        depth -= 1
        return id
    }

    func struct_(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws -> Int {
        try enter()
        i += 1
        let id = doc.startContainer(kStruct)
        try skipWs()
        if i < n && b() == 125 {
            i += 1
            depth -= 1
            return id
        }
        while true {
            let field: Int
            if i < n && isIdent(b()) && !(b() >= 48 && b() <= 57) {
                try takeIdent()
                let node = fastSymbolNode(doc)
                if node >= 0 {
                    field = doc.nodes[node].a
                } else {
                    i -= hitText().utf8.count
                    field = try fieldName(doc, tab)
                }
            } else {
                field = try fieldName(doc, tab)
            }
            if i < n && b() == 58 {
                i += 1
                if i < n && b() == 58 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            } else {
                try skipWs()
                try expect(58)
                if i < n && b() == 58 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            }
            let child: Int
            if i < n {
                let c = b()
                if c >= 48 && c <= 57 {
                    let fast = fastI64(doc, false)
                    child = fast >= 0 ? fast : try number(doc)
                } else if c == 45 || c == 43 {
                    child = try number(doc)
                } else if c == 34 {
                    child = try string_(doc, false)
                } else {
                    child = try parseValue(doc, tab, cat)
                }
            } else {
                child = try parseValue(doc, tab, cat)
            }
            if child >= 0 { doc.addChild(id, child, field) }
            if i >= n || (b() != 44 && b() != 125) { try skipWs() }
            if i < n && b() == 44 {
                i += 1
                try skipWs()
                if i < n && b() == 125 {
                    i += 1
                    break
                }
                continue
            }
            if i < n && b() == 125 {
                i += 1
                break
            }
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        depth -= 1
        return id
    }

    func fieldName(_ doc: IonDoc, _ tab: LocalTab) throws -> Int {
        try skipWs()
        if i >= n { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        let c = b()
        let long = c == 39 && i + 2 < n && at(i + 1) == 39 && at(i + 2) == 39
        if c == 34 || long {
            let node = try string_(doc, long)
            return stringAsSym(doc, node)
        }
        if c == 39 { return try parseSymbol(doc, tab, true) }
        if isIdent(c) && !(c >= 48 && c <= 57) { return try parseSymbol(doc, tab, false) }
        throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
    }

    func stringAsSym(_ doc: IonDoc, _ node: Int) -> Int {
        let text = doc.textAt(node)
        let sym = doc.addSymbolText(text)
        return doc.nodes[sym].a
    }

    func parseSymbol(_ doc: IonDoc, _ tab: LocalTab, _ quoted: Bool) throws -> Int {
        if quoted {
            let text = try quotedBytes(39, false)
            let node = doc.addSymbolText(String(decoding: text, as: UTF8.self))
            return doc.nodes[node].a
        }
        try takeIdent()
        let fast = fastSymbolNode(doc)
        if fast >= 0 { return doc.nodes[fast].a }
        let text = hitText()
        let bytes = utf8Bytes(text)
        if bytes.count > 1 && bytes[0] == 36 {
            var allDigit = true
            var k = 1
            while k < bytes.count {
                if bytes[k] < 48 || bytes[k] > 57 {
                    allDigit = false
                    break
                }
                k += 1
            }
            if allDigit {
                var sid = 0
                k = 1
                while k < bytes.count {
                    sid = sid * 10 + Int(bytes[k]) - 48
                    if sid > 2_000_000_000 {
                        throw DecodeError(kind: DecodeError.kindRange, offset: i)
                    }
                    k += 1
                }
                let node = try symFromSid(doc, tab, sid, i)
                return doc.nodes[node].a
            }
        }
        if text == "null" || text == "true" || text == "false" || text == "nan" {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        let node = doc.addSymbolText(text)
        return doc.nodes[node].a
    }

    func identText() throws -> String {
        try takeIdent()
        return hitText()
    }

    @inline(__always)
    func takeIdent() throws {
        if i >= n || !isIdent(b()) || (b() >= 48 && b() <= 57) {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        let start = i
        i += 1
        while i < n && isIdent(b()) { i += 1 }
        let nlen = i - start
        if sameSpan(ident0At, ident0Len, start, nlen) {
            identHit = 0
            return
        }
        if sameSpan(ident1At, ident1Len, start, nlen) {
            identHit = 1
            return
        }
        ident1 = ident0
        ident1At = ident0At
        ident1Len = ident0Len
        identNode1 = identNode0
        ident0At = start
        ident0Len = nlen
        ident0 = String(decoding: raw[start..<i], as: UTF8.self)
        identNode0 = -1
        identHit = 0
    }

    func hitText() -> String { identHit == 0 ? ident0 : ident1 }

    func hitBytes() -> ArraySlice<UInt8> {
        if identHit == 0 { return raw[ident0At..<(ident0At + ident0Len)] }
        return raw[ident1At..<(ident1At + ident1Len)]
    }

    @inline(__always)
    func sameSpan(_ at: Int, _ len: Int, _ start: Int, _ nlen: Int) -> Bool {
        if len == 0 || len != nlen { return false }
        var k = 0
        while k < nlen {
            if raw[at + k] != raw[start + k] { return false }
            k += 1
        }
        return true
    }

    @inline(__always)
    func fastSymbolNode(_ doc: IonDoc) -> Int {
        let cached = identHit == 0 ? identNode0 : identNode1
        if cached >= 0 { return cached }
        let at = identHit == 0 ? ident0At : ident1At
        let len = identHit == 0 ? ident0Len : ident1Len
        if keywordOrDollarSpan(at, len) { return -1 }
        let node = doc.addSymbolText(hitText())
        if identHit == 0 { identNode0 = node } else { identNode1 = node }
        return node
    }

    @inline(__always)
    func keywordOrDollarSpan(_ at: Int, _ nlen: Int) -> Bool {
        if nlen == 0 || raw[at] == 36 { return true }
        if nlen == 3 { return raw[at] == 110 && raw[at + 1] == 97 && raw[at + 2] == 110 }
        if nlen == 4 && raw[at] == 110 {
            return raw[at + 1] == 117 && raw[at + 2] == 108 && raw[at + 3] == 108
        }
        if nlen == 4 && raw[at] == 116 {
            return raw[at + 1] == 114 && raw[at + 2] == 117 && raw[at + 3] == 101
        }
        if nlen == 5 {
            return raw[at] == 102 && raw[at + 1] == 97 && raw[at + 2] == 108 && raw[at + 3] == 115
                && raw[at + 4] == 101
        }
        return false
    }

    func readOperator() throws -> String {
        var buf: [UInt8] = []
        while i < n && isOp(b()) {
            if b() == 47 && i + 1 < n {
                let nxt = at(i + 1)
                if nxt == 47 || nxt == 42 { break }
            }
            buf.append(raw[i])
            i += 1
        }
        if buf.isEmpty { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        return String(decoding: buf, as: UTF8.self)
    }

    func keywordOrSymbol(_ doc: IonDoc, _ tab: LocalTab) throws -> Int {
        try takeIdent()
        let fast = fastSymbolNode(doc)
        if fast >= 0 { return fast }
        let text = hitText()
        if text == "null" { return try null_(doc) }
        if text == "true" { return doc.addBool(true) }
        if text == "false" { return doc.addBool(false) }
        if text == "nan" { return doc.addFloat(8, 0x7FF8_0000_0000_0000) }
        let bytes = utf8Bytes(text)
        if bytes.count > 1 && bytes[0] == 36 {
            var allDigit = true
            var k = 1
            while k < bytes.count {
                if bytes[k] < 48 || bytes[k] > 57 {
                    allDigit = false
                    break
                }
                k += 1
            }
            if allDigit {
                var sid = 0
                k = 1
                while k < bytes.count {
                    sid = sid * 10 + Int(bytes[k]) - 48
                    k += 1
                }
                return try symFromSid(doc, tab, sid, i)
            }
        }
        return doc.addSymbolText(text)
    }

    func null_(_ doc: IonDoc) throws -> Int {
        if i >= n || b() != 46 { return doc.addNull(0) }
        i += 1
        let name = try identText()
        switch name {
        case "null": return doc.addNull(0)
        case "bool": return doc.addNull(kBool)
        case "int": return doc.addNull(kInt)
        case "float": return doc.addNull(kFloat)
        case "decimal": return doc.addNull(kDecimal)
        case "timestamp": return doc.addNull(kTimestamp)
        case "string": return doc.addNull(kString)
        case "symbol": return doc.addNull(kSymbol)
        case "blob": return doc.addNull(kBlob)
        case "clob": return doc.addNull(kClob)
        case "list": return doc.addNull(kList)
        case "sexp": return doc.addNull(kSexp)
        case "struct": return doc.addNull(kStruct)
        default: throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
    }

    func plainQuoteEnd(_ end: Int) -> Int {
        if i >= n || b() != end { return -1 }
        var j = i + 1
        while j < n {
            let c = at(j)
            if c == end { return j }
            if c == 92 || c < 32 { return -1 }
            j += 1
        }
        return -1
    }

    func string_(_ doc: IonDoc, _ long: Bool) throws -> Int {
        if !long {
            let end = plainQuoteEnd(34)
            if end >= 0 {
                let start = i + 1
                let nlen = end - start
                if strValid && ((nlen == 0 && strLen == 0) || sameSpan(strAt, strLen, start, nlen)) {
                    i = end + 1
                    if strId >= 0 { return doc.addStringAt(strId) }
                    let hit = doc.addString(strCache)
                    strId = doc.nodes[hit].a
                    return hit
                }
                strAt = start
                strLen = nlen
                strValid = true
                strCache = String(decoding: raw[start..<end], as: UTF8.self)
                i = end + 1
                let made = doc.addString(strCache)
                strId = doc.nodes[made].a
                return made
            }
        }
        var buf: [UInt8] = []
        if long {
            try readLong(&buf, false)
            while true {
                let save = i
                try skipWs()
                if startsLong() {
                    try readLong(&buf, false)
                } else {
                    i = save
                    break
                }
            }
        } else {
            try readShort(&buf, 34, false)
        }
        return doc.addString(String(decoding: buf, as: UTF8.self))
    }

    func quotedBytes(_ end: Int, _ long: Bool) throws -> [UInt8] {
        var buf: [UInt8] = []
        if long { try readLong(&buf, false) }
        else { try readShort(&buf, end, false) }
        return buf
    }

    func startsLong() -> Bool {
        i + 2 < n && b() == 39 && at(i + 1) == 39 && at(i + 2) == 39
    }

    func readShort(_ buf: inout [UInt8], _ end: Int, _ clob: Bool) throws {
        try expect(end)
        while i < n {
            let c = b()
            if c == end {
                i += 1
                return
            }
            if c < 32 && c != 9 && c != 11 && c != 12 {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
            if c == 92 {
                try escape(&buf, clob)
                continue
            }
            if clob && c >= 128 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            buf.append(UInt8(c))
            i += 1
        }
        throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
    }

    func readLong(_ buf: inout [UInt8], _ clob: Bool) throws {
        if !startsLong() { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        i += 3
        while i < n {
            if startsLong() {
                i += 3
                return
            }
            let c = b()
            if c < 32 && c != 9 && c != 10 && c != 11 && c != 12 && c != 13 {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
            if c == 92 {
                try escape(&buf, clob)
                continue
            }
            if c == 13 {
                i += 1
                if i < n && b() == 10 { i += 1 }
                buf.append(10)
                continue
            }
            if clob && c >= 128 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            buf.append(UInt8(c))
            i += 1
        }
        throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
    }

    func escape(_ buf: inout [UInt8], _ clob: Bool) throws {
        i += 1
        if i >= n { throw DecodeError(kind: DecodeError.kindEscape, offset: i) }
        let c = b()
        i += 1
        switch c {
        case 48: buf.append(0)
        case 97: buf.append(7)
        case 98: buf.append(8)
        case 116: buf.append(9)
        case 110: buf.append(10)
        case 118: buf.append(11)
        case 102: buf.append(12)
        case 114: buf.append(13)
        case 34, 39, 47, 63, 92: buf.append(UInt8(c))
        case 10: return
        case 13:
            if i < n && b() == 10 { i += 1 }
            return
        case 120:
            try uEscape(&buf, 2)
        case 117, 85:
            if clob { throw DecodeError(kind: DecodeError.kindEscape, offset: i) }
            if c == 85 {
                try uEscape(&buf, 8)
            } else {
                var cp = try hexCP(4)
                if cp >= 0xD800 && cp <= 0xDBFF {
                    if i + 1 < n && b() == 92 && at(i + 1) == 117 {
                        i += 2
                        let low = try hexCP(4)
                        if low < 0xDC00 || low > 0xDFFF {
                            throw DecodeError(kind: DecodeError.kindEscape, offset: i)
                        }
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00)
                    } else {
                        throw DecodeError(kind: DecodeError.kindEscape, offset: i)
                    }
                }
                try appendUTF8(&buf, cp, i)
            }
        default:
            throw DecodeError(kind: DecodeError.kindEscape, offset: i)
        }
    }

    func hexCP(_ count: Int) throws -> Int {
        if i + count > n { throw DecodeError(kind: DecodeError.kindEscape, offset: i) }
        var cp = 0
        var k = 0
        while k < count {
            let h = hexVal(at(i + k))
            if h < 0 { throw DecodeError(kind: DecodeError.kindEscape, offset: i) }
            cp = (cp << 4) | h
            k += 1
        }
        i += count
        return cp
    }

    func uEscape(_ buf: inout [UInt8], _ count: Int) throws {
        let cp = try hexCP(count)
        try appendUTF8(&buf, cp, i)
    }

    func lob(_ doc: IonDoc) throws -> Int {
        try expect(123)
        try expect(123)
        var j = i
        while j < n && isWs(at(j)) { j += 1 }
        if j < n && (at(j) == 34 || at(j) == 39) { return try clob(doc) }
        var chars: [UInt8] = []
        while i < n {
            let c = b()
            if c == 125 && i + 1 < n && at(i + 1) == 125 {
                i += 2
                let rawB = try b64(chars, i)
                return doc.addBytes(kBlob, rawB)
            }
            if isWs(c) {
                i += 1
                continue
            }
            if b64Char(c) < 0 && c != 61 {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
            chars.append(UInt8(c))
            i += 1
        }
        throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
    }

    func clob(_ doc: IonDoc) throws -> Int {
        while i < n && isWs(b()) { i += 1 }
        var buf: [UInt8] = []
        let long = startsLong()
        if long {
            try readLong(&buf, true)
        } else if i < n && b() == 34 {
            try readShort(&buf, 34, true)
        } else {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        if long {
            while true {
                let save = i
                while i < n && isWs(b()) { i += 1 }
                if startsLong() {
                    try readLong(&buf, true)
                } else {
                    i = save
                    break
                }
            }
        }
        while i < n && isWs(b()) { i += 1 }
        if i + 1 >= n || b() != 125 || at(i + 1) != 125 {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        i += 2
        return doc.addBytes(kClob, buf)
    }

    func number(_ doc: IonDoc) throws -> Int {
        var neg = false
        if b() == 43 {
            let save = i
            i += 1
            if wordAt("inf") {
                try needStop()
                return doc.addFloat(8, 0x7FF0_0000_0000_0000)
            }
            if sexp > 0 {
                i = save
                return doc.addSymbolText(try readOperator())
            }
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        if b() == 45 {
            let save = i
            i += 1
            if wordAt("inf") {
                try needStop()
                return doc.addFloat(8, 0xFFF0_0000_0000_0000)
            }
            if i >= n || !(b() >= 48 && b() <= 57) {
                if sexp > 0 {
                    i = save
                    return doc.addSymbolText(try readOperator())
                }
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
            neg = true
        }
        if i < n && b() == 48 && i + 1 < n {
            let nxt = at(i + 1)
            if nxt == 120 || nxt == 88 || nxt == 98 || nxt == 66 {
                return try radix(doc, neg, nxt == 98 || nxt == 66)
            }
        }
        let fast = fastI64(doc, neg)
        if fast >= 0 { return fast }
        return try real(doc, neg)
    }

    @inline(__always)
    func fastI64(_ doc: IonDoc, _ neg: Bool) -> Int {
        if i >= n { return -1 }
        let c0 = b()
        if c0 < 48 || c0 > 57 { return -1 }
        if c0 == 48 {
            let nxt = i + 1
            if nxt < n {
                let ch = at(nxt)
                if !isStop(ch) && !isWs(ch) { return -1 }
            }
            i = nxt
            return doc.addI64(0)
        }
        var acc = UInt64(0)
        var j = i
        var digits = 0
        while j < n {
            let c = at(j)
            if c < 48 || c > 57 { break }
            if acc > 922_337_203_685_477_580 { return -1 }
            let next = acc * 10 + UInt64(c - 48)
            if neg {
                if next > (UInt64(1) << 63) { return -1 }
            } else if next > UInt64(Int64.max) {
                return -1
            }
            acc = next
            digits += 1
            j += 1
        }
        if digits == 0 { return -1 }
        if j < n {
            let ch = at(j)
            if !isStop(ch) && !isWs(ch) { return -1 }
        }
        i = j
        if neg {
            if acc == (UInt64(1) << 63) { return doc.addI64(Int64.min) }
            return doc.addI64(-Int64(acc))
        }
        return doc.addI64(Int64(acc))
    }

    func wordAt(_ word: String) -> Bool {
        let bts = utf8Bytes(word)
        if i + bts.count > n { return false }
        for k in bts.indices where at(i + k) != Int(bts[k]) { return false }
        let end = i + bts.count
        if end < n && isIdent(at(end)) { return false }
        i = end
        return true
    }

    func needStop() throws {
        if i < n && !isStop(b()) { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
    }

    func radix(_ doc: IonDoc, _ neg: Bool, _ binary: Bool) throws -> Int {
        i += 2
        let base = binary ? 2 : 16
        var acc = BigInt()
        var any = false
        var prevUs = false
        while i < n {
            let c = b()
            if c == 95 {
                if !any || prevUs { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                prevUs = true
                i += 1
                continue
            }
            var d = hexVal(c)
            if binary && (c == 48 || c == 49) {
                d = c - 48
            } else if binary {
                d = -1
            }
            if d < 0 || (!binary && d > 15) { break }
            any = true
            prevUs = false
            acc.mulSmall(UInt32(base))
            acc.addSmall(UInt32(d))
            i += 1
        }
        if !any || prevUs { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        if neg && !acc.isZero { acc.neg = true }
        try needStop()
        return doc.addInt(acc)
    }

    func real(_ doc: IonDoc, _ neg: Bool) throws -> Int {
        var whole: [UInt8] = []
        var under = false
        let nwhole = try digits(&whole, &under)
        if nwhole == 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        if i < n && (b() == 45 || b() == 84) {
            if !neg && !under && nwhole >= 4 { return try timestamp(doc, whole) }
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        if whole.count > 1 && whole[0] == 48 {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        var frac: [UInt8] = []
        var sawDot = false
        if i < n && b() == 46 {
            sawDot = true
            i += 1
            if i < n && b() == 95 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            if i < n && ((b() >= 48 && b() <= 57) || b() == 95) {
                var fracUnder = false
                _ = try digits(&frac, &fracUnder)
            }
        }
        var exp = 0
        var isFloat = false
        var isDec = sawDot
        if i < n && (b() == 101 || b() == 69 || b() == 100 || b() == 68) {
            isFloat = b() == 101 || b() == 69
            isDec = !isFloat
            i += 1
            exp = try exp_()
        }
        if !isDec && !isFloat {
            let coef = bigFromDigits(whole, false)
            var signed = coef
            if neg && !signed.isZero { signed.neg = true }
            try needStop()
            return doc.addInt(signed)
        }
        var all = whole
        all.append(contentsOf: frac)
        if isFloat {
            try needStop()
            return try floatNode(doc, neg, whole, frac, exp)
        }
        let coef = bigFromDigits(all, false)
        try needStop()
        return doc.addDecimal(coef, neg, exp - frac.count)
    }

    func digits(_ out: inout [UInt8], _ under: inout Bool) throws -> Int {
        var count = 0
        var prev = false
        while i < n {
            let c = b()
            if c >= 48 && c <= 57 {
                out.append(UInt8(c))
                count += 1
                prev = false
                i += 1
                continue
            }
            if c == 95 {
                if count == 0 || prev { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                prev = true
                under = true
                i += 1
                continue
            }
            break
        }
        if prev { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        return count
    }

    func exp_() throws -> Int {
        var sign = 1
        if i < n && (b() == 43 || b() == 45) {
            if b() == 45 { sign = -1 }
            i += 1
        }
        var digs: [UInt8] = []
        var under = false
        let count = try digits(&digs, &under)
        if count == 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        var v = 0
        for b in digs {
            if v > 922_337_203_685_477_580 {
                throw DecodeError(kind: DecodeError.kindRange, offset: i)
            }
            v = v * 10 + Int(b) - 48
        }
        return sign * v
    }

    func floatNode(_ doc: IonDoc, _ neg: Bool, _ whole: [UInt8], _ frac: [UInt8], _ exp: Int) throws -> Int {
        var zero = true
        for b in whole where b != 48 { zero = false }
        for b in frac where b != 48 { zero = false }
        if zero && neg { return doc.addFloat(8, UInt64(1) << 63) }
        if zero { return doc.addFloat(0, 0) }
        var sig: [UInt8] = []
        var seen = false
        for b in whole where seen || b != 48 {
            seen = true
            sig.append(b)
        }
        for b in frac {
            if seen || b != 48 {
                seen = true
                sig.append(b)
            }
        }
        var power = exp - frac.count
        if sig.count > 17 {
            let next = Int(sig[17])
            var extra = sig.count - 17
            while sig.count > 17 { sig.removeLast() }
            if next >= 53 {
                var p = sig.count - 1
                var carry = 1
                while p >= 0 && carry == 1 {
                    let d = Int(sig[p]) - 48 + carry
                    if d == 10 {
                        sig[p] = 48
                        carry = 1
                    } else {
                        sig[p] = UInt8(d + 48)
                        carry = 0
                    }
                    p -= 1
                }
                if carry == 1 {
                    var grown: [UInt8] = [49]
                    if sig.count > 1 { grown.append(contentsOf: sig[0..<(sig.count - 1)]) }
                    sig = grown
                    extra += 1
                }
            }
            power += extra
        }
        var token = ""
        if neg { token += "-" }
        token += String(decoding: sig, as: UTF8.self)
        token += "e"
        if power < 0 {
            token += "-"
            token += String(-power)
        } else {
            token += String(power)
        }
        guard let f = Double(token) else {
            throw DecodeError(kind: DecodeError.kindRange, offset: i)
        }
        return doc.addFloat(8, f.bitPattern)
    }

    func timestamp(_ doc: IonDoc, _ digitsIn: [UInt8]) throws -> Int {
        if digitsIn.count != 4 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        var year = 0
        for b in digitsIn {
            year = year * 10 + Int(b) - 48
            if year > 999_999_999 { throw DecodeError(kind: DecodeError.kindRange, offset: i) }
        }
        if year < 1 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        var prec = precYear
        var month = 1
        var day = 1
        var hour = 0
        var minute = 0
        var second = 0
        var frac: [UInt8] = []
        var unknown = true
        var off = 0
        if i < n && b() == 45 {
            i += 1
            month = try two()
            prec = precMonth
            if month < 1 || month > 12 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            if i < n && b() == 45 {
                i += 1
                day = try two()
                prec = precDay
                if day < 1 || day > daysInMonth(year, month) {
                    throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
                }
            }
        }
        if i < n && b() == 84 {
            i += 1
            if i < n && b() >= 48 && b() <= 57 {
                if prec != precDay { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                hour = try two()
                try expect(58)
                minute = try two()
                prec = precMin
                if hour > 23 || minute > 59 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                if i < n && b() == 58 {
                    i += 1
                    second = try two()
                    prec = precSec
                    if second > 59 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                    if i < n && b() == 46 {
                        i += 1
                        var u = false
                        let nfrac = try digits(&frac, &u)
                        if nfrac == 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                        prec = precFrac
                    }
                }
                if i >= n { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                let c = b()
                if c == 90 {
                    i += 1
                    unknown = false
                    off = 0
                } else if c == 43 || c == 45 {
                    var sign = 1
                    if c == 45 { sign = -1 }
                    i += 1
                    let oh = try two()
                    try expect(58)
                    let om = try two()
                    if oh > 23 || om > 59 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                    if sign < 0 && oh == 0 && om == 0 {
                        unknown = true
                        off = 0
                    } else {
                        unknown = false
                        off = sign * (oh * 60 + om)
                    }
                } else {
                    throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
                }
            } else if prec != precYear && prec != precMonth && prec != precDay {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
        } else if prec != precDay {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        try needStop()
        var when = IonTime()
        when.prec = prec
        when.year = year
        when.month = month
        when.day = day
        when.hour = hour
        when.minute = minute
        when.second = second
        when.unknown = unknown
        when.off = off
        if prec == precFrac {
            when.fracExp = -frac.count
            let coef = bigFromDigits(frac, false)
            when.fracAt = doc.limbs.count
            when.fracLen = coef.limbs.count
            doc.limbs.append(contentsOf: coef.limbs)
        }
        return doc.addTime(when)
    }

    func two() throws -> Int {
        if i + 1 >= n { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        let a = b()
        let b2 = at(i + 1)
        if a < 48 || a > 57 || b2 < 48 || b2 > 57 {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        i += 2
        return (a - 48) * 10 + (b2 - 48)
    }

    func clearMacros() {
        macroName = []
        macroRoot = []
        macroParamAt = []
        macroNParam = []
        paramKind = []
        paramDefault = []
    }

    func colon(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws -> Int {
        i += 2
        try skipWs()
        if i < n && b() == 63 { return try placeholder(doc, tab, cat) }
        if i < n && b() == 41 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        let name = try identText()
        if name == "$ion" {
            if depth != 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            return try directive11(doc, tab, cat)
        }
        if templ { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        return try invoke(doc, tab, cat, name)
    }

    func placeholder(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws -> Int {
        if !templ { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        i += 1
        try skipWs()
        var defaultId = -1
        if i < n && b() != 41 {
            if b() == 123 && i + 1 < n && at(i + 1) == 35 {
                try skipGroup(123, 125)
            } else {
                let saved = templ
                templ = false
                defaultId = try parseValue(doc, tab, cat)
                templ = saved
                if defaultId < 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            }
        }
        try skipWs()
        try expect(41)
        let rel = paramKind.count - curParam0
        paramKind.append(0)
        paramDefault.append(defaultId)
        var hole = IonNode(kind: kHole)
        hole.a = rel
        hole.b = defaultId
        return doc._add(hole)
    }

    func skipGroup(_ open: Int, _ close: Int) throws {
        if i >= n || b() != open { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        var depthG = 0
        while i < n {
            let c = b()
            if c == 34 || c == 39 {
                let long = startsLong()
                _ = try quotedBytes(c, long)
                continue
            }
            i += 1
            if c == open { depthG += 1 }
            else if c == close {
                depthG -= 1
                if depthG == 0 { return }
            }
        }
        throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
    }

    func directive11(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws -> Int {
        try skipWs()
        let op = try identText()
        if op == "set_symbols" {
            tab.resetSystem()
            try addSymbolTexts(doc, tab)
        } else if op == "add_symbols" {
            try addSymbolTexts(doc, tab)
        } else if op == "set_macros" || op == "add_macros" {
            if op == "set_macros" { clearMacros() }
            let saved = templ
            templ = true
            while true {
                try skipWs()
                if i < n && b() == 41 { break }
                let param0 = paramKind.count
                curParam0 = param0
                let node = try sexp_(doc, tab, cat)
                try defineMacro(doc, node, param0)
            }
            templ = saved
        } else if op == "use" {
            try useModule(doc, tab, cat)
        } else if op == "module" || op == "import" || op == "encoding" {
            try skipDirectiveRest()
        } else {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        try skipWs()
        try expect(41)
        return -1
    }

    func addSymbolTexts(_ doc: IonDoc, _ tab: LocalTab) throws {
        while true {
            try skipWs()
            if i < n && b() == 41 { return }
            let text = try symbolText(doc)
            _ = tab.addText(text)
        }
    }

    func symbolText(_ doc: IonDoc) throws -> String {
        try skipWs()
        if i >= n { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        let c = b()
        let long = startsLong()
        if c == 34 || long {
            let node = try string_(doc, long)
            return doc.textAt(node)
        }
        if c == 39 {
            let rawB = try quotedBytes(39, false)
            return String(decoding: rawB, as: UTF8.self)
        }
        return try identText()
    }

    func useModule(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws {
        try skipWs()
        let nameNode = try string_(doc, startsLong())
        let name = doc.textAt(nameNode)
        var version = 1
        try skipWs()
        if i < n && b() >= 48 && b() <= 57 {
            let num = try parseValue(doc, tab, cat)
            version = try docInt(doc, num, i)
        }
        let idx = cat.exact(name, version)
        if idx < 0 { throw DecodeError(kind: DecodeError.kindSymbol, offset: i) }
        let count = cat.tables[idx].texts.count
        var k = 0
        while k < count {
            if cat.tables[idx].gap[k] { _ = tab.addGap() }
            else { _ = tab.addText(cat.tables[idx].texts[k]) }
            k += 1
        }
    }

    func skipDirectiveRest() throws {
        var depthD = 1
        while i < n && depthD > 0 {
            let c = b()
            if c == 34 || c == 39 {
                let long = startsLong()
                _ = try quotedBytes(c, long)
                continue
            }
            i += 1
            if c == 40 { depthD += 1 }
            else if c == 41 { depthD -= 1 }
        }
        if depthD != 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        i -= 1
    }

    func defineMacro(_ doc: IonDoc, _ id: Int, _ param0: Int) throws {
        let node = doc.nodes[id]
        if node.kind != kSexp || node.nchild != 2 {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        let nameId = doc.childAt(id, 0)
        let body = doc.childAt(id, 1)
        if doc.nodes[nameId].kind != kSymbol || doc.nodes[body].kind == kHole {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        macroName.append(doc.symText(doc.nodes[nameId].a))
        macroRoot.append(body)
        macroParamAt.append(param0)
        macroNParam.append(paramKind.count - param0)
    }

    func invoke(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog, _ name: String) throws -> Int {
        let addr = try macroAddr(name)
        let nparam = macroNParam[addr]
        var args: [Int] = []
        var p = 0
        while p < nparam {
            try skipWs()
            if atAbsent() {
                try eatAbsent()
                args.append(-1)
            } else {
                let arg = try parseValue(doc, tab, cat)
                if arg < 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                args.append(arg)
            }
            p += 1
        }
        try skipWs()
        try expect(41)
        return try expand(doc, macroRoot[addr], args)
    }

    func macroAddr(_ name: String) throws -> Int {
        let bytes = utf8Bytes(name)
        if bytes.count > 1 && bytes[0] == 36 {
            var addr = 0
            var digits = true
            var k = 1
            while k < bytes.count {
                let ch = Int(bytes[k])
                if ch < 48 || ch > 57 {
                    digits = false
                    break
                }
                addr = addr * 10 + ch - 48
                k += 1
            }
            if digits {
                if addr >= macroRoot.count {
                    throw DecodeError(kind: DecodeError.kindSymbol, offset: i)
                }
                return addr
            }
        }
        for i in macroName.indices where macroName[i] == name { return i }
        throw DecodeError(kind: DecodeError.kindSymbol, offset: i)
    }

    func atAbsent() -> Bool {
        if i + 2 >= n || b() != 40 || at(i + 1) != 58 { return false }
        var k = i + 2
        while k < n && isWs(at(k)) { k += 1 }
        return k < n && at(k) == 41
    }

    func eatAbsent() throws {
        i += 2
        try skipWs()
        try expect(41)
    }

    func expand(_ doc: IonDoc, _ id: Int, _ args: [Int]) throws -> Int {
        let node = doc.nodes[id]
        if node.kind == kHole {
            var out = -1
            if node.a < args.count && args[node.a] >= 0 {
                out = args[node.a]
            } else if node.b >= 0 {
                out = try expand(doc, node.b, args)
            }
            if out < 0 { return -1 }
            if node.annN == 0 { return out }
            let copied = doc.nodes[out]
            let cloned = doc._add(copied)
            var anns: [Int] = []
            var k = 0
            while k < node.annN {
                anns.append(doc.anns[node.ann + k])
                k += 1
            }
            doc.setAnns(cloned, anns)
            return cloned
        }
        if node.kind == kList || node.kind == kSexp || node.kind == kStruct {
            let nid = doc.startContainer(node.kind)
            if node.annN > 0 {
                var anns: [Int] = []
                var k = 0
                while k < node.annN {
                    anns.append(doc.anns[node.ann + k])
                    k += 1
                }
                doc.setAnns(nid, anns)
            }
            var e = node.child
            var seen = 0
            while seen < node.nchild {
                let edge = doc.edges[e]
                let child = try expand(doc, edge.child, args)
                if child >= 0 { doc.addChild(nid, child, edge.field) }
                e = edge.next
                seen += 1
            }
            return nid
        }
        return id
    }
}

func docInt(_ doc: IonDoc, _ id: Int, _ offset: Int) throws -> Int {
    let node = doc.nodes[id]
    if node.kind != kInt || node.c != 0 || node.b > 1 {
        throw DecodeError(kind: DecodeError.kindRange, offset: offset)
    }
    if node.b == 0 { return 0 }
    return Int(doc.limbs[node.a])
}

func b64Char(_ c: Int) -> Int {
    if c >= 65 && c <= 90 { return c - 65 }
    if c >= 97 && c <= 122 { return c - 71 }
    if c >= 48 && c <= 57 { return c + 4 }
    if c == 43 { return 62 }
    if c == 47 { return 63 }
    return -1
}

func b64(_ chars: [UInt8], _ offset: Int) throws -> [UInt8] {
    let count = chars.count
    if count == 0 { return [] }
    var pad = 0
    var i = count - 1
    while i >= 0 && chars[i] == 61 {
        pad += 1
        i -= 1
    }
    if pad > 2 || (count % 4) != 0 {
        throw DecodeError(kind: DecodeError.kindSyntax, offset: offset)
    }
    i = 0
    while i < count - pad {
        if chars[i] == 61 || b64Char(Int(chars[i])) < 0 {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: offset)
        }
        i += 1
    }
    var out: [UInt8] = []
    var k = 0
    while k < count {
        let c0 = b64Char(Int(chars[k]))
        let c1 = b64Char(Int(chars[k + 1]))
        var c2 = 0
        var c3 = 0
        if chars[k + 2] != 61 { c2 = b64Char(Int(chars[k + 2])) }
        if chars[k + 3] != 61 { c3 = b64Char(Int(chars[k + 3])) }
        if c0 < 0 || c1 < 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: offset) }
        let v = (c0 << 18) | (c1 << 12) | (c2 << 6) | c3
        out.append(UInt8((v >> 16) & 255))
        if chars[k + 2] != 61 { out.append(UInt8((v >> 8) & 255)) }
        if chars[k + 3] != 61 { out.append(UInt8(v & 255)) }
        k += 4
    }
    return out
}

func utf8FromWide(_ raw: [UInt8]) throws -> [UInt8] {
    var out: [UInt8] = []
    var width = 1
    var be = true
    if raw.count >= 4 && raw[0] == 0 && raw[1] == 0 && raw[2] == 0 {
        width = 4
    } else if raw.count >= 4 && raw[0] != 0 && raw[1] == 0 && raw[2] == 0 && raw[3] == 0 {
        width = 4
        be = false
    } else if raw.count >= 2 && raw[0] == 0 && raw[1] != 0 {
        width = 2
    } else if raw.count >= 2 && raw[0] != 0 && raw[1] == 0 {
        width = 2
        be = false
    }
    if width == 1 { return raw }
    if raw.count % width != 0 { throw DecodeError(kind: DecodeError.kindUTF8, offset: 0) }
    var i = 0
    while i < raw.count {
        var cp = 0
        var b = 0
        while b < width {
            var idx = i + b
            if !be { idx = i + width - 1 - b }
            cp = (cp << 8) | Int(raw[idx])
            b += 1
        }
        i += width
        if width == 2 && cp >= 0xD800 && cp <= 0xDBFF && i + 1 < raw.count {
            var low = (Int(raw[i + 1]) << 8) | Int(raw[i])
            if be { low = (Int(raw[i]) << 8) | Int(raw[i + 1]) }
            if low >= 0xDC00 && low <= 0xDFFF {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00)
                i += 2
            }
        }
        try appendUTF8(&out, cp, i)
    }
    return out
}

func isWide(_ raw: [UInt8]) -> Bool {
    if raw.count >= 4 && raw[0] == 0 && raw[1] == 0 && raw[2] == 0 { return true }
    if raw.count >= 4 && raw[0] != 0 && raw[1] == 0 && raw[2] == 0 && raw[3] == 0 { return true }
    if raw.count >= 2 && raw[0] == 0 && raw[1] != 0 { return true }
    if raw.count >= 2 && raw[0] != 0 && raw[1] == 0 { return true }
    return false
}

func isAscii(_ raw: [UInt8]) -> Bool {
    var bits = 0
    var i = 0
    while i + 4 <= raw.count {
        bits |= Int(raw[i]) | Int(raw[i + 1]) | Int(raw[i + 2]) | Int(raw[i + 3])
        i += 4
    }
    while i < raw.count {
        bits |= Int(raw[i])
        i += 1
    }
    return (bits & 128) == 0
}

public func decodeText(_ raw: [UInt8], _ cat: Catalog) throws -> IonDoc {
    if raw.count >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF {
        throw DecodeError(kind: DecodeError.kindSyntax, offset: 0)
    }
    let doc = IonDoc()
    doc.reserve(raw.count / 2 + 8)
    let tab = LocalTab()
    if isWide(raw) {
        let utf = try utf8FromWide(raw)
        try validateUTF8(utf, 0)
        let parser = TextParser(utf)
        try parser.readAll(doc, tab, cat)
        return doc
    }
    if !isAscii(raw) { try validateUTF8(raw, 0) }
    let parser = TextParser(raw)
    try parser.readAll(doc, tab, cat)
    return doc
}

public func adoptText(_ doc: IonDoc, _ text: String) throws -> Int {
    let raw = utf8Bytes(text)
    let tab = LocalTab()
    let cat = Catalog()
    let parser = TextParser(raw)
    let id = try parser.parseValue(doc, tab, cat)
    if id < 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: 0) }
    return id
}
