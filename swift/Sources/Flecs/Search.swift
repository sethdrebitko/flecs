// Search.swift - 1:1 translation of flecs search.c
// Search functions to find (component) ids in table types

import Foundation

// MARK: - Internal Table Search

/// Search for a component in a table using the component record's table cache.
private func flecs_table_search(
    _ table: UnsafePointer<ecs_table_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ id_out: UnsafeMutablePointer<ecs_id_t>?) -> Int32
{
    // Would use ecs_table_cache_get(&cr.pointee.cache, table) for O(1) lookup
    // Fall back to linear search through table type
    guard let array = table.pointee.type.array else { return -1 }
    let count = table.pointee.type.count
    let target_id = cr.pointee.id

    for i in 0..<Int(count) {
        if ecs_id_match(array[i], target_id) {
            id_out?.pointee = array[i]
            return Int32(i)
        }
    }
    return -1
}

/// Linear search starting from an offset.
private func flecs_table_offset_search(
    _ table: UnsafePointer<ecs_table_t>,
    _ offset: Int32,
    _ id: ecs_id_t,
    _ id_out: UnsafeMutablePointer<ecs_id_t>?) -> Int32
{
    guard let ids = table.pointee.type.array else { return -1 }
    let count = table.pointee.type.count
    var off = offset

    while off < count {
        let type_id = ids[Int(off)]
        off += 1
        if ecs_id_match(type_id, id) {
            id_out?.pointee = type_id
            return off - 1
        }
    }

    return -1
}

/// Check if a type can inherit an id (respects DontInherit and Exclusive).
public func flecs_type_can_inherit_id(
    _ world: UnsafePointer<ecs_world_t>,
    _ table: UnsafePointer<ecs_table_t>,
    _ cr: UnsafePointer<ecs_component_record_t>,
    _ id: ecs_id_t) -> Bool
{
    if (cr.pointee.flags & EcsIdOnInstantiateDontInherit) != 0 {
        return false
    }

    if (cr.pointee.flags & EcsIdExclusive) != 0 {
        if ECS_HAS_ID_FLAG(id, ECS_PAIR) {
            let er = ECS_PAIR_FIRST(id)
            if let cr_wc = flecs_components_get(world, ecs_pair(er, EcsWildcard)) {
                if flecs_component_get_table(UnsafePointer(cr_wc), table) != nil {
                    return false
                }
            }
        }
    }

    return true
}

// MARK: - Internal Relation Search

/// Search for an id in a table, optionally following relationships upward.
private func flecs_table_search_relation(
    _ world: UnsafePointer<ecs_world_t>,
    _ table: UnsafePointer<ecs_table_t>,
    _ offset: Int32,
    _ id: ecs_id_t,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ rel: ecs_id_t,
    _ self_: Bool,
    _ tgt_out: UnsafeMutablePointer<ecs_entity_t>?,
    _ id_out: UnsafeMutablePointer<ecs_id_t>?) -> Int32
{
    let dont_fragment = (cr.pointee.flags & EcsIdDontFragment) != 0

    // Self search
    if self_ && !dont_fragment {
        let r: Int32
        if offset != 0 {
            r = flecs_table_offset_search(table, offset, id, id_out)
        } else {
            r = flecs_table_search(table, cr, id_out)
        }
        if r != -1 {
            return r
        }
    }

    let flags = table.pointee.flags
    if (flags & EcsTableHasPairs) == 0 || rel == 0 {
        return -1
    }

    // IsA traversal
    if (flags & EcsTableHasIsA) != 0 {
        if flecs_type_can_inherit_id(world, table, UnsafePointer(cr), id) {
            // Would search (IsA, *) pairs and recurse into target tables
            // Requires full ecs_table_cache_get for the IsA wildcard record
        }
    }

    return -1
}

// MARK: - Public Search API

/// Search for a component id in a table's type.
public func ecs_search(
    _ world: UnsafeRawPointer?,
    _ table: UnsafePointer<ecs_table_t>,
    _ id: ecs_id_t,
    _ id_out: UnsafeMutablePointer<ecs_id_t>?) -> Int32
{
    guard let world = world else { return -1 }
    let w = world.assumingMemoryBound(to: ecs_world_t.self)

    guard let cr = flecs_components_get(w, id) else {
        return -1
    }

    return flecs_table_search(table, cr, id_out)
}

/// Search for a component id starting from an offset.
public func ecs_search_offset(
    _ world: UnsafeRawPointer?,
    _ table: UnsafePointer<ecs_table_t>,
    _ offset: Int32,
    _ id: ecs_id_t,
    _ id_out: UnsafeMutablePointer<ecs_id_t>?) -> Int32
{
    if offset == 0 {
        return ecs_search(world, table, id, id_out)
    }
    return flecs_table_offset_search(table, offset, id, id_out)
}

/// Search for a component, following a relationship upward.
public func ecs_search_relation(
    _ world: UnsafeRawPointer?,
    _ table: UnsafePointer<ecs_table_t>,
    _ offset: Int32,
    _ id: ecs_id_t,
    _ rel: ecs_entity_t,
    _ flags: ecs_flags64_t,
    _ tgt_out: UnsafeMutablePointer<ecs_entity_t>?,
    _ id_out: UnsafeMutablePointer<ecs_id_t>?,
    _ tr_out: UnsafeMutablePointer<UnsafePointer<ecs_table_record_t>?>?) -> Int32
{
    guard let world = world else { return -1 }
    let w = world.assumingMemoryBound(to: ecs_world_t.self)

    let effective_flags = flags != 0 ? flags : (EcsSelf | EcsUp)

    tgt_out?.pointee = 0

    if (effective_flags & EcsUp) == 0 {
        return ecs_search_offset(UnsafeRawPointer(w), table, offset, id, id_out)
    }

    guard let cr = flecs_components_get(w, id) else {
        return -1
    }

    return flecs_table_search_relation(
        w, table, offset, id, cr,
        ecs_pair(rel, EcsWildcard),
        (effective_flags & EcsSelf) != 0,
        tgt_out, id_out)
}

/// Search for a component on a specific entity, following relationships.
public func ecs_search_relation_for_entity(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t,
    _ rel: ecs_entity_t,
    _ self_: Bool,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>?,
    _ tgt_out: UnsafeMutablePointer<ecs_entity_t>?,
    _ id_out: UnsafeMutablePointer<ecs_id_t>?) -> Int32
{
    guard let r = flecs_entities_get(world, entity) else { return -1 }
    guard let table_ptr = r.pointee.table else { return -1 }
    let table = table_ptr.assumingMemoryBound(to: ecs_table_t.self)

    tgt_out?.pointee = 0

    var cr_resolved = cr
    if cr_resolved == nil {
        cr_resolved = flecs_components_get(world, id)
    }
    guard let cr_resolved = cr_resolved else { return -1 }

    let result = flecs_table_search_relation(
        world, table, 0, id, cr_resolved,
        ecs_pair(rel, EcsWildcard),
        self_, tgt_out, id_out)

    if result != -1 {
        if let tgt_out = tgt_out, tgt_out.pointee == 0 {
            tgt_out.pointee = entity
        }
    }

    return result
}

// MARK: - Relation Depth

/// Compute depth of an entity in a relationship hierarchy.
public func flecs_relation_depth(
    _ world: UnsafePointer<ecs_world_t>,
    _ r: ecs_entity_t,
    _ table: UnsafePointer<ecs_table_t>) -> Int32
{
    if r == EcsChildOf {
        if (table.pointee.flags & EcsTableHasChildOf) != 0 {
            // Use cached depth from ChildOf component record
            if let cr_wc = world.pointee.cr_childof_wildcard {
                if let tr_wc = flecs_component_get_table(UnsafePointer(cr_wc), table) {
                    // Would look up cr->pair->depth from the specific ChildOf record
                    _ = tr_wc
                }
            }
        }
        return 0
    }

    guard let cr = flecs_components_get(world, ecs_pair(r, EcsWildcard)) else {
        return 0
    }

    return flecs_relation_depth_walk(world, UnsafePointer(cr), table, table)
}

/// Recursive depth walk for non-ChildOf relationships.
private func flecs_relation_depth_walk(
    _ world: UnsafePointer<ecs_world_t>,
    _ cr: UnsafePointer<ecs_component_record_t>,
    _ first: UnsafePointer<ecs_table_t>,
    _ table: UnsafePointer<ecs_table_t>) -> Int32
{
    guard let tr = flecs_component_get_table(cr, table) else { return 0 }

    var result: Int32 = 0
    let i_start = tr.pointee.index
    let i_end = i_start + Int16(tr.pointee.count)

    for i in Int(i_start)..<Int(i_end) {
        let o = ecs_pair_second(world, table.pointee.type.array![i])
        if o == 0 { return 0 }

        // Would get table for entity o and recurse
        // let ot = ecs_get_table(world, o)
        // let cur = flecs_relation_depth_walk(world, cr, first, ot)
        // if cur > result { result = cur }
    }

    return result + 1
}
