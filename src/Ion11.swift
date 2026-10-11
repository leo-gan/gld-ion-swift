final class Ion11 {
    let raw: [UInt8]
    var i: Int
    var templ = false
    var curParam0 = 0
    var depth = 0
    var macroName: [String] = []
    var macroRoot: [Int] = []
    var macroParamAt: [Int] = []
    var macroNParam: [Int] = []
    var paramKind: [Int] = []
    var paramDefault: [Int] = []

    init(_ raw: [UInt8]) {
        self.raw = raw
        i = 0
    }

    func clearMacros() {
        macroName = []
        macroRoot = []
        macroParamAt = []
        macroNParam = []
        paramKind = []
        paramDefault = []
    }

    func readTop(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws {
        while i < raw.count {
            if bvm() {
                tab.resetSystem()
                clearMacros()
                continue
            }
            let id = try value(doc, tab, false, cat)
            if id >= 0 { doc.addTop(id) }
        }
    }

    func bvm() -> Bool {
        if i + 3 >= raw.count { return false }
        if raw[i] != 0xE0 || raw[i + 3] != 0xEA { return false }
        if raw[i + 1] != 1 { return false }
        i += 4
        return true
    }

    func value(_ doc: IonDoc, _ tab: LocalTab, _ inE: Bool, _ cat: Catalog) throws -> Int {
        if depth > maxDepth { throw DecodeError(kind: DecodeError.kindDepth, offset: i) }
        if i >= raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        let op = Int(raw[i])
        i += 1
        if op == 0xEC { return -1 }
        if op == 0xED {
            let n = try flexUInt(raw, &i)
            if i + n > raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
            i += n
            return -1
        }
        if op == 0xEF { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        if op == 0x8E { return doc.addNull(0) }
        if op == 0x8F { return try typedNull(doc) }
        if op >= 0x60 && op <= 0x68 {
            if op == 0x60 { return doc.addI64(0) }
            let v = try fixedInt(raw, &i, op - 0x60)
            return doc.addI64(Int64(v))
        }
        if op == 0xF5 {
            let n = try flexUInt(raw, &i)
            if n > 8 { return try longInt(doc, n) }
            let v = try fixedInt(raw, &i, n)
            return doc.addI64(Int64(v))
        }
        if op == 0x6E { return doc.addBool(true) }
        if op == 0x6F { return doc.addBool(false) }
        if op == 0x6A { return doc.addFloat(0, 0) }
        if op >= 0x6B && op <= 0x6D {
            var n = 2
            if op == 0x6C { n = 4 }
            if op == 0x6D { n = 8 }
            return try readFloat(doc, n)
        }
        if op >= 0x70 && op <= 0x7F { return try readDecimal(doc, op - 0x70) }
        if op == 0xF6 {
            let n = try flexUInt(raw, &i)
            return try readDecimal(doc, n)
        }
        if op >= 0x90 && op <= 0x9F { return doc.addString(try text(op - 0x90)) }
        if op == 0xF8 {
            let n = try flexUInt(raw, &i)
            return doc.addString(try text(n))
        }
        if op >= 0xA0 && op <= 0xAF { return doc.addSymbolText(try text(op - 0xA0)) }
        if op == 0xF9 {
            let n = try flexUInt(raw, &i)
            return doc.addSymbolText(try text(n))
        }
        if op >= 0x50 && op <= 0x57 {
            let hi = try flexUInt(raw, &i)
            let sid = (hi << 3) | (op - 0x50)
            return try symFromSid(doc, tab, sid, i)
        }
        if op == 0x58 || op == 0x59 {
            i -= 1
            return try annotated(doc, tab, cat)
        }
        if op >= 0xB0 && op <= 0xBF { return try container(doc, tab, kList, op - 0xB0, false, cat) }
        if op == 0xFA {
            let n = try flexUInt(raw, &i)
            return try container(doc, tab, kList, n, false, cat)
        }
        if op == 0xF0 { return try container(doc, tab, kList, -1, true, cat) }
        if op >= 0xC0 && op <= 0xCF { return try container(doc, tab, kSexp, op - 0xC0, false, cat) }
        if op == 0xFB {
            let n = try flexUInt(raw, &i)
            return try container(doc, tab, kSexp, n, false, cat)
        }
        if op == 0xF1 { return try container(doc, tab, kSexp, -1, true, cat) }
        if op == 0xD0 { return doc.startContainer(kStruct) }
        if (op >= 0xD2 && op <= 0xDF) || op == 0xFC || op == 0xFD {
            var n = op - 0xD0
            var flex = false
            if op == 0xFC || op == 0xFD { n = try flexUInt(raw, &i) }
            if op == 0xFD { flex = true }
            return try readStruct(doc, tab, n, false, flex || op == 0xFD, cat)
        }
        if op == 0xF2 || op == 0xF3 {
            return try readStruct(doc, tab, -1, true, op == 0xF3, cat)
        }
        if op == 0xFE || op == 0xFF {
            let n = try flexUInt(raw, &i)
            let kind = op == 0xFF ? kClob : kBlob
            return try readBytes(doc, kind, n)
        }
        if op >= 0x80 && op <= 0x8C { return try shortTime(doc, op) }
        if op == 0xF7 { return try longTime(doc) }
        if op == 0xE0 {
            if inE { return -2 }
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        if op == 0xE9 || op == 0xEA || op == 0xEB {
            return try placeholder(doc, tab, op, cat)
        }
        if op >= 0xE1 && op <= 0xE8 {
            try directive(doc, tab, op, cat)
            return -1
        }
        if templ && (op < 0x48 || (op >= 0x48 && op <= 0x4F) || op == 0xF4) {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        if op < 0x48 || (op >= 0x48 && op <= 0x4F) || op == 0xF4 {
            return try eexp(doc, tab, op, cat)
        }
        throw DecodeError(kind: DecodeError.kindVersion, offset: i)
    }

    func text(_ n: Int) throws -> String { try takeUTF(raw, &i, n) }

    func longInt(_ doc: IonDoc, _ n: Int) throws -> Int {
        if n < 0 || i + n > raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        let bytes = Array(raw[i..<(i + n)])
        i += n
        return doc.addInt(bigFromLESigned(bytes))
    }

    func typedNull(_ doc: IonDoc) throws -> Int {
        if i >= raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        let t = Int(raw[i])
        i += 1
        switch t {
        case 1: return doc.addNull(kBool)
        case 2: return doc.addNull(kInt)
        case 3: return doc.addNull(kFloat)
        case 4: return doc.addNull(kDecimal)
        case 5: return doc.addNull(kTimestamp)
        case 6: return doc.addNull(kString)
        case 7: return doc.addNull(kSymbol)
        case 8: return doc.addNull(kBlob)
        case 9: return doc.addNull(kClob)
        case 10: return doc.addNull(kList)
        case 11: return doc.addNull(kSexp)
        case 12: return doc.addNull(kStruct)
        default: throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
    }

    func readFloat(_ doc: IonDoc, _ n: Int) throws -> Int {
        if i + n > raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        var bits = UInt64(0)
        var k = 0
        while k < n {
            bits |= UInt64(raw[i + k]) << UInt64(k * 8)
            k += 1
        }
        i += n
        return doc.addFloat(n, bits)
    }

    func readDecimal(_ doc: IonDoc, _ n: Int) throws -> Int {
        if n == 0 { return doc.addDecimal(BigInt(), false, 0) }
        let end = i + n
        if n < 0 || end > raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        let exp = try flexInt(raw, &i)
        var coef = BigInt()
        var neg = false
        if i < end {
            let nbytes = end - i
            if nbytes > 8 {
                let bytes = Array(raw[i..<end])
                i = end
                let big = bigFromLESigned(bytes)
                let sign = big.neg
                var mag = big
                mag.neg = false
                return doc.addDecimal(mag, sign, exp)
            }
            var v = try fixedInt(raw, &i, nbytes)
            if v < 0 {
                neg = true
                v = -v
            } else {
                neg = v == 0
            }
            coef = bigFromU64(UInt64(v), false)
        }
        return doc.addDecimal(coef, neg, exp)
    }

    func readBytes(_ doc: IonDoc, _ kind: Int, _ n: Int) throws -> Int {
        if n < 0 || i + n > raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        let buf = Array(raw[i..<(i + n)])
        i += n
        return doc.addBytes(kind, buf)
    }

    func container(_ doc: IonDoc, _ tab: LocalTab, _ kind: Int, _ n: Int, _ delim: Bool, _ cat: Catalog) throws -> Int {
        if depth >= maxDepth { throw DecodeError(kind: DecodeError.kindDepth, offset: i) }
        depth += 1
        defer { depth -= 1 }
        let id = doc.startContainer(kind)
        var end = raw.count
        if !delim {
            end = i + n
            if n < 0 || end > raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        }
        while i < end {
            if delim && i < raw.count && raw[i] == 0xEF {
                i += 1
                return id
            }
            let child = try value(doc, tab, false, cat)
            if child >= 0 { doc.addChild(id, child, -1) }
        }
        return id
    }

    func fieldId(_ doc: IonDoc, _ tab: LocalTab, _ mode: Bool, _ cat: Catalog) throws -> Int {
        _ = cat
        if mode {
            let iv = try flexInt(raw, &i)
            if iv >= 0 {
                let sym = try symFromSid(doc, tab, iv, i)
                return doc.nodes[sym].a
            }
            let nbytes = -1 - iv
            return doc.nodes[doc.addSymbolText(try text(nbytes))].a
        }
        let sid = try flexUInt(raw, &i)
        let sym = try symFromSid(doc, tab, sid, i)
        return doc.nodes[sym].a
    }

    func readStruct(_ doc: IonDoc, _ tab: LocalTab, _ n: Int, _ delim: Bool, _ flex: Bool, _ cat: Catalog) throws -> Int {
        if depth >= maxDepth { throw DecodeError(kind: DecodeError.kindDepth, offset: i) }
        depth += 1
        defer { depth -= 1 }
        let id = doc.startContainer(kStruct)
        var end = raw.count
        var mode = flex
        if !delim {
            if n < 0 || i + n > raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
            end = i + n
        }
        while i < end {
            if delim && raw[i] == 0xEF {
                i += 1
                return id
            }
            let field = try fieldId(doc, tab, mode, cat)
            if i < raw.count && (raw[i] == 0xEE || raw[i] == 0xEC || raw[i] == 0xEF) {
                let marker = Int(raw[i])
                i += 1
                if marker == 0xEE { mode = !mode }
                if marker == 0xEF { return id }
                continue
            }
            let child = try value(doc, tab, false, cat)
            if child >= 0 { doc.addChild(id, child, field) }
        }
        return id
    }

    func annotated(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws -> Int {
        var anns: [Int] = []
        while i < raw.count {
            let op = Int(raw[i])
            if op == 0x58 {
                i += 1
                let sid = try flexUInt(raw, &i)
                let sym = try symFromSid(doc, tab, sid, i)
                anns.append(doc.nodes[sym].a)
            } else if op == 0x59 {
                i += 1
                let n = try flexUInt(raw, &i)
                let sym = doc.addSymbolText(try text(n))
                anns.append(doc.nodes[sym].a)
            } else {
                break
            }
        }
        if anns.isEmpty { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        let id = try value(doc, tab, false, cat)
        if id < 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        doc.setAnns(id, anns)
        return id
    }

    func directive(_ doc: IonDoc, _ tab: LocalTab, _ op: Int, _ cat: Catalog) throws {
        if op == 0xE1 { tab.resetSystem() }
        if op == 0xE3 { clearMacros() }
        let saved = templ
        if op == 0xE3 || op == 0xE4 { templ = true }
        var useName = ""
        var useVer = 1
        var sawUse = false
        while i < raw.count && raw[i] != 0xEF {
            let param0 = paramKind.count
            curParam0 = param0
            let v = try value(doc, tab, false, cat)
            if op == 0xE1 || op == 0xE2 {
                if v >= 0 && doc.nodes[v].kind == kString {
                    _ = tab.addText(doc.textAt(v))
                }
            }
            if (op == 0xE3 || op == 0xE4) && v >= 0 {
                try defineMacro(doc, v, param0)
            }
            if op == 0xE5 && v >= 0 {
                if !sawUse && doc.nodes[v].kind == kString {
                    useName = doc.textAt(v)
                    sawUse = true
                } else if doc.nodes[v].kind == kInt {
                    useVer = positiveInt(doc, v)
                }
            }
        }
        templ = saved
        if op == 0xE5 { try importNamed(tab, cat, useName, useVer, i) }
        if i < raw.count && raw[i] == 0xEF { i += 1 }
    }

    func takeBits(_ n: Int) throws -> Int {
        if n < 0 || i + n > raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        let start = i
        i += n
        return start
    }

    func fieldBits(_ start: Int, _ at: Int, _ width: Int) -> Int {
        var v = 0
        var k = 0
        while k < width {
            let pos = at + k
            let b = Int(raw[start + (pos / 8)])
            let bit = (b >> (pos % 8)) & 1
            v |= bit << k
            k += 1
        }
        return v
    }

    func finishTime(_ doc: IonDoc, _ when: IonTime) throws -> Int {
        if when.month < 1 || when.month > 12 {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        if when.prec >= precDay {
            if when.day < 1 || when.day > daysInMonth(when.year, when.month) {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
        }
        if when.prec >= precMin {
            if when.hour > 23 || when.minute > 59 {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
        }
        if when.prec >= precSec && when.second > 59 {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        if when.year < 1 || when.year > 999_999_999 {
            throw DecodeError(kind: DecodeError.kindRange, offset: i)
        }
        return doc.addTime(when)
    }

    func putFrac(_ doc: IonDoc, _ when: inout IonTime, _ coef: Int, _ exp: Int) {
        when.prec = precFrac
        when.fracExp = exp
        let big = bigFromU64(UInt64(coef), false)
        when.fracAt = doc.limbs.count
        when.fracLen = big.limbs.count
        doc.limbs.append(contentsOf: big.limbs)
    }

    func shortTime(_ doc: IonDoc, _ op: Int) throws -> Int {
        var n = 1
        if op != 0x80 {
            if op == 0x81 || op == 0x82 {
                n = 2
            } else if op == 0x83 {
                n = 4
            } else if op == 0x84 || op == 0x88 || op == 0x89 {
                n = 5
            } else if op == 0x85 {
                n = 6
            } else if op == 0x86 || op == 0x8A {
                n = 7
            } else if op == 0x87 || op == 0x8B {
                n = 8
            } else {
                n = 9
            }
        }
        let start = try takeBits(n)
        var when = IonTime()
        when.year = 1970 + fieldBits(start, 0, 7)
        when.prec = precYear
        when.unknown = true
        when.off = 0
        if op == 0x80 { return try finishTime(doc, when) }
        when.month = fieldBits(start, 7, 4)
        when.prec = precMonth
        if op == 0x81 { return try finishTime(doc, when) }
        when.day = fieldBits(start, 11, 5)
        when.prec = precDay
        if op == 0x82 { return try finishTime(doc, when) }
        when.hour = fieldBits(start, 16, 5)
        when.minute = fieldBits(start, 21, 6)
        when.prec = precMin
        let known = op >= 0x88
        if known {
            let q = fieldBits(start, 27, 7)
            if q == 127 {
                when.unknown = true
                when.off = 0
            } else {
                when.unknown = false
                when.off = (q - 56) * 15
            }
        } else {
            let u = fieldBits(start, 27, 1)
            if u == 0 {
                when.unknown = true
                when.off = 0
            } else {
                when.unknown = false
                when.off = 0
            }
        }
        if op == 0x83 || op == 0x88 { return try finishTime(doc, when) }
        var secAt = 28
        var fracAt = 34
        if known {
            secAt = 34
            fracAt = 40
        }
        when.second = fieldBits(start, secAt, 6)
        when.prec = precSec
        var digits = 0
        var fbits = 0
        if op == 0x85 || op == 0x8A {
            digits = 3
            fbits = 10
        } else if op == 0x86 || op == 0x8B {
            digits = 6
            fbits = 20
        } else if op == 0x87 || op == 0x8C {
            digits = 9
            fbits = 30
        }
        if digits != 0 {
            let coef = fieldBits(start, fracAt, fbits)
            putFrac(doc, &when, coef, -digits)
        }
        return try finishTime(doc, when)
    }

    func longTime(_ doc: IonDoc) throws -> Int {
        let n = try flexUInt(raw, &i)
        if n < 2 || n == 4 || n == 5 {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        let start = try takeBits(n)
        var when = IonTime()
        when.year = fieldBits(start, 0, 14)
        when.prec = precYear
        when.unknown = true
        when.off = 0
        when.month = 1
        when.day = 1
        if n == 2 { return try finishTime(doc, when) }
        when.month = fieldBits(start, 14, 4)
        when.prec = precMonth
        if n == 3 {
            let day = fieldBits(start, 18, 5)
            if day != 0 {
                when.day = day
                when.prec = precDay
            }
            return try finishTime(doc, when)
        }
        when.day = fieldBits(start, 18, 5)
        when.hour = fieldBits(start, 23, 5)
        when.minute = fieldBits(start, 28, 6)
        when.prec = precMin
        let rawOff = fieldBits(start, 34, 12)
        if rawOff == 4095 {
            when.unknown = true
            when.off = 0
        } else {
            when.unknown = false
            when.off = rawOff - 1440
        }
        if n == 6 { return try finishTime(doc, when) }
        when.second = fieldBits(start, 46, 6)
        when.prec = precSec
        if n == 7 { return try finishTime(doc, when) }
        let fracAt = start + 7
        let saved = i
        i = fracAt
        let scale = try flexUInt(raw, &i)
        if scale == 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        let coefN = (start + n) - i
        if coefN < 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        var coef = 0
        var k = 0
        while k < coefN {
            coef |= Int(raw[i + k]) << (k * 8)
            k += 1
        }
        i = saved
        if scale > 0 && coef >= 1 {
            var lim = 1
            var p = 0
            while p < scale {
                if lim > 100_000_000 { break }
                lim *= 10
                p += 1
            }
            if p == scale && coef >= lim {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
        }
        putFrac(doc, &when, coef, -scale)
        return try finishTime(doc, when)
    }

    func placeholder(_ doc: IonDoc, _ tab: LocalTab, _ op: Int, _ cat: Catalog) throws -> Int {
        if !templ { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        let rel = paramKind.count - curParam0
        var kind = 0
        var defaultId = -1
        if op == 0xEB {
            if i >= raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
            kind = Int(raw[i])
            i += 1
        }
        if op == 0xEA {
            let saved = templ
            templ = false
            while i < raw.count && (raw[i] == 0xEC || raw[i] == 0xED) {
                _ = try value(doc, tab, false, cat)
            }
            defaultId = try value(doc, tab, false, cat)
            templ = saved
            if defaultId < 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        }
        paramKind.append(kind)
        paramDefault.append(defaultId)
        var hole = IonNode(kind: kHole)
        hole.a = rel
        hole.b = defaultId
        return doc._add(hole)
    }

    func defineMacro(_ doc: IonDoc, _ id: Int, _ param0: Int) throws {
        let n = doc.nodes[id]
        if n.kind != kSexp || n.nchild != 2 {
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

    func eexp(_ doc: IonDoc, _ tab: LocalTab, _ op: Int, _ cat: Catalog) throws -> Int {
        var addr = op
        var limit = raw.count
        if op >= 0x48 && op <= 0x4F {
            let hi = try flexUInt(raw, &i)
            addr = ((hi << 3) | (op - 0x48)) + 72
        }
        if op == 0xF4 {
            addr = try flexUInt(raw, &i)
            let nbytes = try flexUInt(raw, &i)
            limit = i + nbytes
            if limit > raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        }
        if addr < 0 || addr >= macroRoot.count {
            throw DecodeError(kind: DecodeError.kindSymbol, offset: i)
        }
        let nparam = macroNParam[addr]
        let paramAt = macroParamAt[addr]
        var args: [Int] = []
        var p = 0
        while p < nparam {
            while i < limit && raw[i] == 0xEC { i += 1 }
            if i >= limit { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
            let kind = paramKind[paramAt + p]
            if kind == 0 {
                if raw[i] == 0xE0 {
                    i += 1
                    args.append(-1)
                } else {
                    let arg = try value(doc, tab, true, cat)
                    if arg < 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                    args.append(arg)
                }
            } else {
                args.append(try tagless(doc, tab, kind))
            }
            p += 1
        }
        if op == 0xF4 && i != limit {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        return try expand(doc, macroRoot[addr], args)
    }

    func tagless(_ doc: IonDoc, _ tab: LocalTab, _ code: Int) throws -> Int {
        _ = tab
        if code == 0x60 { return doc.addI64(Int64(try flexInt(raw, &i))) }
        if code == 0x61 || code == 0x62 || code == 0x64 || code == 0x68 {
            var n = 1
            if code == 0x62 { n = 2 }
            if code == 0x64 { n = 4 }
            if code == 0x68 { n = 8 }
            return doc.addI64(Int64(try fixedInt(raw, &i, n)))
        }
        if code == 0xE0 { return doc.addI64(Int64(try flexUInt(raw, &i))) }
        if code == 0xE1 || code == 0xE2 || code == 0xE4 || code == 0xE8 {
            var n = 1
            if code == 0xE2 { n = 2 }
            if code == 0xE4 { n = 4 }
            if code == 0xE8 { n = 8 }
            if i + n > raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
            var acc = 0
            var k = 0
            while k < n {
                acc |= Int(raw[i + k]) << (k * 8)
                k += 1
            }
            i += n
            return doc.addI64(Int64(acc))
        }
        if code >= 0x6B && code <= 0x6D {
            var n = 2
            if code == 0x6C { n = 4 }
            if code == 0x6D { n = 8 }
            return try readFloat(doc, n)
        }
        if code == 0x82 || code == 0x83 || code == 0x84 || code == 0x85 || code == 0x86 || code == 0x87 {
            return try shortTime(doc, code)
        }
        if code == 0xF8 || code == 0xF9 || code == 0x90 {
            let n = try flexUInt(raw, &i)
            return doc.addString(try text(n))
        }
        throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
    }

    func expand(_ doc: IonDoc, _ id: Int, _ args: [Int]) throws -> Int {
        let n = doc.nodes[id]
        if n.kind == kHole {
            var out = -1
            if n.a < args.count && args[n.a] >= 0 {
                out = args[n.a]
            } else if n.b >= 0 {
                out = try expand(doc, n.b, args)
            }
            if out < 0 { return -1 }
            if n.annN > 0 {
                let node = doc.nodes[out]
                let cloned = doc._add(node)
                var anns: [Int] = []
                var k = 0
                while k < n.annN {
                    anns.append(doc.anns[n.ann + k])
                    k += 1
                }
                doc.setAnns(cloned, anns)
                return cloned
            }
            return out
        }
        if n.kind == kList || n.kind == kSexp || n.kind == kStruct {
            let nid = doc.startContainer(n.kind)
            if n.annN > 0 {
                var anns: [Int] = []
                var k = 0
                while k < n.annN {
                    anns.append(doc.anns[n.ann + k])
                    k += 1
                }
                doc.setAnns(nid, anns)
            }
            var e = n.child
            var seen = 0
            while seen < n.nchild {
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

func positiveInt(_ doc: IonDoc, _ id: Int) -> Int {
    let n = doc.nodes[id]
    if n.kind != kInt || n.c != 0 || n.b > 1 { return 1 }
    if n.b == 0 { return 0 }
    return Int(doc.limbs[n.a])
}

func importNamed(_ tab: LocalTab, _ cat: Catalog, _ name: String, _ version: Int, _ offset: Int) throws {
    if name.isEmpty { throw DecodeError(kind: DecodeError.kindSymbol, offset: offset) }
    let idx = cat.exact(name, version)
    if idx < 0 { throw DecodeError(kind: DecodeError.kindSymbol, offset: offset) }
    let n = cat.tables[idx].texts.count
    var k = 0
    while k < n {
        if cat.tables[idx].gap[k] {
            _ = tab.addGap()
        } else {
            _ = tab.addText(cat.tables[idx].texts[k])
        }
        k += 1
    }
}
