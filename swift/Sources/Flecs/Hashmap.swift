/// Hashmap.swift
/// Translation of ecs_hashmap_t and its operations from flecs.
/// Hashmap with variable-sized keys/values built on top of ecs_map_t.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


// ecs_hash_value_action_t and ecs_compare_action_t defined in Structs.swift

/// A bucket in the hashmap, storing parallel key and value vectors.
public struct ecs_hm_bucket_t {
    public var keys: ecs_vec_t
    public var values: ecs_vec_t

    public init() {
        self.keys = ecs_vec_t()
        self.values = ecs_vec_t()
    }
}

/// A hashmap that supports variable-sized keys and values.
public struct ecs_hashmap_t {
    public var hash: ecs_hash_value_action_t?
    public var compare: ecs_compare_action_t?
    public var key_size: ecs_size_t
    public var value_size: ecs_size_t
    public var impl: ecs_map_t

    public init() {
        self.hash = nil
        self.compare = nil
        self.key_size = 0
        self.value_size = 0
        self.impl = ecs_map_t()
    }
}

/// Iterator for a hashmap.
public struct flecs_hashmap_iter_t {
    public var it: ecs_map_iter_t
    public var bucket: UnsafeMutablePointer<ecs_hm_bucket_t>?
    public var index: Int32

    public init() {
        self.it = ecs_map_iter_t()
        self.bucket = nil
        self.index = 0
    }
}

/// Result of a hashmap ensure operation.
public struct flecs_hashmap_result_t {
    public var key: UnsafeMutableRawPointer?
    public var value: UnsafeMutableRawPointer?
    public var hash: UInt64

    public init() {
        self.key = nil
        self.value = nil
        self.hash = 0
    }
}


private func flecs_hashmap_find_key(
    _ map: UnsafePointer<ecs_hashmap_t>,
    _ keys: UnsafeMutablePointer<ecs_vec_t>,
    _ key_size: ecs_size_t,
    _ key: UnsafeRawPointer) -> Int32
{
    let count = ecs_vec_count(keys)
    let key_array = ecs_vec_first(keys)
    if key_array == nil {
        return -1
    }
    for i in 0..<Int(count) {
        let key_ptr = key_array!.advanced(by: Int(key_size) * i)
        if map.pointee.compare != nil && map.pointee.compare!(key_ptr, key) == 0 {
            return Int32(i)
        }
    }
    return -1
}

private func flecs_hm_bucket_new(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>) -> UnsafeMutablePointer<ecs_hm_bucket_t>
{
    let bucket = ecs_os_calloc_t(ecs_hm_bucket_t.self)!
    bucket.pointee = ecs_hm_bucket_t()
    return bucket
}

private func flecs_hm_bucket_free_internal(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>,
    _ bucket: UnsafeMutablePointer<ecs_hm_bucket_t>)
{
    ecs_os_free(UnsafeMutableRawPointer(bucket))
}


/// Initialize a hashmap.
public func flecs_hashmap_init_(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>,
    _ key_size: ecs_size_t,
    _ value_size: ecs_size_t,
    _ hash: ecs_hash_value_action_t?,
    _ compare: ecs_compare_action_t?,
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?)
{
    map.pointee.key_size = key_size
    map.pointee.value_size = value_size
    map.pointee.hash = hash
    map.pointee.compare = compare
    ecs_map_init(&map.pointee.impl, allocator)
}

/// Deinitialize a hashmap.
public func flecs_hashmap_fini(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>)
{
    let a = map.pointee.impl.allocator
    var it = ecs_map_iter(&map.pointee.impl)

    while ecs_map_next(&it) {
        let bucket_raw = ecs_map_ptr(&it)
        if bucket_raw != nil {
            let bucket = bucket_raw!.bindMemory(to: ecs_hm_bucket_t.self, capacity: 1)
            ecs_vec_fini(a, &bucket.pointee.keys, map.pointee.key_size)
            ecs_vec_fini(a, &bucket.pointee.values, map.pointee.value_size)
            flecs_hm_bucket_free_internal(map, bucket)
        }
    }

    ecs_map_fini(&map.pointee.impl)
}

/// Get a value from the hashmap.
public func flecs_hashmap_get_(
    _ map: UnsafePointer<ecs_hashmap_t>,
    _ key_size: ecs_size_t,
    _ key: UnsafeRawPointer,
    _ value_size: ecs_size_t) -> UnsafeMutableRawPointer?
{
    if map.pointee.hash == nil { return nil }
    let hash = map.pointee.hash!(key)

    // We need a mutable pointer to call ecs_map_get on the impl field.
    // The map itself is logically const; this is safe because ecs_map_get doesn't mutate.
    let map_mut = UnsafeMutablePointer(mutating: map)
    let bucket_val = ecs_map_get(&map_mut.pointee.impl, hash)
    if bucket_val == nil {
        return nil
    }
    let bucket_ptr_val = bucket_val!.pointee
    if bucket_ptr_val == 0 { return nil }
    let bucket = UnsafeMutableRawPointer(bitPattern: UInt(bucket_ptr_val))!
        .bindMemory(to: ecs_hm_bucket_t.self, capacity: 1)

    let index = flecs_hashmap_find_key(map, &bucket.pointee.keys, key_size, key)
    if index == -1 {
        return nil
    }

    return ecs_vec_get(&bucket.pointee.values, value_size, index)
}

/// Ensure a key exists in the hashmap, inserting if necessary.
public func flecs_hashmap_ensure_(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>,
    _ key_size: ecs_size_t,
    _ key: UnsafeRawPointer,
    _ value_size: ecs_size_t) -> flecs_hashmap_result_t
{
    if map.pointee.hash == nil {
        return flecs_hashmap_result_t()
    }
    let hash = map.pointee.hash!(key)

    let r = ecs_map_ensure(&map.pointee.impl, hash)
    var bucket: UnsafeMutablePointer<ecs_hm_bucket_t>

    if r.pointee == 0 {
        bucket = flecs_hm_bucket_new(map)
        r.pointee = ecs_map_val_t(UInt(bitPattern: UnsafeMutableRawPointer(bucket)))
    } else {
        bucket = UnsafeMutableRawPointer(bitPattern: UInt(r.pointee))!
            .bindMemory(to: ecs_hm_bucket_t.self, capacity: 1)
    }

    let a = map.pointee.impl.allocator
    var value_ptr: UnsafeMutableRawPointer?
    var key_ptr: UnsafeMutableRawPointer?

    if bucket.pointee.keys.array == nil {
        ecs_vec_init(a, &bucket.pointee.keys, key_size, 1)
        ecs_vec_init(a, &bucket.pointee.values, value_size, 1)
        key_ptr = ecs_vec_append(a, &bucket.pointee.keys, key_size)
        value_ptr = ecs_vec_append(a, &bucket.pointee.values, value_size)
        if key_ptr != nil {
            memcpy(key_ptr!, key, Int(key_size))
        }
        if value_ptr != nil {
            memset(value_ptr!, 0, Int(value_size))
        }
    } else {
        let index = flecs_hashmap_find_key(
            UnsafePointer(map), &bucket.pointee.keys, key_size, key)
        if index == -1 {
            key_ptr = ecs_vec_append(a, &bucket.pointee.keys, key_size)
            value_ptr = ecs_vec_append(a, &bucket.pointee.values, value_size)
            if key_ptr != nil {
                memcpy(key_ptr!, key, Int(key_size))
            }
            if value_ptr != nil {
                memset(value_ptr!, 0, Int(value_size))
            }
        } else {
            key_ptr = ecs_vec_get(&bucket.pointee.keys, key_size, index)
            value_ptr = ecs_vec_get(&bucket.pointee.values, value_size, index)
        }
    }

    var result = flecs_hashmap_result_t()
    result.key = key_ptr
    result.value = value_ptr
    result.hash = hash
    return result
}

/// Set a key-value pair in the hashmap.
public func flecs_hashmap_set_(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>,
    _ key_size: ecs_size_t,
    _ key: UnsafeMutableRawPointer,
    _ value_size: ecs_size_t,
    _ value: UnsafeRawPointer)
{
    let result = flecs_hashmap_ensure_(map, key_size, key, value_size)
    if result.value != nil {
        memcpy(result.value!, value, Int(value_size))
    }
}

/// Get a bucket from the hashmap by hash value.
public func flecs_hashmap_get_bucket(
    _ map: UnsafePointer<ecs_hashmap_t>,
    _ hash: UInt64) -> UnsafeMutablePointer<ecs_hm_bucket_t>?
{
    let map_mut = UnsafeMutablePointer(mutating: map)
    let val = ecs_map_get(&map_mut.pointee.impl, hash)
    if val == nil {
        return nil
    }
    let ptr_val = val!.pointee
    if ptr_val == 0 { return nil }
    return UnsafeMutableRawPointer(bitPattern: UInt(ptr_val))?
        .bindMemory(to: ecs_hm_bucket_t.self, capacity: 1)
}

/// Remove an entry from a hashmap bucket by index.
public func flecs_hm_bucket_remove(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>,
    _ bucket: UnsafeMutablePointer<ecs_hm_bucket_t>,
    _ hash: UInt64,
    _ index: Int32)
{
    ecs_vec_remove(&bucket.pointee.keys, map.pointee.key_size, index)
    ecs_vec_remove(&bucket.pointee.values, map.pointee.value_size, index)

    if ecs_vec_count(&bucket.pointee.keys) == 0 {
        let a = map.pointee.impl.allocator
        ecs_vec_fini(a, &bucket.pointee.keys, map.pointee.key_size)
        ecs_vec_fini(a, &bucket.pointee.values, map.pointee.value_size)
        ecs_map_remove(&map.pointee.impl, hash)
        flecs_hm_bucket_free_internal(map, bucket)
    }
}

/// Remove a key from the hashmap using a precomputed hash.
public func flecs_hashmap_remove_w_hash_(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>,
    _ key_size: ecs_size_t,
    _ key: UnsafeRawPointer,
    _ value_size: ecs_size_t,
    _ hash: UInt64)
{
    let bucket = flecs_hashmap_get_bucket(UnsafePointer(map), hash)
    if bucket == nil {
        return
    }

    let index = flecs_hashmap_find_key(UnsafePointer(map), &bucket!.pointee.keys, key_size, key)
    if index == -1 {
        return
    }

    flecs_hm_bucket_remove(map, bucket!, hash, index)
}

/// Remove a key from the hashmap.
public func flecs_hashmap_remove_(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>,
    _ key_size: ecs_size_t,
    _ key: UnsafeRawPointer,
    _ value_size: ecs_size_t)
{
    if map.pointee.hash == nil { return }
    let hash = map.pointee.hash!(key)
    flecs_hashmap_remove_w_hash_(map, key_size, key, value_size, hash)
}

/// Copy a hashmap.
public func flecs_hashmap_copy(
    _ dst: UnsafeMutablePointer<ecs_hashmap_t>,
    _ src: UnsafePointer<ecs_hashmap_t>)
{
    flecs_hashmap_init_(dst, src.pointee.key_size, src.pointee.value_size,
        src.pointee.hash, src.pointee.compare, src.pointee.impl.allocator)

    let src_mut = UnsafeMutablePointer(mutating: src)
    withUnsafePointer(to: &src_mut.pointee.impl) { implPtr in
        ecs_map_copy(&dst.pointee.impl, implPtr)
    }

    let a = dst.pointee.impl.allocator
    var it = ecs_map_iter(&dst.pointee.impl)
    while ecs_map_next(&it) {
        if it.res == nil { continue }
        let res = it.res!
        let src_bucket_val = res[1]
        if src_bucket_val == 0 { continue }
        let src_bucket = UnsafeMutableRawPointer(bitPattern: UInt(src_bucket_val))!
            .bindMemory(to: ecs_hm_bucket_t.self, capacity: 1)

        let dst_bucket = flecs_hm_bucket_new(dst)
        dst_bucket.pointee.keys = ecs_vec_copy(a, &src_bucket.pointee.keys,
            dst.pointee.key_size)
        dst_bucket.pointee.values = ecs_vec_copy(a, &src_bucket.pointee.values,
            dst.pointee.value_size)

        res[1] = ecs_map_val_t(UInt(bitPattern: UnsafeMutableRawPointer(dst_bucket)))
    }
}

/// Create an iterator for a hashmap.
public func flecs_hashmap_iter(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>) -> flecs_hashmap_iter_t
{
    var result = flecs_hashmap_iter_t()
    result.it = ecs_map_iter(&map.pointee.impl)
    return result
}

/// Get the next element from a hashmap iterator.
public func flecs_hashmap_next_(
    _ it: UnsafeMutablePointer<flecs_hashmap_iter_t>,
    _ key_size: ecs_size_t,
    _ key_out: UnsafeMutableRawPointer?,
    _ value_size: ecs_size_t) -> UnsafeMutableRawPointer?
{
    it.pointee.index += 1
    var bucket = it.pointee.bucket

    while bucket == nil || it.pointee.index >= ecs_vec_count(&bucket!.pointee.keys)
    {
        _ = ecs_map_next(&it.pointee.it)
        let ptr = ecs_map_ptr(&it.pointee.it)
        if ptr != nil {
            it.pointee.bucket = ptr!.bindMemory(to: ecs_hm_bucket_t.self, capacity: 1)
            bucket = it.pointee.bucket
        } else {
            it.pointee.bucket = nil
            return nil
        }
        it.pointee.index = 0
    }

    if bucket == nil { return nil }
    let index = it.pointee.index

    if key_out != nil && key_size > 0 {
        let key_ptr = ecs_vec_get(&bucket!.pointee.keys, key_size, index)
        key_out!.storeBytes(of: key_ptr, as: UnsafeMutableRawPointer?.self)
    }

    return ecs_vec_get(&bucket!.pointee.values, value_size, index)
}
