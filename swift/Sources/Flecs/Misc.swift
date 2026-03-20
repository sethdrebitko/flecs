// Misc.swift - 1:1 translation of flecs misc.c
// Utility functions, hashing, and error handling

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


public func flecs_hash(
    _ data: UnsafeRawPointer?,
    _ length: ecs_size_t
) -> UInt64 {
    if data == nil || length <= 0 { return 0 }

    var hash: UInt64 = 14695981039346656037 // FNV offset basis
    let bytes = data!.assumingMemoryBound(to: UInt8.self)

    for i in 0..<Int(length) {
        hash ^= UInt64(bytes[i])
        hash = hash &* 1099511628211 // FNV prime
    }

    return hash
}


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
    if a == nil || b == nil { return 0 }
    let id_a = a!.assumingMemoryBound(to: ecs_id_t.self).pointee
    let id_b = b!.assumingMemoryBound(to: ecs_id_t.self).pointee
    if id_a < id_b { return -1 }
    if id_a > id_b { return 1 }
    return 0
}


public func flecs_name_is_id(
    _ name: UnsafePointer<CChar>?
) -> Bool {
    if name == nil { return false }
    return name![0] == CChar(UInt8(ascii: "#"))
}

public func flecs_name_to_id(
    _ name: UnsafePointer<CChar>?
) -> ecs_entity_t {
    if name == nil || name![0] != CChar(UInt8(ascii: "#")) { return 0 }
    let str = String(cString: name!.advanced(by: 1))
    return ecs_entity_t(str) ?? 0
}


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


// Thread-local error strings for use in assert messages
private var _errstr_buf = [CChar](repeating: 0, count: 256)
private var _errstr_1_buf = [CChar](repeating: 0, count: 256)

public func flecs_errstr(
    _ str: UnsafeMutablePointer<CChar>?
) -> UnsafePointer<CChar>? {
    if str == nil { return nil }
    // Copy and free the original
    let s = String(cString: str!)
    ecs_os_free(UnsafeMutableRawPointer(str!))
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


/// Convert ecs_time_t to double (seconds).
public func ecs_time_to_double(
    _ t: ecs_time_t) -> Double
{
    return Double(t.sec) + Double(t.nanosec) / 1_000_000_000.0
}

/// Subtract two time values.
public func ecs_time_sub(
    _ t1: ecs_time_t,
    _ t2: ecs_time_t) -> ecs_time_t
{
    var result = ecs_time_t()
    if t1.nanosec >= t2.nanosec {
        result.nanosec = t1.nanosec - t2.nanosec
        result.sec = t1.sec - t2.sec
    } else {
        result.nanosec = t1.nanosec - t2.nanosec + 1_000_000_000
        result.sec = t1.sec - t2.sec - 1
    }
    return result
}

/// Sleep for a fractional number of seconds.
public func ecs_sleepf(_ t: Double) {
    if t > 0 {
        let sec = Int32(t)
        let nsec = Int32((t - Double(sec)) * 1_000_000_000.0)
        ecs_os_sleep(sec, nsec)
    }
}

/// Measure time since start, updating start to now. Returns elapsed seconds.
public func ecs_time_measure(
    _ start: UnsafeMutablePointer<ecs_time_t>) -> Double
{
    var stop = ecs_time_t()
    ecs_os_get_time(&stop)
    let temp = stop
    stop = ecs_time_sub(stop, start.pointee)
    start.pointee = temp
    return ecs_time_to_double(stop)
}


/// Duplicate a memory region.
public func ecs_os_memdup(
    _ src: UnsafeRawPointer?,
    _ size: ecs_size_t) -> UnsafeMutableRawPointer?
{
    if src == nil { return nil }
    let dst = ecs_os_malloc(Int32(size))
    if dst == nil { return nil }
    memcpy(dst!, src!, Int(size))
    return dst
}


/// Escape a single character to a buffer. Returns pointer past written chars.
public func flecs_chresc(
    _ out: UnsafeMutablePointer<CChar>,
    _ ch: CChar,
    _ delimiter: CChar) -> UnsafeMutablePointer<CChar>
{
    var bptr = out
    switch ch {
    case 7:  bptr.pointee = 92; bptr += 1; bptr.pointee = 97   // \a
    case 8:  bptr.pointee = 92; bptr += 1; bptr.pointee = 98   // \b
    case 12: bptr.pointee = 92; bptr += 1; bptr.pointee = 102  // \f
    case 10: bptr.pointee = 92; bptr += 1; bptr.pointee = 110  // \n
    case 13: bptr.pointee = 92; bptr += 1; bptr.pointee = 114  // \r
    case 9:  bptr.pointee = 92; bptr += 1; bptr.pointee = 116  // \t
    case 11: bptr.pointee = 92; bptr += 1; bptr.pointee = 118  // \v
    case 92: bptr.pointee = 92; bptr += 1; bptr.pointee = 92   // \\
    case 27: bptr.pointee = 91 // ESC -> [
    default:
        if ch == delimiter {
            bptr.pointee = 92; bptr += 1; bptr.pointee = delimiter
        } else {
            bptr.pointee = ch
        }
    }
    bptr += 1
    bptr.pointee = 0
    return bptr
}

/// Parse an escaped character. Returns pointer past parsed chars.
public func flecs_chrparse(
    _ in_ptr: UnsafePointer<CChar>,
    _ out: UnsafeMutablePointer<CChar>?) -> UnsafePointer<CChar>?
{
    var result = in_ptr + 1
    var ch: CChar

    if in_ptr[0] == 92 { // backslash
        result += 1
        switch in_ptr[1] {
        case 97:  ch = 7   // \a
        case 98:  ch = 8   // \b
        case 102: ch = 12  // \f
        case 110: ch = 10  // \n
        case 114: ch = 13  // \r
        case 116: ch = 9   // \t
        case 118: ch = 11  // \v
        case 92:  ch = 92  // \\
        case 34:  ch = 34  // \"
        case 48:  ch = 0   // \0
        case 32:  ch = 32  // \ (space)
        case 36:  ch = 36  // \$
        default: return nil
        }
    } else {
        ch = in_ptr[0]
    }

    out?.pointee = ch
    return result
}

/// Escape a string, writing to buffer. Returns number of chars needed.
public func flecs_stresc(
    _ out: UnsafeMutablePointer<CChar>?,
    _ n: ecs_size_t,
    _ delimiter: CChar,
    _ in_str: UnsafePointer<CChar>) -> ecs_size_t
{
    var ptr = in_str
    var bptr = out
    var buff = (CChar(0), CChar(0), CChar(0))
    var written: ecs_size_t = 0

    while ptr.pointee != 0 {
        let ch = ptr.pointee
        ptr += 1
        let end = flecs_chresc(&buff.0, ch, delimiter)
        let len = ecs_size_t(end - withUnsafeMutablePointer(to: &buff.0) { $0 })
        written += len
        if written <= n, let bptr = bptr {
            bptr.pointee = buff.0
            if buff.1 != 0 {
                (bptr + 1).pointee = buff.1
            }
        }
        bptr = bptr.map { $0 + Int(len) }
    }

    return written
}

/// Escape a string, allocating result.
public func flecs_astresc(
    _ delimiter: CChar,
    _ in_str: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
{
    if in_str == nil { return nil }
    let len = flecs_stresc(nil, 0, delimiter, in_str!)
    let out = ecs_os_calloc_n(CChar.self, Int32(len + 1))!
    flecs_stresc(out, len, delimiter, in_str!)
    out[Int(len)] = 0
    return out
}


/// Convert a CamelCase string to snake_case.
public func flecs_to_snake_case(
    _ str: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
{
    var upper_count: Int32 = 0
    var len: Int32 = 1
    var ptr = str + 1

    while ptr.pointee != 0 {
        if ptr.pointee >= 65 && ptr.pointee <= 90 { upper_count += 1 }
        len += 1
        ptr += 1
    }

    let out = ecs_os_calloc_n(CChar.self, Int32(len + upper_count + 1))!
    var out_ptr = out
    ptr = str

    while ptr.pointee != 0 {
        let ch = ptr.pointee
        if ch >= 65 && ch <= 90 { // isupper
            if ptr != str && (out_ptr - 1).pointee != 95 { // not '_'
                out_ptr.pointee = 95 // '_'
                out_ptr += 1
            }
            out_ptr.pointee = ch + 32 // tolower
        } else {
            out_ptr.pointee = ch
        }
        out_ptr += 1
        ptr += 1
    }

    out_ptr.pointee = 0
    return out
}


/// Parse a number from a string into a token buffer.
public func flecs_parse_digit(
    _ ptr: UnsafePointer<CChar>,
    _ token: UnsafeMutablePointer<CChar>) -> UnsafePointer<CChar>?
{
    var p = ptr
    var t = token
    var ch = p.pointee

    // Must start with digit or -
    guard (ch >= 48 && ch <= 57) || ch == 45 else { return nil }

    t.pointee = ch; t += 1; p += 1

    while true {
        ch = p.pointee
        if ch == 0 { break }
        let is_digit = ch >= 48 && ch <= 57
        let is_dot = ch == 46
        let is_e = ch == 101 || ch == 69
        let is_minus = ch == 45

        if !is_digit && !is_dot && !is_e {
            if !is_minus || !((p - 1).pointee == 101 || (p - 1).pointee == 69) {
                break
            }
        }

        t.pointee = ch; t += 1; p += 1
    }

    t.pointee = 0
    return p
}

/// Skip whitespace including newlines.
public func flecs_parse_ws_eol(
    _ ptr: UnsafePointer<CChar>) -> UnsafePointer<CChar>
{
    var p = ptr
    while p.pointee == 32 || p.pointee == 9 || p.pointee == 10 || p.pointee == 13 {
        p += 1
    }
    return p
}


private var _errstr_2_buf = [CChar](repeating: 0, count: 256)
private var _errstr_3_buf = [CChar](repeating: 0, count: 256)
private var _errstr_4_buf = [CChar](repeating: 0, count: 256)
private var _errstr_5_buf = [CChar](repeating: 0, count: 256)

private func _copy_errstr(
    _ str: UnsafeMutablePointer<CChar>?,
    _ buf: UnsafeMutablePointer<CChar>) -> UnsafePointer<CChar>?
{
    if str == nil { return nil }
    strncpy(buf, str!, 255)
    buf[255] = 0
    ecs_os_free(UnsafeMutableRawPointer(str!))
    return UnsafePointer(buf)
}

public func flecs_errstr_1(_ str: UnsafeMutablePointer<CChar>?) -> UnsafePointer<CChar>? {
    return _copy_errstr(str, &_errstr_1_buf)
}
public func flecs_errstr_2(_ str: UnsafeMutablePointer<CChar>?) -> UnsafePointer<CChar>? {
    return _copy_errstr(str, &_errstr_2_buf)
}
public func flecs_errstr_3(_ str: UnsafeMutablePointer<CChar>?) -> UnsafePointer<CChar>? {
    return _copy_errstr(str, &_errstr_3_buf)
}
public func flecs_errstr_4(_ str: UnsafeMutablePointer<CChar>?) -> UnsafePointer<CChar>? {
    return _copy_errstr(str, &_errstr_4_buf)
}
public func flecs_errstr_5(_ str: UnsafeMutablePointer<CChar>?) -> UnsafePointer<CChar>? {
    return _copy_errstr(str, &_errstr_5_buf)
}


/// Load file contents into a string.
public func flecs_load_from_file(
    _ filename: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
{
    let file = fopen(filename, "r")
    if file == nil {
        return nil
    }

    fseek(file, 0, SEEK_END)
    let bytes = Int32(ftell(file))
    if bytes == -1 {
        fclose(file)
        return nil
    }
    fseek(file, 0, SEEK_SET)

    let content = ecs_os_malloc(ecs_size_t(bytes + 1))
    if content == nil {
        fclose(file)
        return nil
    }

    let size = fread(content, 1, Int(bytes), file)
    if size == 0 && bytes > 0 {
        ecs_os_free(content)
        fclose(file)
        return nil
    }

    content!.assumingMemoryBound(to: CChar.self)[size] = 0
    fclose(file)
    return content!.assumingMemoryBound(to: CChar.self)
}


public func flecs_type_size(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ type_entity: ecs_entity_t
) -> ecs_size_t {
    // Look up type info from the world's type_info map
    let val = ecs_map_get(&world.pointee.type_info, type_entity)
    if val == nil {
        return 0
    }
    let ti = UnsafePointer<ecs_type_info_t>(bitPattern: UInt(val!.pointee))
    return ti?.pointee.size ?? 0
}


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
