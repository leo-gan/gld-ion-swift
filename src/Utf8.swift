func validateUTF8(_ span: some Collection<UInt8>, _ offset: Int) throws {
    let bytes = Array(span)
    var i = 0
    let n = bytes.count
    while i < n {
        let c = Int(bytes[i])
        if c < 0x80 {
            i += 1
            continue
        }
        let need: Int
        var cp: Int
        let minCP: Int
        if c >= 0xC2 && c <= 0xDF {
            need = 1
            cp = c & 0x1F
            minCP = 0x80
        } else if c >= 0xE0 && c <= 0xEF {
            need = 2
            cp = c & 0x0F
            minCP = 0x800
        } else if c >= 0xF0 && c <= 0xF4 {
            need = 3
            cp = c & 0x07
            minCP = 0x10000
        } else {
            throw DecodeError(kind: DecodeError.kindUTF8, offset: offset + i)
        }
        if i + need >= n {
            throw DecodeError(kind: DecodeError.kindUTF8, offset: offset + i)
        }
        var k = 0
        while k < need {
            i += 1
            let cc = Int(bytes[i])
            if (cc & 0xC0) != 0x80 {
                throw DecodeError(kind: DecodeError.kindUTF8, offset: offset + i)
            }
            cp = (cp << 6) | (cc & 0x3F)
            k += 1
        }
        if cp < minCP || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
            throw DecodeError(kind: DecodeError.kindUTF8, offset: offset + i)
        }
        i += 1
    }
}

func stringFromBytes(_ bytes: [UInt8], _ offset: Int) throws -> String {
    try validateUTF8(bytes, offset)
    return String(decoding: bytes, as: UTF8.self)
}

func appendUTF8(_ buf: inout [UInt8], _ cp: Int, _ offset: Int) throws {
    if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
        throw DecodeError(kind: DecodeError.kindEscape, offset: offset)
    }
    if cp < 0x80 {
        buf.append(UInt8(cp))
        return
    }
    if cp < 0x800 {
        buf.append(UInt8(0xC0 | (cp >> 6)))
        buf.append(UInt8(0x80 | (cp & 0x3F)))
        return
    }
    if cp < 0x10000 {
        buf.append(UInt8(0xE0 | (cp >> 12)))
        buf.append(UInt8(0x80 | ((cp >> 6) & 0x3F)))
        buf.append(UInt8(0x80 | (cp & 0x3F)))
        return
    }
    buf.append(UInt8(0xF0 | (cp >> 18)))
    buf.append(UInt8(0x80 | ((cp >> 12) & 0x3F)))
    buf.append(UInt8(0x80 | ((cp >> 6) & 0x3F)))
    buf.append(UInt8(0x80 | (cp & 0x3F)))
}

func utf8Bytes(_ text: String) -> [UInt8] {
    Array(text.utf8)
}
