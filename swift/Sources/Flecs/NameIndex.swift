// NameIndex.swift - 1:1 translation of flecs name_index.c
// Data structure for resolving 64-bit keys by string name

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


public struct ecs_hashed_string_t {
    public var value: UnsafeMutablePointer<CChar>?
    public var length: ecs_size_t
    public var hash: UInt64

    public init() {
        self.value = nil
        self.length = 0
        self.hash = 0
    }
}


private func flecs_name_index_hash(
    _ ptr: UnsafeRawPointer?) -> UInt64
{
    if ptr == nil { return 0 }
    let str = ptr!.assumingMemoryBound(to: ecs_hashed_string_t.self)
    return str.pointee.hash
}

private func flecs_name_index_compare(
    _ ptr1: UnsafeRawPointer?,
    _ ptr2: UnsafeRawPointer?) -> Int32
{
    if ptr1 == nil || ptr2 == nil { return 0 }
    let str1 = ptr1!.assumingMemoryBound(to: ecs_hashed_string_t.self)
    let str2 = ptr2!.assumingMemoryBound(to: ecs_hashed_string_t.self)
    let len1 = str1.pointee.length
    let len2 = str2.pointee.length
    if len1 != len2 {
        return (len1 > len2 ? 1 : 0) - (len1 < len2 ? 1 : 0)
    }
    return Int32(memcmp(str1.pointee.value, str2.pointee.value, Int(len1)))
}

private func flecs_get_hashed_string(
    _ name: UnsafePointer<CChar>,
    _ length: ecs_size_t,
    _ hash: UInt64) -> ecs_hashed_string_t
{
    var length = length
    var hash = hash

    if length == 0 {
        length = Int32(strlen(name))
    }

    if hash == 0 {
        hash = flecs_hash(name, length)
    }

    var result = ecs_hashed_string_t()
    result.value = UnsafeMutablePointer(mutating: name)
    result.length = length
    result.hash = hash
    return result
}


public func flecs_name_index_init(
    _ hm: UnsafeMutablePointer<ecs_hashmap_t>,
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?)
{
    flecs_hashmap_init_(hm,
        Int32(MemoryLayout<ecs_hashed_string_t>.stride),
        Int32(MemoryLayout<UInt64>.stride),
        flecs_name_index_hash,
        flecs_name_index_compare,
        allocator)
}

public func flecs_name_index_init_if(
    _ hm: UnsafeMutablePointer<ecs_hashmap_t>,
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?)
{
    if hm.pointee.compare == nil {
        flecs_name_index_init(hm, allocator)
    }
}

public func flecs_name_index_is_init(
    _ hm: UnsafePointer<ecs_hashmap_t>) -> Bool
{
    return hm.pointee.compare != nil
}

public func flecs_name_index_new(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?) -> UnsafeMutablePointer<ecs_hashmap_t>
{
    let result = ecs_os_calloc_t(ecs_hashmap_t.self)!
    result.pointee = ecs_hashmap_t()
    flecs_name_index_init(result, allocator)
    return result
}

public func flecs_name_index_fini(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>)
{
    flecs_hashmap_fini(map)
}

public func flecs_name_index_free(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>?)
{
    if map == nil { return }
    flecs_name_index_fini(map!)
    map!.deinitialize(count: 1)
    ecs_os_free(UnsafeMutableRawPointer(map!))
}

public func flecs_name_index_copy(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>) -> UnsafeMutablePointer<ecs_hashmap_t>
{
    let result = ecs_os_calloc_t(ecs_hashmap_t.self)!
    result.pointee = ecs_hashmap_t()
    flecs_hashmap_copy(result, UnsafePointer(map))
    return result
}

public func flecs_name_index_find_ptr(
    _ map: UnsafePointer<ecs_hashmap_t>,
    _ name: UnsafePointer<CChar>,
    _ length: ecs_size_t,
    _ hash: UInt64) -> UnsafePointer<UInt64>?
{
    let hs = flecs_get_hashed_string(name, length, hash)
    let b = flecs_hashmap_get_bucket(map, hs.hash)
    if b == nil {
        return nil
    }

    let count = ecs_vec_count(&b!.pointee.keys)
    let keys = ecs_vec_first(&b!.pointee.keys)?
        .bindMemory(to: ecs_hashed_string_t.self, capacity: Int(count))
    if keys == nil {
        return nil
    }

    for i in 0..<Int(count) {
        let key = keys!.advanced(by: i)
        if hs.length != key.pointee.length {
            continue
        }
        if strcmp(name, key.pointee.value) == 0 {
            let e = ecs_vec_get(&b!.pointee.values,
                Int32(MemoryLayout<UInt64>.stride), Int32(i))
            if e == nil { return nil }
            return UnsafePointer<UInt64>(
                e!.bindMemory(to: UInt64.self, capacity: 1))
        }
    }

    return nil
}

public func flecs_name_index_find(
    _ map: UnsafePointer<ecs_hashmap_t>,
    _ name: UnsafePointer<CChar>,
    _ length: ecs_size_t,
    _ hash: UInt64) -> UInt64
{
    let id = flecs_name_index_find_ptr(map, name, length, hash)
    if id == nil {
        return 0
    }
    return id!.pointee
}

public func flecs_name_index_remove(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>,
    _ e: UInt64,
    _ hash: UInt64)
{
    let b = flecs_hashmap_get_bucket(UnsafePointer(map), hash)
    if b == nil {
        return
    }

    let count = ecs_vec_count(&b!.pointee.values)
    let ids = ecs_vec_first(&b!.pointee.values)?
        .bindMemory(to: UInt64.self, capacity: Int(count))
    if ids == nil {
        return
    }

    for i in 0..<Int(count) {
        if ids![i] == e {
            flecs_hm_bucket_remove(map, b!, hash, Int32(i))
            break
        }
    }
}

public func flecs_name_index_update_name(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>,
    _ e: UInt64,
    _ hash: UInt64,
    _ name: UnsafePointer<CChar>)
{
    let b = flecs_hashmap_get_bucket(UnsafePointer(map), hash)
    if b == nil {
        return
    }

    let count = ecs_vec_count(&b!.pointee.values)
    let ids = ecs_vec_first(&b!.pointee.values)?
        .bindMemory(to: UInt64.self, capacity: Int(count))
    if ids == nil {
        return
    }

    for i in 0..<Int(count) {
        if ids![i] == e {
            let key_ptr = ecs_vec_get(&b!.pointee.keys,
                Int32(MemoryLayout<ecs_hashed_string_t>.stride), Int32(i))
            if key_ptr == nil {
                return
            }
            let key = key_ptr!.bindMemory(
                to: ecs_hashed_string_t.self, capacity: 1)
            key.pointee.value = UnsafeMutablePointer(mutating: name)
            return
        }
    }
}

public func flecs_name_index_ensure(
    _ map: UnsafeMutablePointer<ecs_hashmap_t>,
    _ id: UInt64,
    _ name: UnsafePointer<CChar>,
    _ length: ecs_size_t,
    _ hash: UInt64)
{
    var key = flecs_get_hashed_string(name, length, hash)

    let existing = flecs_name_index_find(
        UnsafePointer(map), name, key.length, key.hash)
    if existing != 0 {
        if existing != id {
            // Conflicting entity registered with same name
            return
        }
    }

    let hmr = flecs_hashmap_ensure_(map,
        Int32(MemoryLayout<ecs_hashed_string_t>.stride),
        &key,
        Int32(MemoryLayout<UInt64>.stride))
    if hmr.value != nil {
        hmr.value!.bindMemory(to: UInt64.self, capacity: 1).pointee = id
    }
}
