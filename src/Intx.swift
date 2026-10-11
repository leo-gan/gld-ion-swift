let limbBits = 32
let limbMask = UInt64(0xFFFF_FFFF)

public struct BigInt {
    public var neg: Bool
    public var limbs: [UInt32]

    public init() {
        neg = false
        limbs = []
    }

    public init(neg: Bool, limbs: [UInt32]) {
        self.neg = neg
        self.limbs = limbs
        trim()
        if self.limbs.isEmpty {
            self.neg = false
        }
    }

    public var isZero: Bool { limbs.isEmpty }

    public mutating func trim() {
        while let last = limbs.last, last == 0 {
            limbs.removeLast()
        }
    }

    public func cmpMag(_ other: BigInt) -> Int {
        if limbs.count != other.limbs.count {
            return limbs.count < other.limbs.count ? -1 : 1
        }
        var i = limbs.count - 1
        while i >= 0 {
            if limbs[i] < other.limbs[i] { return -1 }
            if limbs[i] > other.limbs[i] { return 1 }
            i -= 1
        }
        return 0
    }

    public func toI64(_ offset: Int) throws -> Int64 {
        if limbs.count > 2 {
            throw DecodeError(kind: DecodeError.kindRange, offset: offset)
        }
        var mag = UInt64(0)
        if limbs.count > 0 { mag = UInt64(limbs[0]) }
        if limbs.count > 1 { mag |= UInt64(limbs[1]) << 32 }
        if !neg {
            if mag > 0x7FFF_FFFF_FFFF_FFFF {
                throw DecodeError(kind: DecodeError.kindRange, offset: offset)
            }
            return Int64(mag)
        }
        if mag > 0x8000_0000_0000_0000 {
            throw DecodeError(kind: DecodeError.kindRange, offset: offset)
        }
        if mag == 0x8000_0000_0000_0000 {
            return Int64.min
        }
        return -Int64(mag)
    }

    public func toDec() -> String {
        String(decoding: toDecBytes(), as: UTF8.self)
    }

    public func toDecBytes() -> [UInt8] {
        if limbs.isEmpty { return [48] }
        var scratch = limbs
        var digits: [UInt8] = []
        while !scratch.isEmpty {
            var rem = UInt64(0)
            var j = scratch.count - 1
            while j >= 0 {
                let cur = (rem << 32) | UInt64(scratch[j])
                scratch[j] = UInt32(cur / 10)
                rem = cur % 10
                j -= 1
            }
            digits.append(UInt8(rem) + 48)
            while let last = scratch.last, last == 0 {
                scratch.removeLast()
            }
        }
        var out: [UInt8] = []
        if neg { out.append(45) }
        var k = digits.count - 1
        while k >= 0 {
            out.append(digits[k])
            k -= 1
        }
        return out
    }

    public mutating func mulSmall(_ m: UInt32) {
        if m == 0 || limbs.isEmpty {
            limbs.removeAll(keepingCapacity: true)
            neg = false
            return
        }
        var carry = UInt64(0)
        var i = 0
        while i < limbs.count {
            let cur = UInt64(limbs[i]) * UInt64(m) + carry
            limbs[i] = UInt32(truncatingIfNeeded: cur & limbMask)
            carry = cur >> 32
            i += 1
        }
        if carry != 0 {
            limbs.append(UInt32(truncatingIfNeeded: carry))
        }
    }

    public mutating func addSmall(_ m: UInt32) {
        var carry = UInt64(m)
        var i = 0
        while carry != 0 {
            if i == limbs.count {
                limbs.append(UInt32(truncatingIfNeeded: carry))
                return
            }
            let cur = UInt64(limbs[i]) + carry
            limbs[i] = UInt32(truncatingIfNeeded: cur & limbMask)
            carry = cur >> 32
            i += 1
        }
    }

    public func toBEBytes() -> [UInt8] {
        if limbs.isEmpty { return [] }
        var out: [UInt8] = []
        var started = false
        var i = limbs.count - 1
        while i >= 0 {
            let limb = limbs[i]
            var shift = 24
            while shift >= 0 {
                let b = UInt8((Int(limb) >> shift) & 0xFF)
                if started || b != 0 {
                    started = true
                    out.append(b)
                }
                shift -= 8
            }
            i -= 1
        }
        return out
    }
}

public func bigFromU64(_ v: UInt64, _ neg: Bool) -> BigInt {
    var limbs: [UInt32] = []
    let lo = UInt32(truncatingIfNeeded: v & limbMask)
    let hi = UInt32(truncatingIfNeeded: v >> 32)
    if lo != 0 || hi != 0 { limbs.append(lo) }
    if hi != 0 { limbs.append(hi) }
    let useNeg = neg && (lo != 0 || hi != 0)
    return BigInt(neg: useNeg, limbs: limbs)
}

public func bigFromDigits(_ digits: [UInt8], _ neg: Bool) -> BigInt {
    var acc = BigInt()
    var seen = false
    for b in digits {
        let d = Int(b) - 48
        if !seen && d == 0 { continue }
        seen = true
        acc.mulSmall(10)
        acc.addSmall(UInt32(d))
    }
    if !acc.limbs.isEmpty { acc.neg = neg }
    return acc
}

public func bigFromBE(_ raw: [UInt8], _ neg: Bool, _ offset: Int) throws -> BigInt {
    var start = 0
    while start < raw.count && raw[start] == 0 { start += 1 }
    if start == raw.count { return BigInt() }
    if raw.count - start > 1_048_576 {
        throw DecodeError(kind: DecodeError.kindRange, offset: offset)
    }
    var limbs: [UInt32] = []
    var pos = raw.count
    while pos > start {
        var take = pos - start
        if take > 4 { take = 4 }
        var chunk = UInt32(0)
        var k = 0
        while k < take {
            chunk = (chunk << 8) | UInt32(raw[pos - take + k])
            k += 1
        }
        limbs.append(chunk)
        pos -= take
    }
    return BigInt(neg: neg, limbs: limbs)
}

func bigFromLESigned(_ raw: [UInt8]) -> BigInt {
    if raw.isEmpty { return BigInt() }
    let neg = (raw[raw.count - 1] & 0x80) != 0
    if !neg {
        return (try? bigFromBE(Array(raw.reversed()), false, 0)) ?? BigInt()
    }
    var mag = raw
    var carry = 1
    var i = 0
    while i < mag.count {
        let inv = (Int(mag[i]) ^ 255) + carry
        mag[i] = UInt8(inv & 255)
        carry = inv >> 8
        i += 1
    }
    return (try? bigFromBE(Array(mag.reversed()), true, 0)) ?? BigInt()
}
