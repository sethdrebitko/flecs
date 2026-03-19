/// Strbuf.swift
/// Translation of ecs_strbuf_t and its operations from flecs.
/// String builder with small string optimization.

import Foundation

// MARK: - Constants

/// Size of the small string optimization buffer.
public let ECS_STRBUF_SMALL_STRING_SIZE: Int32 = 512

/// Maximum nesting depth for list operations.
public let ECS_STRBUF_MAX_LIST_DEPTH: Int32 = 32

// MARK: - Types

/// Element tracking for nested list appends.
public struct ecs_strbuf_list_elem {
    public var count: Int32
    public var separator: UnsafePointer<CChar>?

    public init() {
        self.count = 0
        self.separator = nil
    }
}

/// A string buffer for efficient string construction.
/// Uses a small string optimization: starts with an inline buffer,
/// then moves to heap allocation when the string outgrows it.
public struct ecs_strbuf_t {
    public var content: UnsafeMutablePointer<CChar>?
    public var length: ecs_size_t
    public var size: ecs_size_t

    public var list_stack: (
        ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem,
        ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem,
        ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem,
        ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem,
        ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem,
        ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem,
        ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem,
        ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem, ecs_strbuf_list_elem
    )
    public var list_sp: Int32

    /// Small string buffer for SSO. 512 bytes stored as a tuple of 64 UInt64s.
    public var small_string: (
        UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
        UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
        UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
        UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
        UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
        UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
        UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
        UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64
    )

    public init() {
        self.content = nil
        self.length = 0
        self.size = 0
        let e = ecs_strbuf_list_elem()
        self.list_stack = (
            e, e, e, e, e, e, e, e, e, e, e, e, e, e, e, e,
            e, e, e, e, e, e, e, e, e, e, e, e, e, e, e, e
        )
        self.list_sp = 0
        self.small_string = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }
}

// MARK: - Internal helpers

/// Get a pointer to the small_string inline buffer.
@inline(__always)
internal func strbuf_small_string_ptr(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>) -> UnsafeMutablePointer<CChar>
{
    return withUnsafeMutablePointer(to: &b.pointee.small_string) {
        UnsafeMutableRawPointer($0).bindMemory(to: CChar.self, capacity: Int(ECS_STRBUF_SMALL_STRING_SIZE))
    }
}

/// Check if content points to the small string buffer.
@inline(__always)
internal func strbuf_is_small(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>) -> Bool
{
    return b.pointee.content == strbuf_small_string_ptr(b)
}

/// Get the list stack element at an index.
@inline(__always)
internal func strbuf_list_stack_ptr(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>) -> UnsafeMutablePointer<ecs_strbuf_list_elem>
{
    return withUnsafeMutablePointer(to: &b.pointee.list_stack) {
        UnsafeMutableRawPointer($0).bindMemory(
            to: ecs_strbuf_list_elem.self, capacity: Int(ECS_STRBUF_MAX_LIST_DEPTH))
    }
}

/// Get pointer to current write position.
@inline(__always)
private func flecs_strbuf_ptr(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>) -> UnsafeMutablePointer<CChar>
{
    return b.pointee.content!.advanced(by: Int(b.pointee.length))
}

/// Grow the buffer.
private func flecs_strbuf_grow(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>)
{
    if b.pointee.content == nil {
        b.pointee.content = strbuf_small_string_ptr(b)
        b.pointee.size = ECS_STRBUF_SMALL_STRING_SIZE
    } else if strbuf_is_small(b) {
        b.pointee.size *= 2
        let new_content = malloc(Int(b.pointee.size))!
            .bindMemory(to: CChar.self, capacity: Int(b.pointee.size))
        memcpy(new_content, b.pointee.content, Int(b.pointee.length))
        b.pointee.content = new_content
    } else {
        b.pointee.size *= 2
        if b.pointee.size < 16 {
            b.pointee.size = 16
        }
        b.pointee.content = realloc(b.pointee.content, Int(b.pointee.size))?
            .bindMemory(to: CChar.self, capacity: Int(b.pointee.size))
    }
}

/// Append n characters.
private func flecs_strbuf_appendstr(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ str: UnsafePointer<CChar>,
    _ n: Int32)
{
    var mem_left = b.pointee.size - b.pointee.length
    while n >= mem_left {
        flecs_strbuf_grow(b)
        mem_left = b.pointee.size - b.pointee.length
    }
    memcpy(flecs_strbuf_ptr(b), str, Int(n))
    b.pointee.length += n
}

/// Append a single character.
private func flecs_strbuf_appendch(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ ch: CChar)
{
    if b.pointee.size == b.pointee.length {
        flecs_strbuf_grow(b)
    }
    flecs_strbuf_ptr(b).pointee = ch
    b.pointee.length += 1
}

/// Integer to ASCII conversion.
private func flecs_strbuf_itoa(
    _ buf: UnsafeMutablePointer<CChar>,
    _ v: Int64) -> UnsafeMutablePointer<CChar>
{
    var ptr = buf
    var uv: UInt64

    if v < 0 {
        ptr.pointee = CChar(UInt8(ascii: "-"))
        ptr = ptr.advanced(by: 1)
        uv = UInt64(bitPattern: 0 &- v)
    } else {
        uv = UInt64(v)
    }

    if uv == 0 {
        ptr.pointee = CChar(UInt8(ascii: "0"))
        ptr = ptr.advanced(by: 1)
    } else {
        let start = ptr
        while uv > 0 {
            let vdiv = uv / 10
            let vmod = uv - (vdiv * 10)
            ptr.pointee = CChar(UInt8(ascii: "0") + UInt8(vmod))
            ptr = ptr.advanced(by: 1)
            uv = vdiv
        }

        // Reverse
        let end = ptr
        var lo = start
        var hi = ptr.advanced(by: -1)
        while lo < hi {
            let c = lo.pointee
            lo.pointee = hi.pointee
            hi.pointee = c
            lo = lo.advanced(by: 1)
            hi = hi.advanced(by: -1)
        }
        ptr = end
    }

    return ptr
}

// MARK: - Public API

/// Append a string to a buffer.
public func ecs_strbuf_appendstr(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ str: UnsafePointer<CChar>)
{
    flecs_strbuf_appendstr(b, str, Int32(strlen(str)))
}

/// Append n characters to a buffer.
public func ecs_strbuf_appendstrn(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ str: UnsafePointer<CChar>,
    _ n: Int32)
{
    flecs_strbuf_appendstr(b, str, n)
}

/// Append a character to a buffer.
public func ecs_strbuf_appendch(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ ch: CChar)
{
    flecs_strbuf_appendch(b, ch)
}

/// Append an integer to a buffer.
public func ecs_strbuf_appendint(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ v: Int64)
{
    let numbuf = UnsafeMutablePointer<CChar>.allocate(capacity: 32)
    defer { numbuf.deallocate() }
    let end = flecs_strbuf_itoa(numbuf, v)
    let len = end - numbuf
    ecs_strbuf_appendstrn(b, numbuf, Int32(len))
}

/// Append a float to a buffer.
public func ecs_strbuf_appendflt(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ v: Double,
    _ nan_delim: CChar)
{
    // Use snprintf for float formatting
    let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 64)
    defer { buf.deallocate() }

    if v.isNaN {
        if nan_delim != 0 {
            ecs_strbuf_appendch(b, nan_delim)
            "NaN".withCString { ecs_strbuf_appendstrn(b, $0, 3) }
            ecs_strbuf_appendch(b, nan_delim)
        } else {
            "NaN".withCString { ecs_strbuf_appendstrn(b, $0, 3) }
        }
        return
    }
    if v.isInfinite {
        if nan_delim != 0 {
            ecs_strbuf_appendch(b, nan_delim)
            "Inf".withCString { ecs_strbuf_appendstrn(b, $0, 3) }
            ecs_strbuf_appendch(b, nan_delim)
        } else {
            "Inf".withCString { ecs_strbuf_appendstrn(b, $0, 3) }
        }
        return
    }

    let len = snprintf(buf, 64, "%g", v)
    if len > 0 {
        ecs_strbuf_appendstrn(b, buf, Int32(len))
    }
}

/// Append a boolean to a buffer.
public func ecs_strbuf_appendbool(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ v: Bool)
{
    if v {
        "true".withCString { ecs_strbuf_appendstrn(b, $0, 4) }
    } else {
        "false".withCString { ecs_strbuf_appendstrn(b, $0, 5) }
    }
}

/// Append a source buffer to a destination buffer.
public func ecs_strbuf_mergebuff(
    _ dst: UnsafeMutablePointer<ecs_strbuf_t>,
    _ src: UnsafeMutablePointer<ecs_strbuf_t>)
{
    if let content = src.pointee.content {
        flecs_strbuf_appendstr(dst, content, src.pointee.length)
    }
    ecs_strbuf_reset(src)
}

/// Return the result string. Caller owns the returned memory.
/// Returns nil if the buffer is empty.
public func ecs_strbuf_get(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>) -> UnsafeMutablePointer<CChar>?
{
    guard b.pointee.content != nil else {
        return nil
    }

    // Append null terminator
    flecs_strbuf_appendch(b, 0)
    var result = b.pointee.content!

    // If the string is in the small buffer, duplicate to heap
    if strbuf_is_small(b) {
        let len = Int(b.pointee.length)
        let dup = malloc(len)!.bindMemory(to: CChar.self, capacity: len)
        memcpy(dup, result, len)
        result = dup
    }

    b.pointee.length = 0
    b.pointee.content = nil
    b.pointee.size = 0
    b.pointee.list_sp = 0
    return result
}

/// Return the small string from the buffer (appends null terminator in place).
public func ecs_strbuf_get_small(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>) -> UnsafeMutablePointer<CChar>?
{
    guard let result = b.pointee.content else { return nil }
    result[Int(b.pointee.length)] = 0
    b.pointee.length = 0
    b.pointee.content = nil
    b.pointee.size = 0
    return result
}

/// Reset a buffer without returning a string.
public func ecs_strbuf_reset(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>)
{
    if let content = b.pointee.content, !strbuf_is_small(b) {
        free(content)
    }
    b.pointee = ecs_strbuf_t()
}

/// Push a list.
public func ecs_strbuf_list_push(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ list_open: UnsafePointer<CChar>?,
    _ separator: UnsafePointer<CChar>?)
{
    b.pointee.list_sp += 1
    let stack = strbuf_list_stack_ptr(b)
    stack[Int(b.pointee.list_sp)].count = 0
    stack[Int(b.pointee.list_sp)].separator = separator

    if let list_open = list_open {
        let ch = list_open[0]
        if ch != 0 && list_open[1] == 0 {
            ecs_strbuf_appendch(b, ch)
        } else {
            ecs_strbuf_appendstr(b, list_open)
        }
    }
}

/// Pop a list.
public func ecs_strbuf_list_pop(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ list_close: UnsafePointer<CChar>?)
{
    b.pointee.list_sp -= 1

    if let list_close = list_close {
        let ch = list_close[0]
        if ch != 0 && list_close[1] == 0 {
            ecs_strbuf_appendch(b, ch)
        } else {
            ecs_strbuf_appendstr(b, list_close)
        }
    }
}

/// Insert a new element in the list.
public func ecs_strbuf_list_next(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>)
{
    let stack = strbuf_list_stack_ptr(b)
    let list_sp = b.pointee.list_sp
    if stack[Int(list_sp)].count != 0 {
        if let sep = stack[Int(list_sp)].separator {
            if sep[0] != 0 && sep[1] == 0 {
                ecs_strbuf_appendch(b, sep[0])
            } else {
                ecs_strbuf_appendstr(b, sep)
            }
        }
    }
    stack[Int(list_sp)].count += 1
}

/// Append a character as a new element in the list.
public func ecs_strbuf_list_appendch(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ ch: CChar)
{
    ecs_strbuf_list_next(b)
    flecs_strbuf_appendch(b, ch)
}

/// Append a string as a new element in the list.
public func ecs_strbuf_list_appendstr(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ str: UnsafePointer<CChar>)
{
    ecs_strbuf_list_next(b)
    ecs_strbuf_appendstr(b, str)
}

/// Append n characters as a new element in the list.
public func ecs_strbuf_list_appendstrn(
    _ b: UnsafeMutablePointer<ecs_strbuf_t>,
    _ str: UnsafePointer<CChar>,
    _ n: Int32)
{
    ecs_strbuf_list_next(b)
    ecs_strbuf_appendstrn(b, str, n)
}

/// Return the number of bytes written to the buffer.
public func ecs_strbuf_written(
    _ b: UnsafePointer<ecs_strbuf_t>) -> Int32
{
    return b.pointee.length
}
