/// Vec.swift
/// Translation of ecs_vec_t and its operations from flecs.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Dynamic array with allocator support.
public struct ecs_vec_t {
    public var array: UnsafeMutableRawPointer?
    public var count: Int32
    public var size: Int32  // capacity

    public init() {
        self.array = nil
        self.count = 0
        self.size = 0
    }
}


@inline(__always)
internal func ECS_ELEM(_ array: UnsafeMutableRawPointer?, _ size: ecs_size_t, _ index: Int32) -> UnsafeMutableRawPointer? {
    if array == nil { return nil }
    return array!.advanced(by: Int(size) * Int(index))
}

@inline(__always)
internal func flecs_next_pow_of_2(_ n: Int32) -> Int32 {
    var v = n
    if v <= 0 { return 0 }
    v -= 1
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8
    v |= v >> 16
    return v + 1
}


public func ecs_vec_init(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ v: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t,
    _ elem_count: Int32)
{
    if elem_count > 0 {
        v.pointee.array = malloc(Int(size) * Int(elem_count))
    } else {
        v.pointee.array = nil
    }
    v.pointee.count = 0
    v.pointee.size = elem_count
}

public func ecs_vec_init_if(
    _ vec: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t)
{
    // No-op in non-sanitize mode; the vec is assumed to be zero-initialized
    // if not yet initialized.
    _ = vec
    _ = size
}

public func ecs_vec_fini(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ v: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t)
{
    if v.pointee.array != nil {
        free(v.pointee.array)
        v.pointee.array = nil
        v.pointee.count = 0
        v.pointee.size = 0
    }
}

@discardableResult
public func ecs_vec_reset(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ v: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t) -> UnsafeMutablePointer<ecs_vec_t>
{
    if v.pointee.size == 0 {
        ecs_vec_init(allocator, v, size, 0)
    } else {
        ecs_vec_clear(v)
    }
    return v
}

public func ecs_vec_clear(
    _ vec: UnsafeMutablePointer<ecs_vec_t>)
{
    vec.pointee.count = 0
}

public func ecs_vec_append(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ v: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t) -> UnsafeMutableRawPointer?
{
    let count = v.pointee.count
    if v.pointee.size == count {
        ecs_vec_set_size(allocator, v, size, count + 1)
    }
    v.pointee.count = count + 1
    return ECS_ELEM(v.pointee.array, size, count)
}

public func ecs_vec_remove(
    _ v: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t,
    _ index: Int32)
{
    v.pointee.count -= 1
    if index == v.pointee.count {
        return
    }
    let dst = ECS_ELEM(v.pointee.array, size, index)
    let src = ECS_ELEM(v.pointee.array, size, v.pointee.count)
    if dst == nil || src == nil { return }
    memcpy(dst!, src!, Int(size))
}

public func ecs_vec_remove_ordered(
    _ v: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t,
    _ index: Int32)
{
    let newCount = v.pointee.count - 1
    v.pointee.count = newCount
    if index == newCount {
        return
    }
    let dst = ECS_ELEM(v.pointee.array, size, index)
    let src = ECS_ELEM(v.pointee.array, size, index + 1)
    if dst == nil || src == nil { return }
    memmove(dst!, src!, Int(size) * Int(newCount - index))
}

public func ecs_vec_remove_last(
    _ v: UnsafeMutablePointer<ecs_vec_t>)
{
    v.pointee.count -= 1
}

public func ecs_vec_copy(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ v: UnsafePointer<ecs_vec_t>,
    _ size: ecs_size_t) -> ecs_vec_t
{
    var result = ecs_vec_t()
    result.count = v.pointee.count
    result.size = v.pointee.size
    if v.pointee.size > 0 && v.pointee.array != nil {
        let byteCount = Int(size) * Int(v.pointee.size)
        result.array = malloc(byteCount)
        memcpy(result.array, v.pointee.array, byteCount)
    }
    return result
}

public func ecs_vec_copy_shrink(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ v: UnsafePointer<ecs_vec_t>,
    _ size: ecs_size_t) -> ecs_vec_t
{
    var result = ecs_vec_t()
    let count = v.pointee.count
    result.count = count
    result.size = count
    if count > 0 && v.pointee.array != nil {
        let byteCount = Int(size) * Int(count)
        result.array = malloc(byteCount)
        memcpy(result.array, v.pointee.array, byteCount)
    }
    return result
}

public func ecs_vec_reclaim(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ v: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t)
{
    let count = v.pointee.count
    if count < v.pointee.size {
        if count > 0 {
            let byteCount = Int(size) * Int(count)
            let newArray = malloc(byteCount)
            memcpy(newArray, v.pointee.array, byteCount)
            free(v.pointee.array)
            v.pointee.array = newArray
            v.pointee.size = count
        } else {
            ecs_vec_fini(allocator, v, size)
        }
    }
}

public func ecs_vec_set_size(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ v: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t,
    _ elem_count: Int32)
{
    var elem_count = elem_count
    if v.pointee.size != elem_count {
        if elem_count < v.pointee.count {
            elem_count = v.pointee.count
        }
        elem_count = flecs_next_pow_of_2(elem_count)
        if elem_count < 2 {
            elem_count = 2
        }
        if elem_count != v.pointee.size {
            v.pointee.array = realloc(v.pointee.array, Int(size) * Int(elem_count))
            v.pointee.size = elem_count
        }
    }
}

public func ecs_vec_set_min_size(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ vec: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t,
    _ elem_count: Int32)
{
    if elem_count > vec.pointee.size {
        ecs_vec_set_size(allocator, vec, size, elem_count)
    }
}

public func ecs_vec_set_count(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ v: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t,
    _ elem_count: Int32)
{
    if v.pointee.count != elem_count {
        if v.pointee.size < elem_count {
            ecs_vec_set_size(allocator, v, size, elem_count)
        }
        v.pointee.count = elem_count
    }
}

public func ecs_vec_set_min_count(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ vec: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t,
    _ elem_count: Int32)
{
    ecs_vec_set_min_size(allocator, vec, size, elem_count)
    if vec.pointee.count < elem_count {
        vec.pointee.count = elem_count
    }
}

public func ecs_vec_set_min_count_zeromem(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ vec: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t,
    _ elem_count: Int32)
{
    let count = vec.pointee.count
    if count < elem_count {
        ecs_vec_set_min_count(allocator, vec, size, elem_count)
        let ptr = ECS_ELEM(vec.pointee.array, size, count)
        if ptr != nil {
            memset(ptr!, 0, Int(size) * Int(elem_count - count))
        }
    }
}

public func ecs_vec_grow(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ v: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t,
    _ elem_count: Int32) -> UnsafeMutableRawPointer?
{
    let count = v.pointee.count
    ecs_vec_set_count(allocator, v, size, count + elem_count)
    return ECS_ELEM(v.pointee.array, size, count)
}

public func ecs_vec_count(
    _ v: UnsafePointer<ecs_vec_t>) -> Int32
{
    return v.pointee.count
}

public func ecs_vec_count(
    _ v: UnsafeMutablePointer<ecs_vec_t>) -> Int32
{
    return v.pointee.count
}

public func ecs_vec_size(
    _ v: UnsafePointer<ecs_vec_t>) -> Int32
{
    return v.pointee.size
}

public func ecs_vec_get(
    _ v: UnsafePointer<ecs_vec_t>,
    _ size: ecs_size_t,
    _ index: Int32) -> UnsafeMutableRawPointer?
{
    return ECS_ELEM(v.pointee.array, size, index)
}

public func ecs_vec_get(
    _ v: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t,
    _ index: Int32) -> UnsafeMutableRawPointer?
{
    return ECS_ELEM(v.pointee.array, size, index)
}

public func ecs_vec_first(
    _ v: UnsafePointer<ecs_vec_t>) -> UnsafeMutableRawPointer?
{
    return v.pointee.array
}

public func ecs_vec_first(
    _ v: UnsafeMutablePointer<ecs_vec_t>) -> UnsafeMutableRawPointer?
{
    return v.pointee.array
}

public func ecs_vec_last(
    _ v: UnsafePointer<ecs_vec_t>,
    _ size: ecs_size_t) -> UnsafeMutableRawPointer?
{
    return ECS_ELEM(v.pointee.array, size, v.pointee.count - 1)
}

public func ecs_vec_copy(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ v: UnsafeMutablePointer<ecs_vec_t>,
    _ size: ecs_size_t) -> ecs_vec_t
{
    return ecs_vec_copy(allocator, UnsafePointer(v), size)
}
