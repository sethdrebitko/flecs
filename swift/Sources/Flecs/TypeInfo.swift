// TypeInfo.swift - 1:1 translation of flecs type_info.c
// Component metadata, lifecycle hooks, and hook dispatch

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


public func flecs_default_ctor(
    _ ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    if ptr == nil || ti == nil { return }
    memset(ptr, 0, Int(ti!.pointee.size) * Int(count))
}

// These are the canonical versions - they replace the simplified ones in Value.swift

/// Invoke constructor hook. Returns true if a ctor was called.
public func flecs_type_info_ctor_full(
    _ ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>) -> Bool
{
    if ti.pointee.hooks.ctor != nil {
        ti.pointee.hooks.ctor!(ptr, count, ti)
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
    if ti.pointee.hooks.dtor != nil {
        ti.pointee.hooks.dtor!(ptr, count, ti)
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
    if ti.pointee.hooks.copy != nil {
        ti.pointee.hooks.copy!(dst_ptr, src_ptr, count, ti)
    } else if dst_ptr != nil && src_ptr != nil {
        memcpy(dst_ptr!, src_ptr!, Int(ti.pointee.size) * Int(count))
    }
}

/// Invoke move hook. Falls back to memcpy.
public func flecs_type_info_move_full(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if ti.pointee.hooks.move != nil {
        ti.pointee.hooks.move!(dst_ptr, src_ptr, count, ti)
    } else if dst_ptr != nil && src_ptr != nil {
        memcpy(dst_ptr!, src_ptr!, Int(ti.pointee.size) * Int(count))
    }
}

/// Invoke copy-ctor hook. Falls back to memcpy.
public func flecs_type_info_copy_ctor(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if ti.pointee.hooks.copy_ctor != nil {
        ti.pointee.hooks.copy_ctor!(dst_ptr, src_ptr, count, ti)
    } else if dst_ptr != nil && src_ptr != nil {
        memcpy(dst_ptr!, src_ptr!, Int(ti.pointee.size) * Int(count))
    }
}

/// Invoke move-ctor hook. Falls back to memcpy.
public func flecs_type_info_move_ctor_full(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if ti.pointee.hooks.move_ctor != nil {
        ti.pointee.hooks.move_ctor!(dst_ptr, src_ptr, count, ti)
    } else if dst_ptr != nil && src_ptr != nil {
        memcpy(dst_ptr!, src_ptr!, Int(ti.pointee.size) * Int(count))
    }
}

/// Invoke ctor-move-dtor hook. Falls back to memcpy.
public func flecs_type_info_ctor_move_dtor(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if ti.pointee.hooks.ctor_move_dtor != nil {
        ti.pointee.hooks.ctor_move_dtor!(dst_ptr, src_ptr, count, ti)
    } else if dst_ptr != nil && src_ptr != nil {
        memcpy(dst_ptr!, src_ptr!, Int(ti.pointee.size) * Int(count))
    }
}

/// Invoke move-dtor hook. Falls back to memcpy.
public func flecs_type_info_move_dtor(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    if ti.pointee.hooks.move_dtor != nil {
        ti.pointee.hooks.move_dtor!(dst_ptr, src_ptr, count, ti)
    } else if dst_ptr != nil && src_ptr != nil {
        memcpy(dst_ptr!, src_ptr!, Int(ti.pointee.size) * Int(count))
    }
}

/// Invoke compare hook.
public func flecs_type_info_cmp(
    _ a_ptr: UnsafeRawPointer?,
    _ b_ptr: UnsafeRawPointer?,
    _ ti: UnsafePointer<ecs_type_info_t>) -> Int32
{
    if ti.pointee.hooks.cmp == nil { return 0 }
    return ti.pointee.hooks.cmp!(a_ptr, b_ptr, ti)
}

/// Invoke equals hook.
public func flecs_type_info_equals(
    _ a_ptr: UnsafeRawPointer?,
    _ b_ptr: UnsafeRawPointer?,
    _ ti: UnsafePointer<ecs_type_info_t>) -> Bool
{
    if ti.pointee.hooks.equals == nil { return false }
    return ti.pointee.hooks.equals!(a_ptr, b_ptr, ti)
}


private func flecs_default_copy_ctor_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    if ti == nil { return }
    let cl = ti!.pointee.hooks
    cl.ctor?(dst_ptr, count, ti!)
    cl.copy?(dst_ptr, src_ptr, count, ti!)
}

private func flecs_default_move_ctor_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    if ti == nil { return }
    let cl = ti!.pointee.hooks
    cl.ctor?(dst_ptr, count, ti!)
    cl.move?(dst_ptr, src_ptr, count, ti!)
}

private func flecs_default_ctor_w_move_w_dtor_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    if ti == nil { return }
    let cl = ti!.pointee.hooks
    cl.ctor?(dst_ptr, count, ti!)
    cl.move?(dst_ptr, src_ptr, count, ti!)
    cl.dtor?(src_ptr, count, ti!)
}

private func flecs_default_move_ctor_w_dtor_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    if ti == nil { return }
    let cl = ti!.pointee.hooks
    cl.move_ctor?(dst_ptr, src_ptr, count, ti!)
    cl.dtor?(src_ptr, count, ti!)
}

private func flecs_default_move_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    if ti == nil { return }
    ti!.pointee.hooks.move?(dst_ptr, src_ptr, count, ti!)
}

private func flecs_default_dtor_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    if ti == nil { return }
    let cl = ti!.pointee.hooks
    cl.dtor?(dst_ptr, count, ti!)
    if dst_ptr != nil && src_ptr != nil {
        memcpy(dst_ptr!, src_ptr!, Int(ti!.pointee.size) * Int(count))
    }
}

private func flecs_default_move_w_dtor_fn(
    _ dst_ptr: UnsafeMutableRawPointer?,
    _ src_ptr: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ ti: UnsafePointer<ecs_type_info_t>?)
{
    if ti == nil { return }
    let cl = ti!.pointee.hooks
    cl.move?(dst_ptr, src_ptr, count, ti!)
    cl.dtor?(src_ptr, count, ti!)
}


/// Finalize type info, freeing associated resources.
public func flecs_type_info_fini(
    _ ti: UnsafeMutablePointer<ecs_type_info_t>)
{
    if ti.pointee.hooks.ctx_free != nil {
        ti.pointee.hooks.ctx_free!(ti.pointee.hooks.ctx)
    }
    if ti.pointee.hooks.binding_ctx_free != nil {
        ti.pointee.hooks.binding_ctx_free!(ti.pointee.hooks.binding_ctx)
    }
    if ti.pointee.hooks.lifecycle_ctx_free != nil {
        ti.pointee.hooks.lifecycle_ctx_free!(ti.pointee.hooks.lifecycle_ctx)
    }
    if ti.pointee.name != nil {
        free(UnsafeMutableRawPointer(mutating: ti.pointee.name!))
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
        let ti = ecs_map_ptr(&it)
        if ti != nil {
            let ti_typed = ti!.bindMemory(to: ecs_type_info_t.self, capacity: 1)
            flecs_type_info_fini(ti_typed)
            free(ti!)
        }
    }
    ecs_map_fini(&world.pointee.type_info)
}


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
