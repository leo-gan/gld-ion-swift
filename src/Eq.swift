func f16ToF64(_ h: UInt16) -> Double {
    let sign = UInt64(h & 0x8000) << 48
    var exp = Int((h & 0x7C00) >> 10)
    var frac = UInt64(h & 0x03FF)
    if exp == 0 {
        if frac == 0 { return Double(bitPattern: sign) }
        exp = 1
        while (frac & 0x0400) == 0 {
            frac <<= 1
            exp -= 1
        }
        frac &= 0x03FF
        let e = UInt64(exp + (1023 - 15))
        let bits = sign | (e << 52) | (frac << 42)
        return Double(bitPattern: bits)
    }
    if exp == 31 {
        let bits = sign | (UInt64(0x7FF) << 52) | (frac << 42)
        return Double(bitPattern: bits)
    }
    let e = UInt64(exp + (1023 - 15))
    let bits = sign | (e << 52) | (frac << 42)
    return Double(bitPattern: bits)
}

func symEq(_ a: IonDoc, _ sa: Int, _ b: IonDoc, _ sb: Int) -> Bool {
    let x = a.syms[sa]
    let y = b.syms[sb]
    if x.text >= 0 && y.text >= 0 { return a.texts[x.text] == b.texts[y.text] }
    if x.text >= 0 || y.text >= 0 { return false }
    let xImp = x.impName >= 0
    let yImp = y.impName >= 0
    if xImp || yImp {
        if !(xImp && yImp) { return false }
        return a.texts[x.impName] == b.texts[y.impName] && x.impSid == y.impSid
    }
    return true
}

func limbsEq(_ a: IonDoc, _ at: Int, _ n: Int, _ b: IonDoc, _ bt: Int, _ bn: Int) -> Bool {
    if n != bn { return false }
    if n == 0 { return true }
    for i in 0..<n where a.limbs[at + i] != b.limbs[bt + i] { return false }
    return true
}

private func asF64Bits(_ bits: UInt64, _ width: Int) -> (Double, Bool, Bool) {
    if width == 0 { return (0, false, false) }
    if width == 4 {
        let f = Float(bitPattern: UInt32(truncatingIfNeeded: bits))
        let nan = f.isNaN
        let neg0 = f == 0 && (UInt32(truncatingIfNeeded: bits) & 0x8000_0000) != 0
        return (Double(f), nan, neg0)
    }
    if width == 2 {
        let f = f16ToF64(UInt16(truncatingIfNeeded: bits))
        let nan = f.isNaN
        let neg0 = f == 0 && (bits & 0x8000) != 0
        return (f, nan, neg0)
    }
    let f = Double(bitPattern: bits)
    let nan = f.isNaN
    let neg0 = f == 0 && (bits & (UInt64(1) << 63)) != 0
    return (f, nan, neg0)
}

private func floatEq(_ a: IonDoc, _ ai: Int, _ b: IonDoc, _ bi: Int) -> Bool {
    let ab = a.floats[a.nodes[ai].b]
    let bb = b.floats[b.nodes[bi].b]
    let av = asF64Bits(ab, a.nodes[ai].a)
    let bv = asF64Bits(bb, b.nodes[bi].a)
    if av.1 || bv.1 { return av.1 && bv.1 }
    if av.2 || bv.2 { return av.2 && bv.2 }
    return av.0 == bv.0
}

private func timeEq(_ a: IonDoc, _ ai: Int, _ b: IonDoc, _ bi: Int) -> Bool {
    let x = a.times[a.nodes[ai].a]
    let y = b.times[b.nodes[bi].a]
    if x.prec != y.prec || x.unknown != y.unknown { return false }
    if !x.unknown && x.off != y.off { return false }
    if x.year != y.year || x.month != y.month || x.day != y.day { return false }
    if x.hour != y.hour || x.minute != y.minute || x.second != y.second { return false }
    if x.fracExp != y.fracExp { return false }
    return limbsEq(a, x.fracAt, x.fracLen, b, y.fracAt, y.fracLen)
}

private func annEq(_ a: IonDoc, _ ai: Int, _ b: IonDoc, _ bi: Int) -> Bool {
    let an = a.nodes[ai]
    let bn = b.nodes[bi]
    if an.annN != bn.annN { return false }
    for i in 0..<an.annN {
        if !symEq(a, a.anns[an.ann + i], b, b.anns[bn.ann + i]) { return false }
    }
    return true
}

public func ionEq(_ a: IonDoc, _ ai: Int, _ b: IonDoc, _ bi: Int) -> Bool {
    if !annEq(a, ai, b, bi) { return false }
    let ak = a.nodes[ai].kind
    let bk = b.nodes[bi].kind
    if ak != bk { return false }
    switch ak {
    case kNull:
        return a.nodes[ai].a == b.nodes[bi].a
    case kBool:
        return a.nodes[ai].a == b.nodes[bi].a
    case kInt:
        if a.nodes[ai].c != b.nodes[bi].c { return false }
        return limbsEq(a, a.nodes[ai].a, a.nodes[ai].b, b, b.nodes[bi].a, b.nodes[bi].b)
    case kFloat:
        return floatEq(a, ai, b, bi)
    case kDecimal:
        if a.nodes[ai].c != b.nodes[bi].c || a.nodes[ai].d != b.nodes[bi].d { return false }
        return limbsEq(a, a.nodes[ai].a, a.nodes[ai].b, b, b.nodes[bi].a, b.nodes[bi].b)
    case kTimestamp:
        return timeEq(a, ai, b, bi)
    case kString:
        return a.texts[a.nodes[ai].a] == b.texts[b.nodes[bi].a]
    case kSymbol:
        return symEq(a, a.nodes[ai].a, b, b.nodes[bi].a)
    case kBlob, kClob:
        return a.blobs[a.nodes[ai].a] == b.blobs[b.nodes[bi].a]
    case kList, kSexp:
        if a.nodes[ai].nchild != b.nodes[bi].nchild { return false }
        var ea = a.nodes[ai].child
        var eb = b.nodes[bi].child
        var i = 0
        while i < a.nodes[ai].nchild {
            if !ionEq(a, a.edges[ea].child, b, b.edges[eb].child) { return false }
            ea = a.edges[ea].next
            eb = b.edges[eb].next
            i += 1
        }
        return true
    case kStruct:
        return structEq(a, ai, b, bi)
    default:
        return false
    }
}

private func structEq(_ a: IonDoc, _ ai: Int, _ b: IonDoc, _ bi: Int) -> Bool {
    let n = a.nodes[ai].nchild
    if n != b.nodes[bi].nchild { return false }
    var aChild: [Int] = []
    var aField: [Int] = []
    var bChild: [Int] = []
    var bField: [Int] = []
    aChild.reserveCapacity(n)
    var e = a.nodes[ai].child
    var i = 0
    while i < n {
        aChild.append(a.edges[e].child)
        aField.append(a.edges[e].field)
        e = a.edges[e].next
        i += 1
    }
    e = b.nodes[bi].child
    i = 0
    while i < n {
        bChild.append(b.edges[e].child)
        bField.append(b.edges[e].field)
        e = b.edges[e].next
        i += 1
    }
    var used = [Bool](repeating: false, count: n)
    i = 0
    while i < n {
        var found = false
        var j = 0
        while j < n {
            if !used[j] && symEq(a, aField[i], b, bField[j]) && ionEq(a, aChild[i], b, bChild[j]) {
                used[j] = true
                found = true
                break
            }
            j += 1
        }
        if !found { return false }
        i += 1
    }
    return true
}

public func docsEq(_ a: IonDoc, _ b: IonDoc) -> Bool {
    if a.top.count != b.top.count { return false }
    for i in a.top.indices where !ionEq(a, a.top[i], b, b.top[i]) { return false }
    return true
}
