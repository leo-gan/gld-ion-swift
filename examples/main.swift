import Foundation
import Ion

@main
struct EncodeValue {
    static func main() throws {
        let cat = Catalog()
        let doc = try decode(Array("{a:1,b:\"hi\"}\n".utf8), cat)
        let text = try encode(doc, EncodeOptions(binary: false, pretty: false, version: 10), cat)
        let binary = try encode(doc, EncodeOptions(binary: true, pretty: false, version: 11), cat)
        print("text bytes \(text.count)")
        print("ion 1.1 binary bytes \(binary.count)")
    }
}
