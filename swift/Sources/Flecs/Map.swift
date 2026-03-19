/// Map.swift
/// Translation of ecs_map_t and its operations from flecs.
/// Hash map with uint64 keys and uint64 values.

import Foundation

// MARK: - Types

/// Map key type.
public typealias ecs_map_key_t = UInt64

/// Map value type.
public typealias ecs_map_val_t = UInt64

/// Map data type (used for key-value storage).
public typealias ecs_map_data_t = UInt64

/// A single entry in a map bucket (linked list node).
public struct ecs_bucket_entry_t {
    public var key: ecs_map_key_t
    public var value: ecs_map_val_t
    public var next: UnsafeMutablePointer<ecs_bucket_entry_t>?

    public init() {
        self.key = 0
        self.value = 0
        self.next = nil
    }
}

/// A bucket in the map hash table.
public struct ecs_bucket_t {
    public var first: UnsafeMutablePointer<ecs_bucket_entry_t>?

    public init() {
        self.first = nil
    }
}

/// A hashmap data structure.
/// The C struct uses bitfields (count:26, bucket_shift:6). We pack them into a UInt32.
public struct ecs_map_t {
    public var buckets: UnsafeMutablePointer<ecs_bucket_t>?
    public var bucket_count: Int32
    /// Packed bitfield: lower 26 bits = count, upper 6 bits = bucket_shift
    public var count_and_shift: UInt32
    public var allocator: UnsafeMutablePointer<ecs_allocator_t>?

    public init() {
        self.buckets = nil
        self.bucket_count = 0
        self.count_and_shift = 0
        self.allocator = nil
    }

    /// Number of elements in the map (26-bit field).
    public var count: Int32 {
        get { return Int32(count_and_shift & 0x03FF_FFFF) }
        set {
            let shift = count_and_shift & 0xFC00_0000
            count_and_shift = shift | (UInt32(newValue) & 0x03FF_FFFF)
        }
    }

    /// Bit shift for bucket index computation (6-bit field).
    public var bucket_shift: UInt32 {
        get { return (count_and_shift >> 26) & 0x3F }
        set {
            let cnt = count_and_shift & 0x03FF_FFFF
            count_and_shift = cnt | ((newValue & 0x3F) << 26)
        }
    }
}

/// Iterator for traversing map contents.
public struct ecs_map_iter_t {
    public var map: UnsafePointer<ecs_map_t>?
    public var bucket: UnsafeMutablePointer<ecs_bucket_t>?
    public var entry: UnsafeMutablePointer<ecs_bucket_entry_t>?
    public var res: UnsafeMutablePointer<ecs_map_data_t>?

    public init() {
        self.map = nil
        self.bucket = nil
        self.entry = nil
        self.res = nil
    }
}

// MARK: - Internal helpers

@inline(__always)
internal func flecs_log2(_ v: UInt32) -> UInt8 {
    let log2table: [UInt8] = [
        0, 9,  1,  10, 13, 21, 2,  29, 11, 14, 16, 18, 22, 25, 3, 30,
        8, 12, 20, 28, 15, 17, 24, 7,  19, 27, 23, 6,  26, 5,  4, 31
    ]
    var v = v
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8
    v |= v >> 16
    return log2table[Int((v &* 0x07C4ACDD) >> 27)]
}

private let ECS_LOAD_FACTOR: Int32 = 12

@inline(__always)
internal func flecs_map_get_bucket_count(_ count: Int32) -> Int32 {
    return flecs_next_pow_of_2(Int32(Double(count) * Double(ECS_LOAD_FACTOR) * 0.1))
}

@inline(__always)
internal func flecs_map_get_bucket_shift(_ bucket_count: Int32) -> UInt8 {
    return UInt8(64 &- flecs_log2(UInt32(bucket_count)))
}

@inline(__always)
internal func flecs_map_get_bucket_index(_ bucket_shift: UInt16, _ key: ecs_map_key_t) -> Int32 {
    return Int32((11400714819323198485 &* key) >> UInt64(bucket_shift))
}

internal func flecs_map_get_bucket(
    _ map: UnsafePointer<ecs_map_t>,
    _ key: ecs_map_key_t) -> UnsafeMutablePointer<ecs_bucket_t>
{
    let bucket_id = flecs_map_get_bucket_index(
        UInt16(map.pointee.bucket_shift), key)
    return map.pointee.buckets!.advanced(by: Int(bucket_id))
}

internal func flecs_map_bucket_add(
    _ a: UnsafeMutablePointer<ecs_allocator_t>?,
    _ bucket: UnsafeMutablePointer<ecs_bucket_t>,
    _ key: ecs_map_key_t) -> UnsafeMutablePointer<ecs_map_val_t>
{
    let new_entry = UnsafeMutablePointer<ecs_bucket_entry_t>.allocate(capacity: 1)
    new_entry.pointee.key = key
    new_entry.pointee.value = 0
    new_entry.pointee.next = bucket.pointee.first
    bucket.pointee.first = new_entry
    return withUnsafeMutablePointer(to: &new_entry.pointee.value) { $0 }
}

internal func flecs_map_bucket_remove(
    _ map: UnsafeMutablePointer<ecs_map_t>,
    _ bucket: UnsafeMutablePointer<ecs_bucket_t>,
    _ key: ecs_map_key_t) -> ecs_map_val_t
{
    var entry = bucket.pointee.first
    while let e = entry {
        if e.pointee.key == key {
            let value = e.pointee.value
            // Find and unlink
            var next_holder: UnsafeMutablePointer<UnsafeMutablePointer<ecs_bucket_entry_t>?> =
                withUnsafeMutablePointer(to: &bucket.pointee.first) { $0 }
            while next_holder.pointee != e {
                next_holder = withUnsafeMutablePointer(to: &next_holder.pointee!.pointee.next) { $0 }
            }
            next_holder.pointee = e.pointee.next
            e.deallocate()
            map.pointee.count -= 1
            return value
        }
        entry = e.pointee.next
    }
    return 0
}

internal func flecs_map_bucket_clear(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ bucket: UnsafeMutablePointer<ecs_bucket_t>)
{
    var entry = bucket.pointee.first
    while let e = entry {
        let next = e.pointee.next
        e.deallocate()
        entry = next
    }
    bucket.pointee.first = nil
}

internal func flecs_map_bucket_get(
    _ bucket: UnsafeMutablePointer<ecs_bucket_t>,
    _ key: ecs_map_key_t) -> UnsafeMutablePointer<ecs_map_val_t>?
{
    var entry = bucket.pointee.first
    while let e = entry {
        if e.pointee.key == key {
            return withUnsafeMutablePointer(to: &e.pointee.value) { $0 }
        }
        entry = e.pointee.next
    }
    return nil
}

internal func flecs_map_rehash(
    _ map: UnsafeMutablePointer<ecs_map_t>,
    _ count: Int32)
{
    var count = flecs_next_pow_of_2(count)
    if count < 2 {
        count = 2
    }

    let old_count = map.pointee.bucket_count
    let old_buckets = map.pointee.buckets

    let new_buckets = UnsafeMutablePointer<ecs_bucket_t>.allocate(capacity: Int(count))
    new_buckets.initialize(repeating: ecs_bucket_t(), count: Int(count))
    map.pointee.buckets = new_buckets
    map.pointee.bucket_count = count
    map.pointee.bucket_shift = UInt32(flecs_map_get_bucket_shift(count)) & 0x3F

    if let old_buckets = old_buckets {
        for i in 0..<Int(old_count) {
            var entry = old_buckets[i].first
            while let e = entry {
                let next = e.pointee.next
                let bucket_index = flecs_map_get_bucket_index(
                    UInt16(map.pointee.bucket_shift), e.pointee.key)
                let bucket = &new_buckets[Int(bucket_index)]
                e.pointee.next = bucket.pointee.first
                bucket.pointee.first = e
                entry = next
            }
        }
        old_buckets.deallocate()
    }
}

// MARK: - Public API

public func ecs_map_init(
    _ result: UnsafeMutablePointer<ecs_map_t>,
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?)
{
    result.pointee = ecs_map_t()
    result.pointee.allocator = allocator
    flecs_map_rehash(result, 0)
}

public func ecs_map_init_if(
    _ result: UnsafeMutablePointer<ecs_map_t>,
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?)
{
    if !ecs_map_is_init(result) {
        ecs_map_init(result, allocator)
    }
}

public func ecs_map_fini(
    _ map: UnsafeMutablePointer<ecs_map_t>)
{
    if !ecs_map_is_init(map) {
        return
    }

    if let buckets = map.pointee.buckets {
        for i in 0..<Int(map.pointee.bucket_count) {
            flecs_map_bucket_clear(map.pointee.allocator, &buckets[i])
        }
        buckets.deallocate()
    }

    map.pointee.bucket_shift = 0
    map.pointee.buckets = nil
    map.pointee.bucket_count = 0
}

public func ecs_map_get(
    _ map: UnsafePointer<ecs_map_t>,
    _ key: ecs_map_key_t) -> UnsafeMutablePointer<ecs_map_val_t>?
{
    let bucket = flecs_map_get_bucket(map, key)
    return flecs_map_bucket_get(bucket, key)
}

public func ecs_map_get_deref_(
    _ map: UnsafePointer<ecs_map_t>,
    _ key: ecs_map_key_t) -> UnsafeMutableRawPointer?
{
    let bucket = flecs_map_get_bucket(map, key)
    guard let ptr = flecs_map_bucket_get(bucket, key) else {
        return nil
    }
    let val = ptr.pointee
    if val == 0 { return nil }
    return UnsafeMutableRawPointer(bitPattern: UInt(val))
}

public func ecs_map_ensure(
    _ map: UnsafeMutablePointer<ecs_map_t>,
    _ key: ecs_map_key_t) -> UnsafeMutablePointer<ecs_map_val_t>
{
    let bucket = flecs_map_get_bucket(UnsafePointer(map), key)
    if let result = flecs_map_bucket_get(bucket, key) {
        return result
    }

    map.pointee.count += 1
    let map_count = map.pointee.count
    let tgt_bucket_count = flecs_map_get_bucket_count(map_count)
    let bucket_count = map.pointee.bucket_count
    var b = bucket
    if tgt_bucket_count > bucket_count {
        flecs_map_rehash(map, tgt_bucket_count)
        b = flecs_map_get_bucket(UnsafePointer(map), key)
    }

    let v = flecs_map_bucket_add(map.pointee.allocator, b, key)
    v.pointee = 0
    return v
}

public func ecs_map_ensure_alloc(
    _ map: UnsafeMutablePointer<ecs_map_t>,
    _ elem_size: ecs_size_t,
    _ key: ecs_map_key_t) -> UnsafeMutableRawPointer?
{
    let val = ecs_map_ensure(map, key)
    if val.pointee == 0 {
        let elem = calloc(1, Int(elem_size))!
        val.pointee = ecs_map_val_t(UInt(bitPattern: elem))
        return elem
    } else {
        return UnsafeMutableRawPointer(bitPattern: UInt(val.pointee))
    }
}

public func ecs_map_insert(
    _ map: UnsafeMutablePointer<ecs_map_t>,
    _ key: ecs_map_key_t,
    _ value: ecs_map_val_t)
{
    map.pointee.count += 1
    let map_count = map.pointee.count
    let tgt_bucket_count = flecs_map_get_bucket_count(map_count)
    let bucket_count = map.pointee.bucket_count
    if tgt_bucket_count > bucket_count {
        flecs_map_rehash(map, tgt_bucket_count)
    }

    let bucket = flecs_map_get_bucket(UnsafePointer(map), key)
    flecs_map_bucket_add(map.pointee.allocator, bucket, key).pointee = value
}

public func ecs_map_insert_alloc(
    _ map: UnsafeMutablePointer<ecs_map_t>,
    _ elem_size: ecs_size_t,
    _ key: ecs_map_key_t) -> UnsafeMutableRawPointer?
{
    let elem = calloc(1, Int(elem_size))
    let ptr_val = ecs_map_val_t(UInt(bitPattern: elem))
    ecs_map_insert(map, key, ptr_val)
    return elem
}

@discardableResult
public func ecs_map_remove(
    _ map: UnsafeMutablePointer<ecs_map_t>,
    _ key: ecs_map_key_t) -> ecs_map_val_t
{
    let bucket = flecs_map_get_bucket(UnsafePointer(map), key)
    return flecs_map_bucket_remove(map, bucket, key)
}

public func ecs_map_remove_free(
    _ map: UnsafeMutablePointer<ecs_map_t>,
    _ key: ecs_map_key_t)
{
    let val = ecs_map_remove(map, key)
    if val != 0 {
        free(UnsafeMutableRawPointer(bitPattern: UInt(val)))
    }
}

public func ecs_map_clear(
    _ map: UnsafeMutablePointer<ecs_map_t>)
{
    if let buckets = map.pointee.buckets {
        for i in 0..<Int(map.pointee.bucket_count) {
            flecs_map_bucket_clear(map.pointee.allocator, &buckets[i])
        }
        buckets.deallocate()
    }
    map.pointee.buckets = nil
    map.pointee.bucket_count = 0
    map.pointee.count = 0
    flecs_map_rehash(map, 2)
}

public func ecs_map_count(_ map: UnsafePointer<ecs_map_t>) -> Int32 {
    return map.pointee.count
}

public func ecs_map_is_init(_ map: UnsafePointer<ecs_map_t>) -> Bool {
    return map.pointee.bucket_shift != 0
}

public func ecs_map_iter(
    _ map: UnsafePointer<ecs_map_t>) -> ecs_map_iter_t
{
    if ecs_map_is_init(map) {
        var iter = ecs_map_iter_t()
        iter.map = map
        iter.bucket = nil
        iter.entry = nil
        return iter
    } else {
        return ecs_map_iter_t()
    }
}

public func ecs_map_next(
    _ iter: UnsafeMutablePointer<ecs_map_iter_t>) -> Bool
{
    guard let map = iter.pointee.map else {
        return false
    }

    let end = map.pointee.buckets!.advanced(by: Int(map.pointee.bucket_count))

    if iter.pointee.bucket == end {
        return false
    }

    var entry: UnsafeMutablePointer<ecs_bucket_entry_t>? = nil

    if iter.pointee.bucket == nil {
        // First iteration
        var b = map.pointee.buckets!
        while b != end {
            if b.pointee.first != nil {
                entry = b.pointee.first
                iter.pointee.bucket = b
                break
            }
            b = b.advanced(by: 1)
        }
        if b == end {
            iter.pointee.bucket = end
            return false
        }
    } else if iter.pointee.entry == nil {
        // Move to next bucket
        var b = iter.pointee.bucket!.advanced(by: 1)
        while b != end {
            if b.pointee.first != nil {
                break
            }
            b = b.advanced(by: 1)
        }
        iter.pointee.bucket = b
        if b == end {
            return false
        }
        entry = b.pointee.first
    } else {
        entry = iter.pointee.entry
    }

    guard let e = entry else {
        return false
    }
    iter.pointee.entry = e.pointee.next
    iter.pointee.res = withUnsafeMutablePointer(to: &e.pointee.key) {
        UnsafeMutablePointer<ecs_map_data_t>(OpaquePointer($0))
    }
    return true
}

/// Get the key from an iterator.
@inline(__always)
public func ecs_map_key(_ it: UnsafePointer<ecs_map_iter_t>) -> ecs_map_data_t {
    return it.pointee.res![0]
}

/// Get the value from an iterator.
@inline(__always)
public func ecs_map_value(_ it: UnsafePointer<ecs_map_iter_t>) -> ecs_map_data_t {
    return it.pointee.res![1]
}

/// Get the value from an iterator as a raw pointer.
@inline(__always)
public func ecs_map_ptr(_ it: UnsafePointer<ecs_map_iter_t>) -> UnsafeMutableRawPointer? {
    let val = ecs_map_value(it)
    return UnsafeMutableRawPointer(bitPattern: UInt(val))
}

public func ecs_map_copy(
    _ dst: UnsafeMutablePointer<ecs_map_t>,
    _ src: UnsafePointer<ecs_map_t>)
{
    if ecs_map_is_init(dst) {
        ecs_map_fini(dst)
    }

    if !ecs_map_is_init(src) {
        return
    }

    ecs_map_init(dst, src.pointee.allocator)

    var it = ecs_map_iter(src)
    while ecs_map_next(&it) {
        ecs_map_insert(dst, ecs_map_key(&it), ecs_map_value(&it))
    }
}

public func ecs_map_reclaim(
    _ map: UnsafeMutablePointer<ecs_map_t>)
{
    let tgt_bucket_count = flecs_map_get_bucket_count(map.pointee.count - 1)
    if tgt_bucket_count != map.pointee.bucket_count {
        flecs_map_rehash(map, tgt_bucket_count)
    }
}

// MARK: - UnsafeMutablePointer overloads

/// ecs_map_get accepting UnsafeMutablePointer (no mutation).
public func ecs_map_get(
    _ map: UnsafeMutablePointer<ecs_map_t>,
    _ key: ecs_map_key_t) -> UnsafeMutablePointer<ecs_map_val_t>?
{
    return ecs_map_get(UnsafePointer(map), key)
}

/// ecs_map_is_init accepting UnsafeMutablePointer.
public func ecs_map_is_init(_ map: UnsafeMutablePointer<ecs_map_t>) -> Bool {
    return map.pointee.bucket_shift != 0
}

/// ecs_map_iter accepting UnsafeMutablePointer.
public func ecs_map_iter(
    _ map: UnsafeMutablePointer<ecs_map_t>) -> ecs_map_iter_t
{
    return ecs_map_iter(UnsafePointer(map))
}

/// ecs_map_count accepting UnsafeMutablePointer.
public func ecs_map_count(_ map: UnsafeMutablePointer<ecs_map_t>) -> Int32 {
    return map.pointee.count
}
