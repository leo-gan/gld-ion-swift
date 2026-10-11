func appendText(_ buf: inout [UInt8], _ text: String) {
    buf.append(contentsOf: text.utf8)
}

func identOK(_ text: String) -> Bool {
    var n = 0
    var c0 = 0
    var b1 = 0
    var b2 = 0
    var b3 = 0
    var b4 = 0
    for b in text.utf8 {
        let c = Int(b)
        if n == 0 {
            c0 = c
            if c >= 48 && c <= 57 { return false }
            if !((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36) { return false }
        } else {
            let ok = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36
            if !ok { return false }
            if n == 1 { b1 = c }
            else if n == 2 { b2 = c }
            else if n == 3 { b3 = c }
            else if n == 4 { b4 = c }
        }
        n += 1
    }
    if n == 0 { return false }
    if n == 4 && c0 == 110 { return !(b1 == 117 && b2 == 108 && b3 == 108) }
    if n == 4 && c0 == 116 { return !(b1 == 114 && b2 == 117 && b3 == 101) }
    if n == 3 && c0 == 110 { return !(b1 == 97 && b2 == 110) }
    if n == 5 && c0 == 102 { return !(b1 == 97 && b2 == 108 && b3 == 115 && b4 == 101) }
    return true
}

func putDec(_ buf: inout [UInt8], _ neg: Bool, _ mag: Int) {
    if neg { buf.append(45) }
    if mag < 10 {
        buf.append(UInt8(48 + mag))
        return
    }
    if mag < 100 {
        buf.append(UInt8(48 + mag / 10))
        buf.append(UInt8(48 + mag % 10))
        return
    }
    if mag < 1000 {
        buf.append(UInt8(48 + mag / 100))
        let r = mag % 100
        buf.append(UInt8(48 + r / 10))
        buf.append(UInt8(48 + r % 10))
        return
    }
    var tmp: [UInt8] = []
    var v = mag
    while v > 0 {
        tmp.append(UInt8(48 + (v % 10)))
        v /= 10
    }
    var i = tmp.count - 1
    while i >= 0 {
        buf.append(tmp[i])
        i -= 1
    }
}

func pad(_ buf: inout [UInt8], _ n: Int, _ width: Int) {
    let s = utf8Bytes(String(n))
    var i = s.count
    while i < width {
        buf.append(48)
        i += 1
    }
    buf.append(contentsOf: s)
}

func limbsOf(_ doc: IonDoc, _ at: Int, _ n: Int) -> BigInt {
    if n == 0 { return BigInt() }
    return BigInt(neg: false, limbs: Array(doc.limbs[at..<(at + n)]))
}

@inline(__always)
func varUIntW(_ buf: inout [UInt8], _ value: Int) {
    var v = value
    if v < 0 { v = 0 }
    if v < 128 {
        buf.append(UInt8(0x80 | v))
        return
    }
    var parts: [Int] = []
    var x = v
    while x > 0 {
        parts.append(x & 0x7F)
        x >>= 7
    }
    var i = parts.count - 1
    while i >= 0 {
        var b = parts[i]
        if i == 0 { b |= 0x80 }
        buf.append(UInt8(b))
        i -= 1
    }
}

func varIntW(_ buf: inout [UInt8], _ v: Int, _ neg0: Bool) {
    let neg = v < 0 || neg0
    var mag = v
    if mag < 0 { mag = -mag }
    if mag < 64 {
        var b = 0x80 | mag
        if neg { b |= 0x40 }
        buf.append(UInt8(b))
        return
    }
    var lows: [Int] = []
    while mag >= 64 {
        lows.append(mag & 0x7F)
        mag >>= 7
    }
    var first = mag
    if neg { first |= 0x40 }
    buf.append(UInt8(first))
    var i = lows.count - 1
    while i >= 0 {
        var b = lows[i]
        if i == 0 { b |= 0x80 }
        buf.append(UInt8(b))
        i -= 1
    }
}

func td(_ buf: inout [UInt8], _ t: Int, _ body: [UInt8]) {
    if body.count < 14 {
        buf.append(UInt8((t << 4) | body.count))
    } else {
        buf.append(UInt8((t << 4) | 14))
        varUIntW(&buf, body.count)
    }
    buf.append(contentsOf: body)
}

final class SymMap {
    var texts: [String] = []
    var sids: [Int] = []
    var index: [String: Int] = [:]
    var byRef: [Int: Int] = [:]
    var hotText = -1
    var hotBytes: [UInt8] = []

    func sid(_ text: String) -> Int {
        let sys = sysSid(text)
        if sys != 0 { return sys }
        if let id = index[text] { return id }
        let id = 10 + texts.count
        texts.append(text)
        sids.append(id)
        index[text] = id
        return id
    }

    @inline(__always)
    func sidRef(_ doc: IonDoc, _ sym: Int) -> Int {
        if sym < 0 { return 0 }
        if let hit = byRef[sym] { return hit }
        let s = doc.syms[sym]
        let id = s.text < 0 ? 0 : sid(doc.texts[s.text])
        byRef[sym] = id
        return id
    }
}

func quoteSym(_ buf: inout [UInt8], _ text: String) {
    buf.append(39)
    for c in text.utf8 {
        let v = Int(c)
        if v == 39 || v == 92 {
            buf.append(92)
            buf.append(c)
        } else if v < 32 {
            hexByte(&buf, v)
        } else {
            buf.append(c)
        }
    }
    buf.append(39)
}

func hexByte(_ buf: inout [UInt8], _ c: Int) {
    buf.append(92)
    buf.append(120)
    let hi = (c >> 4) & 15
    let lo = c & 15
    buf.append(hi < 10 ? UInt8(48 + hi) : UInt8(87 + hi))
    buf.append(lo < 10 ? UInt8(48 + lo) : UInt8(87 + lo))
}

func symTextW(_ buf: inout [UInt8], _ text: String) {
    if identOK(text) {
        appendText(&buf, text)
    } else {
        quoteSym(&buf, text)
    }
}

final class TextCache {
    var aI = -1
    var aBytes: [UInt8] = []
    var bI = -1
    var bBytes: [UInt8] = []
    var strI = -1
    var encoded: [UInt8] = []
}

func symPlain(_ buf: inout [UInt8], _ textI: Int, _ texts: [String], _ cache: TextCache) {
    if textI == cache.aI {
        buf.append(contentsOf: cache.aBytes)
        return
    }
    if textI == cache.bI {
        buf.append(contentsOf: cache.bBytes)
        return
    }
    let text = texts[textI]
    if identOK(text) {
        cache.bI = cache.aI
        cache.bBytes = cache.aBytes
        cache.aI = textI
        cache.aBytes = Array(text.utf8)
        buf.append(contentsOf: cache.aBytes)
    } else {
        quoteSym(&buf, text)
    }
}

func strW(_ buf: inout [UInt8], _ text: String) {
    var plain = true
    for c in text.utf8 where c < 32 || c == 34 || c == 92 {
        plain = false
        break
    }
    if plain {
        buf.append(34)
        appendText(&buf, text)
        buf.append(34)
        return
    }
    buf.append(34)
    for c in text.utf8 {
        let v = Int(c)
        if v == 34 || v == 92 {
            buf.append(92)
            buf.append(c)
        } else if v == 10 {
            buf.append(92)
            buf.append(110)
        } else if v < 32 {
            hexByte(&buf, v)
        } else {
            buf.append(c)
        }
    }
    buf.append(34)
}

func nl(_ buf: inout [UInt8], _ options: EncodeOptions, _ depth: Int) {
    if !options.pretty { return }
    buf.append(10)
    var i = 0
    while i < depth {
        buf.append(32)
        buf.append(32)
        i += 1
    }
}

func writeTextValue(_ doc: IonDoc, _ id: Int, _ buf: inout [UInt8], _ options: EncodeOptions, _ depth: Int, _ cache: TextCache) throws {
    let n = doc.nodes[id]
    var a = 0
    while a < n.annN {
        let s = doc.syms[doc.anns[n.ann + a]]
        if s.text < 0 {
            buf.append(36)
            buf.append(48)
        } else {
            symPlain(&buf, s.text, doc.texts, cache)
        }
        buf.append(58)
        buf.append(58)
        a += 1
    }
    switch n.kind {
    case kNull:
        buf.append(contentsOf: Array("null".utf8))
        if n.a != 0 {
            buf.append(46)
            let name: String
            switch n.a {
            case kBool: name = "bool"
            case kInt: name = "int"
            case kFloat: name = "float"
            case kDecimal: name = "decimal"
            case kTimestamp: name = "timestamp"
            case kString: name = "string"
            case kSymbol: name = "symbol"
            case kBlob: name = "blob"
            case kClob: name = "clob"
            case kList: name = "list"
            case kSexp: name = "sexp"
            case kStruct: name = "struct"
            default: name = "null"
            }
            appendText(&buf, name)
        }
    case kBool:
        appendText(&buf, n.a != 0 ? "true" : "false")
    case kInt:
        if n.b <= 1 {
            let mag = n.b == 1 ? Int(doc.limbs[n.a]) : 0
            putDec(&buf, n.c != 0 && mag != 0, mag)
        } else {
            var mag = limbsOf(doc, n.a, n.b)
            if n.c != 0 { mag.neg = true }
            buf.append(contentsOf: mag.toDecBytes())
        }
    case kFloat:
        floatText(doc, id, &buf)
    case kDecimal:
        decText(doc, id, &buf)
    case kTimestamp:
        try timeText(doc, id, &buf)
    case kString:
        if n.a == cache.strI {
            buf.append(contentsOf: cache.encoded)
        } else {
            let mark = buf.count
            strW(&buf, doc.texts[n.a])
            cache.strI = n.a
            cache.encoded = Array(buf[mark...])
        }
    case kSymbol:
        let s = doc.syms[n.a]
        if s.text < 0 {
            buf.append(36)
            buf.append(48)
        } else {
            symPlain(&buf, s.text, doc.texts, cache)
        }
    case kBlob, kClob:
        lobText(doc, id, &buf)
    case kList, kSexp:
        let open: UInt8 = n.kind == kSexp ? 40 : 91
        let close: UInt8 = n.kind == kSexp ? 41 : 93
        buf.append(open)
        var edge = n.child
        var i = 0
        while i < n.nchild {
            if i > 0 {
                if n.kind == kList { buf.append(44) }
                else if !options.pretty { buf.append(32) }
            }
            if options.pretty { nl(&buf, options, depth + 1) }
            try writeTextValue(doc, doc.edges[edge].child, &buf, options, depth + 1, cache)
            edge = doc.edges[edge].next
            i += 1
        }
        if n.nchild > 0 && options.pretty { nl(&buf, options, depth) }
        buf.append(close)
    case kStruct:
        buf.append(123)
        var edge = n.child
        var i = 0
        while i < n.nchild {
            if i > 0 { buf.append(44) }
            if options.pretty { nl(&buf, options, depth + 1) }
            let f = doc.syms[doc.edges[edge].field]
            if f.text < 0 {
                buf.append(36)
                buf.append(48)
            } else {
                symPlain(&buf, f.text, doc.texts, cache)
            }
            buf.append(58)
            try writeTextValue(doc, doc.edges[edge].child, &buf, options, depth + 1, cache)
            edge = doc.edges[edge].next
            i += 1
        }
        if n.nchild > 0 && options.pretty { nl(&buf, options, depth) }
        buf.append(125)
    default:
        throw DecodeError(kind: DecodeError.kindType, offset: 0)
    }
}

func floatText(_ doc: IonDoc, _ id: Int, _ buf: inout [UInt8]) {
    let n = doc.nodes[id]
    let bits = doc.floats[n.b]
    if n.a == 0 {
        buf.append(contentsOf: Array("0e0".utf8))
        return
    }
    var f = Double(bitPattern: bits)
    if n.a == 4 { f = Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits))) }
    else if n.a == 2 { f = f16ToF64(UInt16(truncatingIfNeeded: bits)) }
    if f.isNaN {
        buf.append(contentsOf: Array("nan".utf8))
        return
    }
    var sign = (bits & (UInt64(1) << 63)) != 0
    if n.a == 4 { sign = (UInt32(truncatingIfNeeded: bits) & 0x8000_0000) != 0 }
    if n.a == 2 { sign = (UInt16(truncatingIfNeeded: bits) & 0x8000) != 0 }
    if f == 0 && sign {
        buf.append(contentsOf: Array("-0e0".utf8))
        return
    }
    if f.isInfinite {
        buf.append(contentsOf: Array((sign ? "-inf" : "+inf").utf8))
        return
    }
    let raw = String(f)
    var expAll = false
    for b in raw.utf8 where b == 101 || b == 69 { expAll = true }
    buf.append(contentsOf: Array(raw.utf8))
    if !expAll { buf.append(contentsOf: Array("e0".utf8)) }
}

func decText(_ doc: IonDoc, _ id: Int, _ buf: inout [UInt8]) {
    let n = doc.nodes[id]
    let mag = limbsOf(doc, n.a, n.b)
    let digits = mag.toDecBytes()
    if n.c != 0 { buf.append(45) }
    if n.d >= 0 {
        buf.append(contentsOf: digits)
        buf.append(100)
        buf.append(contentsOf: utf8Bytes(String(n.d)))
        return
    }
    let frac = -n.d
    if digits.count == 1 && digits[0] == 48 {
        buf.append(48)
        buf.append(46)
        buf.append(contentsOf: [UInt8](repeating: 48, count: frac))
        return
    }
    if frac >= digits.count {
        buf.append(48)
        buf.append(46)
        let z = frac - digits.count
        if z > 0 { buf.append(contentsOf: [UInt8](repeating: 48, count: z)) }
        buf.append(contentsOf: digits)
        return
    }
    let cut = digits.count - frac
    buf.append(contentsOf: digits[0..<cut])
    buf.append(46)
    buf.append(contentsOf: digits[cut...])
}

func timeText(_ doc: IonDoc, _ id: Int, _ buf: inout [UInt8]) throws {
    let t = doc.times[doc.nodes[id].a]
    pad(&buf, t.year, 4)
    if t.prec == precYear {
        buf.append(84)
        return
    }
    buf.append(45)
    pad(&buf, t.month, 2)
    if t.prec == precMonth {
        buf.append(84)
        return
    }
    buf.append(45)
    pad(&buf, t.day, 2)
    if t.prec == precDay { return }
    buf.append(84)
    pad(&buf, t.hour, 2)
    buf.append(58)
    pad(&buf, t.minute, 2)
    if t.prec >= precSec {
        buf.append(58)
        pad(&buf, t.second, 2)
    }
    if t.prec == precFrac {
        buf.append(46)
        let mag = limbsOf(doc, t.fracAt, t.fracLen)
        let digits = mag.toDecBytes()
        let need = -t.fracExp
        if digits.count < need {
            buf.append(contentsOf: [UInt8](repeating: 48, count: need - digits.count))
        }
        buf.append(contentsOf: digits)
    }
    if t.unknown {
        buf.append(contentsOf: Array("-00:00".utf8))
        return
    }
    if t.off == 0 {
        buf.append(90)
        return
    }
    var off = t.off
    if off < 0 {
        buf.append(45)
        off = -off
    } else {
        buf.append(43)
    }
    pad(&buf, off / 60, 2)
    buf.append(58)
    pad(&buf, off % 60, 2)
}

let b64Alpha = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

func lobText(_ doc: IonDoc, _ id: Int, _ buf: inout [UInt8]) {
    let n = doc.nodes[id]
    buf.append(123)
    buf.append(123)
    let bytes = doc.blobs[n.a]
    if n.kind == kClob {
        buf.append(34)
        for c in bytes {
            let v = Int(c)
            if v == 34 || v == 92 {
                buf.append(92)
                buf.append(c)
            } else if v >= 32 && v < 127 {
                buf.append(c)
            } else {
                hexByte(&buf, v)
            }
        }
        buf.append(34)
    } else {
        var i = 0
        while i < bytes.count {
            let b0 = Int(bytes[i])
            var b1 = 0
            var b2 = 0
            var have = 1
            if i + 1 < bytes.count {
                b1 = Int(bytes[i + 1])
                have = 2
            }
            if i + 2 < bytes.count {
                b2 = Int(bytes[i + 2])
                have = 3
            }
            let v = (b0 << 16) | (b1 << 8) | b2
            buf.append(b64Alpha[(v >> 18) & 63])
            buf.append(b64Alpha[(v >> 12) & 63])
            buf.append(have > 1 ? b64Alpha[(v >> 6) & 63] : 61)
            buf.append(have > 2 ? b64Alpha[v & 63] : 61)
            i += 3
        }
    }
    buf.append(125)
    buf.append(125)
}

func appendIVM(_ buf: inout [UInt8], _ version: Int) {
    buf.append(36)
    buf.append(105)
    buf.append(111)
    buf.append(110)
    buf.append(95)
    buf.append(49)
    buf.append(95)
    buf.append(version == 11 ? 49 : 48)
}

public func encodeText(_ doc: IonDoc, _ options: EncodeOptions) throws -> String {
    var buf: [UInt8] = []
    buf.reserveCapacity(64 + doc.top.count * 48)
    appendIVM(&buf, options.version)
    let cache = TextCache()
    for id in doc.top {
        buf.append(10)
        try writeTextValue(doc, id, &buf, options, 0, cache)
    }
    buf.append(10)
    return String(decoding: buf, as: UTF8.self)
}

public func formatValue(_ doc: IonDoc, _ id: Int) throws -> String {
    var buf: [UInt8] = []
    try writeTextValue(doc, id, &buf, EncodeOptions(), 0, TextCache())
    return String(decoding: buf, as: UTF8.self)
}

@inline(__always)
func putU32Int(_ neg: Bool, _ mag: Int, _ buf: inout [UInt8]) {
    var t = 2
    if neg && mag != 0 { t = 3 }
    if mag == 0 {
        buf.append(UInt8(t << 4))
        return
    }
    if mag < 256 {
        buf.append(UInt8((t << 4) | 1))
        buf.append(UInt8(mag))
        return
    }
    if mag < 65536 {
        buf.append(UInt8((t << 4) | 2))
        buf.append(UInt8((mag >> 8) & 255))
        buf.append(UInt8(mag & 255))
        return
    }
    if mag < 16_777_216 {
        buf.append(UInt8((t << 4) | 3))
        buf.append(UInt8((mag >> 16) & 255))
        buf.append(UInt8((mag >> 8) & 255))
        buf.append(UInt8(mag & 255))
        return
    }
    buf.append(UInt8((t << 4) | 4))
    buf.append(UInt8((mag >> 24) & 255))
    buf.append(UInt8((mag >> 16) & 255))
    buf.append(UInt8((mag >> 8) & 255))
    buf.append(UInt8(mag & 255))
}

func seal(_ buf: inout [UInt8], _ mark: Int, _ tcode: Int) {
    let ln = buf.count - (mark + 1)
    if ln < 14 {
        buf[mark] = UInt8((tcode << 4) | ln)
        return
    }
    let tail = Array(buf[(mark + 1)...])
    buf.removeSubrange(mark...)
    buf.append(UInt8((tcode << 4) | 14))
    varUIntW(&buf, ln)
    buf.append(contentsOf: tail)
}

@inline(__always)
func binValue(_ doc: IonDoc, _ id: Int, _ sm: SymMap, _ buf: inout [UInt8]) throws {
    let n = doc.nodes[id]
    if n.annN == 0 {
        try emitCore(doc, id, sm, &buf)
        return
    }
    var bare: [UInt8] = []
    try emitCore(doc, id, sm, &bare)
    var ann: [UInt8] = []
    var a = 0
    while a < n.annN {
        varUIntW(&ann, sm.sidRef(doc, doc.anns[n.ann + a]))
        a += 1
    }
    var wrapped: [UInt8] = []
    varUIntW(&wrapped, ann.count)
    wrapped.append(contentsOf: ann)
    wrapped.append(contentsOf: bare)
    td(&buf, 14, wrapped)
}

func emitCore(_ doc: IonDoc, _ id: Int, _ sm: SymMap, _ buf: inout [UInt8]) throws {
    let n = doc.nodes[id]
    switch n.kind {
    case kNull where n.a == 0:
        buf.append(0x0F)
    case kNull:
        var code = 0
        switch n.a {
        case kBool: code = 0x1F
        case kInt: code = 0x2F
        case kFloat: code = 0x4F
        case kDecimal: code = 0x5F
        case kTimestamp: code = 0x6F
        case kSymbol: code = 0x7F
        case kString: code = 0x8F
        case kClob: code = 0x9F
        case kBlob: code = 0xAF
        case kList: code = 0xBF
        case kSexp: code = 0xCF
        case kStruct: code = 0xDF
        default: code = 0
        }
        buf.append(UInt8(code))
    case kBool:
        buf.append(n.a == 0 ? 0x10 : 0x11)
    case kInt:
        if n.b <= 1 {
            putU32Int(n.c != 0, n.b == 0 ? 0 : Int(doc.limbs[n.a]), &buf)
        } else {
            let mag = limbsOf(doc, n.a, n.b)
            td(&buf, n.c != 0 ? 3 : 2, mag.toBEBytes())
        }
    case kFloat:
        if n.a == 0 {
            buf.append(0x40)
        } else {
            let bits = doc.floats[n.b]
            var tmp: [UInt8] = []
            var s = n.a - 1
            while s >= 0 {
                tmp.append(UInt8((bits >> UInt64(s * 8)) & 255))
                s -= 1
            }
            td(&buf, 4, tmp)
        }
    case kDecimal:
        var tmp: [UInt8] = []
        varIntW(&tmp, n.d, false)
        if n.c != 0 || n.b > 0 {
            var be = limbsOf(doc, n.a, n.b).toBEBytes()
            if n.c != 0 {
                if be.isEmpty { be.append(0x80) }
                else { be[0] |= 0x80 }
            }
            tmp.append(contentsOf: be)
        }
        td(&buf, 5, tmp)
    case kString:
        let bytes: [UInt8]
        if n.a == sm.hotText {
            bytes = sm.hotBytes
        } else {
            bytes = Array(doc.texts[n.a].utf8)
            sm.hotText = n.a
            sm.hotBytes = bytes
        }
        let ln = bytes.count
        if ln < 14 {
            buf.append(UInt8((8 << 4) | ln))
        } else {
            buf.append(UInt8((8 << 4) | 14))
            varUIntW(&buf, ln)
        }
        buf.append(contentsOf: bytes)
    case kBlob, kClob:
        td(&buf, n.kind == kClob ? 9 : 10, doc.blobs[n.a])
    case kSymbol:
        let sid = sm.sidRef(doc, n.a)
        if sid == 0 {
            buf.append(0x70)
        } else {
            var tmp: [UInt8] = []
            var x = sid
            while x > 0 {
                tmp.append(UInt8(x & 255))
                x >>= 8
            }
            td(&buf, 7, Array(tmp.reversed()))
        }
    case kTimestamp:
        try binTime(doc, id, &buf)
    case kList, kSexp, kStruct:
        var tcode = 11
        if n.kind == kSexp { tcode = 12 }
        if n.kind == kStruct { tcode = 13 }
        let mark = buf.count
        buf.append(0)
        var edge = n.child
        var i = 0
        while i < n.nchild {
            if n.kind == kStruct {
                varUIntW(&buf, sm.sidRef(doc, doc.edges[edge].field))
            }
            try binValue(doc, doc.edges[edge].child, sm, &buf)
            edge = doc.edges[edge].next
            i += 1
        }
        seal(&buf, mark, tcode)
    default:
        throw DecodeError(kind: DecodeError.kindType, offset: 0)
    }
}

func binTime(_ doc: IonDoc, _ id: Int, _ buf: inout [UInt8]) throws {
    let t = doc.times[doc.nodes[id].a]
    var tmp: [UInt8] = []
    if t.prec < precMin || t.unknown {
        varIntW(&tmp, 0, true)
    } else {
        varIntW(&tmp, t.off, false)
    }
    var year = t.year
    var month = t.month
    var day = t.day
    var hour = t.hour
    var minute = t.minute
    if t.prec >= precMin && !t.unknown && t.off != 0 {
        var total = hour * 60 + minute - t.off
        var days = 0
        while total < 0 {
            total += 1440
            days -= 1
        }
        while total >= 1440 {
            total -= 1440
            days += 1
        }
        hour = total / 60
        minute = total % 60
        if days != 0 {
            var when = t
            when.hour = hour
            when.minute = minute
            try shiftDays(&when, days)
            year = when.year
            month = when.month
            day = when.day
        }
    }
    varUIntW(&tmp, year)
    if t.prec >= precMonth { varUIntW(&tmp, month) }
    if t.prec >= precDay { varUIntW(&tmp, day) }
    if t.prec >= precMin {
        varUIntW(&tmp, hour)
        varUIntW(&tmp, minute)
    }
    if t.prec >= precSec { varUIntW(&tmp, t.second) }
    if t.prec == precFrac {
        varIntW(&tmp, t.fracExp, false)
        tmp.append(contentsOf: limbsOf(doc, t.fracAt, t.fracLen).toBEBytes())
    }
    td(&buf, 6, tmp)
}

func writeSimpleLst(_ sm: SymMap, _ buf: inout [UInt8]) {
    let mark = buf.count
    buf.append(0)
    varUIntW(&buf, 1)
    varUIntW(&buf, 3)
    let smark = buf.count
    buf.append(0)
    varUIntW(&buf, 7)
    let lmark = buf.count
    buf.append(0)
    for text in sm.texts {
        let ln = text.utf8.count
        if ln < 14 {
            buf.append(UInt8((8 << 4) | ln))
        } else {
            buf.append(UInt8((8 << 4) | 14))
            varUIntW(&buf, ln)
        }
        buf.append(contentsOf: text.utf8)
    }
    seal(&buf, lmark, 11)
    seal(&buf, smark, 13)
    seal(&buf, mark, 14)
}

func beInt(_ value: Int) -> [UInt8] {
    if value == 0 { return [0] }
    var tmp: [UInt8] = []
    var x = value
    while x > 0 {
        tmp.append(UInt8(x & 255))
        x >>= 8
    }
    return Array(tmp.reversed())
}

func writeLst(_ sm: SymMap, _ options: EncodeOptions, _ cat: Catalog, _ buf: inout [UInt8]) {
    if sm.texts.isEmpty && options.importNames.isEmpty { return }
    if options.importNames.isEmpty {
        writeSimpleLst(sm, &buf)
        return
    }
    var fields: [UInt8] = []
    if !options.importNames.isEmpty {
        varUIntW(&fields, 6)
        var items: [UInt8] = []
        for i in options.importNames.indices {
            var item: [UInt8] = []
            varUIntW(&item, 4)
            td(&item, 8, Array(options.importNames[i].utf8))
            varUIntW(&item, 5)
            td(&item, 2, beInt(options.importVersions[i]))
            var maxId = 0
            let idx = cat.exact(options.importNames[i], options.importVersions[i])
            if idx >= 0 { maxId = cat.tables[idx].texts.count }
            varUIntW(&item, 8)
            td(&item, 2, beInt(maxId))
            td(&items, 13, item)
        }
        td(&fields, 11, items)
    }
    if !sm.texts.isEmpty {
        varUIntW(&fields, 7)
        var items: [UInt8] = []
        for text in sm.texts {
            td(&items, 8, Array(text.utf8))
        }
        td(&fields, 11, items)
    }
    var structed: [UInt8] = []
    td(&structed, 13, fields)
    var ann: [UInt8] = []
    varUIntW(&ann, 1)
    varUIntW(&ann, 3)
    ann.append(contentsOf: structed)
    td(&buf, 14, ann)
}

public func encodeBinary(_ doc: IonDoc, _ options: EncodeOptions, _ cat: Catalog) throws -> [UInt8] {
    var buf: [UInt8] = [0xE0, 0x01]
    if options.version == 11 {
        buf.append(0x01)
        buf.append(0xEA)
        try encodeValues11(doc, &buf)
        return buf
    }
    buf.append(0x00)
    buf.append(0xEA)
    let sm = SymMap()
    var body: [UInt8] = []
    body.reserveCapacity(64 + doc.top.count * 24)
    for id in doc.top {
        try binValue(doc, id, sm, &body)
    }
    writeLst(sm, options, cat, &buf)
    buf.append(contentsOf: body)
    return buf
}
