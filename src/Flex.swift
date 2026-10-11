func flexUInt(_ raw: [UInt8], _ i: inout Int) throws -> Int {
    let start = i
    var acc = UInt64(0)
    var shift = UInt64(0)
    var nread = 0
    while nread < 8 {
        if i >= raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: start) }
        let b = UInt64(raw[i])
        i += 1
        nread += 1
        acc |= b << shift
        shift += 8
        if acc == 0 { continue }
        var low = 0
        var probe = acc
        while (probe & 1) == 0 {
            probe >>= 1
            low += 1
        }
        let width = low + 1
        if nread >= width {
            return Int(acc >> UInt64(width))
        }
    }
    throw DecodeError(kind: DecodeError.kindRange, offset: start)
}

func flexInt(_ raw: [UInt8], _ i: inout Int) throws -> Int {
    let start = i
    var acc = UInt64(0)
    var shift = UInt64(0)
    var nread = 0
    while nread < 8 {
        if i >= raw.count { throw DecodeError(kind: DecodeError.kindEOF, offset: start) }
        let b = UInt64(raw[i])
        i += 1
        nread += 1
        acc |= b << shift
        shift += 8
        if acc == 0 { continue }
        var low = 0
        var probe = acc
        while (probe & 1) == 0 {
            probe >>= 1
            low += 1
        }
        let width = low + 1
        if nread >= width {
            let magBits = 7 * width
            let mag = acc >> UInt64(width)
            let signbit = UInt64(1) << UInt64(magBits - 1)
            if (mag & signbit) != 0 {
                let full = (UInt64(1) << UInt64(magBits)) - mag
                return -Int(full)
            }
            return Int(mag)
        }
    }
    throw DecodeError(kind: DecodeError.kindRange, offset: start)
}

func writeFlexInt(_ buf: inout [UInt8], _ v: Int) {
    var n = 1
    while n < 8 {
        let half = UInt64(1) << UInt64(7 * n - 1)
        let minN = -Int(half)
        let maxN = Int(half - 1)
        if v >= minN && v <= maxN { break }
        n += 1
    }
    let mask = (UInt64(1) << UInt64(7 * n)) - UInt64(1)
    let pattern = UInt64(bitPattern: Int64(v)) & mask
    var bits = pattern << UInt64(n)
    bits |= UInt64(1) << UInt64(n - 1)
    var k = 0
    while k < n {
        buf.append(UInt8((bits >> UInt64(k * 8)) & 255))
        k += 1
    }
}

func writeFlexUInt(_ buf: inout [UInt8], _ v: Int) {
    var n = 1
    var limit = 128
    var x = v
    if x < 0 { x = 0 }
    while x >= limit && n < 8 {
        n += 1
        limit *= 128
    }
    var bits = UInt64(x) << UInt64(n)
    bits |= UInt64(1) << UInt64(n - 1)
    var k = 0
    while k < n {
        buf.append(UInt8((bits >> UInt64(k * 8)) & 255))
        k += 1
    }
}

func fixedInt(_ raw: [UInt8], _ i: inout Int, _ n: Int) throws -> Int {
    if n == 0 { return 0 }
    if n < 0 || n > 8 || i + n > raw.count {
        if n > 8 { throw DecodeError(kind: DecodeError.kindRange, offset: i) }
        throw DecodeError(kind: DecodeError.kindEOF, offset: i)
    }
    var acc = UInt64(0)
    var k = 0
    while k < n {
        acc |= UInt64(raw[i + k]) << (k * 8)
        k += 1
    }
    i += n
    if n == 8 { return Int(Int64(bitPattern: acc)) }
    let sign = UInt64(1) << (n * 8 - 1)
    if (acc & sign) != 0 {
        let mod = UInt64(1) << (n * 8)
        return Int(acc) - Int(mod)
    }
    return Int(acc)
}

func takeUTF(_ raw: [UInt8], _ i: inout Int, _ n: Int) throws -> String {
    if n < 0 || i + n > raw.count {
        throw DecodeError(kind: DecodeError.kindEOF, offset: i)
    }
    let start = i
    i += n
    return try stringFromBytes(Array(raw[start..<i]), start)
}
