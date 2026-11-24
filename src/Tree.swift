import Foundation

private enum TreeStep {
    case skip
    case node(IonTree)
}

private let treeSystem = [
    "",
    "$ion",
    "$ion_1_0",
    "$ion_symbol_table",
    "name",
    "version",
    "imports",
    "symbols",
    "max_id",
    "$ion_shared_symbol_table",
]

/// Reused buffers. The value bytes are written on every call; only the symbol-table
/// image and the decode header are kept when the next datagram has the same names.
private final class TreeCache: @unchecked Sendable {
    let lock = NSLock()
    var sid: [String: Int] = [:]
    var symbols: [String] = []
    var lstKey: [String] = []
    var lstBytes: [UInt8] = []
    var body: [UInt8] = []

    var hot: [UInt8] = []
    var hotAt = 0
    var hotSyms: [String] = []

    var raw: [UInt8] = []
    var i = 0
    var n = 0
    var depth = 0
    var syms: [String] = treeSystem

    func encode(_ value: IonTree) -> [UInt8] {
        if sid.capacity < 8 { sid.reserveCapacity(8) }
        sid.removeAll(keepingCapacity: true)
        symbols.removeAll(keepingCapacity: true)
        if body.capacity < 64 { body.reserveCapacity(64) }
        body.removeAll(keepingCapacity: true)
        write(value, &body, 0)
        if symbols != lstKey {
            lstKey = symbols
            lstBytes.removeAll(keepingCapacity: true)
            if !symbols.isEmpty {
                writeLst(&lstBytes)
            }
        }
        var out: [UInt8] = []
        out.reserveCapacity(4 + lstBytes.count + body.count)
        out.append(0xE0)
        out.append(0x01)
        out.append(0x00)
        out.append(0xEA)
        if !lstBytes.isEmpty { out.append(contentsOf: lstBytes) }
        out.append(contentsOf: body)
        return out
    }

    func write(_ value: IonTree, _ buf: inout [UInt8], _ depth: Int) {
        if depth > maxDepth {
            buf.append(0x0F)
            return
        }
        switch value {
        case .null:
            buf.append(0x0F)
        case .bool(let v):
            buf.append(v ? 0x11 : 0x10)
        case .int(let v):
            appendInt(&buf, v)
        case .float(let v):
            appendF64(&buf, v)
        case .string(let text):
            appendString(&buf, text)
        case .list(let items):
            let mark = buf.count
            buf.append(0)
            for item in items {
                write(item, &buf, depth + 1)
            }
            sealBody(&buf, mark, 11)
        case .fields(let pairs):
            let mark = buf.count
            buf.append(0)
            for (name, item) in pairs {
                appendVarUInt(&buf, intern(name))
                write(item, &buf, depth + 1)
            }
            sealBody(&buf, mark, 13)
        }
    }

    func intern(_ name: String) -> Int {
        if let id = sid[name] { return id }
        let id = 10 + symbols.count
        sid[name] = id
        symbols.append(name)
        return id
    }

    func writeLst(_ buf: inout [UInt8]) {
        let mark = buf.count
        buf.append(0)
        appendVarUInt(&buf, 1)
        appendVarUInt(&buf, 3)
        let smark = buf.count
        buf.append(0)
        appendVarUInt(&buf, 7)
        let lmark = buf.count
        buf.append(0)
        for text in symbols {
            appendString(&buf, text)
        }
        sealBody(&buf, lmark, 11)
        sealBody(&buf, smark, 13)
        sealBody(&buf, mark, 14)
    }

    func decode(_ input: [UInt8]) throws -> IonTree {
        raw = input
        n = input.count
        depth = 0
        defer { raw = [] }
        if hotAt > 4 && hotAt < n && raw.starts(with: hot) {
            syms = hotSyms
            i = hotAt
            let step = try readValue(n)
            if case .node(let node) = step, i == n {
                return node
            }
        }
        i = 0
        depth = 0
        resetSyms()
        var values: [IonTree] = []
        var markAt = 0
        var markSyms: [String] = []
        while i < n {
            if atBvm() {
                let minor = Int(raw[i + 2])
                i += 4
                if minor != 0 {
                    throw DecodeError(kind: DecodeError.kindVersion, offset: i - 4)
                }
                resetSyms()
                continue
            }
            let pendingAt = i
            let pendingSyms = syms
            let step = try readValue(n)
            if case .skip = step { continue }
            if case .node(let node) = step {
                if values.isEmpty {
                    markAt = pendingAt
                    markSyms = pendingSyms
                }
                values.append(node)
            }
        }
        if values.count == 1 {
            hotAt = markAt
            hot = Array(raw[0..<markAt])
            hotSyms = markSyms
            return values[0]
        }
        hotAt = 0
        hot.removeAll(keepingCapacity: true)
        if values.isEmpty { return .null }
        return .list(values)
    }

    func resetSyms() {
        syms = treeSystem
    }

    func atBvm() -> Bool {
        i + 3 < n && raw[i] == 0xE0 && raw[i + 1] == 0x01 && raw[i + 3] == 0xEA
    }

    func readValue(_ limit: Int) throws -> TreeStep {
        while true {
            if i >= limit || i >= n {
                throw DecodeError(kind: DecodeError.kindEOF, offset: i)
            }
            let td = Int(raw[i])
            i += 1
            let type = td >> 4
            let ln = td & 15
            if type == 0 && ln != 15 {
                let len = try bodyLen(0, ln)
                try skip(len, limit)
                return .skip
            }
            if ln == 15 { return .node(.null) }
            switch type {
            case 1:
                return .node(.bool(try readBool(ln)))
            case 2:
                return .node(.int(try readInt(ln, false)))
            case 3:
                return .node(.int(try readInt(ln, true)))
            case 4:
                return .node(.float(try readFloat(ln)))
            case 7:
                return .node(.string(try symText(try readMag(try bodyLen(7, ln)))))
            case 8:
                return .node(.string(try takeString(try bodyLen(8, ln))))
            case 11:
                return .node(try readList(ln))
            case 13:
                return .node(try readStruct(ln))
            case 14:
                return try readAnn(ln)
            default:
                throw DecodeError(kind: DecodeError.kindType, offset: i - 1)
            }
        }
    }

    func readBool(_ ln: Int) throws -> Bool {
        if ln == 0 { return false }
        if ln == 1 { return true }
        throw DecodeError(kind: DecodeError.kindType, offset: i - 1)
    }

    func readInt(_ ln: Int, _ neg: Bool) throws -> Int64 {
        let len = try bodyLen(neg ? 3 : 2, ln)
        if len == 0 { return 0 }
        if len > 8 { throw DecodeError(kind: DecodeError.kindRange, offset: i) }
        if i + len > n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        if len == 8 {
            let b0 = raw[i]
            if b0 == 0x80 && raw[i + 1] == 0 && raw[i + 2] == 0 && raw[i + 3] == 0
                && raw[i + 4] == 0 && raw[i + 5] == 0 && raw[i + 6] == 0 && raw[i + 7] == 0 {
                i += 8
                if !neg { throw DecodeError(kind: DecodeError.kindRange, offset: i - 8) }
                return Int64.min
            }
            if (b0 & 0x80) != 0 {
                i += 8
                throw DecodeError(kind: DecodeError.kindRange, offset: i - 8)
            }
        }
        var mag = UInt64(0)
        var k = 0
        while k < len {
            mag = (mag << 8) | UInt64(raw[i + k])
            k += 1
        }
        i += len
        if neg { return -Int64(mag) }
        return Int64(mag)
    }

    func readMag(_ len: Int) throws -> Int {
        if len == 0 { return 0 }
        if len > 8 { throw DecodeError(kind: DecodeError.kindRange, offset: i) }
        if i + len > n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        var mag = UInt64(0)
        var k = 0
        while k < len {
            mag = (mag << 8) | UInt64(raw[i + k])
            k += 1
        }
        i += len
        if mag > UInt64(Int.max) {
            throw DecodeError(kind: DecodeError.kindRange, offset: i - len)
        }
        return Int(mag)
    }

    func readFloat(_ ln: Int) throws -> Double {
        let len = try bodyLen(4, ln)
        if len == 0 { return 0.0 }
        if len == 4 {
            let bits = try readBits(4)
            return Double(Float(bitPattern: UInt32(bits)))
        }
        if len == 8 {
            return Double(bitPattern: try readBits(8))
        }
        throw DecodeError(kind: DecodeError.kindType, offset: i - 1)
    }

    func readBits(_ len: Int) throws -> UInt64 {
        if i + len > n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        var bits = UInt64(0)
        var k = 0
        while k < len {
            bits = (bits << 8) | UInt64(raw[i + k])
            k += 1
        }
        i += len
        return bits
    }

    func readList(_ ln: Int) throws -> IonTree {
        if depth > maxDepth { throw DecodeError(kind: DecodeError.kindDepth, offset: i) }
        let len = try bodyLen(11, ln)
        let end = i + len
        if end > n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        depth += 1
        var out: [IonTree] = []
        if len > 0 { out.reserveCapacity(min(len, 16)) }
        while i < end {
            let step = try readValue(end)
            if case .node(let node) = step { out.append(node) }
        }
        if i != end { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        depth -= 1
        return .list(out)
    }

    func readStruct(_ ln: Int) throws -> IonTree {
        if depth > maxDepth { throw DecodeError(kind: DecodeError.kindDepth, offset: i) }
        let len = try bodyLen(13, ln)
        let end = i + len
        if end > n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        depth += 1
        var out: [(String, IonTree)] = []
        if len > 0 { out.reserveCapacity(min(len, 8)) }
        while i < end {
            let sid = try varUint()
            let step = try readValue(end)
            if case .node(let node) = step {
                out.append((try symText(sid), node))
            }
        }
        if i != end { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        depth -= 1
        return .fields(out)
    }

    func readAnn(_ ln: Int) throws -> TreeStep {
        let len = try bodyLen(14, ln)
        let end = i + len
        if end > n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        let alen = try varUint()
        let annEnd = i + alen
        if annEnd > end { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        var table = false
        while i < annEnd {
            if try varUint() == 3 { table = true }
        }
        let step = try readValue(end)
        if i != end { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
        if table {
            if case .node(let node) = step { try applyTable(node) }
            return .skip
        }
        return step
    }

    func applyTable(_ value: IonTree) throws {
        guard case .fields(let pairs) = value else { return }
        var saw = false
        var items: [IonTree] = []
        for (name, item) in pairs where name == "symbols" {
            saw = true
            if case .list(let list) = item {
                items = list
            } else {
                items = []
                saw = false
            }
        }
        if !saw { return }
        for item in items {
            guard case .string(let text) = item else {
                throw DecodeError(kind: DecodeError.kindSymbol, offset: i)
            }
            syms.append(text)
        }
    }

    func symText(_ sid: Int) throws -> String {
        if sid == 0 { return "" }
        if sid < 0 || sid >= syms.count {
            throw DecodeError(kind: DecodeError.kindSymbol, offset: i)
        }
        return syms[sid]
    }

    func bodyLen(_ type: Int, _ ln: Int) throws -> Int {
        if type == 13 && ln == 1 {
            let size = try varUint()
            if size == 0 { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
            return size
        }
        if ln < 14 { return ln }
        return try varUint()
    }

    func varUint() throws -> Int {
        var acc = 0
        let start = i
        var guardN = 0
        while i < n && guardN < 10 {
            let b = Int(raw[i])
            i += 1
            if acc > (Int.max >> 7) {
                throw DecodeError(kind: DecodeError.kindRange, offset: start)
            }
            acc = (acc << 7) | (b & 0x7F)
            guardN += 1
            if (b & 0x80) != 0 { return acc }
        }
        throw DecodeError(kind: DecodeError.kindEOF, offset: start)
    }

    func takeString(_ len: Int) throws -> String {
        if len < 0 || i + len > n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        if len == 0 { return "" }
        let s = String(decoding: raw[i..<(i + len)], as: UTF8.self)
        i += len
        return s
    }

    func skip(_ len: Int, _ limit: Int) throws {
        if len < 0 || i + len > n { throw DecodeError(kind: DecodeError.kindEOF, offset: i) }
        i += len
        if i > limit { throw DecodeError(kind: DecodeError.kindSyntax, offset: i) }
    }
}

private let treeCache = TreeCache()

@inline(__always)
private func appendVarUInt(_ buf: inout [UInt8], _ value: Int) {
    if value < 128 {
        buf.append(UInt8(0x80 | value))
        return
    }
    var parts: [UInt8] = []
    var x = value
    while x > 0 {
        parts.append(UInt8(x & 0x7F))
        x >>= 7
    }
    var k = parts.count - 1
    while k >= 0 {
        var b = parts[k]
        if k == 0 { b |= 0x80 }
        buf.append(b)
        k -= 1
    }
}

@inline(__always)
private func appendInt(_ buf: inout [UInt8], _ value: Int64) {
    if value == 0 {
        buf.append(0x20)
        return
    }
    if value == Int64.min {
        buf.append(0x38)
        buf.append(0x80)
        buf.append(0)
        buf.append(0)
        buf.append(0)
        buf.append(0)
        buf.append(0)
        buf.append(0)
        buf.append(0)
        return
    }
    let neg = value < 0
    let mag = UInt64(neg ? -value : value)
    let tag: UInt8 = neg ? 0x30 : 0x20
    if mag <= 0xFF {
        buf.append(tag | 1)
        buf.append(UInt8(truncatingIfNeeded: mag))
        return
    }
    if mag <= 0xFFFF {
        buf.append(tag | 2)
        buf.append(UInt8(truncatingIfNeeded: mag >> 8))
        buf.append(UInt8(truncatingIfNeeded: mag))
        return
    }
    if mag <= 0xFF_FFFF {
        buf.append(tag | 3)
        buf.append(UInt8(truncatingIfNeeded: mag >> 16))
        buf.append(UInt8(truncatingIfNeeded: mag >> 8))
        buf.append(UInt8(truncatingIfNeeded: mag))
        return
    }
    if mag <= 0xFFFF_FFFF {
        buf.append(tag | 4)
        buf.append(UInt8(truncatingIfNeeded: mag >> 24))
        buf.append(UInt8(truncatingIfNeeded: mag >> 16))
        buf.append(UInt8(truncatingIfNeeded: mag >> 8))
        buf.append(UInt8(truncatingIfNeeded: mag))
        return
    }
    if mag <= 0xFF_FFFF_FFFF {
        buf.append(tag | 5)
        buf.append(UInt8(truncatingIfNeeded: mag >> 32))
        buf.append(UInt8(truncatingIfNeeded: mag >> 24))
        buf.append(UInt8(truncatingIfNeeded: mag >> 16))
        buf.append(UInt8(truncatingIfNeeded: mag >> 8))
        buf.append(UInt8(truncatingIfNeeded: mag))
        return
    }
    if mag <= 0xFFFF_FFFF_FFFF {
        buf.append(tag | 6)
        buf.append(UInt8(truncatingIfNeeded: mag >> 40))
        buf.append(UInt8(truncatingIfNeeded: mag >> 32))
        buf.append(UInt8(truncatingIfNeeded: mag >> 24))
        buf.append(UInt8(truncatingIfNeeded: mag >> 16))
        buf.append(UInt8(truncatingIfNeeded: mag >> 8))
        buf.append(UInt8(truncatingIfNeeded: mag))
        return
    }
    if mag <= 0xFF_FFFF_FFFF_FFFF {
        buf.append(tag | 7)
        buf.append(UInt8(truncatingIfNeeded: mag >> 48))
        buf.append(UInt8(truncatingIfNeeded: mag >> 40))
        buf.append(UInt8(truncatingIfNeeded: mag >> 32))
        buf.append(UInt8(truncatingIfNeeded: mag >> 24))
        buf.append(UInt8(truncatingIfNeeded: mag >> 16))
        buf.append(UInt8(truncatingIfNeeded: mag >> 8))
        buf.append(UInt8(truncatingIfNeeded: mag))
        return
    }
    buf.append(tag | 8)
    buf.append(UInt8(truncatingIfNeeded: mag >> 56))
    buf.append(UInt8(truncatingIfNeeded: mag >> 48))
    buf.append(UInt8(truncatingIfNeeded: mag >> 40))
    buf.append(UInt8(truncatingIfNeeded: mag >> 32))
    buf.append(UInt8(truncatingIfNeeded: mag >> 24))
    buf.append(UInt8(truncatingIfNeeded: mag >> 16))
    buf.append(UInt8(truncatingIfNeeded: mag >> 8))
    buf.append(UInt8(truncatingIfNeeded: mag))
}

@inline(__always)
private func appendF64(_ buf: inout [UInt8], _ value: Double) {
    let bits = value.bitPattern
    buf.append(0x48)
    buf.append(UInt8(truncatingIfNeeded: bits >> 56))
    buf.append(UInt8(truncatingIfNeeded: bits >> 48))
    buf.append(UInt8(truncatingIfNeeded: bits >> 40))
    buf.append(UInt8(truncatingIfNeeded: bits >> 32))
    buf.append(UInt8(truncatingIfNeeded: bits >> 24))
    buf.append(UInt8(truncatingIfNeeded: bits >> 16))
    buf.append(UInt8(truncatingIfNeeded: bits >> 8))
    buf.append(UInt8(truncatingIfNeeded: bits))
}

private func appendString(_ buf: inout [UInt8], _ text: String) {
    let mark = buf.count
    buf.append(0)
    buf.append(contentsOf: text.utf8)
    let n = buf.count - mark - 1
    if n < 14 {
        buf[mark] = 0x80 | UInt8(n)
        return
    }
    let bytes = Array(buf[(mark + 1)...])
    buf.removeSubrange(mark...)
    buf.append(0x8E)
    appendVarUInt(&buf, n)
    buf.append(contentsOf: bytes)
}

private func sealBody(_ buf: inout [UInt8], _ mark: Int, _ tcode: Int) {
    let n = buf.count - mark - 1
    if n < 14 {
        buf[mark] = UInt8((tcode << 4) | n)
        return
    }
    buf[mark] = UInt8((tcode << 4) | 14)
    if n < 128 {
        buf.insert(UInt8(0x80 | n), at: mark + 1)
        return
    }
    var parts: [UInt8] = []
    var x = n
    while x > 0 {
        parts.append(UInt8(x & 0x7F))
        x >>= 7
    }
    var k = parts.count - 1
    var at = mark + 1
    while k >= 0 {
        var b = parts[k]
        if k == 0 { b |= 0x80 }
        buf.insert(b, at: at)
        at += 1
        k -= 1
    }
}

public enum IonTree: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case float(Double)
    case string(String)
    case list([IonTree])
    case fields([(String, IonTree)])

    public static func == (lhs: IonTree, rhs: IonTree) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            return true
        case (.bool(let a), .bool(let b)):
            return a == b
        case (.int(let a), .int(let b)):
            return a == b
        case (.float(let a), .float(let b)):
            return a == b
        case (.string(let a), .string(let b)):
            return a == b
        case (.list(let a), .list(let b)):
            return a == b
        case (.fields(let a), .fields(let b)):
            if a.count != b.count { return false }
            var i = 0
            while i < a.count {
                if a[i].0 != b[i].0 || a[i].1 != b[i].1 { return false }
                i += 1
            }
            return true
        default:
            return false
        }
    }
}

public func encodeTree(_ value: IonTree) -> [UInt8] {
    treeCache.lock.lock()
    defer { treeCache.lock.unlock() }
    return treeCache.encode(value)
}

public func decodeTree(_ raw: [UInt8]) throws -> IonTree {
    treeCache.lock.lock()
    defer { treeCache.lock.unlock() }
    return try treeCache.decode(raw)
}
