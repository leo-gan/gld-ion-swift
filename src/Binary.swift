final class BinParser {
    let raw: [UInt8]
    var i: Int
    let n: Int
    var depth = 0
    var cacheSid0 = -1
    var cacheSym0 = -1
    var cacheSid1 = -1
    var cacheSym1 = -1
    var hotStr: [UInt8] = []
    var hotId = -1

    init(_ raw: [UInt8]) {
        self.raw = raw
        i = 0
        n = raw.count
    }

    @inline(__always)
    func hotBytesEqual(_ at: Int, _ nlen: Int) -> Bool {
        if nlen == 4 {
            return raw[at] == hotStr[0] && raw[at + 1] == hotStr[1] && raw[at + 2] == hotStr[2]
                && raw[at + 3] == hotStr[3]
        }
        if nlen == 2 { return raw[at] == hotStr[0] && raw[at + 1] == hotStr[1] }
        var k = 0
        while k < nlen {
            if raw[at + k] != hotStr[k] { return false }
            k += 1
        }
        return true
    }

    func clearSidCache() {
        cacheSid0 = -1
        cacheSid1 = -1
    }

    @inline(__always)
    func byte() throws -> Int {
        if i >= n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        let c = Int(raw[i])
        i += 1
        return c
    }

    func varUInt() throws -> Int {
        let b0 = try byte()
        if (b0 & 0x80) != 0 { return b0 & 0x7F }
        var acc = b0 & 0x7F
        var k = 1
        while k < 10 {
            let b = try byte()
            let piece = b & 0x7F
            if acc > 0x00FF_FFFF_FFFF_FFFF / 128 {
                throw DecodeError(kind: DecodeError.kindRange, offset: i)
            }
            acc = (acc << 7) | piece
            if (b & 0x80) != 0 { return acc }
            k += 1
        }
        throw DecodeError(kind: DecodeError.kindRange, offset: i)
    }

    func varInt(_ neg0: inout Bool) throws -> Int {
        neg0 = false
        var b = try byte()
        let neg = (b & 0x40) != 0
        var acc = b & 0x3F
        var guardN = 0
        while (b & 0x80) == 0 {
            guardN += 1
            if guardN > 10 { throw DecodeError(kind: DecodeError.kindRange, offset: i) }
            b = try byte()
            if acc > 0x00FF_FFFF_FFFF_FFFF / 128 {
                throw DecodeError(kind: DecodeError.kindRange, offset: i)
            }
            acc = (acc << 7) | (b & 0x7F)
        }
        if neg && acc == 0 {
            neg0 = true
            return 0
        }
        if neg { return -acc }
        return acc
    }

    func take(_ count: Int) throws -> ArraySlice<UInt8> {
        if count < 0 || i + count > n {
            throw DecodeError(kind: DecodeError.kindEOF, offset: i)
        }
        let start = i
        i += count
        return raw[start..<i]
    }

    func reprLen(_ ln: Int) throws -> Int {
        if ln == 14 { return try varUInt() }
        return ln
    }

    func readAll(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws {
        if n == 0 { return }
        var ver = try bvm()
        while i < n {
            if ver == 11 {
                ver = try read11(doc, tab, cat)
            } else {
                ver = try read10(doc, tab, cat)
            }
        }
    }

    func read10(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws -> Int {
        while i < n {
            if atBVM() {
                let next = try bvm()
                tab.resetSystem()
                clearSidCache()
                return next
            }
            let id = try value(doc, tab, 10, false)
            if id < 0 { continue }
            if isLocalTable(doc, id) {
                try applyLst(doc, id, tab, cat, i)
                clearSidCache()
                continue
            }
            doc.addTop(id)
        }
        return 10
    }

    func read11(_ doc: IonDoc, _ tab: LocalTab, _ cat: Catalog) throws -> Int {
        let r11 = Ion11(raw)
        r11.i = i
        while r11.i < n {
            i = r11.i
            if atBVM() {
                let next = try bvm()
                tab.resetSystem()
                clearSidCache()
                r11.clearMacros()
                if next != 11 { return next }
                r11.i = i
                continue
            }
            let id11 = try r11.value(doc, tab, false, cat)
            i = r11.i
            if id11 >= 0 && !isLocalTable(doc, id11) {
                doc.addTop(id11)
            }
        }
        i = r11.i
        return 11
    }

    func atBVM() -> Bool {
        if i + 3 >= n { return false }
        return raw[i] == 0xE0 && raw[i + 1] == 0x01 && raw[i + 3] == 0xEA
    }

    func bvm() throws -> Int {
        if i + 3 >= n { throw DecodeError(kind: DecodeError.kindVersion, offset: i) }
        if raw[i] != 0xE0 || raw[i + 3] != 0xEA || raw[i + 1] != 0x01 {
            throw DecodeError(kind: DecodeError.kindVersion, offset: i)
        }
        let minor = Int(raw[i + 2])
        i += 4
        if minor == 0 { return 10 }
        if minor == 1 { return 11 }
        throw DecodeError(kind: DecodeError.kindVersion, offset: i)
    }

    func value(_ doc: IonDoc, _ tab: LocalTab, _ ver: Int, _ inAnn: Bool) throws -> Int {
        if depth > maxDepth { throw DecodeError(kind: DecodeError.kindDepth, offset: i) }
        if i < n {
            let td0 = Int(raw[i])
            let t0 = td0 >> 4
            let ln0 = td0 & 15
            if t0 == 2 && ln0 == 0 {
                i += 1
                return doc.addI64(0)
            }
            if t0 == 2 && ln0 == 1 && i + 1 < n {
                let one = Int(raw[i + 1])
                i += 2
                return doc.addI64(Int64(one))
            }
            if t0 == 8 && ln0 < 14 {
                i += 1
                return try doc.addStringRaw(try take(ln0), i)
            }
            if t0 >= 11 && t0 <= 13 {
                i += 1
                return try container(doc, tab, ver, t0, ln0)
            }
        }
        let td = try byte()
        let t = td >> 4
        let ln = td & 0x0F
        if t == 0 {
            if ln == 15 { return doc.addNull(0) }
            var skip = ln
            if ln == 14 { skip = try varUInt() }
            _ = try take(skip)
            return -1
        }
        if t == 15 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        if t == 14 { return try ann(doc, tab, ver, ln, inAnn) }
        if t == 1 {
            if ln == 0 { return doc.addBool(false) }
            if ln == 1 { return doc.addBool(true) }
            if ln == 15 { return doc.addNull(kBool) }
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        if t == 2 || t == 3 {
            if ln == 15 { return doc.addNull(kInt) }
            if t == 3 && ln == 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            let size = try reprLen(ln)
            if size == 0 { return doc.addI64(0) }
            if size == 1 {
                if i >= n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
                let one = Int(raw[i])
                i += 1
                if t == 3 && one == 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                if t == 3 { return doc.addI64(-Int64(one)) }
                return doc.addI64(Int64(one))
            }
            if size <= 8 {
                if i + size > n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
                var mag = UInt64(0)
                var k = 0
                while k < size {
                    mag = (mag << 8) | UInt64(raw[i + k])
                    k += 1
                }
                i += size
                if t == 3 && mag == 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                if mag <= 0x7FFF_FFFF_FFFF_FFFF {
                    if t == 3 { return doc.addI64(-Int64(mag)) }
                    return doc.addI64(Int64(mag))
                }
                if t == 3 && mag == (UInt64(1) << 63) {
                    return doc.addI64(Int64.min)
                }
                return doc.addInt(bigFromU64(mag, t == 3))
            }
            var mag = try bigFromBE(Array(try take(size)), false, i)
            if t == 3 {
                if mag.isZero { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                mag.neg = true
            }
            return doc.addInt(mag)
        }
        if t == 4 {
            if ln == 15 { return doc.addNull(kFloat) }
            if ln == 0 { return doc.addFloat(0, 0) }
            if ln != 4 && ln != 8 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            return try readFloat(doc, ln)
        }
        if t == 5 {
            if ln == 15 { return doc.addNull(kDecimal) }
            if ln == 0 { return doc.addDecimal(BigInt(), false, 0) }
            let size = try reprLen(ln)
            return try readDecimal(doc, i + size)
        }
        if t == 6 {
            if ln == 15 { return doc.addNull(kTimestamp) }
            if ln < 2 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            let size = try reprLen(ln)
            return try readTime(doc, i + size)
        }
        if t == 7 {
            if ln == 15 { return doc.addNull(kSymbol) }
            if ln == 0 { return try symFromSid(doc, tab, 0, i) }
            let size = try reprLen(ln)
            let sid = try readUInt(size)
            return try symFromSid(doc, tab, sid, i)
        }
        if t == 8 || t == 9 || t == 10 {
            var kind = kString
            var nullK = kString
            if t == 9 {
                kind = kClob
                nullK = kClob
            }
            if t == 10 {
                kind = kBlob
                nullK = kBlob
            }
            if ln == 15 { return doc.addNull(nullK) }
            let size = try reprLen(ln)
            let span = try take(size)
            if t == 8 { return try doc.addStringRaw(span, i) }
            return doc.addBytes(kind, Array(span))
        }
        if t == 11 || t == 12 || t == 13 {
            return try container(doc, tab, ver, t, ln)
        }
        throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
    }

    func readFloat(_ doc: IonDoc, _ count: Int) throws -> Int {
        let span = try take(count)
        var bits = UInt64(0)
        for b in span {
            bits = (bits << 8) | UInt64(b)
        }
        return doc.addFloat(count, bits)
    }

    func readUInt(_ count: Int) throws -> Int {
        let span = try take(count)
        var acc = 0
        for b in span {
            if acc > 0x00FF_FFFF_FFFF_FFFF / 256 {
                throw DecodeError(kind: DecodeError.kindRange, offset: i)
            }
            acc = (acc << 8) | Int(b)
        }
        return acc
    }

    func readDecimal(_ doc: IonDoc, _ end: Int) throws -> Int {
        var neg0 = false
        let exp = try varInt(&neg0)
        if i > end { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        let left = end - i
        var negz = false
        var coef = try signedMag(left, &negz)
        if i != end { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        let neg = coef.neg || negz
        coef.neg = false
        return doc.addDecimal(coef, neg, exp)
    }

    func signedMag(_ count: Int, _ neg0: inout Bool) throws -> BigInt {
        neg0 = false
        if count == 0 { return BigInt() }
        let span = Array(try take(count))
        let first = Int(span[0])
        let neg = (first & 0x80) != 0
        var buf: [UInt8] = [UInt8(first & 0x7F)]
        if span.count > 1 { buf.append(contentsOf: span[1...]) }
        var mag = try bigFromBE(buf, false, i)
        if neg && mag.isZero {
            neg0 = true
            return mag
        }
        if neg { mag.neg = true }
        return mag
    }

    func readTime(_ doc: IonDoc, _ end: Int) throws -> Int {
        var neg0 = false
        let off = try varInt(&neg0)
        if i >= end { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        let year = try varUInt()
        if year < 1 || year > 999_999_999 {
            throw DecodeError(kind: DecodeError.kindRange, offset: i)
        }
        var when = IonTime()
        when.year = year
        when.prec = precYear
        when.unknown = neg0
        when.off = off
        if i < end {
            when.month = try varUInt()
            when.prec = precMonth
            if when.month < 1 || when.month > 12 {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
        }
        if i < end {
            when.day = try varUInt()
            when.prec = precDay
            if when.month < 1 || when.day < 1 || when.day > daysInMonth(when.year, when.month) {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
        }
        if i < end {
            when.hour = try varUInt()
            if i >= end { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            when.minute = try varUInt()
            when.prec = precMin
            if when.hour > 23 || when.minute > 59 {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
        }
        if i < end {
            when.second = try varUInt()
            when.prec = precSec
            if when.second > 59 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        }
        if i < end {
            var fneg = false
            let fexp = try varInt(&fneg)
            var coef = BigInt()
            if i < end {
                var nz = false
                coef = try signedMag(end - i, &nz)
                if coef.neg && !nz { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
                if nz { coef = BigInt() }
            } else if i != end {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
            let drop = coef.isZero && fexp >= 0
            if !drop && fracGEOne(coef, fexp) {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
            if !drop {
                if fexp >= 0 && !coef.isZero {
                    throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
                }
                when.prec = precFrac
                when.fracExp = fexp
                when.fracAt = doc.limbs.count
                when.fracLen = coef.limbs.count
                doc.limbs.append(contentsOf: coef.limbs)
            }
        }
        if i != end { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        if when.prec < precMin {
            when.unknown = true
            when.off = 0
        } else if !when.unknown {
            try applyOffset(&when, when.off)
        }
        return doc.addTime(when)
    }

    func container(_ doc: IonDoc, _ tab: LocalTab, _ ver: Int, _ t: Int, _ ln: Int) throws -> Int {
        var kind = kList
        var nullK = kList
        if t == 12 {
            kind = kSexp
            nullK = kSexp
        }
        if t == 13 {
            kind = kStruct
            nullK = kStruct
        }
        if ln == 15 { return doc.addNull(nullK) }
        if ln == 0 { return doc.startContainer(kind) }
        var size = ln
        if ln == 14 || (t == 13 && ln == 1) {
            size = try varUInt()
            if t == 13 && ln == 1 && size == 0 {
                throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
            }
        }
        let end = i + size
        if size < 0 || end > n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        depth += 1
        let id = doc.startContainer(kind)
        while i < end {
            if t == 13 {
                let b = Int(raw[i])
                var sid = b & 0x7F
                if (b & 0x80) != 0 {
                    i += 1
                } else {
                    sid = try varUInt()
                }
                var slot = cacheSym0
                if sid != cacheSid0 {
                    if sid == cacheSid1 {
                        slot = cacheSym1
                    } else {
                        let sym = try symFromSid(doc, tab, sid, i)
                        slot = doc.nodes[sym].a
                        cacheSid1 = cacheSid0
                        cacheSym1 = cacheSym0
                        cacheSid0 = sid
                        cacheSym0 = slot
                    }
                }
                if i < n {
                    let td0 = Int(raw[i])
                    let t0 = td0 >> 4
                    let ln0 = td0 & 15
                    if t0 == 1 && (ln0 == 0 || ln0 == 1) {
                        i += 1
                        doc.addChild(id, doc.addBool(ln0 == 1), slot)
                        continue
                    }
                    if t0 == 2 && ln0 == 0 {
                        i += 1
                        doc.addChild(id, doc.addI64(0), slot)
                        continue
                    }
                    if t0 == 2 && ln0 == 1 && i + 1 < n {
                        let one = Int(raw[i + 1])
                        i += 2
                        doc.addChild(id, doc.addI64(Int64(one)), slot)
                        continue
                    }
                    if t0 == 3 && ln0 == 1 && i + 1 < n && raw[i + 1] != 0 {
                        let one = Int(raw[i + 1])
                        i += 2
                        doc.addChild(id, doc.addI64(-Int64(one)), slot)
                        continue
                    }
                    if t0 == 8 && ln0 < 14 {
                        if i + 1 + ln0 > n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
                        i += 1
                        if ln0 == hotStr.count && ln0 > 0 && hotBytesEqual(i, ln0) {
                            i += ln0
                            doc.addChild(id, doc.addStringAt(hotId), slot)
                            continue
                        }
                        let start = i
                        let str = try doc.addStringRaw(try take(ln0), i)
                        if ln0 > 0 && ln0 <= 8 {
                            hotStr = Array(raw[start..<i])
                            hotId = doc.nodes[str].a
                        }
                        doc.addChild(id, str, slot)
                        continue
                    }
                }
                let child = try value(doc, tab, ver, false)
                if child < 0 { continue }
                doc.addChild(id, child, slot)
            } else {
                let child = try value(doc, tab, ver, false)
                if child < 0 { continue }
                doc.addChild(id, child, -1)
            }
        }
        depth -= 1
        if i != end { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        return id
    }

    func ann(_ doc: IonDoc, _ tab: LocalTab, _ ver: Int, _ ln: Int, _ inAnn: Bool) throws -> Int {
        if inAnn || ln < 3 || ln == 15 {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        let size = try reprLen(ln)
        let end = i + size
        if size < 0 || end > n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        let alen = try varUInt()
        let annotEnd = i + alen
        if annotEnd > end || alen <= 0 {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        var anns: [Int] = []
        while i < annotEnd {
            let sid = try varUInt()
            let sym = try symFromSid(doc, tab, sid, i)
            anns.append(doc.nodes[sym].a)
        }
        if i != annotEnd || anns.isEmpty {
            throw DecodeError(kind: DecodeError.kindSyntax, offset: i)
        }
        let id = try value(doc, tab, ver, true)
        if id < 0 || i != end { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        doc.setAnns(id, anns)
        return id
    }
}

func fracGEOne(_ coef: BigInt, _ exp: Int) -> Bool {
    if coef.isZero { return false }
    if exp >= 0 { return true }
    var limit = BigInt()
    limit.addSmall(1)
    let n = -exp
    var k = 0
    while k < n {
        limit.mulSmall(10)
        k += 1
    }
    return coef.cmpMag(limit) >= 0
}

public func decodeBinary(_ raw: [UInt8], _ cat: Catalog) throws -> IonDoc {
    let doc = IonDoc()
    doc.reserve(raw.count)
    let tab = LocalTab()
    let parser = BinParser(raw)
    try parser.readAll(doc, tab, cat)
    return doc
}
