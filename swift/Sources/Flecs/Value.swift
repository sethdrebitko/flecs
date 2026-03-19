// Value.swift - 1:1 translation of flecs value.c
// Utility functions to work with non-trivial pointers of user types

import Foundation

// MARK: - Type info helpers (internal)

// These call the type hooks (ctor/dtor/copy/move) through the type_info
@inline(__always)
internal func flecs_type_info_ctor(
    _ ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>) -> Bool
{
    if let ctor = ti.pointee.hooks.ctor {
        ctor(ptr, count, ti)
        return true
    }
    return false
}

@inline(__always)
internal func flecs_type_info_dtor(
    _ ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if let dtor = ti.pointee.hooks.dtor {
        dtor(ptr, count, ti)
    }
}

@inline(__always)
internal func flecs_type_info_copy(
    _ dst: UnsafeMutableRawPointer?,
    _ src: UnsafeRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if let copy = ti.pointee.hooks.copy {
        copy(dst, src, count, ti)
    } else if let dst = dst, let src = src {
        memcpy(dst, src, Int(ti.pointee.size) * Int(count))
    }
}

@inline(__always)
internal func flecs_type_info_move(
    _ dst: UnsafeMutableRawPointer?,
    _ src: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if let move = ti.pointee.hooks.move {
        move(dst, src, count, ti)
    } else if let dst = dst, let src = src {
        memcpy(dst, src, Int(ti.pointee.size) * Int(count))
    }
}

@inline(__always)
internal func flecs_type_info_move_ctor(
    _ dst: UnsafeMutableRawPointer?,
    _ src: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if let move_ctor = ti.pointee.hooks.move_ctor {
        move_ctor(dst, src, count, ti)
    } else if let dst = dst, let src = src {
        memcpy(dst, src, Int(ti.pointee.size) * Int(count))
    }
}

// MARK: - Public API

/// Initialize a value using type info.
public func ecs_value_init_w_type_info(
    _ world: UnsafePointer<ecs_world_t>,
    _ ti: UnsafePointer<ecs_type_info_t>,
    _ ptr: UnsafeMutableRawPointer?) -> Int32
{
    guard let ptr = ptr else { return -1 }

    if !flecs_type_info_ctor(ptr, 1, ti) {
        memset(ptr, 0, Int(ti.pointee.size))
    }

    return 0
}

/// Initialize a value by entity type.
public func ecs_value_init(
    _ world: UnsafePointer<ecs_world_t>,
    _ type: ecs_entity_t,
    _ ptr: UnsafeMutableRawPointer?) -> Int32
{
    // Would call ecs_get_type_info(world, type) in full implementation
    // For now, return error since we don't have the full lookup chain yet
    return -1
}

/// Finalize a value using type info.
public func ecs_value_fini_w_type_info(
    _ world: UnsafePointer<ecs_world_t>,
    _ ti: UnsafePointer<ecs_type_info_t>,
    _ ptr: UnsafeMutableRawPointer?) -> Int32
{
    guard let ptr = ptr else { return -1 }
    flecs_type_info_dtor(ptr, 1, ti)
    return 0
}

/// Finalize a value by entity type.
public func ecs_value_fini(
    _ world: UnsafePointer<ecs_world_t>,
    _ type: ecs_entity_t,
    _ ptr: UnsafeMutableRawPointer?) -> Int32
{
    return -1
}

/// Copy a value using type info.
public func ecs_value_copy_w_type_info(
    _ world: UnsafePointer<ecs_world_t>,
    _ ti: UnsafePointer<ecs_type_info_t>,
    _ dst: UnsafeMutableRawPointer?,
    _ src: UnsafeRawPointer?) -> Int32
{
    flecs_type_info_copy(dst, src, 1, ti)
    return 0
}

/// Move a value using type info.
public func ecs_value_move_w_type_info(
    _ world: UnsafePointer<ecs_world_t>,
    _ ti: UnsafePointer<ecs_type_info_t>,
    _ dst: UnsafeMutableRawPointer?,
    _ src: UnsafeMutableRawPointer?) -> Int32
{
    flecs_type_info_move(dst, src, 1, ti)
    return 0
}

/// Move-construct a value using type info.
public func ecs_value_move_ctor_w_type_info(
    _ world: UnsafePointer<ecs_world_t>,
    _ ti: UnsafePointer<ecs_type_info_t>,
    _ dst: UnsafeMutableRawPointer?,
    _ src: UnsafeMutableRawPointer?) -> Int32
{
    flecs_type_info_move_ctor(dst, src, 1, ti)
    return 0
}
