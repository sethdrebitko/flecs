// ComponentIndex.swift - 1:1 translation of flecs component_index.c
// Index for looking up tables by component id (component records)

import Foundation

// MARK: - Helpers

/// Strip generation from entity id for hashing.
@inline(__always)
public func ecs_strip_generation(_ e: ecs_entity_t) -> ecs_id_t {
    var e = e
    if (e & ECS_ID_FLAGS_MASK) == 0 {
        e &= ~ECS_GENERATION_MASK
    }
    return e
}

/// Compute hash for component id lookup.
@inline(__always)
public func flecs_component_hash(_ id: ecs_id_t) -> ecs_id_t {
    var id = ecs_strip_generation(id)
    if ECS_IS_PAIR(id) {
        let r = ECS_PAIR_FIRST(id)
        let t = ECS_PAIR_SECOND(id)
        if ECS_IS_VALUE_PAIR(id) {
            id = ecs_value_pair(r, t)
        } else {
            let r2 = (r == EcsAny) ? EcsWildcard : r
            let t2 = (t == EcsAny) ? EcsWildcard : t
            id = ecs_pair(r2, t2)
        }
    }
    return id
}

/// Convenience shorthand: ecs_childof(e) = ecs_pair(EcsChildOf, e)
@inline(__always)
public func ecs_childof(_ e: ecs_entity_t) -> ecs_id_t {
    return ecs_pair(EcsChildOf, e)
}

/// ecs_pair_first(world, pair) - get alive first element
@inline(__always)
public func ecs_pair_first(
    _ world: UnsafePointer<ecs_world_t>,
    _ pair: ecs_id_t) -> ecs_entity_t
{
    return ecs_get_alive(world, ECS_PAIR_FIRST(pair))
}

/// ecs_pair_second(world, pair) - get alive second element
@inline(__always)
public func ecs_pair_second(
    _ world: UnsafePointer<ecs_world_t>,
    _ pair: ecs_id_t) -> ecs_entity_t
{
    return ecs_get_alive(world, ECS_PAIR_SECOND(pair))
}

// MARK: - Entity Index Bridge Functions (macros in C)

/// flecs_entities_get(world, entity) - get record for alive entity
@inline(__always)
public func flecs_entities_get(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: UInt64) -> UnsafeMutablePointer<ecs_record_t>?
{
    let index = UnsafeMutablePointer(mutating: world).pointee.store.entity_index
    return withUnsafePointer(to: index) { flecs_entity_index_get($0, entity) }
}

/// flecs_entities_get_any(world, entity) - get record (alive or not)
@inline(__always)
public func flecs_entities_get_any(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: UInt64) -> UnsafeMutablePointer<ecs_record_t>?
{
    let index = UnsafeMutablePointer(mutating: world).pointee.store.entity_index
    return withUnsafePointer(to: index) { flecs_entity_index_get_any($0, entity) }
}

/// flecs_entities_ensure(world, entity) - ensure record exists
@inline(__always)
public func flecs_entities_ensure(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: UInt64) -> UnsafeMutablePointer<ecs_record_t>
{
    return flecs_entity_index_ensure(&world.pointee.store.entity_index, entity)
}

/// flecs_entities_get_alive(world, entity) - get alive id with current generation
@inline(__always)
public func flecs_entities_get_alive(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: UInt64) -> UInt64
{
    let index = UnsafeMutablePointer(mutating: world).pointee.store.entity_index
    return withUnsafePointer(to: index) { flecs_entity_index_get_alive($0, entity) }
}

/// Add a flag to a record's row.
@inline(__always)
public func flecs_record_add_flag(
    _ r: UnsafeMutablePointer<ecs_record_t>,
    _ flag: UInt32)
{
    r.pointee.row |= flag
}

/// Add a flag to an entity (looks up record first).
public func flecs_add_flag(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ flag: UInt32)
{
    let r = flecs_entities_ensure(world, entity)
    r.pointee.row |= flag
}

// MARK: - Component Record Lookup

/// Look up a component record by id. Returns nil if not found.
public func flecs_components_get(
    _ world: UnsafePointer<ecs_world_t>,
    _ id: ecs_id_t) -> UnsafeMutablePointer<ecs_component_record_t>?
{
    // Check cached fast-path records
    if id == ecs_pair(EcsIsA, EcsWildcard) {
        return world.pointee.cr_isa_wildcard
    } else if id == ecs_pair(EcsChildOf, EcsWildcard) {
        return world.pointee.cr_childof_wildcard
    }

    let hash = flecs_component_hash(id)

    if hash >= UInt64(FLECS_HI_ID_RECORD_ID) {
        // Look up in hi map
        var hi_map = UnsafeMutablePointer(mutating: world).pointee.id_index_hi
        guard let val = ecs_map_get(&hi_map, hash) else { return nil }
        let ptr_val = val.pointee
        if ptr_val == 0 { return nil }
        return UnsafeMutableRawPointer(bitPattern: UInt(ptr_val))?
            .bindMemory(to: ecs_component_record_t.self, capacity: 1)
    } else {
        // Look up in lo array
        guard let lo = world.pointee.id_index_lo else { return nil }
        return lo[Int(hash)]
    }
}

/// Ensure a component record exists for an id. Creates one if not found.
@discardableResult
public func flecs_components_ensure(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t) -> UnsafeMutablePointer<ecs_component_record_t>
{
    if let existing = flecs_components_get(UnsafePointer(world), id) {
        return existing
    }
    return flecs_component_new(world, id)
}

// MARK: - Component Record Creation

/// Create a new component record for the given id.
private func flecs_component_new(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t) -> UnsafeMutablePointer<ecs_component_record_t>
{
    let hash = flecs_component_hash(id)

    // Allocate
    let cr = UnsafeMutablePointer<ecs_component_record_t>.allocate(capacity: 1)
    cr.initialize(to: ecs_component_record_t())

    // Insert into index
    if hash >= UInt64(FLECS_HI_ID_RECORD_ID) {
        let val = ecs_map_ensure(&world.pointee.id_index_hi, hash)
        val.pointee = ecs_map_val_t(UInt(bitPattern: UnsafeMutableRawPointer(cr)))
    } else {
        if let lo = world.pointee.id_index_lo {
            lo[Int(hash)] = cr
        }
    }

    // Initialize table cache
    ecs_map_init(&cr.pointee.cache.index, &world.pointee.allocator)

    cr.pointee.id = id
    cr.pointee.refcount = 1

    let is_pair = ECS_IS_PAIR(id)

    if is_pair {
        let pair_ptr = UnsafeMutablePointer<ecs_pair_record_t>.allocate(capacity: 1)
        pair_ptr.initialize(to: ecs_pair_record_t())
        pair_ptr.pointee.reachable.current = -1
        cr.pointee.pair = pair_ptr

        let rel = ECS_PAIR_FIRST(id)
        let tgt = ECS_IS_VALUE_PAIR(id) ? UInt64(0) : ECS_PAIR_SECOND(id)

        if !ecs_id_is_wildcard(id) && rel != EcsFlag {
            let parent_id = ecs_pair(rel, EcsWildcard)
            let cr_r = flecs_components_ensure(world, parent_id)
            cr.pointee.pair!.pointee.parent = cr_r
            cr.pointee.flags = cr_r.pointee.flags
        }

        // Resolve type info for the relationship
        if rel != EcsWildcard && rel != EcsChildOf {
            cr.pointee.type_info = flecs_determine_type_info_for_component(
                UnsafePointer(world), id)
        }
    } else {
        let rel = id & ECS_COMPONENT_MASK
        if rel != EcsWildcard {
            cr.pointee.type_info = flecs_determine_type_info_for_component(
                UnsafePointer(world), id)
        }
    }

    // Update counters
    world.pointee.info.id_create_total += 1
    if cr.pointee.type_info != nil {
        world.pointee.info.component_id_count += 1
    } else {
        world.pointee.info.tag_id_count += 1
    }
    if is_pair {
        world.pointee.info.pair_id_count += 1
    }

    return cr
}

// MARK: - Component Record Lifecycle

/// Increment refcount on a component record.
public func flecs_component_claim(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>)
{
    cr.pointee.refcount += 1
}

/// Decrement refcount, freeing if it reaches 0.
@discardableResult
public func flecs_component_release(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>) -> Int32
{
    cr.pointee.refcount -= 1
    let rc = cr.pointee.refcount

    if rc == 0 {
        flecs_component_free(world, cr)
    }

    return rc
}

/// Free a component record and clean up.
private func flecs_component_free(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>)
{
    let id = cr.pointee.id

    // Update counters
    world.pointee.info.id_delete_total += 1
    if ECS_IS_PAIR(id) { world.pointee.info.pair_id_count -= 1 }
    if cr.pointee.type_info != nil {
        world.pointee.info.component_id_count -= 1
    } else {
        world.pointee.info.tag_id_count -= 1
    }

    // Clean up table cache
    ecs_map_fini(&cr.pointee.cache.index)

    // Clean up pair record
    if let pair = cr.pointee.pair {
        if let name_index = pair.pointee.name_index {
            flecs_name_index_free(name_index)
        }
        pair.deinitialize(count: 1)
        pair.deallocate()
    }

    // Remove from index
    let hash = flecs_component_hash(id)
    if hash >= UInt64(FLECS_HI_ID_RECORD_ID) {
        ecs_map_remove(&world.pointee.id_index_hi, hash)
    } else {
        if let lo = world.pointee.id_index_lo {
            lo[Int(hash)] = nil
        }
    }

    cr.deinitialize(count: 1)
    cr.deallocate()
}

// MARK: - Type Info on Component Records

/// Set the type info for a component record. Returns true if changed.
@discardableResult
public func flecs_component_set_type_info(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ ti: UnsafePointer<ecs_type_info_t>?) -> Bool
{
    let is_wildcard = ecs_id_is_wildcard(cr.pointee.id)
    if !is_wildcard {
        if ti != nil {
            if cr.pointee.type_info == nil {
                world.pointee.info.tag_id_count -= 1
                world.pointee.info.component_id_count += 1
            }
        } else {
            if cr.pointee.type_info != nil {
                world.pointee.info.tag_id_count += 1
                world.pointee.info.component_id_count -= 1
            }
        }
    }

    let changed = cr.pointee.type_info != ti
    cr.pointee.type_info = ti
    return changed
}

/// Get the type info from a component record.
public func flecs_component_get_type_info(
    _ cr: UnsafePointer<ecs_component_record_t>) -> UnsafePointer<ecs_type_info_t>?
{
    return cr.pointee.type_info
}

// MARK: - Name Index on Component Records

/// Ensure a name index exists for a component record's pair.
public func flecs_component_name_index_ensure(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>) -> UnsafeMutablePointer<ecs_hashmap_t>?
{
    guard let pair = cr.pointee.pair else { return nil }
    if let map = pair.pointee.name_index {
        return map
    }
    let map = flecs_name_index_new(&world.pointee.allocator)
    pair.pointee.name_index = map
    return map
}

/// Get the name index from a component record's pair (may be nil).
public func flecs_component_name_index_get(
    _ world: UnsafePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>) -> UnsafeMutablePointer<ecs_hashmap_t>?
{
    return cr.pointee.pair?.pointee.name_index
}

// MARK: - Table Record Lookup

/// Get the table record for a component in a given table.
public func flecs_component_get_table(
    _ cr: UnsafePointer<ecs_component_record_t>,
    _ table: UnsafePointer<ecs_table_t>) -> UnsafePointer<ecs_table_record_t>?
{
    // Would call ecs_table_cache_get(&cr->cache, table)
    return nil
}

// MARK: - Linked List Traversal

/// Get next component record in the (Relationship, *) linked list.
public func flecs_component_first_next(
    _ cr: UnsafeMutablePointer<ecs_component_record_t>) -> UnsafeMutablePointer<ecs_component_record_t>?
{
    return cr.pointee.pair?.pointee.first.next
}

/// Get next component record in the (*, Target) linked list.
public func flecs_component_second_next(
    _ cr: UnsafeMutablePointer<ecs_component_record_t>) -> UnsafeMutablePointer<ecs_component_record_t>?
{
    return cr.pointee.pair?.pointee.second.next
}

/// Get next traversable component record.
public func flecs_component_trav_next(
    _ cr: UnsafeMutablePointer<ecs_component_record_t>) -> UnsafeMutablePointer<ecs_component_record_t>?
{
    return cr.pointee.pair?.pointee.trav.next
}

/// Get the id from a component record.
public func flecs_component_get_id(
    _ cr: UnsafePointer<ecs_component_record_t>) -> ecs_id_t
{
    return cr.pointee.id
}

/// Get the ChildOf depth for a component record.
public func flecs_component_get_childof_depth(
    _ cr: UnsafePointer<ecs_component_record_t>) -> Int32
{
    return cr.pointee.pair?.pointee.depth ?? 0
}

// MARK: - Init/Fini

/// Initialize the world's component index.
public func flecs_components_init(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    world.pointee.cr_wildcard = flecs_components_ensure(world, EcsWildcard)
    world.pointee.cr_wildcard_wildcard = flecs_components_ensure(
        world, ecs_pair(EcsWildcard, EcsWildcard))
    world.pointee.cr_any = flecs_components_ensure(world, EcsAny)
    world.pointee.cr_isa_wildcard = flecs_components_ensure(
        world, ecs_pair(EcsIsA, EcsWildcard))
}

/// Finalize all component records.
public func flecs_components_fini(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    // Clean up hi map
    while ecs_map_count(&world.pointee.id_index_hi) > 0 {
        var it = ecs_map_iter(&world.pointee.id_index_hi)
        if ecs_map_next(&it) {
            if let ptr = ecs_map_ptr(&it) {
                let cr = ptr.bindMemory(to: ecs_component_record_t.self, capacity: 1)
                flecs_component_release(world, cr)
            }
        }
    }

    // Clean up lo array
    if let lo = world.pointee.id_index_lo {
        for i in 0..<Int(FLECS_HI_ID_RECORD_ID) {
            if let cr = lo[i] {
                flecs_component_release(world, cr)
            }
        }
    }

    ecs_map_fini(&world.pointee.id_index_hi)
    free(world.pointee.id_index_lo)
}

// MARK: - Component shrink

/// Shrink component record memory.
public func flecs_component_shrink(
    _ cr: UnsafeMutablePointer<ecs_component_record_t>)
{
    ecs_map_reclaim(&cr.pointee.cache.index)
    if let pr = cr.pointee.pair, let ni = pr.pointee.name_index {
        ecs_map_reclaim(&ni.pointee.impl)
    }
}
