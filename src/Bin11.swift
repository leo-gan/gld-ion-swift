func encodeValues11(_ doc: IonDoc, _ buf: inout [UInt8]) throws {
    for id in doc.top {
        try value11(doc, id, &buf)
    }
}

func value11(_ doc: IonDoc, _ id: Int, _ buf: inout [UInt8]) throws {
    let n = doc.nodes[id]
    var i = 0
    while i < n.annN {
        try annotation11(doc, doc.anns[n.ann + i], &buf)
        i += 1
    }
    switch n.kind {
    case kNull:
        null11(n.a, &buf)
    case kBool:
        buf.append(n.a == 0 ? 0x6F : 0x6E)
    case kInt:
        int11(doc, n.a, n.b, n.c != 0, &buf)
    case kFloat:
        float11(doc, n.a, n.b, &buf)
    case kDecimal:
        decimal11(doc, n.a, n.b, n.c != 0, n.d, &buf)
    case kTimestamp:
        try time11(doc, doc.times[n.a], &buf)
    case kString:
        textOp(doc.texts[n.a], 0x90, 0xF8, &buf)
    case kSymbol:
        let s = doc.syms[n.a]
        if s.text < 0 {
            buf.append(UInt8(0x50 | (s.sid & 7)))
            writeFlexUInt(&buf, s.sid >> 3)
        } else {
            textOp(doc.texts[s.text], 0xA0, 0xF9, &buf)
        }
    case kBlob, kClob:
        let raw = doc.blobs[n.a]
        buf.append(n.kind == kBlob ? 0xFE : 0xFF)
        writeFlexUInt(&buf, raw.count)
        buf.append(contentsOf: raw)
    case kList, kSexp, kStruct:
        try container11(doc, id, &buf)
    default:
        throw DecodeError(kind: DecodeError.kindType, offset: 0)
    }
}

func null11(_ typeKind: Int, _ buf: inout [UInt8]) {
    if typeKind == 0 {
        buf.append(0x8E)
        return
    }
    var code = 0
    switch typeKind {
    case kBool: code = 1
    case kInt: code = 2
    case kFloat: code = 3
    case kDecimal: code = 4
    case kTimestamp: code = 5
    case kString: code = 6
    case kSymbol: code = 7
    case kBlob: code = 8
    case kClob: code = 9
    case kList: code = 10
    case kSexp: code = 11
    case kStruct: code = 12
    default: code = 0
    }
    if code == 0 {
        buf.append(0x8E)
        return
    }
    buf.append(0x8F)
    buf.append(UInt8(code))
}

func annotation11(_ doc: IonDoc, _ sym: Int, _ buf: inout [UInt8]) throws {
    let s = doc.syms[sym]
    if s.text < 0 {
        buf.append(0x58)
        writeFlexUInt(&buf, s.sid)
        return
    }
    let raw = utf8Bytes(doc.texts[s.text])
    buf.append(0x59)
    writeFlexUInt(&buf, raw.count)
    buf.append(contentsOf: raw)
}

func textOp(_ text: String, _ shortBase: Int, _ longOp: Int, _ buf: inout [UInt8]) {
    let raw = utf8Bytes(text)
    if raw.count <= 15 {
        buf.append(UInt8(shortBase + raw.count))
    } else {
        buf.append(UInt8(longOp))
        writeFlexUInt(&buf, raw.count)
    }
    buf.append(contentsOf: raw)
}

func magLE(_ doc: IonDoc, _ at: Int, _ n: Int) -> [UInt8] {
    var out: [UInt8] = []
    var i = 0
    while i < n {
        let limb = doc.limbs[at + i]
        var s = 0
        while s < 32 {
            out.append(UInt8((limb >> UInt32(s)) & 255))
            s += 8
        }
        i += 1
    }
    while out.count > 1 && out[out.count - 1] == 0 { out.removeLast() }
    if out.count == 1 && out[0] == 0 { out.removeLast() }
    return out
}

func twos(_ mag: [UInt8], _ width: Int, _ neg: Bool) -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(width)
    if !neg {
        var i = 0
        while i < width {
            out.append(i < mag.count ? mag[i] : 0)
            i += 1
        }
        return out
    }
    var carry = 1
    var i = 0
    while i < width {
        let b = i < mag.count ? Int(mag[i]) : 0
        let inv = (b ^ 255) + carry
        out.append(UInt8(inv & 255))
        carry = inv >> 8
        i += 1
    }
    return out
}

func signedBytes(_ mag: [UInt8], _ neg: Bool) -> [UInt8] {
    if mag.isEmpty { return neg ? [0] : [] }
    var width = mag.count
    if width == 0 { width = 1 }
    while true {
        let raw = twos(mag, width, neg)
        let high = Int(raw[raw.count - 1]) & 128
        if neg && high != 0 { return raw }
        if !neg && high == 0 { return raw }
        width += 1
    }
}

func putIntBytes(_ raw: [UInt8], _ buf: inout [UInt8]) {
    let n = raw.count
    if n == 0 {
        buf.append(0x60)
        return
    }
    if n <= 8 {
        buf.append(UInt8(0x60 + n))
    } else {
        buf.append(0xF5)
        writeFlexUInt(&buf, n)
    }
    buf.append(contentsOf: raw)
}

func int11(_ doc: IonDoc, _ at: Int, _ n: Int, _ neg: Bool, _ buf: inout [UInt8]) {
    if n == 0 && !neg {
        buf.append(0x60)
        return
    }
    let mag = magLE(doc, at, n)
    putIntBytes(signedBytes(mag, neg), &buf)
}

func float11(_ doc: IonDoc, _ width: Int, _ slot: Int, _ buf: inout [UInt8]) {
    if width == 0 {
        buf.append(0x6A)
        return
    }
    var op = 0x6D
    var n = 8
    if width == 2 {
        op = 0x6B
        n = 2
    } else if width == 4 {
        op = 0x6C
        n = 4
    }
    buf.append(UInt8(op))
    let bits = doc.floats[slot]
    var k = 0
    while k < n {
        buf.append(UInt8((bits >> UInt64(k * 8)) & 255))
        k += 1
    }
}

func decimal11(_ doc: IonDoc, _ at: Int, _ n: Int, _ neg: Bool, _ exp: Int, _ buf: inout [UInt8]) {
    if n == 0 && !neg && exp == 0 {
        buf.append(0x70)
        return
    }
    var body: [UInt8] = []
    writeFlexInt(&body, exp)
    if n > 0 || neg {
        let mag = magLE(doc, at, n)
        if mag.isEmpty && neg {
            body.append(0)
        } else {
            body.append(contentsOf: signedBytes(mag, neg))
        }
    }
    if body.count <= 15 {
        buf.append(UInt8(0x70 + body.count))
    } else {
        buf.append(0xF6)
        writeFlexUInt(&buf, body.count)
    }
    buf.append(contentsOf: body)
}

func container11(_ doc: IonDoc, _ id: Int, _ buf: inout [UInt8]) throws {
    let n = doc.nodes[id]
    var body: [UInt8] = []
    var edge = n.child
    var i = 0
    while i < n.nchild {
        if n.kind == kStruct {
            let field = doc.edges[edge].field
            var text = ""
            if field >= 0 && doc.syms[field].text >= 0 {
                text = doc.texts[doc.syms[field].text]
            }
            let nb = utf8Bytes(text)
            writeFlexInt(&body, -1 - nb.count)
            body.append(contentsOf: nb)
        }
        try value11(doc, doc.edges[edge].child, &body)
        edge = doc.edges[edge].next
        i += 1
    }
    if n.kind == kStruct && body.isEmpty {
        buf.append(0xD0)
        return
    }
    let ln = body.count
    if n.kind == kStruct {
        buf.append(0xFD)
        writeFlexUInt(&buf, ln)
    } else if ln <= 15 {
        let base = n.kind == kSexp ? 0xC0 : 0xB0
        buf.append(UInt8(base + ln))
    } else {
        buf.append(n.kind == kSexp ? 0xFB : 0xFA)
        writeFlexUInt(&buf, ln)
    }
    buf.append(contentsOf: body)
}

func putBits(_ raw: inout [UInt8], _ nbits: inout Int, _ value: Int, _ width: Int) {
    var k = 0
    while k < width {
        let bit = (value >> k) & 1
        let pos = nbits
        let bi = pos / 8
        while raw.count <= bi { raw.append(0) }
        raw[bi] = UInt8(Int(raw[bi]) | (bit << (pos % 8)))
        nbits += 1
        k += 1
    }
}

func time11(_ doc: IonDoc, _ t: IonTime, _ buf: inout [UInt8]) throws {
    var raw: [UInt8] = []
    var nbits = 0
    putBits(&raw, &nbits, t.year, 14)
    var length = 2
    if t.prec >= precMonth {
        var day = 0
        if t.prec >= precDay { day = t.day }
        putBits(&raw, &nbits, t.month, 4)
        putBits(&raw, &nbits, day, 5)
        length = 3
    }
    if t.prec >= precMin {
        putBits(&raw, &nbits, t.hour, 5)
        putBits(&raw, &nbits, t.minute, 6)
        var off = 4095
        if !t.unknown {
            off = t.off + 1440
            if off < 0 || off > 4094 {
                throw DecodeError(kind: DecodeError.kindRange, offset: 0)
            }
        }
        putBits(&raw, &nbits, off, 12)
        length = 6
    }
    if t.prec >= precSec {
        putBits(&raw, &nbits, t.second, 6)
        length = 7
    }
    var frac: [UInt8] = []
    if t.prec == precFrac {
        let scale = -t.fracExp
        if scale < 1 { throw DecodeError(kind: DecodeError.kindSyntax, offset: 0) }
        writeFlexUInt(&frac, scale)
        let mag = magLE(doc, t.fracAt, t.fracLen)
        if mag.isEmpty { frac.append(0) }
        else { frac.append(contentsOf: mag) }
        length = 7 + frac.count
    }
    buf.append(0xF7)
    writeFlexUInt(&buf, length)
    var i = 0
    while i < length && i < raw.count {
        buf.append(raw[i])
        i += 1
    }
    while i < length && t.prec < precFrac {
        buf.append(0)
        i += 1
    }
    if t.prec == precFrac { buf.append(contentsOf: frac) }
}
