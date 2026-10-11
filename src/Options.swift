public struct EncodeOptions {
    public var binary: Bool
    public var pretty: Bool
    public var version: Int
    public var importNames: [String]
    public var importVersions: [Int]

    public init(binary: Bool = false, pretty: Bool = false, version: Int = 10) {
        self.binary = binary
        self.pretty = pretty
        self.version = version
        importNames = []
        importVersions = []
    }

    public mutating func addImport(_ name: String, _ version: Int) {
        importNames.append(name)
        importVersions.append(version)
    }
}
