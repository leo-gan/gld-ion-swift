public struct IonTime {
    public var prec: Int
    public var off: Int
    public var unknown: Bool
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int
    public var minute: Int
    public var second: Int
    public var fracExp: Int
    public var fracAt: Int
    public var fracLen: Int

    public init() {
        prec = precYear
        off = 0
        unknown = true
        year = 1
        month = 1
        day = 1
        hour = 0
        minute = 0
        second = 0
        fracExp = 0
        fracAt = 0
        fracLen = 0
    }
}

public struct IonNode {
    public var kind: Int
    public var a: Int
    public var b: Int
    public var c: Int
    public var d: Int
    public var ann: Int
    public var annN: Int
    public var child: Int
    public var nchild: Int

    public init(kind: Int) {
        self.kind = kind
        a = 0
        b = 0
        c = 0
        d = -1
        ann = -1
        annN = 0
        child = -1
        nchild = 0
    }
}

public struct IonEdge {
    public var child: Int
    public var field: Int
    public var next: Int

    public init(child: Int, field: Int) {
        self.child = child
        self.field = field
        next = -1
    }
}

public struct SymRef {
    public var text: Int
    public var sid: Int
    public var impName: Int
    public var impSid: Int

    public init(text: Int, sid: Int, impName: Int, impSid: Int) {
        self.text = text
        self.sid = sid
        self.impName = impName
        self.impSid = impSid
    }
}

public final class IonDoc {
    public var nodes: [IonNode] = []
    public var edges: [IonEdge] = []
    public var anns: [Int] = []
    public var texts: [String] = []
    public var syms: [SymRef] = []
    public var limbs: [UInt32] = []
    public var floats: [UInt64] = []
    public var times: [IonTime] = []
    public var blobs: [[UInt8]] = []
    public var top: [Int] = []
    var symAt: [Int] = []
    var textIndex: [String: Int] = [:]
    var shortKey: [UInt64: Int] = [:]

    public init() {}

    public func reserve(_ n: Int) {
        let count = max(n, 8)
        nodes.reserveCapacity(count)
        edges.reserveCapacity(count)
        limbs.reserveCapacity(count)
        top.reserveCapacity(count)
        texts.reserveCapacity(16)
        syms.reserveCapacity(16)
    }

    public func intern(_ text: String) -> Int {
        if let hit = textIndex[text] { return hit }
        let i = texts.count
        texts.append(text)
        symAt.append(-1)
        textIndex[text] = i
        return i
    }

    func _add(_ node: IonNode) -> Int {
        nodes.append(node)
        return nodes.count - 1
    }

    public func addNull(_ nullType: Int) -> Int {
        var n = IonNode(kind: kNull)
        n.a = nullType
        return _add(n)
    }

    public func addBool(_ value: Bool) -> Int {
        var n = IonNode(kind: kBool)
        if value { n.a = 1 }
        return _add(n)
    }

    public func addInt(_ value: BigInt) -> Int {
        var n = IonNode(kind: kInt)
        n.a = limbs.count
        n.b = value.limbs.count
        if value.neg { n.c = 1 }
        limbs.append(contentsOf: value.limbs)
        return _add(n)
    }

    @inline(__always)
    public func addI64(_ value: Int64) -> Int {
        var n = IonNode(kind: kInt)
        if value == 0 { return _add(n) }
        var mag: UInt64
        if value < 0 {
            n.c = 1
            if value == Int64.min {
                mag = 0x8000_0000_0000_0000
            } else {
                mag = UInt64(bitPattern: -value)
            }
        } else {
            mag = UInt64(value)
        }
        n.a = limbs.count
        let lo = UInt32(truncatingIfNeeded: mag & 0xFFFF_FFFF)
        let hi = UInt32(truncatingIfNeeded: mag >> 32)
        limbs.append(lo)
        n.b = 1
        if hi != 0 {
            limbs.append(hi)
            n.b = 2
        }
        return _add(n)
    }

    public func addFloat(_ width: Int, _ bits: UInt64) -> Int {
        var n = IonNode(kind: kFloat)
        n.a = width
        n.b = floats.count
        floats.append(bits)
        return _add(n)
    }

    public func addDecimal(_ coef: BigInt, _ neg: Bool, _ exp: Int) -> Int {
        var n = IonNode(kind: kDecimal)
        n.a = limbs.count
        n.b = coef.limbs.count
        if neg || coef.neg { n.c = 1 }
        n.d = exp
        limbs.append(contentsOf: coef.limbs)
        return _add(n)
    }

    public func addTime(_ when: IonTime) -> Int {
        var n = IonNode(kind: kTimestamp)
        n.a = times.count
        times.append(when)
        return _add(n)
    }

    public func addString(_ text: String) -> Int {
        addStringAt(intern(text))
    }

    @inline(__always)
    public func addStringAt(_ textI: Int) -> Int {
        var n = IonNode(kind: kString)
        n.a = textI
        return _add(n)
    }

    @inline(__always)
    func internShort(_ span: ArraySlice<UInt8>) -> Int? {
        let count = span.count
        if count > 8 { return nil }
        var key = UInt64(count) << 56
        var shift: UInt64 = 0
        for b in span {
            if b >= 128 { return nil }
            key |= UInt64(b) << shift
            shift += 8
        }
        if let hit = shortKey[key] { return hit }
        let id = intern(String(decoding: span, as: UTF8.self))
        shortKey[key] = id
        return id
    }

    public func addStringRaw(_ span: ArraySlice<UInt8>, _ offset: Int) throws -> Int {
        if let id = internShort(span) { return addStringAt(id) }
        let bytes = Array(span)
        try validateUTF8(bytes, offset)
        return addString(String(decoding: bytes, as: UTF8.self))
    }

    public func addSymbolText(_ text: String) -> Int {
        let ti = intern(text)
        let cached = symAt[ti]
        if cached >= 0 { return cached }
        var n = IonNode(kind: kSymbol)
        let s = SymRef(text: ti, sid: 0, impName: -1, impSid: 0)
        n.a = syms.count
        syms.append(s)
        let id = _add(n)
        symAt[ti] = id
        return id
    }

    public func wrapSym(_ sym: Int) -> Int {
        var n = IonNode(kind: kSymbol)
        n.a = sym
        return _add(n)
    }

    public func addSymbolRef(_ sym: SymRef) -> Int {
        var n = IonNode(kind: kSymbol)
        n.a = syms.count
        syms.append(sym)
        return _add(n)
    }

    public func addBytes(_ kind: Int, _ data: [UInt8]) -> Int {
        var n = IonNode(kind: kind)
        n.a = blobs.count
        blobs.append(data)
        return _add(n)
    }

    public func startContainer(_ kind: Int) -> Int {
        _add(IonNode(kind: kind))
    }

    @inline(__always)
    public func addChild(_ parent: Int, _ child: Int, _ field: Int) {
        let idx = edges.count
        edges.append(IonEdge(child: child, field: field))
        var node = nodes[parent]
        if node.child < 0 {
            node.child = idx
        } else {
            edges[node.d].next = idx
        }
        node.d = idx
        node.nchild += 1
        nodes[parent] = node
    }

    public func setAnns(_ id: Int, _ annsIn: [Int]) {
        if annsIn.isEmpty { return }
        var node = nodes[id]
        node.ann = anns.count
        node.annN = annsIn.count
        anns.append(contentsOf: annsIn)
        nodes[id] = node
    }

    public func addTop(_ id: Int) {
        top.append(id)
    }

    public func childAt(_ parent: Int, _ index: Int) -> Int {
        var edge = nodes[parent].child
        var i = 0
        while i < index {
            edge = edges[edge].next
            i += 1
        }
        return edges[edge].child
    }

    public func fieldAt(_ parent: Int, _ index: Int) -> Int {
        var edge = nodes[parent].child
        var i = 0
        while i < index {
            edge = edges[edge].next
            i += 1
        }
        return edges[edge].field
    }

    public func textAt(_ id: Int) -> String {
        texts[nodes[id].a]
    }

    public func symText(_ sym: Int) -> String {
        let s = syms[sym]
        if s.text < 0 { return "" }
        return texts[s.text]
    }
}
