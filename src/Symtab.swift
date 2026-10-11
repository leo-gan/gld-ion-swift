let sysMax = 9

func sysName(_ sid: Int) -> String {
    switch sid {
    case 1: return "$ion"
    case 2: return "$ion_1_0"
    case 3: return "$ion_symbol_table"
    case 4: return "name"
    case 5: return "version"
    case 6: return "imports"
    case 7: return "symbols"
    case 8: return "max_id"
    case 9: return "$ion_shared_symbol_table"
    default: return ""
    }
}

func sysSid(_ text: String) -> Int {
    switch text {
    case "$ion": return 1
    case "$ion_1_0": return 2
    case "$ion_symbol_table": return 3
    case "name": return 4
    case "version": return 5
    case "imports": return 6
    case "symbols": return 7
    case "max_id": return 8
    case "$ion_shared_symbol_table": return 9
    default: return 0
    }
}

public struct SharedTable {
    public var name: String
    public var version: Int
    public var texts: [String]
    public var gap: [Bool]

    public init(name: String, version: Int) {
        self.name = name
        self.version = version
        texts = []
        gap = []
    }

    public mutating func add(_ text: String, _ isGap: Bool) {
        texts.append(text)
        gap.append(isGap)
    }
}

public final class Catalog {
    public var tables: [SharedTable] = []

    public init() {}

    public func add(_ table: SharedTable) {
        tables.append(table)
    }

    public func exact(_ name: String, _ version: Int) -> Int {
        for i in tables.indices where tables[i].name == name && tables[i].version == version {
            return i
        }
        return -1
    }

    public func greatest(_ name: String) -> Int {
        var best = -1
        var bestVer = -1
        for i in tables.indices where tables[i].name == name && tables[i].version > bestVer {
            best = i
            bestVer = tables[i].version
        }
        return best
    }
}

struct TabSeg {
    var start = 0
    var count = 0
    var flatAt = -1
    var flatN = 0
    var nameAt = -1
}

struct Resolved {
    var known = false
    var text = ""
    var imp = ""
    var impSid = 0
}

final class LocalTab {
    var text: [String] = [""]
    var known: [Bool] = [false]
    var names: [String] = []
    var segs: [TabSeg] = []
    var maxId: Int

    init() {
        maxId = sysMax
        var seg = TabSeg()
        seg.start = 1
        seg.count = sysMax
        seg.flatAt = 1
        seg.flatN = 0
        segs.append(seg)
    }

    func resetSystem() {
        if segs.count > 1 { segs.removeLast(segs.count - 1) }
        if text.count > 1 {
            text.removeLast(text.count - 1)
            known.removeLast(known.count - 1)
        }
        maxId = sysMax
        segs[0].count = sysMax
        segs[0].flatN = 0
    }

    func _addFlat(_ textIn: String, _ isKnown: Bool) -> Int {
        let lastI = segs.count - 1
        var last = segs[lastI]
        if last.nameAt < 0 && last.start + last.count == maxId + 1 && lastI > 0 {
            text.append(textIn)
            known.append(isKnown)
            last.count += 1
            last.flatN += 1
            segs[lastI] = last
            maxId += 1
            return maxId
        }
        var seg = TabSeg()
        seg.start = maxId + 1
        seg.count = 1
        seg.flatAt = text.count
        seg.flatN = 1
        text.append(textIn)
        known.append(isKnown)
        segs.append(seg)
        maxId += 1
        return maxId
    }

    func addText(_ textIn: String) -> Int { _addFlat(textIn, true) }

    func addGap() -> Int { _addFlat("", false) }

    func sidOf(_ textIn: String) -> Int {
        let sys = sysSid(textIn)
        if sys != 0 { return sys }
        for seg in segs where seg.flatN > 0 {
            var i = 0
            while i < seg.flatN {
                let at = seg.flatAt + i
                if known[at] && text[at] == textIn { return seg.start + i }
                i += 1
            }
        }
        return 0
    }

    func lookup(_ sid: Int, _ offset: Int) throws -> Resolved {
        var out = Resolved()
        if sid < 0 || sid > maxId {
            throw DecodeError(kind: DecodeError.kindSymbol, offset: offset)
        }
        if sid == 0 { return out }
        if sid <= sysMax {
            out.known = true
            out.text = sysName(sid)
            return out
        }
        for seg in segs where sid >= seg.start && sid < seg.start + seg.count {
            let off = sid - seg.start
            if seg.nameAt < 0 {
                let at = seg.flatAt + off
                if known[at] {
                    out.known = true
                    out.text = text[at]
                }
                return out
            }
            if off < seg.flatN && known[seg.flatAt + off] {
                out.known = true
                out.text = text[seg.flatAt + off]
                return out
            }
            out.imp = names[seg.nameAt]
            out.impSid = off + 1
            return out
        }
        throw DecodeError(kind: DecodeError.kindSymbol, offset: offset)
    }

    func importTable(_ table: SharedTable, _ maxIdIn: Int, _ offset: Int) throws {
        if maxIdIn < 0 {
            throw DecodeError(kind: DecodeError.kindSymbol, offset: offset)
        }
        var prefix = table.texts.count
        if prefix > maxIdIn { prefix = maxIdIn }
        var seg = TabSeg()
        seg.start = maxId + 1
        seg.count = maxIdIn
        seg.nameAt = names.count
        names.append(table.name)
        if prefix > 0 {
            seg.flatAt = text.count
            seg.flatN = prefix
            var i = 0
            while i < prefix {
                if table.gap[i] {
                    text.append("")
                    known.append(false)
                } else {
                    text.append(table.texts[i])
                    known.append(true)
                }
                i += 1
            }
        }
        segs.append(seg)
        maxId += maxIdIn
    }
}
