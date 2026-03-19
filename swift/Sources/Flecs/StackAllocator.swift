/// StackAllocator.swift
/// Translation of ecs_stack_t and its operations from flecs.
/// Linear/bump allocator with cursor support for temporary allocations.

import Foundation

// MARK: - Constants

/// Offset of usable data within a stack page (aligned to 16 bytes).
public let FLECS_STACK_PAGE_OFFSET: Int32 = ECS_ALIGN(
    Int32(MemoryLayout<ecs_stack_page_t>.stride), 16)

/// Size of usable data within a stack page.
public let FLECS_STACK_PAGE_SIZE: Int16 = Int16(1024 - Int(FLECS_STACK_PAGE_OFFSET))

// MARK: - Types

/// A page of memory in the stack allocator.
public struct ecs_stack_page_t {
    public var data: UnsafeMutableRawPointer?
    public var next: UnsafeMutablePointer<ecs_stack_page_t>?
    public var sp: Int16
    public var id: UInt32

    public init() {
        self.data = nil
        self.next = nil
        self.sp = 0
        self.id = 0
    }
}

/// Cursor that marks a position in the stack allocator for later restoration.
public struct ecs_stack_cursor_t {
    public var prev: UnsafeMutablePointer<ecs_stack_cursor_t>?
    public var page: UnsafeMutablePointer<ecs_stack_page_t>?
    public var sp: Int16
    public var is_free: Bool

    public init() {
        self.prev = nil
        self.page = nil
        self.sp = 0
        self.is_free = false
    }
}

/// Stack allocator for quick allocation of small temporary values.
public struct ecs_stack_t {
    public var first: UnsafeMutablePointer<ecs_stack_page_t>?
    public var tail_page: UnsafeMutablePointer<ecs_stack_page_t>?
    public var tail_cursor: UnsafeMutablePointer<ecs_stack_cursor_t>?

    public init() {
        self.first = nil
        self.tail_page = nil
        self.tail_cursor = nil
    }
}

// MARK: - Internal helpers

private func flecs_stack_page_new(_ page_id: UInt32) -> UnsafeMutablePointer<ecs_stack_page_t> {
    let total_size = Int(FLECS_STACK_PAGE_OFFSET) + Int(FLECS_STACK_PAGE_SIZE)
    let raw = malloc(total_size)!
    let result = raw.bindMemory(to: ecs_stack_page_t.self, capacity: 1)
    result.pointee.data = raw.advanced(by: Int(FLECS_STACK_PAGE_OFFSET))
    result.pointee.next = nil
    result.pointee.id = page_id + 1
    result.pointee.sp = 0
    return result
}

// MARK: - Public API

/// Initialize a stack allocator.
public func flecs_stack_init(
    _ stack: UnsafeMutablePointer<ecs_stack_t>)
{
    stack.pointee = ecs_stack_t()
}

/// Deinitialize a stack allocator, freeing all pages.
public func flecs_stack_fini(
    _ stack: UnsafeMutablePointer<ecs_stack_t>)
{
    var cur = stack.pointee.first
    while let c = cur {
        let next = c.pointee.next
        free(UnsafeMutableRawPointer(c))
        cur = next
    }
    stack.pointee = ecs_stack_t()
}

/// Allocate memory from the stack.
public func flecs_stack_alloc(
    _ stack: UnsafeMutablePointer<ecs_stack_t>,
    _ size: ecs_size_t,
    _ align: ecs_size_t) -> UnsafeMutableRawPointer?
{
    if size > Int32(FLECS_STACK_PAGE_SIZE) {
        // Too large for page, fall back to malloc
        return malloc(Int(size))
    }

    if stack.pointee.tail_page == nil {
        let page = flecs_stack_page_new(0)
        stack.pointee.first = page
        stack.pointee.tail_page = page
    }

    var page = stack.pointee.tail_page!

    var sp = Int16((Int(page.pointee.sp) + Int(align) - 1) & ~(Int(align) - 1))
    var next_sp = sp + Int16(size)

    if next_sp > FLECS_STACK_PAGE_SIZE {
        if let n = page.pointee.next {
            page = n
        } else {
            let new_page = flecs_stack_page_new(page.pointee.id)
            page.pointee.next = new_page
            page = new_page
        }
        sp = 0
        next_sp = Int16(size)
        stack.pointee.tail_page = page
    }

    page.pointee.sp = next_sp
    return page.pointee.data!.advanced(by: Int(sp))
}

/// Allocate zeroed memory from the stack.
public func flecs_stack_calloc(
    _ stack: UnsafeMutablePointer<ecs_stack_t>,
    _ size: ecs_size_t,
    _ align: ecs_size_t) -> UnsafeMutableRawPointer?
{
    guard let ptr = flecs_stack_alloc(stack, size, align) else { return nil }
    memset(ptr, 0, Int(size))
    return ptr
}

/// Free memory allocated from the stack.
/// Only frees if the allocation was too large for a page (malloc fallback).
public func flecs_stack_free(
    _ ptr: UnsafeMutableRawPointer?,
    _ size: ecs_size_t)
{
    if size > Int32(FLECS_STACK_PAGE_SIZE) {
        free(ptr)
    }
}

/// Get a cursor marking the current position in the stack.
public func flecs_stack_get_cursor(
    _ stack: UnsafeMutablePointer<ecs_stack_t>) -> UnsafeMutablePointer<ecs_stack_cursor_t>?
{
    if stack.pointee.tail_page == nil {
        let page = flecs_stack_page_new(0)
        stack.pointee.first = page
        stack.pointee.tail_page = page
    }

    let page = stack.pointee.tail_page!
    let sp = page.pointee.sp

    // Allocate cursor from the stack itself
    let cursor_size = Int32(MemoryLayout<ecs_stack_cursor_t>.stride)
    let cursor_align = Int32(MemoryLayout<ecs_stack_cursor_t>.alignment)
    guard let raw = flecs_stack_alloc(stack, cursor_size, cursor_align) else {
        return nil
    }
    let result = raw.bindMemory(to: ecs_stack_cursor_t.self, capacity: 1)
    result.pointee.page = page
    result.pointee.sp = sp
    result.pointee.is_free = false
    result.pointee.prev = stack.pointee.tail_cursor
    stack.pointee.tail_cursor = result
    return result
}

/// Restore the stack to a previously saved cursor position.
public func flecs_stack_restore_cursor(
    _ stack: UnsafeMutablePointer<ecs_stack_t>,
    _ cursor: UnsafeMutablePointer<ecs_stack_cursor_t>?)
{
    guard let cursor = cursor else { return }

    cursor.pointee.is_free = true

    // If cursor is not the last on the stack, no memory should be freed
    if cursor != stack.pointee.tail_cursor {
        return
    }

    // Iterate freed cursors to know how much memory we can free
    var c = cursor
    while true {
        guard let prev = c.pointee.prev, prev.pointee.is_free else {
            break
        }
        c = prev
    }

    stack.pointee.tail_cursor = c.pointee.prev
    stack.pointee.tail_page = c.pointee.page
    stack.pointee.tail_page!.pointee.sp = c.pointee.sp
}

/// Reset the stack allocator.
public func flecs_stack_reset(
    _ stack: UnsafeMutablePointer<ecs_stack_t>)
{
    stack.pointee.tail_page = stack.pointee.first
    if let first = stack.pointee.first {
        first.pointee.sp = 0
    }
    stack.pointee.tail_cursor = nil
}
