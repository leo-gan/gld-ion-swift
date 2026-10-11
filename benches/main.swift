import Dispatch
import Ion

func sample() -> IonDoc {
    let doc = IonDoc()
    var i = 0
    while i < 32 {
        let st = doc.startContainer(kStruct)
        let name = doc.addSymbolText("id")
        doc.addChild(st, doc.addI64(Int64(i)), doc.nodes[name].a)
        let label = doc.addSymbolText("name")
        doc.addChild(st, doc.addString("item"), doc.nodes[label].a)
        doc.addTop(st)
        i += 1
    }
    return doc
}

@main
struct Bench {
    static func main() throws {
        let doc = sample()
        let cat = Catalog()
        let opt = EncodeOptions(binary: true, pretty: false, version: 10)
        let textOpt = EncodeOptions(binary: false, pretty: false, version: 10)
        let n = 200
        var i = 0
        while i < 20 {
            _ = try encodeBinary(doc, opt, cat)
            _ = try encodeText(doc, textOpt)
            i += 1
        }
        var t0 = DispatchTime.now().uptimeNanoseconds
        i = 0
        while i < n {
            _ = try encodeBinary(doc, opt, cat)
            i += 1
        }
        let binNs = Int(DispatchTime.now().uptimeNanoseconds - t0) / n
        t0 = DispatchTime.now().uptimeNanoseconds
        i = 0
        while i < n {
            _ = try encodeText(doc, textOpt)
            i += 1
        }
        let textNs = Int(DispatchTime.now().uptimeNanoseconds - t0) / n
        let raw = try encodeBinary(doc, opt, cat)
        let text = try encodeText(doc, textOpt)
        let textBytes = Array(text.utf8)
        i = 0
        while i < 20 {
            _ = try decodeBinary(raw, cat)
            _ = try decodeText(textBytes, cat)
            i += 1
        }
        t0 = DispatchTime.now().uptimeNanoseconds
        i = 0
        while i < n {
            _ = try decodeBinary(raw, cat)
            i += 1
        }
        let decBin = Int(DispatchTime.now().uptimeNanoseconds - t0) / n
        t0 = DispatchTime.now().uptimeNanoseconds
        i = 0
        while i < n {
            _ = try decodeText(textBytes, cat)
            i += 1
        }
        let decText = Int(DispatchTime.now().uptimeNanoseconds - t0) / n
        print("binary_encode_ns \(binNs)")
        print("text_encode_ns \(textNs)")
        print("binary_decode_ns \(decBin)")
        print("text_decode_ns \(decText)")
        print("binary_bytes \(raw.count)")
        print("text_bytes \(textBytes.count)")
    }
}
