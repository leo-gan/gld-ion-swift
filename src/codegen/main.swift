import Foundation
import Ion

func usage() {
    print("gld-iongen-swift --schema FILE --out DIR")
}

@main
struct Main {
    static func main() {
        let args = CommandLine.arguments
        var outDir = ""
        var schemaPath = ""
        var i = 1
        while i < args.count {
            if args[i] == "--out" && i + 1 < args.count {
                i += 1
                outDir = args[i]
            } else if args[i] == "--schema" && i + 1 < args.count {
                i += 1
                schemaPath = args[i]
            } else if args[i] == "--help" || args[i] == "-h" {
                usage()
                return
            }
            i += 1
        }
        if outDir.isEmpty || schemaPath.isEmpty {
            usage()
            exit(2)
        }
        do {
            let schema = try parseSchemaFile(schemaPath)
            let files = try emitAll(schema)
            try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
            for (name, source) in files {
                let path = outDir + "/" + name + ".swift"
                try source.write(toFile: path, atomically: true, encoding: .utf8)
                print("wrote \(path)")
            }
        } catch {
            print("gld-iongen-swift: \(error)")
            exit(1)
        }
    }
}
