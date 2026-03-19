/// Allocator.swift
/// Translation of ecs_allocator_t and its operations from flecs.
/// General purpose allocator that manages block allocators for different sizes.

import Foundation

// MARK: - Types

/// Type alias for ecs_size_t used throughout. Defined here but will be in Types.swift.
public typealias ecs_size_t = Int32

/// General purpose allocator that manages block allocators for different sizes.
/// Uses a sparse set to map allocation sizes to block allocators.
public struct ecs_allocator_t {
    public var chunks: ecs_block_allocator_t
    public var sizes: ecs_sparse_t

    public init() {
        self.chunks = ecs_block_allocator_t()
        self.sizes = ecs_sparse_t()
    }
}

// MARK: - Internal helpers

@inline(__always)
internal func flecs_allocator_size(_ size: ecs_size_t) -> ecs_size_t {
    return ECS_ALIGN(size, 16)
}

@inline(__always)
internal func flecs_allocator_size_hash(_ size: ecs_size_t) -> ecs_size_t {
    return size >> 4
}

// MARK: - Public API

/// Initialize an allocator.
public func flecs_allocator_init(
    _ a: UnsafeMutablePointer<ecs_allocator_t>)
{
    let ba_size = Int32(MemoryLayout<ecs_block_allocator_t>.stride)
    flecs_ballocator_init(&a.pointee.chunks, ba_size * FLECS_SPARSE_PAGE_SIZE)
    flecs_sparse_init(&a.pointee.sizes, nil, &a.pointee.chunks, ba_size)
}

/// Deinitialize an allocator.
public func flecs_allocator_fini(
    _ a: UnsafeMutablePointer<ecs_allocator_t>)
{
    let count = flecs_sparse_count(withUnsafePointer(to: &a.pointee.sizes) { $0 })
    for i in 0..<count {
        if let ba_ptr = flecs_sparse_get_dense(
            withUnsafePointer(to: &a.pointee.sizes) { $0 },
            Int32(MemoryLayout<ecs_block_allocator_t>.stride),
            i)
        {
            let ba = ba_ptr.bindMemory(to: ecs_block_allocator_t.self, capacity: 1)
            flecs_ballocator_fini(ba)
        }
    }
    flecs_sparse_fini(&a.pointee.sizes)
    flecs_ballocator_fini(&a.pointee.chunks)
}

/// Get or create a block allocator for the specified size.
public func flecs_allocator_get(
    _ a: UnsafeMutablePointer<ecs_allocator_t>,
    _ size: ecs_size_t) -> UnsafeMutablePointer<ecs_block_allocator_t>?
{
    if size <= 0 {
        return nil
    }

    let aligned_size = flecs_allocator_size(size)
    let hash = flecs_allocator_size_hash(aligned_size)
    let ba_size = Int32(MemoryLayout<ecs_block_allocator_t>.stride)

    if let result = flecs_sparse_get(
        withUnsafePointer(to: &a.pointee.sizes) { $0 },
        ba_size,
        UInt64(UInt32(bitPattern: hash)))
    {
        return result.bindMemory(to: ecs_block_allocator_t.self, capacity: 1)
    }

    guard let result = flecs_sparse_ensure_fast(
        &a.pointee.sizes,
        ba_size,
        UInt64(UInt32(bitPattern: hash)))
    else {
        return nil
    }

    let ba = result.bindMemory(to: ecs_block_allocator_t.self, capacity: 1)
    flecs_ballocator_init(ba, aligned_size)
    return ba
}

/// Allocate memory of a given size.
public func flecs_alloc(
    _ a: UnsafeMutablePointer<ecs_allocator_t>?,
    _ size: ecs_size_t) -> UnsafeMutableRawPointer?
{
    guard let a = a else { return malloc(Int(size)) }
    guard let ba = flecs_allocator_get(a, size) else { return nil }
    return flecs_balloc(ba)
}

/// Allocate zeroed memory of a given size.
public func flecs_calloc(
    _ a: UnsafeMutablePointer<ecs_allocator_t>?,
    _ size: ecs_size_t) -> UnsafeMutableRawPointer?
{
    guard let a = a else { return calloc(1, Int(size)) }
    guard let ba = flecs_allocator_get(a, size) else { return nil }
    return flecs_bcalloc(ba)
}

/// Free memory of a given size.
public func flecs_free(
    _ a: UnsafeMutablePointer<ecs_allocator_t>?,
    _ size: ecs_size_t,
    _ ptr: UnsafeMutableRawPointer?)
{
    guard let ptr = ptr else { return }
    guard let a = a else { free(ptr); return }
    guard let ba = flecs_allocator_get(a, size) else { free(ptr); return }
    flecs_bfree(ba, ptr)
}

/// Reallocate memory from one size to another.
public func flecs_realloc(
    _ a: UnsafeMutablePointer<ecs_allocator_t>?,
    _ dst_size: ecs_size_t,
    _ src_size: ecs_size_t,
    _ ptr: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
{
    guard let a = a else { return realloc(ptr, Int(dst_size)) }
    let dst_ba = flecs_allocator_get(a, dst_size)
    let src_ba = (src_size > 0) ? flecs_allocator_get(a, src_size) : nil
    return flecs_brealloc(dst_ba, src_ba, ptr)
}

/// Duplicate a string using the allocator.
public func flecs_strdup(
    _ a: UnsafeMutablePointer<ecs_allocator_t>?,
    _ str: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
{
    let len = strlen(str)
    guard let result = flecs_alloc(a, Int32(len + 1)) else { return nil }
    memcpy(result, str, len + 1)
    return result.bindMemory(to: CChar.self, capacity: len + 1)
}

/// Free a string previously allocated with flecs_strdup.
public func flecs_strfree(
    _ a: UnsafeMutablePointer<ecs_allocator_t>?,
    _ str: UnsafeMutablePointer<CChar>?)
{
    guard let str = str else { return }
    let len = strlen(str)
    flecs_free(a, Int32(len + 1), UnsafeMutableRawPointer(str))
}

/// Duplicate a memory block using the allocator.
public func flecs_dup(
    _ a: UnsafeMutablePointer<ecs_allocator_t>?,
    _ size: ecs_size_t,
    _ src: UnsafeRawPointer?) -> UnsafeMutableRawPointer?
{
    if size == 0 { return nil }
    guard let src = src else { return nil }
    guard let dst = flecs_alloc(a, size) else { return nil }
    memcpy(dst, src, Int(size))
    return dst
}
