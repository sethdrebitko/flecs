/// BlockAllocator.swift
/// Translation of ecs_block_allocator_t and its operations from flecs.
/// Pool allocator that allocates fixed-size chunks from larger blocks.

import Foundation

// MARK: - Types

/// A block of memory managed by the block allocator.
public struct ecs_block_allocator_block_t {
    public var memory: UnsafeMutableRawPointer?
    public var next: UnsafeMutablePointer<ecs_block_allocator_block_t>?

    public init() {
        self.memory = nil
        self.next = nil
    }
}

/// Header for a free chunk in the block allocator free list.
public struct ecs_block_allocator_chunk_header_t {
    public var next: UnsafeMutablePointer<ecs_block_allocator_chunk_header_t>?

    public init() {
        self.next = nil
    }
}

/// Block allocator that returns fixed-size memory blocks.
public struct ecs_block_allocator_t {
    public var data_size: Int32
    public var chunk_size: Int32
    public var chunks_per_block: Int32
    public var block_size: Int32
    public var head: UnsafeMutablePointer<ecs_block_allocator_chunk_header_t>?
    public var block_head: UnsafeMutablePointer<ecs_block_allocator_block_t>?

    public init() {
        self.data_size = 0
        self.chunk_size = 0
        self.chunks_per_block = 0
        self.block_size = 0
        self.head = nil
        self.block_head = nil
    }
}

// MARK: - Internal constants

private let FLECS_MIN_CHUNKS_PER_BLOCK: Int32 = 1

// MARK: - Internal helpers

/// Align a value up to the given alignment.
@inline(__always)
internal func ECS_ALIGN(_ size: Int32, _ alignment: Int32) -> Int32 {
    return (size + (alignment - 1)) & ~(alignment - 1)
}

/// Allocate a new block and return a linked list of chunk headers.
private func flecs_balloc_block(
    _ allocator: UnsafeMutablePointer<ecs_block_allocator_t>) -> UnsafeMutablePointer<ecs_block_allocator_chunk_header_t>?
{
    if allocator.pointee.chunk_size == 0 {
        return nil
    }

    let block_header_size = MemoryLayout<ecs_block_allocator_block_t>.stride
    let total_size = block_header_size + Int(allocator.pointee.block_size)
    let raw = malloc(total_size)!

    let block = raw.bindMemory(to: ecs_block_allocator_block_t.self, capacity: 1)
    let first_chunk = raw.advanced(by: block_header_size)
        .bindMemory(to: ecs_block_allocator_chunk_header_t.self, capacity: 1)

    block.pointee.memory = UnsafeMutableRawPointer(first_chunk)
    block.pointee.next = allocator.pointee.block_head
    allocator.pointee.block_head = block

    // Chain chunks together into a free list
    var chunk = first_chunk
    let end = allocator.pointee.chunks_per_block - 1
    for _ in 0..<end {
        let next = UnsafeMutableRawPointer(chunk)
            .advanced(by: Int(allocator.pointee.chunk_size))
            .bindMemory(to: ecs_block_allocator_chunk_header_t.self, capacity: 1)
        chunk.pointee.next = next
        chunk = next
    }
    chunk.pointee.next = nil

    return first_chunk
}

// MARK: - Public API

/// Initialize a block allocator.
public func flecs_ballocator_init(
    _ ba: UnsafeMutablePointer<ecs_block_allocator_t>,
    _ size: ecs_size_t)
{
    ba.pointee.data_size = size
    var aligned_size = size
    let ptr_size = Int32(MemoryLayout<UnsafeMutableRawPointer>.size)
    if aligned_size < ptr_size {
        aligned_size = ptr_size
    }
    ba.pointee.chunk_size = ECS_ALIGN(aligned_size, 16)
    ba.pointee.chunks_per_block = max(4096 / ba.pointee.chunk_size, 1)
    ba.pointee.block_size = ba.pointee.chunks_per_block * ba.pointee.chunk_size
    ba.pointee.head = nil
    ba.pointee.block_head = nil
}

/// Create a new block allocator on the heap.
public func flecs_ballocator_new(
    _ size: ecs_size_t) -> UnsafeMutablePointer<ecs_block_allocator_t>
{
    let result = UnsafeMutablePointer<ecs_block_allocator_t>.allocate(capacity: 1)
    result.pointee = ecs_block_allocator_t()
    flecs_ballocator_init(result, size)
    return result
}

/// Deinitialize a block allocator, freeing all blocks.
public func flecs_ballocator_fini(
    _ ba: UnsafeMutablePointer<ecs_block_allocator_t>)
{
    var block = ba.pointee.block_head
    while let b = block {
        let next = b.pointee.next
        // The block was allocated as a single malloc including header + data
        free(UnsafeMutableRawPointer(b))
        block = next
    }
    ba.pointee.block_head = nil
    ba.pointee.head = nil
}

/// Free a block allocator created with flecs_ballocator_new.
public func flecs_ballocator_free(
    _ ba: UnsafeMutablePointer<ecs_block_allocator_t>)
{
    flecs_ballocator_fini(ba)
    ba.deallocate()
}

/// Allocate a block of memory from the block allocator.
@discardableResult
public func flecs_balloc(
    _ ba: UnsafeMutablePointer<ecs_block_allocator_t>?) -> UnsafeMutableRawPointer?
{
    guard let ba = ba else { return nil }

    if ba.pointee.chunks_per_block <= FLECS_MIN_CHUNKS_PER_BLOCK {
        return malloc(Int(ba.pointee.data_size))
    }

    if ba.pointee.head == nil {
        ba.pointee.head = flecs_balloc_block(ba)
    }

    guard let result = ba.pointee.head else { return nil }
    ba.pointee.head = result.pointee.next
    return UnsafeMutableRawPointer(result)
}

/// Allocate a zeroed block of memory from the block allocator.
@discardableResult
public func flecs_bcalloc(
    _ ba: UnsafeMutablePointer<ecs_block_allocator_t>?) -> UnsafeMutableRawPointer?
{
    guard let ba = ba else { return nil }
    guard let result = flecs_balloc(ba) else { return nil }
    memset(result, 0, Int(ba.pointee.data_size))
    return result
}

/// Free a block of memory back to the block allocator.
public func flecs_bfree(
    _ ba: UnsafeMutablePointer<ecs_block_allocator_t>?,
    _ memory: UnsafeMutableRawPointer?)
{
    guard let ba = ba else { return }
    guard let memory = memory else { return }

    if ba.pointee.chunks_per_block <= FLECS_MIN_CHUNKS_PER_BLOCK {
        free(memory)
        return
    }

    let chunk = memory.bindMemory(
        to: ecs_block_allocator_chunk_header_t.self, capacity: 1)
    chunk.pointee.next = ba.pointee.head
    ba.pointee.head = chunk
}

/// Reallocate a block from one block allocator to another.
@discardableResult
public func flecs_brealloc(
    _ dst: UnsafeMutablePointer<ecs_block_allocator_t>?,
    _ src: UnsafeMutablePointer<ecs_block_allocator_t>?,
    _ memory: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
{
    if dst == src {
        return memory
    }

    let result = flecs_balloc(dst)
    if let result = result, let src = src {
        var size = src.pointee.data_size
        if let dst = dst, dst.pointee.data_size < size {
            size = dst.pointee.data_size
        }
        if let memory = memory {
            memcpy(result, memory, Int(size))
        }
    }
    flecs_bfree(src, memory)
    return result
}

/// Duplicate a block of memory.
@discardableResult
public func flecs_bdup(
    _ ba: UnsafeMutablePointer<ecs_block_allocator_t>?,
    _ memory: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
{
    guard let ba = ba, let memory = memory else { return nil }
    guard let result = flecs_balloc(ba) else { return nil }
    memcpy(result, memory, Int(ba.pointee.data_size))
    return result
}
