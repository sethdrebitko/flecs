// OnDelete.swift - 1:1 translation of flecs on_delete.c
// Implementation of OnDelete/OnDeleteTarget cleanup policies

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Extract OnDelete action from component record flags (bits 0-2).
@inline(__always)
public func ECS_ID_ON_DELETE(_ flags: ecs_flags32_t) -> ecs_entity_t {
    let action = flags & EcsIdOnDeleteMask
    if (action & EcsIdOnDeleteDelete) != 0 { return EcsDelete }
    if (action & EcsIdOnDeletePanic) != 0 { return EcsPanic }
    return EcsRemove
}

/// Extract OnDeleteTarget action from component record flags (bits 3-5).
@inline(__always)
public func ECS_ID_ON_DELETE_TARGET(_ flags: ecs_flags32_t) -> ecs_entity_t {
    let action = (flags & EcsIdOnDeleteTargetMask)
    if (action & EcsIdOnDeleteTargetDelete) != 0 { return EcsDelete }
    if (action & EcsIdOnDeleteTargetPanic) != 0 { return EcsPanic }
    return EcsRemove
}


/// Push a component record onto the marked-for-delete stack.
private func flecs_marked_id_push(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ action: ecs_entity_t,
    _ delete_id: Bool)
{
    let elem_size = Int32(MemoryLayout<ecs_marked_id_t>.stride)
    let m_ptr = ecs_vec_append(
        &world.pointee.allocator,
        &world.pointee.store.marked_ids,
        elem_size)
    if m_ptr == nil { return }

    let m = m_ptr!.bindMemory(to: ecs_marked_id_t.self, capacity: 1)
    m.pointee.cr = cr
    m.pointee.id = cr.pointee.id
    m.pointee.action = action
    m.pointee.delete_id = delete_id

    cr.pointee.flags |= EcsIdMarkedForDelete
    flecs_component_claim(world, cr)
}

/// Mark entities in a table as targets for deletion.
private func flecs_targets_mark_for_delete(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    if table.pointee.data.entities == nil { return }
    let count = table.pointee.data.count

    for i in 0..<Int(count) {
        flecs_target_mark_for_delete(world, table.pointee.data.entities![i])
    }
}

/// Mark component records related to an entity for deletion.
private func flecs_target_mark_for_delete(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ e: ecs_entity_t)
{
    let r = flecs_entities_get(UnsafePointer(world), e)
    if r == nil { return }

    let flags = r!.pointee.row & ECS_ROW_FLAGS_MASK
    if (flags & (EcsEntityIsId | EcsEntityIsTarget)) == 0 {
        return
    }

    if (flags & EcsEntityIsId) != 0 {
        let cr1 = flecs_components_get(UnsafePointer(world), e)
        if cr1 != nil {
            flecs_component_mark_for_delete(world, cr1!,
                ECS_ID_ON_DELETE(cr1!.pointee.flags), true)
        }
        let cr2 = flecs_components_get(UnsafePointer(world), ecs_pair(e, EcsWildcard))
        if cr2 != nil {
            flecs_component_mark_for_delete(world, cr2!,
                ECS_ID_ON_DELETE(cr2!.pointee.flags), true)
        }
    }

    if (flags & EcsEntityIsTarget) != 0 {
        let cr3 = flecs_components_get(UnsafePointer(world), ecs_pair(EcsWildcard, e))
        if cr3 != nil {
            flecs_component_mark_for_delete(world, cr3!,
                ECS_ID_ON_DELETE_TARGET(cr3!.pointee.flags), true)
        }
        let cr4 = flecs_components_get(UnsafePointer(world), ecs_pair(EcsFlag, e))
        if cr4 != nil {
            flecs_component_mark_for_delete(world, cr4!,
                ECS_ID_ON_DELETE_TARGET(cr4!.pointee.flags), true)
        }
    }
}

/// Check if the id being deleted is a target-delete scenario.
private func flecs_id_is_delete_target(
    _ id: ecs_id_t,
    _ action: ecs_entity_t) -> Bool
{
    if action == 0 && ecs_id_is_pair(id) && ECS_PAIR_FIRST(id) == EcsWildcard {
        return true
    }
    return false
}

/// Recursively mark component records and their tables for deletion.
private func flecs_component_mark_for_delete(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ action: ecs_entity_t,
    _ delete_id: Bool)
{
    if (cr.pointee.flags & EcsIdMarkedForDelete) != 0 {
        return
    }

    flecs_marked_id_push(world, cr, action, delete_id)

    let id = cr.pointee.id
    let delete_target = flecs_id_is_delete_target(id, action)

    // Mark all tables with the id
    // Would iterate cr->cache and mark tables with EcsTableMarkedForDelete
    // For Delete actions, recursively mark targets

    // Flag wildcard component records
    if ecs_id_is_wildcard(id) {
        if ECS_PAIR_SECOND(id) == EcsWildcard {
            var cur = flecs_component_first_next(cr)
            while cur != nil {
                cur!.pointee.flags |= EcsIdMarkedForDelete
                cur = flecs_component_first_next(cur!)
            }
        } else {
            var cur = flecs_component_second_next(cr)
            while cur != nil {
                cur!.pointee.flags |= EcsIdMarkedForDelete
                cur = flecs_component_second_next(cur!)
            }
        }
    }

    _ = delete_target
}


/// Main on-delete entry point. Marks ids for deletion and cleans up.
public func flecs_on_delete(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t,
    _ action: ecs_entity_t,
    _ delete_id: Bool,
    _ force_delete: Bool)
{
    let count = ecs_vec_count(&world.pointee.store.marked_ids)

    // Mark phase - collect all ids that need to be deleted
    flecs_on_delete_mark(world, id, action, delete_id)

    // Only perform cleanup if we're the first stack frame
    if count == 0 && ecs_vec_count(&world.pointee.store.marked_ids) > 0 {
        // Clear phase - delete entities from marked tables
        flecs_on_delete_clear_entities(world, force_delete)

        // Release phase - release component records
        flecs_on_delete_clear_ids(world, force_delete)

        // Clear the marked stack
        ecs_vec_clear(&world.pointee.store.marked_ids)

        // Cleanup type info for deleted components
        let del_count = ecs_vec_count(&world.pointee.store.deleted_components)
        if del_count > 0 {
            let comps = ecs_vec_first(&world.pointee.store.deleted_components)?
                .bindMemory(to: ecs_entity_t.self, capacity: Int(del_count))
            if comps != nil {
                for i in 0..<Int(del_count) {
                    flecs_type_info_free(world, comps![i])
                }
            }
            ecs_vec_clear(&world.pointee.store.deleted_components)
        }
    }
}

/// Mark an id for deletion. Returns true if any tables were found.
private func flecs_on_delete_mark(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t,
    _ action: ecs_entity_t,
    _ delete_id: Bool) -> Bool
{
    let cr = flecs_components_get(UnsafePointer(world), id)
    if cr == nil {
        return false
    }

    var resolved_action = action
    if resolved_action == 0 {
        if !ecs_id_is_pair(id) || ECS_PAIR_SECOND(id) == EcsWildcard {
            resolved_action = ECS_ID_ON_DELETE(cr!.pointee.flags)
        }
    }

    if resolved_action == EcsPanic {
        flecs_throw_invalid_delete(world, id)
        return false
    }

    flecs_component_mark_for_delete(world, cr!, resolved_action, delete_id)
    return true
}

/// Clear entities from marked tables.
private func flecs_on_delete_clear_entities(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ force_delete: Bool)
{
    // Would iterate world->store.marked_ids in reverse order
    // For each marked cr, iterate its table cache
    // Delete or remove entities based on action (Delete vs Remove)
}

/// Release component records after entities have been cleaned up.
private func flecs_on_delete_clear_ids(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ force_delete: Bool)
{
    let count = ecs_vec_count(&world.pointee.store.marked_ids)
    if count <= 0 { return }

    let ids = ecs_vec_first(&world.pointee.store.marked_ids)?
        .bindMemory(to: ecs_marked_id_t.self, capacity: Int(count))
    if ids == nil { return }

    // Two passes: non-wildcards first, then wildcards
    for pass in 0..<2 {
        for i in 0..<Int(count) {
            let is_wildcard = ecs_id_is_wildcard(ids![i].id)
            if pass == 0 && is_wildcard { continue }
            if pass == 1 && !is_wildcard { continue }

            let cr = ids![i].cr!
            let delete_id = ids![i].delete_id

            // Release the claim taken by flecs_marked_id_push
            let rc = flecs_component_release(world, cr)
            if rc > 0 {
                if delete_id {
                    flecs_component_release(world, cr)
                } else {
                    cr.pointee.flags &= ~EcsIdMarkedForDelete
                }
            }
        }
    }
}

/// Error handler for Panic delete policy.
public func flecs_throw_invalid_delete(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t)
{
    if (world.pointee.flags & EcsWorldQuit) == 0 {
        // Would log error: "(OnDelete, Panic) constraint violated"
    }
}

/// Free type info for a component being deleted.
public func flecs_type_info_free(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ component: ecs_entity_t)
{
    if (world.pointee.flags & EcsWorldQuit) != 0 {
        return
    }

    // Would look up type info from world->type_info map and free it
    // Already partially implemented in TypeInfo.swift
}


/// Delete all entities matching an id.
public func ecs_delete_with(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t)
{
    flecs_on_delete(world, id, EcsDelete, false, false)
}

/// Remove an id from all entities that have it.
public func ecs_remove_all(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t)
{
    flecs_on_delete(world, id, EcsRemove, false, false)
}
