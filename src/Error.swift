public struct DecodeError: Error, Equatable, CustomStringConvertible {
    public static let kindEOF = 1
    public static let kindSyntax = 2
    public static let kindRange = 3
    public static let kindUTF8 = 4
    public static let kindEscape = 5
    public static let kindType = 6
    public static let kindDepth = 7
    public static let kindSymbol = 8
    public static let kindSchema = 9
    public static let kindVersion = 10

    public var kind: Int
    public var offset: Int
    public var field: Int

    public init(kind: Int, offset: Int, field: Int = 0) {
        self.kind = kind
        self.offset = offset
        self.field = field
    }

    public var description: String {
        "DecodeError(kind=\(kind), offset=\(offset), field=\(field))"
    }
}
