// SparseStorage.swift - 1:1 translation of flecs storage/sparse_storage.c
// Sparse component storage for non-fragmenting components

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Check if a sparse component exists for an entity.
/// Handles wildcard ids by iterating matching component records.
public func flecs_component_sparse_has(
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ entity: ecs_entity_t) -> Bool
{
    let id = cr.pointee.id
    if ecs_id_is_wildcard(id) {
        if ECS_IS_PAIR(id) {
            // (R, *) wildcard - iterate first-next chain
            if ECS_PAIR_SECOND(id) == EcsWildcard &&
                (cr.pointee.flags & EcsIdDontFragment) != 0
            {
                var cur = flecs_component_first_next(cr)
                while cur != nil {
                    if cur!.pointee.sparse != nil &&
                        flecs_sparse_has(cur!.pointee.sparse!, entity) {
                        return true
                    }
                    cur = flecs_component_first_next(cur!)
                }
            }

            // (*, T) wildcard - iterate second-next chain
            if ECS_PAIR_FIRST(id) == EcsWildcard &&
                (cr.pointee.flags & EcsIdMatchDontFragment) != 0
            {
                var cur = flecs_component_second_next(cr)
                while cur != nil {
                    if cur!.pointee.sparse != nil &&
                        flecs_sparse_has(cur!.pointee.sparse!, entity) {
                        return true
                    }
                    cur = flecs_component_second_next(cur!)
                }
            }

            return false
        }
        return false
    } else {
        if cr.pointee.sparse == nil { return false }
        return flecs_sparse_has(cr.pointee.sparse!, entity)
    }
}


/// Get a sparse component pointer for an entity.
/// Handles wildcard resolution through table records or parent sparse sets.
public func flecs_component_sparse_get(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>?,
    _ entity: ecs_entity_t) -> UnsafeMutableRawPointer?
{
    if !ecs_id_is_wildcard(cr.pointee.id) {
        return flecs_sparse_get(cr.pointee.sparse, 0, entity)
    }

    // Wildcard resolution requires a table
    if table == nil { return nil }

    var resolved_cr = cr

    if (cr.pointee.flags & EcsIdDontFragment) == 0 {
        // Fragmenting wildcard: resolve through table record
        let tr = flecs_component_get_table(UnsafePointer(cr), UnsafePointer(table!))
        if tr == nil {
            return nil
        }
        if table!.pointee._.pointee.records == nil { return nil }
        let ttr = table!.pointee._.pointee.records![Int(tr!.pointee.index)]
        resolved_cr = ttr.hdr.cr!
    } else {
        // Non-fragmenting wildcard: resolve through parent sparse
        if (cr.pointee.flags & EcsIdExclusive) != 0 {
            let tgt_ptr = flecs_sparse_get(
                cr.pointee.sparse, Int32(MemoryLayout<ecs_entity_t>.stride), entity)?
                .bindMemory(to: ecs_entity_t.self, capacity: 1)
            if tgt_ptr == nil {
                return nil
            }
            let tgt = tgt_ptr!.pointee

            if ECS_PAIR_FIRST(cr.pointee.id) == EcsWildcard {
                let c = flecs_components_get(
                    UnsafePointer(world),
                    ecs_pair(tgt, ECS_PAIR_SECOND(cr.pointee.id)))
                if c == nil { return nil }
                resolved_cr = c!
            } else {
                let c = flecs_components_get(
                    UnsafePointer(world),
                    ecs_pair(ECS_PAIR_FIRST(cr.pointee.id), tgt))
                if c == nil { return nil }
                resolved_cr = c!
            }
        } else {
            let type = flecs_sparse_get(
                cr.pointee.sparse,
                Int32(MemoryLayout<ecs_type_t>.stride), entity)?
                .bindMemory(to: ecs_type_t.self, capacity: 1)
            if type == nil {
                return nil
            }
            if type!.pointee.array == nil { return nil }
            let tgt = type!.pointee.array![0]

            if ECS_PAIR_FIRST(cr.pointee.id) == EcsWildcard {
                let c = flecs_components_get(
                    UnsafePointer(world),
                    ecs_pair(tgt, ECS_PAIR_SECOND(cr.pointee.id)))
                if c == nil { return nil }
                resolved_cr = c!
            } else {
                let c = flecs_components_get(
                    UnsafePointer(world),
                    ecs_pair(ECS_PAIR_FIRST(cr.pointee.id), tgt))
                if c == nil { return nil }
                resolved_cr = c!
            }
        }
    }

    return flecs_sparse_get(resolved_cr.pointee.sparse, 0, entity)
}


/// Remove a sparse component from an entity at a table row.
private func flecs_component_sparse_remove_intern(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ row: Int32) -> ecs_entity_t
{
    if table.pointee.data.entities == nil { return 0 }
    let entity = table.pointee.data.entities![Int(row)]
    let ti = cr.pointee.type_info

    if ti == nil {
        if flecs_sparse_remove(cr.pointee.sparse!, 0, entity) {
            return entity
        }
        return 0
    }

    let ptr = flecs_sparse_get(cr.pointee.sparse, 0, entity)
    if ptr == nil {
        return 0
    }

    // Invoke on_remove hook
    if ti!.pointee.hooks.on_remove != nil {
        var entity_mut = entity
        let tr: UnsafePointer<ecs_table_record_t>? =
            (cr.pointee.flags & EcsIdDontFragment) == 0
            ? flecs_component_get_table(UnsafePointer(cr), UnsafePointer(table))
            : nil
        flecs_invoke_hook(world, table, cr, tr, 1, row, &entity_mut,
            cr.pointee.id, UnsafePointer(ti!), EcsOnRemove, ti!.pointee.hooks.on_remove!)
    }

    flecs_type_info_dtor(ptr!, 1, UnsafePointer(ti!))
    flecs_sparse_remove(cr.pointee.sparse!, 0, entity)

    return entity
}

/// Remove a sparse component, handling wildcards and non-fragmenting cleanup.
public func flecs_component_sparse_remove(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ row: Int32)
{
    let id = cr.pointee.id
    let flags = cr.pointee.flags
    let dont_fragment = (flags & EcsIdDontFragment) != 0

    // Wildcard removal: iterate all matching component records
    if dont_fragment && ecs_id_is_wildcard(cr.pointee.id) {
        if table.pointee.data.entities == nil { return }
        let entity = table.pointee.data.entities![Int(row)]

        var cur = flecs_component_first_next(cr)
        while cur != nil {
            if flecs_component_sparse_has(cur!, entity) {
                flecs_component_sparse_remove(world, cur!, table, row)
            }
            cur = flecs_component_first_next(cur!)
        }
        return
    }

    let entity = flecs_component_sparse_remove_intern(world, cr, table, row)

    if entity != 0 && dont_fragment && ECS_IS_PAIR(id) {
        if (flags & EcsIdExclusive) != 0 {
            flecs_component_sparse_dont_fragment_exclusive_remove(cr, entity)
        } else {
            flecs_component_sparse_dont_fragment_pair_remove(world, cr, entity)
        }
    }
}

/// Remove the non-fragmenting pair parent record for a pair removal.
private func flecs_component_sparse_dont_fragment_pair_remove(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ entity: ecs_entity_t)
{
    let parent = cr.pointee.pair?.pointee.parent
    if parent == nil { return }
    if parent!.pointee.sparse == nil { return }

    let type = flecs_sparse_get(
        parent!.pointee.sparse!,
        Int32(MemoryLayout<ecs_type_t>.stride), entity)?
        .bindMemory(to: ecs_type_t.self, capacity: 1)
    if type == nil {
        return
    }

    flecs_type_remove_ignoring_generation(world, type!, ECS_PAIR_SECOND(cr.pointee.id))

    if type!.pointee.count == 0 {
        flecs_sparse_remove(parent!.pointee.sparse!, 0, entity)
    }
}

/// Remove exclusive non-fragmenting pair parent record.
private func flecs_component_sparse_dont_fragment_exclusive_remove(
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ entity: ecs_entity_t)
{
    let parent = cr.pointee.pair?.pointee.parent
    if parent == nil { return }
    if parent!.pointee.sparse == nil { return }

    flecs_sparse_remove(
        parent!.pointee.sparse!,
        Int32(MemoryLayout<ecs_entity_t>.stride), entity)
}


/// Remove all instances of a sparse component (used during component deletion).
public func flecs_component_sparse_remove_all(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>)
{
    if cr.pointee.sparse == nil { return }
    let sparse = cr.pointee.sparse!

    if ecs_id_is_wildcard(cr.pointee.id) {
        // For wildcard: free type arrays stored in sparse set
        if !ECS_IS_PAIR(cr.pointee.id) { return }
        if (cr.pointee.flags & EcsIdExclusive) != 0 { return }

        let count = flecs_sparse_count(sparse)
        for i in 0..<Int(count) {
            let type = flecs_sparse_get_dense(
                sparse, Int32(MemoryLayout<ecs_type_t>.stride), Int32(i))?
                .bindMemory(to: ecs_type_t.self, capacity: 1)
            if type != nil {
                flecs_type_free(world, type!)
            }
        }
    } else {
        // For concrete id: invoke hooks and destructors
        let entities = flecs_sparse_ids(sparse)
        let count = flecs_sparse_count(sparse)
        let ti = cr.pointee.type_info

        if ti != nil {
            if ti!.pointee.hooks.on_remove != nil {
                for i in 0..<Int(count) {
                    let e = entities![Int(i)]
                    let r = flecs_entities_get(UnsafePointer(world), e)
                    if r == nil { continue }
                    var e_mut = e
                    flecs_invoke_hook(world, r!.pointee.table, cr, nil, 1,
                        ECS_RECORD_TO_ROW(r!.pointee.row), &e_mut,
                        cr.pointee.id, UnsafePointer(ti!), EcsOnRemove, ti!.pointee.hooks.on_remove!)
                }
            }

            if ti!.pointee.hooks.dtor != nil {
                for i in 0..<Int(count) {
                    let ptr = flecs_sparse_get_dense(sparse, 0, Int32(i))
                    if ptr != nil {
                        flecs_type_info_dtor(ptr!, 1, UnsafePointer(ti!))
                    }
                }
            }
        }

        // Remove pair parent records
        if ECS_IS_PAIR(cr.pointee.id) {
            if (cr.pointee.flags & EcsIdExclusive) != 0 {
                for i in 0..<Int(count) {
                    let e = entities![Int(i)]
                    flecs_component_sparse_dont_fragment_exclusive_remove(cr, e)
                }
            } else {
                for i in 0..<Int(count) {
                    let e = entities![Int(i)]
                    flecs_component_sparse_dont_fragment_pair_remove(world, cr, e)
                }
            }
        }
    }
}


/// Insert a new sparse component for an entity, invoking hooks.
public func flecs_component_sparse_insert(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ row: Int32) -> UnsafeMutableRawPointer?
{
    if table.pointee.data.entities == nil { return nil }
    let entity = table.pointee.data.entities![Int(row)]

    var is_new = true
    let ptr = flecs_sparse_ensure(
        cr.pointee.sparse, 0, entity, &is_new)
    if ptr == nil {
        return nil
    }

    // Update non-fragmenting pair parent records
    let component_id = cr.pointee.id
    if ECS_IS_PAIR(component_id) {
        let flags = cr.pointee.flags
        if (flags & EcsIdDontFragment) != 0 {
            if (flags & EcsIdExclusive) != 0 {
                flecs_component_sparse_dont_fragment_exclusive_insert(
                    world, cr, table, row, entity)
            } else {
                flecs_component_sparse_dont_fragment_pair_insert(
                    world, cr, entity)
            }
        }
    }

    if !is_new { return ptr }

    if cr.pointee.type_info == nil { return ptr }
    let ti = cr.pointee.type_info!

    // Override from base if table has IsA
    flecs_component_sparse_override(world, table, component_id, ptr!, UnsafePointer(ti))

    // Invoke on_add hook
    if ti.pointee.hooks.on_add != nil {
        var entity_mut = entity
        let tr: UnsafePointer<ecs_table_record_t>? =
            (cr.pointee.flags & EcsIdDontFragment) == 0
            ? flecs_component_get_table(UnsafePointer(cr), UnsafePointer(table))
            : nil
        flecs_invoke_hook(world, table, cr, tr, 1, row, &entity_mut,
            component_id, UnsafePointer(ti), EcsOnAdd, ti.pointee.hooks.on_add!)
    }

    return ptr
}

/// Insert non-fragmenting pair into parent sparse set.
private func flecs_component_sparse_dont_fragment_pair_insert(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ entity: ecs_entity_t)
{
    let parent = cr.pointee.pair?.pointee.parent
    if parent == nil { return }
    if parent!.pointee.sparse == nil { return }

    let type = flecs_sparse_ensure(
        parent!.pointee.sparse!,
        Int32(MemoryLayout<ecs_type_t>.stride), entity, nil)?
        .bindMemory(to: ecs_type_t.self, capacity: 1)
    if type == nil {
        return
    }
    flecs_type_add(world, type!, ecs_pair_second(UnsafePointer(world), cr.pointee.id))
}

/// Insert exclusive non-fragmenting pair.
private func flecs_component_sparse_dont_fragment_exclusive_insert(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ row: Int32,
    _ entity: ecs_entity_t)
{
    let parent = cr.pointee.pair?.pointee.parent
    if parent == nil { return }
    if parent!.pointee.sparse == nil { return }

    let component_id = cr.pointee.id
    let tgt_ptr = flecs_sparse_ensure(
        parent!.pointee.sparse!,
        Int32(MemoryLayout<ecs_entity_t>.stride), entity, nil)?
        .bindMemory(to: ecs_entity_t.self, capacity: 1)
    if tgt_ptr == nil {
        return
    }

    let old_tgt = tgt_ptr!.pointee
    if old_tgt != 0 {
        // Exclusive: remove old target first
        let other = flecs_components_get(
            UnsafePointer(world),
            ecs_pair(ECS_PAIR_FIRST(component_id), old_tgt))
        if other != nil {
            if other! != cr {
                _ = flecs_component_sparse_remove_intern(world, other!, table, row)
            }
        }
    }

    tgt_ptr!.pointee = flecs_entities_get_alive(world, ECS_PAIR_SECOND(component_id))
}

/// Override a sparse component value from a base entity (IsA).
private func flecs_component_sparse_override(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ component_id: ecs_id_t,
    _ ptr: UnsafeMutableRawPointer,
    _ ti: UnsafePointer<ecs_type_info_t>)
{
    var override_ptr: UnsafeRawPointer? = nil
    if (table.pointee.flags & EcsTableHasIsA) != 0 {
        var base: ecs_entity_t = 0
        if ecs_search_relation(UnsafeRawPointer(world), UnsafePointer(table), 0,
            component_id, EcsIsA, EcsUp, &base, nil, nil) != -1
        {
            override_ptr = ecs_get_id(world, base, component_id)
        }
    }

    if override_ptr == nil {
        flecs_type_info_ctor(ptr, 1, ti)
    } else {
        if ti.pointee.hooks.copy_ctor != nil {
            flecs_type_info_copy_ctor(ptr, override_ptr!, 1, ti)
        } else {
            flecs_type_info_ctor(ptr, 1, ti)
            ptr.copyMemory(from: override_ptr!, byteCount: Int(ti.pointee.size))
        }
    }
}


/// Emplace (insert without construction) a sparse component.
public func flecs_component_sparse_emplace(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ row: Int32) -> UnsafeMutableRawPointer?
{
    if table.pointee.data.entities == nil { return nil }
    let entity = table.pointee.data.entities![Int(row)]

    let ptr = flecs_sparse_ensure(cr.pointee.sparse, 0, entity, nil)
    if ptr == nil {
        return nil
    }

    if cr.pointee.type_info == nil { return ptr }
    let ti = cr.pointee.type_info!

    if ti.pointee.hooks.on_add != nil {
        var entity_mut = entity
        let tr: UnsafePointer<ecs_table_record_t>? =
            (cr.pointee.flags & EcsIdDontFragment) == 0
            ? flecs_component_get_table(UnsafePointer(cr), UnsafePointer(table))
            : nil
        flecs_invoke_hook(world, table, cr, tr, 1, row, &entity_mut,
            cr.pointee.id, UnsafePointer(ti), EcsOnAdd, ti.pointee.hooks.on_add!)
    }

    return ptr
}


/// Delete all sparse entries for a component record (used during cr cleanup).
public func flecs_component_delete_sparse(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>)
{
    if cr.pointee.sparse == nil { return }
    let sparse = cr.pointee.sparse!

    let count = flecs_sparse_count(sparse)
    if count == 0 { return }

    let entities = flecs_sparse_ids(sparse)
    if entities == nil { return }

    // Invoke on_remove hooks and destructors
    if cr.pointee.type_info != nil {
        let ti = cr.pointee.type_info!
        if ti.pointee.hooks.on_remove != nil {
            for i in 0..<Int(count) {
                let e = entities![i]
                let r = flecs_entities_get(UnsafePointer(world), e)
                if r == nil { continue }
                if r!.pointee.table == nil { continue }
                var e_mut = e
                flecs_invoke_hook(world, r!.pointee.table, cr, nil, 1,
                    ECS_RECORD_TO_ROW(r!.pointee.row), &e_mut,
                    cr.pointee.id, UnsafePointer(ti), EcsOnRemove, ti.pointee.hooks.on_remove!)
            }
        }

        if ti.pointee.hooks.dtor != nil {
            for i in 0..<Int(count) {
                let ptr = flecs_sparse_get_dense(sparse, 0, Int32(i))
                if ptr != nil {
                    flecs_type_info_dtor(ptr!, 1, UnsafePointer(ti))
                }
            }
        }
    }

    flecs_sparse_clear(sparse)
}
