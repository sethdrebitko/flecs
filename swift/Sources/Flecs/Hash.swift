// Hash.swift - 1:1 translation of flecs hash.c (wyhash)
// High-quality hash function used throughout flecs

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


// Default secret parameters
private let wyp_: (UInt64, UInt64, UInt64, UInt64) = (
    0xa0761d6478bd642f, 0xe7037ed1a0b428db,
    0x8ebc6af09c88c6e3, 0x589965cc75374cc3
)

@inline(__always)
private func wymum_(_ A: inout UInt64, _ B: inout UInt64) {
    let r = A.multipliedFullWidth(by: B)
    A = r.low
    B = r.high
}

@inline(__always)
private func wymix_(_ A: UInt64, _ B: UInt64) -> UInt64 {
    var a = A, b = B
    wymum_(&a, &b)
    return a ^ b
}

@inline(__always)
private func wyr8_(_ p: UnsafePointer<UInt8>) -> UInt64 {
    var v: UInt64 = 0
    memcpy(&v, p, 8)
    return v
}

@inline(__always)
private func wyr4_(_ p: UnsafePointer<UInt8>) -> UInt64 {
    var v: UInt32 = 0
    memcpy(&v, p, 4)
    return UInt64(v)
}

@inline(__always)
private func wyr3_(_ p: UnsafePointer<UInt8>, _ k: Int) -> UInt64 {
    return (UInt64(p[0]) << 16) | (UInt64(p[k >> 1]) << 8) | UInt64(p[k - 1])
}

private func wyhash(_ key: UnsafeRawPointer, _ len: Int, _ seed_in: UInt64) -> UInt64 {
    let p = key.assumingMemoryBound(to: UInt8.self)
    var seed = seed_in ^ wymix_(seed_in ^ wyp_.0, wyp_.1)
    var a: UInt64, b: UInt64

    if len <= 16 {
        if len >= 4 {
            a = (wyr4_(p) << 32) | wyr4_(p + ((len >> 3) << 2))
            b = (wyr4_(p + len - 4) << 32) | wyr4_(p + len - 4 - ((len >> 3) << 2))
        } else if len > 0 {
            a = wyr3_(p, len)
            b = 0
        } else {
            a = 0; b = 0
        }
    } else {
        var i = len
        var pp = p
        if i > 48 {
            var see1 = seed, see2 = seed
            repeat {
                seed = wymix_(wyr8_(pp) ^ wyp_.1, wyr8_(pp + 8) ^ seed)
                see1 = wymix_(wyr8_(pp + 16) ^ wyp_.2, wyr8_(pp + 24) ^ see1)
                see2 = wymix_(wyr8_(pp + 32) ^ wyp_.3, wyr8_(pp + 40) ^ see2)
                pp += 48; i -= 48
            } while i > 48
            seed ^= see1 ^ see2
        }
        while i > 16 {
            seed = wymix_(wyr8_(pp) ^ wyp_.1, wyr8_(pp + 8) ^ seed)
            i -= 16; pp += 16
        }
        a = wyr8_(pp + i - 16)
        b = wyr8_(pp + i - 8)
    }

    a ^= wyp_.1; b ^= seed; wymum_(&a, &b)
    return wymix_(a ^ wyp_.0 ^ UInt64(len), b ^ wyp_.1)
}


/// Hash arbitrary data using wyhash. This replaces the FNV-1a implementation
/// in Misc.swift with the production wyhash used by the C codebase.
public func flecs_wyhash(
    _ data: UnsafeRawPointer?,
    _ length: ecs_size_t) -> UInt64
{
    if data == nil || length <= 0 { return 0 }
    return wyhash(data!, Int(length), 0)
}
