// EntityName.swift - 1:1 translation of flecs entity_name.c
// Functions for working with named entities: paths, lookups, scoping

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


private let ECS_NAME_BUFFER_LENGTH: Int32 = 64


/// Check if name is a numeric id reference (starts with '#')
public func flecs_name_is_id_full(
    _ name: UnsafePointer<CChar>?) -> Bool
{
    if name == nil { return false }
    if name![0] != CChar(UInt8(ascii: "#")) { return false }
    var ptr = name!.advanced(by: 1)
    while ptr.pointee != 0 {
        if !(ptr.pointee >= CChar(UInt8(ascii: "0")) && ptr.pointee <= CChar(UInt8(ascii: "9"))) {
            return false
        }
        ptr = ptr.advanced(by: 1)
    }
    return true
}

/// Convert a name like "#123" to an entity id
public func flecs_name_to_id_full(
    _ name: UnsafePointer<CChar>?) -> ecs_entity_t
{
    if name == nil || name![0] != CChar(UInt8(ascii: "#")) { return 0 }
    let res = UInt64(atoll(name!.advanced(by: 1)))
    if res >= UInt64(UInt32.max) {
        return 0
    }
    return res
}

/// Get a builtin entity by single-character name
private func flecs_get_builtin(
    _ name: UnsafePointer<CChar>) -> ecs_entity_t
{
    if name[0] == CChar(UInt8(ascii: ".")) && name[1] == 0 {
        return EcsThis
    } else if name[0] == CChar(UInt8(ascii: "*")) && name[1] == 0 {
        return EcsWildcard
    } else if name[0] == CChar(UInt8(ascii: "_")) && name[1] == 0 {
        return EcsAny
    } else if name[0] == CChar(UInt8(ascii: "$")) && name[1] == 0 {
        return EcsVariable
    }
    return 0
}

/// Check if current position in path matches separator
private func flecs_is_sep(
    _ ptr: UnsafeMutablePointer<UnsafePointer<CChar>>,
    _ sep: UnsafePointer<CChar>) -> Bool
{
    let len = strlen(sep)
    if strncmp(ptr.pointee, sep, len) == 0 {
        ptr.pointee = ptr.pointee.advanced(by: len)
        return true
    }
    return false
}

/// Check if path starts with the root prefix
private func flecs_is_root_path(
    _ path: UnsafePointer<CChar>,
    _ prefix: UnsafePointer<CChar>?) -> Bool
{
    if prefix == nil { return false }
    return strncmp(path, prefix!, strlen(prefix!)) == 0
}

/// Extract the next path element between separators.
/// Returns pointer to rest of path after the element, or nil if done.
public func flecs_path_elem(
    _ path: UnsafePointer<CChar>,
    _ sep: UnsafePointer<CChar>,
    _ buffer_out: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    _ size_out: UnsafeMutablePointer<ecs_size_t>?) -> UnsafePointer<CChar>?
{
    var buffer: UnsafeMutablePointer<CChar>? = nil
    if buffer_out != nil {
        buffer = buffer_out!.pointee
    }

    var template_nesting: Int32 = 0
    var pos: Int32 = 0
    var size: ecs_size_t = size_out?.pointee ?? 0

    var ptr = path
    while ptr.pointee != 0 {
        var ch = ptr.pointee
        var escaped = false

        if ch == CChar(UInt8(ascii: "<")) {
            template_nesting += 1
        } else if ch == CChar(UInt8(ascii: ">")) {
            template_nesting -= 1
        } else if ch == CChar(UInt8(ascii: "\\")) {
            ptr = ptr.advanced(by: 1)
            ch = ptr.pointee
            if ch == 0 { break }
            escaped = true
        }

        if template_nesting < 0 { return nil }

        if !escaped && template_nesting == 0 {
            var sep_ptr = ptr
            if flecs_is_sep(&sep_ptr, sep) {
                ptr = sep_ptr
                break
            }
        }

        if buffer != nil {
            if pos >= (size - 1) {
                if size == ECS_NAME_BUFFER_LENGTH {
                    let new_buffer = ecs_os_calloc_n(CChar.self, Int32(size * 2 + 1))!
                    memcpy(new_buffer, buffer!, Int(size))
                    buffer_out?.pointee = new_buffer
                } else {
                    let new_buffer = realloc(buffer!, Int(size * 2 + 1))!
                        .bindMemory(to: CChar.self, capacity: Int(size * 2 + 1))
                    buffer_out?.pointee = new_buffer
                }
                size *= 2
            }
            buffer_out?.pointee?[Int(pos)] = ch
        }

        pos += 1
        ptr = ptr.advanced(by: 1)
    }

    if buffer_out != nil && buffer_out!.pointee != nil {
        buffer_out!.pointee![Int(pos)] = 0
        if size_out != nil {
            size_out!.pointee = size
        }
    }

    if pos > 0 || ptr.pointee != 0 {
        return UnsafePointer(ptr)
    }
    return nil
}

/// Get parent entity from path prefix
public func flecs_get_parent_from_path(
    _ world: UnsafePointer<ecs_world_t>,
    _ parent: ecs_entity_t,
    _ path_ptr: UnsafeMutablePointer<UnsafePointer<CChar>>,
    _ sep: UnsafePointer<CChar>,
    _ prefix: UnsafePointer<CChar>?,
    _ new_entity: Bool,
    _ error: UnsafeMutablePointer<Bool>) -> ecs_entity_t
{
    var parent = parent
    var start_from_root = false
    var path = path_ptr.pointee

    if flecs_is_root_path(path, prefix) {
        if prefix != nil {
            path = path.advanced(by: strlen(prefix!))
        }
        parent = 0
        start_from_root = true
    }

    if path[0] == CChar(UInt8(ascii: "#")) {
        parent = flecs_name_to_id_full(path)
        // Skip past #<digits>
        path = path.advanced(by: 1)
        while path.pointee != 0 &&
              path.pointee >= CChar(UInt8(ascii: "0")) &&
              path.pointee <= CChar(UInt8(ascii: "9")) {
            path = path.advanced(by: 1)
        }

        let sep_len = strlen(sep)
        if strncmp(path, sep, sep_len) == 0 {
            path = path.advanced(by: sep_len)
        }

        start_from_root = true
    }

    if !start_from_root && parent == 0 && new_entity {
        // Would call ecs_get_scope(world) in full implementation
    }

    path_ptr.pointee = path
    return parent
}


/// Get the full path of an entity as a string
public func ecs_get_path_w_sep(
    _ world: UnsafePointer<ecs_world_t>,
    _ parent: ecs_entity_t,
    _ child: ecs_entity_t,
    _ sep: UnsafePointer<CChar>?,
    _ prefix: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
{
    var buf = ecs_strbuf_t()
    ecs_get_path_w_sep_buf(world, parent, child, sep, prefix, &buf, false)
    return ecs_strbuf_get(&buf)
}

/// Write entity path to a string buffer
public func ecs_get_path_w_sep_buf(
    _ world: UnsafePointer<ecs_world_t>,
    _ parent: ecs_entity_t,
    _ child: ecs_entity_t,
    _ sep: UnsafePointer<CChar>?,
    _ prefix: UnsafePointer<CChar>?,
    _ buf: UnsafeMutablePointer<ecs_strbuf_t>,
    _ escape: Bool)
{
    if child == EcsWildcard {
        "*".withCString { ecs_strbuf_appendch(buf, $0.pointee) }
        return
    }
    if child == EcsAny {
        "_".withCString { ecs_strbuf_appendch(buf, $0.pointee) }
        return
    }

    // Full path building requires ecs_is_alive, ecs_get_target, etc.
    // Those are in entity.c which has complex deps.
    // Stub: just append #<id> for now
    "#".withCString { ecs_strbuf_appendch(buf, $0.pointee) }
    ecs_strbuf_appendint(buf, Int64(child & UInt64(UInt32.max)))
}


/// Set name prefix for automatic name stripping.
public func ecs_set_name_prefix(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ prefix: UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
{
    let old_prefix = world.pointee.info.name_prefix
    world.pointee.info.name_prefix = prefix
    return old_prefix
}
