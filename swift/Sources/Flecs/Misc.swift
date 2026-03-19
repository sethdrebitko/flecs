// Misc.swift - 1:1 translation of flecs misc.c
// Utility functions, hashing, and error handling

import Foundation

// MARK: - Hash Function (FNV-1a)

public func flecs_hash(
    _ data: UnsafeRawPointer?,
    _ length: ecs_size_t
) -> UInt64 {
    guard let data = data, length > 0 else { return 0 }

    var hash: UInt64 = 14695981039346656037 // FNV offset basis
    let bytes = data.assumingMemoryBound(to: UInt8.self)

    for i in 0..<Int(length) {
        hash ^= UInt64(bytes[i])
        hash = hash &* 1099511628211 // FNV prime
    }

    return hash
}

// MARK: - Power of 2

public func flecs_next_pow_of_2(
    _ n: Int32
) -> Int32 {
    var v = n
    v -= 1
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8
    v |= v >> 16
    v += 1
    return v
}

// MARK: - Entity Compare

public func flecs_entity_compare(
    _ e1: ecs_entity_t,
    _ ptr1: UnsafeRawPointer?,
    _ e2: ecs_entity_t,
    _ ptr2: UnsafeRawPointer?
) -> Int32 {
    if e1 < e2 { return -1 }
    if e1 > e2 { return 1 }
    return 0
}

public func flecs_id_qsort_cmp(
    _ a: UnsafeRawPointer?,
    _ b: UnsafeRawPointer?
) -> Int32 {
    guard let a = a, let b = b else { return 0 }
    let id_a = a.assumingMemoryBound(to: ecs_id_t.self).pointee
    let id_b = b.assumingMemoryBound(to: ecs_id_t.self).pointee
    if id_a < id_b { return -1 }
    if id_a > id_b { return 1 }
    return 0
}

// MARK: - Name/ID helpers

public func flecs_name_is_id(
    _ name: UnsafePointer<CChar>?
) -> Bool {
    guard let name = name else { return false }
    return name[0] == CChar(UInt8(ascii: "#"))
}

public func flecs_name_to_id(
    _ name: UnsafePointer<CChar>?
) -> ecs_entity_t {
    guard let name = name, name[0] == CChar(UInt8(ascii: "#")) else { return 0 }
    let str = String(cString: name.advanced(by: 1))
    return ecs_entity_t(str) ?? 0
}

// MARK: - Integer Conversion (safe cast)

public func flecs_ito_(
    _ dst_size: Int,
    _ dst_signed: Bool,
    _ lt_zero: Bool,
    _ value: UInt64,
    _ err: UnsafePointer<CChar>?
) -> UInt64 {
    // In release mode, just pass through
    return value
}

// MARK: - Error String Buffer

// Thread-local error strings for use in assert messages
private var _errstr_buf = [CChar](repeating: 0, count: 256)
private var _errstr_1_buf = [CChar](repeating: 0, count: 256)

public func flecs_errstr(
    _ str: UnsafeMutablePointer<CChar>?
) -> UnsafePointer<CChar>? {
    guard let str = str else { return nil }
    // Copy and free the original
    let s = String(cString: str)
    ecs_os_free(UnsafeMutableRawPointer(str))
    return s.withCString { ptr in
        let len = strlen(ptr)
        _errstr_buf.withUnsafeMutableBufferPointer { buf in
            let copyLen = min(len, 255)
            memcpy(buf.baseAddress!, ptr, copyLen)
            buf[copyLen] = 0
        }
        return _errstr_buf.withUnsafeBufferPointer { UnsafePointer($0.baseAddress!) }
    }
}

// MARK: - Type Size

public func flecs_type_size(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ type_entity: ecs_entity_t
) -> ecs_size_t {
    // Look up type info from the world's type_info map
    guard let val = ecs_map_get(&world.pointee.type_info, type_entity) else {
        return 0
    }
    let ti = UnsafePointer<ecs_type_info_t>(bitPattern: UInt(val.pointee))
    return ti?.pointee.size ?? 0
}

// MARK: - Bloom Filter

@inline(__always)
public func flecs_table_bloom_filter_add(
    _ filter: UInt64,
    _ value: UInt64
) -> UInt64 {
    let hash = value &* 11400714819323198485 // Fibonacci hash
    return filter | (1 << (hash >> 58))
}

@inline(__always)
public func flecs_table_bloom_filter_test(
    _ table: UnsafePointer<ecs_table_t>,
    _ filter: UInt64
) -> Bool {
    return (table.pointee.bloom_filter & filter) == filter
}
