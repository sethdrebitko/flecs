// Bitset.swift - 1:1 translation of flecs bitset.c
// Simple bitset implementation for compact boolean storage

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


public struct ecs_bitset_t {
    public var data: UnsafeMutablePointer<UInt64>?
    public var count: Int32
    public var size: ecs_size_t

    public init() {
        self.data = nil
        self.count = 0
        self.size = 0
    }
}


private func flecs_bitset_ensure_size(
    _ bs: UnsafeMutablePointer<ecs_bitset_t>,
    _ size: ecs_size_t)
{
    if bs.pointee.size == 0 {
        let new_size = Int(((size - 1) / 64 + 1)) * MemoryLayout<UInt64>.stride
        bs.pointee.size = ((size - 1) / 64 + 1) * 64
        bs.pointee.data = calloc(1, new_size)?.bindMemory(
            to: UInt64.self, capacity: new_size / MemoryLayout<UInt64>.stride)
    } else if size > bs.pointee.size {
        let prev_size = Int(((bs.pointee.size - 1) / 64 + 1)) * MemoryLayout<UInt64>.stride
        bs.pointee.size = ((size - 1) / 64 + 1) * 64
        let new_size = Int(((size - 1) / 64 + 1)) * MemoryLayout<UInt64>.stride
        bs.pointee.data = realloc(bs.pointee.data, new_size)?.bindMemory(
            to: UInt64.self, capacity: new_size / MemoryLayout<UInt64>.stride)
        memset(UnsafeMutableRawPointer(bs.pointee.data!).advanced(by: prev_size), 0, new_size - prev_size)
    }
}


public func flecs_bitset_init(
    _ bs: UnsafeMutablePointer<ecs_bitset_t>)
{
    bs.pointee.size = 0
    bs.pointee.count = 0
    bs.pointee.data = nil
}

public func flecs_bitset_ensure(
    _ bs: UnsafeMutablePointer<ecs_bitset_t>,
    _ count: Int32)
{
    if count > bs.pointee.count {
        bs.pointee.count = count
        flecs_bitset_ensure_size(bs, count)
    }
}

public func flecs_bitset_fini(
    _ bs: UnsafeMutablePointer<ecs_bitset_t>)
{
    free(bs.pointee.data)
    bs.pointee.data = nil
    bs.pointee.count = 0
}

public func flecs_bitset_addn(
    _ bs: UnsafeMutablePointer<ecs_bitset_t>,
    _ count: Int32)
{
    bs.pointee.count += count
    flecs_bitset_ensure_size(bs, bs.pointee.count)
}

public func flecs_bitset_set(
    _ bs: UnsafeMutablePointer<ecs_bitset_t>,
    _ elem: Int32,
    _ value: Bool)
{
    let hi = UInt32(bitPattern: elem) >> 6
    let lo = UInt32(bitPattern: elem) & 0x3F
    let v = bs.pointee.data![Int(hi)]
    bs.pointee.data![Int(hi)] = (v & ~(UInt64(1) << lo)) | (UInt64(value ? 1 : 0) << lo)
}

public func flecs_bitset_get(
    _ bs: UnsafePointer<ecs_bitset_t>,
    _ elem: Int32) -> Bool
{
    return (bs.pointee.data![Int(elem >> 6)] & (UInt64(1) << (UInt64(elem) & 0x3F))) != 0
}

public func flecs_bitset_count(
    _ bs: UnsafePointer<ecs_bitset_t>) -> Int32
{
    return bs.pointee.count
}

public func flecs_bitset_remove(
    _ bs: UnsafeMutablePointer<ecs_bitset_t>,
    _ elem: Int32)
{
    let last = bs.pointee.count - 1
    let last_value = flecs_bitset_get(UnsafePointer(bs), last)
    flecs_bitset_set(bs, elem, last_value)
    flecs_bitset_set(bs, last, false)
    bs.pointee.count -= 1
}

public func flecs_bitset_swap(
    _ bs: UnsafeMutablePointer<ecs_bitset_t>,
    _ elem_a: Int32,
    _ elem_b: Int32)
{
    let a = flecs_bitset_get(UnsafePointer(bs), elem_a)
    let b = flecs_bitset_get(UnsafePointer(bs), elem_b)
    flecs_bitset_set(bs, elem_a, b)
    flecs_bitset_set(bs, elem_b, a)
}
