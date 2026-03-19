// NonFragmentingChildOf.swift - 1:1 translation of flecs storage/non_fragmenting_childof.c
// and storage/ordered_children.c
// Non-fragmenting Parent component storage and ordered children management

import Foundation

// MARK: - Non-Fragmenting Child Table Tracking

/// Add an entity as a non-fragmenting child, tracking its table.
private func flecs_add_non_fragmenting_child_to_table(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ entity: ecs_entity_t,
    _ table: UnsafePointer<ecs_table_t>)
{
    guard let pair = cr.pointee.pair else { return }
    ecs_map_init_if(&pair.pointee.children_tables, &world.pointee.allocator)

    let elem = ecs_map_ensure(&pair.pointee.children_tables, table.pointee.id)
    let pr = elem.assumingMemoryBound(to: ecs_parent_record_t.self)

    if pr.pointee.count == 0 {
        pr.pointee.entity = UInt32(entity)
        if (table.pointee.flags & EcsTableIsDisabled) != 0 {
            pair.pointee.disabled_tables += 1
        }
        if (table.pointee.flags & EcsTableIsPrefab) != 0 {
            pair.pointee.prefab_tables += 1
        }
    } else {
        pr.pointee.entity = 0
    }

    pr.pointee.count += 1
}

/// Remove an entity's table tracking from a non-fragmenting child record.
private func flecs_remove_non_fragmenting_child_from_table(
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ table: UnsafePointer<ecs_table_t>)
{
    guard let pair = cr.pointee.pair else { return }
    guard let elem = flecs_component_get_parent_record(cr, table) else { return }

    elem.pointee.count -= 1

    if elem.pointee.count == 0 {
        ecs_map_remove(&pair.pointee.children_tables, table.pointee.id)
        if (table.pointee.flags & EcsTableIsDisabled) != 0 {
            pair.pointee.disabled_tables -= 1
        }
        if (table.pointee.flags & EcsTableIsPrefab) != 0 {
            pair.pointee.prefab_tables -= 1
        }
    }
}

// MARK: - Add/Remove Non-Fragmenting Child

/// Add an entity as a non-fragmenting child with pre-resolved records.
@discardableResult
public func flecs_add_non_fragmenting_child_w_records(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ parent: ecs_entity_t,
    _ entity: ecs_entity_t,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ r: UnsafePointer<ecs_record_t>) -> Int32
{
    guard r.pointee.table != nil else { return -1 }

    if (cr.pointee.flags & EcsIdOrderedChildren) == 0 {
        flecs_component_ordered_children_init(world, cr)
        flecs_ordered_children_populate(world, cr)
    }

    guard parent != 0 else { return -1 }
    guard ecs_is_alive(world, parent) else { return -1 }

    flecs_ordered_entities_append(world, cr, entity)
    flecs_add_non_fragmenting_child_to_table(world, cr, entity,
        UnsafePointer(r.pointee.table!.assumingMemoryBound(to: ecs_table_t.self)))

    if let r_parent = flecs_entities_get(UnsafePointer(world), parent) {
        if let parent_table = r_parent.pointee.table {
            if (parent_table.pointee.flags & EcsTableIsPrefab) != 0 {
                ecs_add_id(world, entity, EcsPrefab)
            }
        }
    }

    return 0
}

/// Add an entity as a non-fragmenting child (creates component record if needed).
private func flecs_add_non_fragmenting_child(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ parent: ecs_entity_t,
    _ entity: ecs_entity_t) -> UnsafeMutablePointer<ecs_component_record_t>?
{
    let cr = flecs_components_ensure(world, ecs_pair(EcsChildOf, parent))
    guard let r = flecs_entities_get(UnsafePointer(world), entity) else { return nil }

    if flecs_add_non_fragmenting_child_w_records(world, parent, entity, cr, r) != 0 {
        return nil
    }

    return cr
}

/// Remove an entity as a non-fragmenting child.
private func flecs_remove_non_fragmenting_child(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ parent: ecs_entity_t,
    _ entity: ecs_entity_t)
{
    if parent == 0 { return }

    guard let cr = flecs_components_get(UnsafePointer(world),
        ecs_pair(EcsChildOf, parent)) else { return }
    if (cr.pointee.flags & EcsIdMarkedForDelete) != 0 { return }

    flecs_ordered_entities_remove(world, cr, entity)

    guard let r = flecs_entities_get(UnsafePointer(world), entity) else { return }
    guard let table = r.pointee.table else { return }

    flecs_remove_non_fragmenting_child_from_table(cr, UnsafePointer(table))
}

// MARK: - Move Handlers (Table Transitions)

/// Handle non-fragmenting child table tracking during entity movement (add side).
public func flecs_on_non_fragmenting_child_move_add(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ dst: UnsafePointer<ecs_table_t>,
    _ src: UnsafePointer<ecs_table_t>?,
    _ row: Int32,
    _ count: Int32)
{
    guard let entities = dst.pointee.data.entities else { return }
    guard let parents = ecs_table_get(world, dst, EcsParent.self, 0) else { return }

    for i in Int(row)..<Int(row + count) {
        let e = entities[i]
        let p = parents[i].value

        guard let cr = flecs_components_get(UnsafePointer(world), ecs_childof(p)) else { continue }

        if let src = src, (src.pointee.flags & EcsTableHasParent) != 0 {
            flecs_remove_non_fragmenting_child_from_table(cr, src)
        }

        flecs_add_non_fragmenting_child_to_table(world, cr, e, dst)
    }
}

/// Handle non-fragmenting child table tracking during entity movement (remove side).
public func flecs_on_non_fragmenting_child_move_remove(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ dst: UnsafePointer<ecs_table_t>?,
    _ src: UnsafePointer<ecs_table_t>,
    _ row: Int32,
    _ count: Int32,
    _ update_parent_records: Bool)
{
    guard let entities = src.pointee.data.entities else { return }
    guard let parents = ecs_table_get(world, src, EcsParent.self, 0) else { return }

    for i in Int(row)..<Int(row + count) {
        let e = entities[i]
        let p = parents[i].value
        if !ecs_is_alive(world, p) { continue }

        let cr = flecs_components_ensure(world, ecs_childof(p))

        if update_parent_records {
            flecs_remove_non_fragmenting_child_from_table(cr, src)
        }

        if let dst = dst, (dst.pointee.flags & EcsTableHasParent) != 0 {
            if update_parent_records {
                flecs_add_non_fragmenting_child_to_table(world, cr, e, dst)
            }
        } else {
            flecs_ordered_entities_remove(world, cr, e)
        }
    }
}

// MARK: - Reparent / Unparent

/// Update cached depth values after reparenting.
public func flecs_non_fragmenting_childof_reparent(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ dst: UnsafePointer<ecs_table_t>,
    _ src: UnsafePointer<ecs_table_t>?,
    _ row: Int32,
    _ count: Int32)
{
    guard let src = src else { return }
    guard let entities = dst.pointee.data.entities else { return }

    for i in Int(row)..<Int(row + count) {
        let e = entities[i]
        guard let cr = flecs_components_get(UnsafePointer(world), ecs_childof(e)) else { continue }
        guard let r = flecs_entities_get(UnsafePointer(world), e) else { continue }
        flecs_component_update_childof_depth(world, cr, e, r)
    }
}

/// Update cached depth values when parent is removed.
public func flecs_non_fragmenting_childof_unparent(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ dst: UnsafePointer<ecs_table_t>?,
    _ src: UnsafePointer<ecs_table_t>,
    _ row: Int32,
    _ count: Int32)
{
    guard let entities = src.pointee.data.entities else { return }

    for i in Int(row)..<Int(row + count) {
        let e = entities[i]
        guard let cr = flecs_components_get(UnsafePointer(world), ecs_childof(e)) else { continue }
        if (cr.pointee.flags & EcsIdMarkedForDelete) != 0 { continue }

        flecs_component_update_childof_w_depth(world, cr, 1)
    }
}

/// Check if a component record has non-fragmenting children.
public func flecs_component_has_non_fragmenting_childof(
    _ cr: UnsafeMutablePointer<ecs_component_record_t>) -> Bool
{
    if (cr.pointee.flags & EcsIdOrderedChildren) != 0 {
        guard let pair = cr.pointee.pair else { return false }
        return ecs_map_count(&pair.pointee.children_tables) != 0
    }
    return false
}

// MARK: - Ordered Children

/// Initialize ordered children storage for a component record.
public func flecs_ordered_children_init(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>)
{
    guard let pair = cr.pointee.pair else { return }
    let elem_size = Int32(MemoryLayout<ecs_entity_t>.stride)
    ecs_vec_init(&world.pointee.allocator, &pair.pointee.ordered_children, elem_size, 0)
}

/// Finalize ordered children storage.
public func flecs_ordered_children_fini(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>)
{
    guard let pair = cr.pointee.pair else { return }
    let elem_size = Int32(MemoryLayout<ecs_entity_t>.stride)
    ecs_vec_fini(&world.pointee.allocator, &pair.pointee.ordered_children, elem_size)
    ecs_map_fini(&pair.pointee.children_tables)
}

/// Populate ordered children from existing entities.
public func flecs_ordered_children_populate(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>)
{
    guard let pair = cr.pointee.pair else { return }
    let count = ecs_vec_count(&pair.pointee.ordered_children)
    if count != 0 { return }

    var it = ecs_each_id(world, cr.pointee.id)
    while ecs_each_next(&it) {
        for i in 0..<Int(it.count) {
            flecs_ordered_entities_append(world, cr, it.entities![i])
        }
    }
}

/// Clear ordered children (when OrderedChildren trait is removed).
public func flecs_ordered_children_clear(
    _ cr: UnsafeMutablePointer<ecs_component_record_t>)
{
    guard let pair = cr.pointee.pair else { return }
    if (cr.pointee.flags & EcsIdMarkedForDelete) == 0 {
        ecs_vec_clear(&pair.pointee.ordered_children)
    }
}

/// Append an entity to the ordered children list.
public func flecs_ordered_entities_append(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ e: ecs_entity_t)
{
    guard let pair = cr.pointee.pair else { return }
    let elem_size = Int32(MemoryLayout<ecs_entity_t>.stride)

    guard let ptr = ecs_vec_append(&world.pointee.allocator,
        &pair.pointee.ordered_children, elem_size)?
        .bindMemory(to: ecs_entity_t.self, capacity: 1) else { return }
    ptr.pointee = e
}

/// Remove an entity from the ordered children list.
public func flecs_ordered_entities_remove(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ e: ecs_entity_t)
{
    guard let pair = cr.pointee.pair else { return }
    let count = ecs_vec_count(&pair.pointee.ordered_children)
    guard count > 0 else { return }
    guard let entities = ecs_vec_first(&pair.pointee.ordered_children)?
        .bindMemory(to: ecs_entity_t.self, capacity: Int(count)) else { return }

    for i in 0..<Int(count) {
        if entities[i] == e {
            // Remove ordered: shift remaining elements left
            if i + 1 < Int(count) {
                (entities + i).update(from: entities + i + 1, count: Int(count) - i - 1)
            }
            pair.pointee.ordered_children.count -= 1
            break
        }
    }
}

/// Handle ordered children during reparent (table transition).
public func flecs_ordered_children_reparent(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ dst: UnsafePointer<ecs_table_t>,
    _ src: UnsafePointer<ecs_table_t>?,
    _ row: Int32,
    _ count: Int32)
{
    // Remove from old parent's ordered children
    if let src = src, (src.pointee.flags & EcsTableHasOrderedChildren) != 0 {
        guard let cr = flecs_table_get_childof_cr(world, src) else { return }
        guard let entities = src.pointee.data.entities else { return }
        for i in Int(row)..<Int(row + count) {
            flecs_ordered_entities_remove(world, cr, entities[i])
        }
    }

    // Add to new parent's ordered children
    if (dst.pointee.flags & EcsTableHasOrderedChildren) != 0 {
        guard let cr = flecs_table_get_childof_cr(world, dst) else { return }
        guard let entities = dst.pointee.data.entities else { return }
        for i in Int(row)..<Int(row + count) {
            flecs_ordered_entities_append(world, cr, entities[i])
        }
    }
}

/// Handle ordered children when parent is removed.
public func flecs_ordered_children_unparent(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ src: UnsafePointer<ecs_table_t>,
    _ row: Int32,
    _ count: Int32)
{
    if (src.pointee.flags & EcsTableHasOrderedChildren) != 0 {
        guard let cr = flecs_table_get_childof_cr(world, src) else { return }
        guard let entities = src.pointee.data.entities else { return }
        for i in Int(row)..<Int(row + count) {
            flecs_ordered_entities_remove(world, cr, entities[i])
        }
    }
}

// MARK: - Bootstrap

/// Register Parent component type info during bootstrap.
public func flecs_bootstrap_parent_component(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    // Would register EcsParent type info with ctor and on_replace hooks
    ecs_add_pair(world, ecs_id_EcsParent, EcsOnInstantiate, EcsDontInherit)
}
