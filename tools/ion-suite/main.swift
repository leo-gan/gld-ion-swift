import Foundation
import Ion

func fail(_ msg: String) -> Never {
    print("FAIL \(msg)")
    exit(1)
}

func ann0(_ doc: IonDoc, _ id: Int) -> String {
    let n = doc.nodes[id]
    if n.annN == 0 { return "" }
    return doc.symText(doc.anns[n.ann])
}

func field(_ doc: IonDoc, _ id: Int, _ name: String) -> Int {
    var i = 0
    while i < doc.nodes[id].nchild {
        let sym = doc.fieldAt(id, i)
        let s = doc.syms[sym]
        if s.text >= 0 && doc.texts[s.text] == name { return doc.childAt(id, i) }
        i += 1
    }
    return -1
}

func asInt(_ doc: IonDoc, _ id: Int) -> Int {
    let n = doc.nodes[id]
    if n.kind != kInt || n.b > 2 || n.c != 0 { return 1 }
    var mag = 0
    if n.b > 0 { mag = Int(doc.limbs[n.a]) }
    if n.b > 1 { mag += Int(doc.limbs[n.a + 1]) * 4_294_967_296 }
    return mag
}

func loadCatalog(_ doc: IonDoc) -> Catalog {
    let cat = Catalog()
    for id in doc.top {
        if ann0(doc, id) == "$ion_shared_symbol_table" && doc.nodes[id].kind == kStruct {
            let nameId = field(doc, id, "name")
            if nameId >= 0 && doc.nodes[nameId].kind == kString {
                var version = 1
                let ver = field(doc, id, "version")
                if ver >= 0 && doc.nodes[ver].kind == kInt { version = asInt(doc, ver) }
                var table = SharedTable(name: doc.textAt(nameId), version: version)
                let syms = field(doc, id, "symbols")
                if syms >= 0 && doc.nodes[syms].kind == kList {
                    var k = 0
                    while k < doc.nodes[syms].nchild {
                        let el = doc.childAt(syms, k)
                        if doc.nodes[el].kind == kString {
                            table.add(doc.textAt(el), false)
                        } else {
                            table.add("", true)
                        }
                        k += 1
                    }
                }
                cat.add(table)
            }
        }
    }
    return cat
}

func embedded(_ doc: IonDoc, _ id: Int) -> Bool {
    let n = doc.nodes[id]
    if n.annN == 0 { return false }
    return doc.symText(doc.anns[n.ann]) == "embedded_documents"
}

func seqOK(_ doc: IonDoc, _ id: Int, _ wantEq: Bool, _ cat: Catalog) -> Bool {
    let n = doc.nodes[id]
    if n.kind != kList && n.kind != kSexp { return false }
    if n.nchild < 2 { return false }
    if embedded(doc, id) {
        var first: IonDoc?
        var i = 0
        while i < n.nchild {
            let el = doc.childAt(id, i)
            if doc.nodes[el].kind != kString { return false }
            let text = Array(doc.textAt(el).utf8)
            guard let got = try? decodeText(text, cat) else { return false }
            if i == 0 {
                first = got
            } else if let first {
                let eq = docsEq(first, got)
                if wantEq && !eq { return false }
                if !wantEq && eq { return false }
            }
            i += 1
        }
        return true
    }
    var i = 1
    while i < n.nchild {
        let eq = ionEq(doc, doc.childAt(id, 0), doc, doc.childAt(id, i))
        if wantEq && !eq { return false }
        if !wantEq && eq { return false }
        i += 1
    }
    if !wantEq {
        var a = 0
        while a < n.nchild {
            var b = a + 1
            while b < n.nchild {
                if ionEq(doc, doc.childAt(id, a), doc, doc.childAt(id, b)) { return false }
                b += 1
            }
            a += 1
        }
    }
    return true
}

func checkFile(_ path: String, _ cat: Catalog) -> Bool {
    let expectBad = path.contains("/bad/")
    let equiv = path.contains("/equivs/")
    let noneq = path.contains("/non-equivs/")
    let binary = path.hasSuffix(".10n")
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let doc = try (binary ? decodeBinary([UInt8](data), cat) : decodeText([UInt8](data), cat))
        if expectBad {
            print("decoded bad \(path)")
            return false
        }
        if equiv || noneq {
            if doc.top.isEmpty { return false }
            for id in doc.top where !seqOK(doc, id, equiv, cat) {
                print("seq \(path) kind \(doc.nodes[id].kind) n \(doc.nodes[id].nchild)")
                return false
            }
            return true
        }
        return true
    } catch {
        if !expectBad { print("throw \(path) \(error)") }
        return expectBad
    }
}

@main
struct Suite {
    static func main() {
        let args = CommandLine.arguments
        let root = FileManager.default.currentDirectoryPath
        let catPath = args.count >= 3 ? args[2] : root + "/testdata/ion-tests/catalog/catalog.ion"
        guard let catData = try? Data(contentsOf: URL(fileURLWithPath: catPath)),
              let catDoc = try? decodeText([UInt8](catData), Catalog())
        else { fail("catalog") }
        let cat = loadCatalog(catDoc)
        if args.count >= 2 && args[1] != "--all" {
            if checkFile(args[1], cat) {
                print("OK")
            } else {
                print("FAIL")
                fail(args[1])
            }
            return
        }
        let base = root + "/testdata/ion-tests/iontestdata"
        guard let en = FileManager.default.enumerator(atPath: base) else { fail("enum") }
        var paths: [String] = []
        while let rel = en.nextObject() as? String {
            if rel.hasSuffix(".ion") || rel.hasSuffix(".10n") {
                paths.append(base + "/" + rel)
            }
        }
        paths.sort()
        var bad = 0
        for path in paths where !checkFile(path, cat) {
            print("FAIL \(path)")
            bad += 1
        }
        print("ion-tests checked \(paths.count) fail \(bad)")
        if bad != 0 { exit(1) }
    }
}
