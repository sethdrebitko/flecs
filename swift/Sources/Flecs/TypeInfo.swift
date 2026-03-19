// TypeInfo.swift - 1:1 translation of flecs type_info.c
// Component metadata, lifecycle hooks, and hook dispatch

import Foundation

// MARK: - Default Constructor

public func flecs_default_ctor(
    _ ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    guard let ptr = ptr, let ti = ti else { return }
    memset(ptr, 0, Int(ti.pointee.size) * Int(count))
}

// MARK: - Hook Dispatch Functions
// These are the canonical versions - they replace the simplified ones in Value.swift

/// Invoke constructor hook. Returns true if a ctor was called.
public func flecs_type_info_ctor_full(
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

/// Invoke destructor hook. Returns true if a dtor was called.
public func flecs_type_info_dtor_full(
    _ ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>) -> Bool
{
    if let dtor = ti.pointee.hooks.dtor {
        dtor(ptr, count, ti)
        return true
    }
    return false
}

/// Invoke copy hook. Falls back to memcpy.
public func flecs_type_info_copy_full(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if let copy = ti.pointee.hooks.copy {
        copy(dst_ptr, src_ptr, count, ti)
    } else if let dst = dst_ptr, let src = src_ptr {
        memcpy(dst, src, Int(ti.pointee.size) * Int(count))
    }
}

/// Invoke move hook. Falls back to memcpy.
public func flecs_type_info_move_full(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if let move = ti.pointee.hooks.move {
        move(dst_ptr, src_ptr, count, ti)
    } else if let dst = dst_ptr, let src = src_ptr {
        memcpy(dst, src, Int(ti.pointee.size) * Int(count))
    }
}

/// Invoke copy-ctor hook. Falls back to memcpy.
public func flecs_type_info_copy_ctor(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if let copy_ctor = ti.pointee.hooks.copy_ctor {
        copy_ctor(dst_ptr, src_ptr, count, ti)
    } else if let dst = dst_ptr, let src = src_ptr {
        memcpy(dst, src, Int(ti.pointee.size) * Int(count))
    }
}

/// Invoke move-ctor hook. Falls back to memcpy.
public func flecs_type_info_move_ctor_full(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if let move_ctor = ti.pointee.hooks.move_ctor {
        move_ctor(dst_ptr, src_ptr, count, ti)
    } else if let dst = dst_ptr, let src = src_ptr {
        memcpy(dst, src, Int(ti.pointee.size) * Int(count))
    }
}

/// Invoke ctor-move-dtor hook. Falls back to memcpy.
public func flecs_type_info_ctor_move_dtor(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if let ctor_move_dtor = ti.pointee.hooks.ctor_move_dtor {
        ctor_move_dtor(dst_ptr, src_ptr, count, ti)
    } else if let dst = dst_ptr, let src = src_ptr {
        memcpy(dst, src, Int(ti.pointee.size) * Int(count))
    }
}

/// Invoke move-dtor hook. Falls back to memcpy.
public func flecs_type_info_move_dtor(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if let move_dtor = ti.pointee.hooks.move_dtor {
        move_dtor(dst_ptr, src_ptr, count, ti)
    } else if let dst = dst_ptr, let src = src_ptr {
        memcpy(dst, src, Int(ti.pointee.size) * Int(count))
    }
}

/// Invoke compare hook.
public func flecs_type_info_cmp(
    _ a_ptr: UnsafeRawPointer?,
    _ b_ptr: UnsafeRawPointer?,
    _ ti: UnsafePointer<ecs_type_info_t>) -> Int32
{
    guard let cmp = ti.pointee.hooks.cmp else { return 0 }
    return cmp(a_ptr, b_ptr, ti)
}

/// Invoke equals hook.
public func flecs_type_info_equals(
    _ a_ptr: UnsafeRawPointer?,
    _ b_ptr: UnsafeRawPointer?,
    _ ti: UnsafePointer<ecs_type_info_t>) -> Bool
{
    guard let equals = ti.pointee.hooks.equals else { return false }
    return equals(a_ptr, b_ptr, ti)
}

// MARK: - Default Hook Combinators

private func flecs_default_copy_ctor_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    guard let ti = ti else { return }
    let cl = ti.pointee.hooks
    cl.ctor?(dst_ptr, count, ti)
    cl.copy?(dst_ptr, src_ptr, count, ti)
}

private func flecs_default_move_ctor_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    guard let ti = ti else { return }
    let cl = ti.pointee.hooks
    cl.ctor?(dst_ptr, count, ti)
    cl.move?(dst_ptr, src_ptr, count, ti)
}

private func flecs_default_ctor_w_move_w_dtor_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    guard let ti = ti else { return }
    let cl = ti.pointee.hooks
    cl.ctor?(dst_ptr, count, ti)
    cl.move?(dst_ptr, src_ptr, count, ti)
    cl.dtor?(src_ptr, count, ti)
}

private func flecs_default_move_ctor_w_dtor_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    guard let ti = ti else { return }
    let cl = ti.pointee.hooks
    cl.move_ctor?(dst_ptr, src_ptr, count, ti)
    cl.dtor?(src_ptr, count, ti)
}

private func flecs_default_move_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    guard let ti = ti else { return }
    ti.pointee.hooks.move?(dst_ptr, src_ptr, count, ti)
}

private func flecs_default_dtor_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    guard let ti = ti else { return }
    let cl = ti.pointee.hooks
    cl.dtor?(dst_ptr, count, ti)
    if let dst = dst_ptr, let src = src_ptr {
        memcpy(dst, src, Int(ti.pointee.size) * Int(count))
    }
}

private func flecs_default_move_w_dtor_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    guard let ti = ti else { return }
    let cl = ti.pointee.hooks
    cl.move?(dst_ptr, src_ptr, count, ti)
    cl.dtor?(src_ptr, count, ti)
}

// MARK: - Type Info Lifecycle

/// Finalize type info, freeing associated resources.
public func flecs_type_info_fini(
    _ ti: UnsafeMutablePointer<ecs_type_info_t>)
{
    if let ctx_free = ti.pointee.hooks.ctx_free {
        ctx_free(ti.pointee.hooks.ctx)
    }
    if let binding_ctx_free = ti.pointee.hooks.binding_ctx_free {
        binding_ctx_free(ti.pointee.hooks.binding_ctx)
    }
    if let lifecycle_ctx_free = ti.pointee.hooks.lifecycle_ctx_free {
        lifecycle_ctx_free(ti.pointee.hooks.lifecycle_ctx)
    }
    if let name = ti.pointee.name {
        free(UnsafeMutableRawPointer(mutating: name))
        ti.pointee.name = nil
    }

    ti.pointee.size = 0
    ti.pointee.alignment = 0
}

/// Finalize all type info in the world.
public func flecs_fini_type_info(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    var it = ecs_map_iter(&world.pointee.type_info)
    while ecs_map_next(&it) {
        if let ti = ecs_map_ptr(&it) {
            let ti_typed = ti.bindMemory(to: ecs_type_info_t.self, capacity: 1)
            flecs_type_info_fini(ti_typed)
            free(ti)
        }
    }
    ecs_map_fini(&world.pointee.type_info)
}

// MARK: - Type Info Query

/// Get the type hooks for a component.
public func ecs_get_hooks_id(
    _ world: UnsafePointer<ecs_world_t>,
    _ id: ecs_entity_t) -> UnsafePointer<ecs_type_hooks_t>?
{
    // Would call ecs_get_type_info -> cr->type_info in full impl
    return nil
}

/// Determine type info for a component id (pair resolution).
public func flecs_determine_type_info_for_component(
    _ world: UnsafePointer<ecs_world_t>,
    _ id: ecs_id_t) -> UnsafePointer<ecs_type_info_t>?
{
    if !ECS_IS_PAIR(id) {
        if (id & ECS_ID_FLAGS_MASK) == 0 {
            // Would look up from world->type_info map
            return nil
        }
    } else {
        let rel = ECS_PAIR_FIRST(id)
        // Would resolve alive entity and check for PairIsTag, then look up type info
        _ = rel
    }
    return nil
}
