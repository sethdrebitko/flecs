// Search.swift - 1:1 translation of flecs search.c
// Component lookup and table search functions

import Foundation

// MARK: - Component Record Lookup

/// Get component record for an id
public func flecs_components_get(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t
) -> UnsafeMutablePointer<ecs_component_record_t>? {
    // Check the lo index first (for small ids)
    if id < UInt64(FLECS_HI_ID_RECORD_ID) {
        guard let lo = world.pointee.id_index_lo else { return nil }
        return lo[Int(id)]
    }

    // Fall back to hi map
    guard let val = ecs_map_get(&world.pointee.id_index_hi, id) else {
        return nil
    }
    return UnsafeMutablePointer<ecs_component_record_t>(
        bitPattern: UInt(val.pointee))
}

/// Get or create component record for an id
public func flecs_components_ensure(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t
) -> UnsafeMutablePointer<ecs_component_record_t> {
    if let existing = flecs_components_get(world, id) {
        return existing
    }

    // Allocate new component record
    let cr = UnsafeMutablePointer<ecs_component_record_t>.allocate(capacity: 1)
    cr.pointee = ecs_component_record_t()
    cr.pointee.id = id

    // Register in the appropriate index
    if id < UInt64(FLECS_HI_ID_RECORD_ID) {
        if world.pointee.id_index_lo == nil {
            world.pointee.id_index_lo = UnsafeMutablePointer<UnsafeMutablePointer<ecs_component_record_t>?>
                .allocate(capacity: Int(FLECS_HI_ID_RECORD_ID))
            world.pointee.id_index_lo!.initialize(repeating: nil, count: Int(FLECS_HI_ID_RECORD_ID))
        }
        world.pointee.id_index_lo![Int(id)] = cr
    } else {
        if !ecs_map_is_init(&world.pointee.id_index_hi) {
            ecs_map_init(&world.pointee.id_index_hi, nil)
        }
        ecs_map_insert(&world.pointee.id_index_hi, id,
                       ecs_map_val_t(UInt(bitPattern: cr)))
    }

    return cr
}

// MARK: - Table Search

/// Search for a component id in a table's type
public func ecs_search(
    _ world: UnsafeRawPointer?,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ id: ecs_id_t,
    _ id_out: UnsafeMutablePointer<ecs_id_t>?
) -> Int32 {
    return ecs_search_offset(world, table, 0, id, id_out)
}

/// Search for a component id in a table's type starting from an offset
public func ecs_search_offset(
    _ world: UnsafeRawPointer?,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ offset: Int32,
    _ id: ecs_id_t,
    _ id_out: UnsafeMutablePointer<ecs_id_t>?
) -> Int32 {
    let type = table.pointee.type
    guard let array = type.array else { return -1 }
    let count = type.count

    for i in offset..<count {
        let table_id = array[Int(i)]

        if table_id == id {
            id_out?.pointee = table_id
            return i
        }

        // Wildcard matching
        if ECS_HAS_ID_FLAG(id, ECS_PAIR) && ECS_HAS_ID_FLAG(table_id, ECS_PAIR) {
            let id_rel = ECS_PAIR_FIRST(id)
            let id_tgt = ECS_PAIR_SECOND(id)
            let table_rel = ECS_PAIR_FIRST(table_id)
            let table_tgt = ECS_PAIR_SECOND(table_id)

            if (id_rel == EcsWildcard || id_rel == table_rel) &&
               (id_tgt == EcsWildcard || id_tgt == table_tgt) {
                id_out?.pointee = table_id
                return i
            }
        }
    }

    return -1
}

/// Search for a component id in a table's type, following relationship traversal
public func ecs_search_relation(
    _ world: UnsafeRawPointer?,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ offset: Int32,
    _ id: ecs_id_t,
    _ rel: ecs_entity_t,
    _ flags: ecs_flags64_t,
    _ subject_out: UnsafeMutablePointer<ecs_entity_t>?,
    _ id_out: UnsafeMutablePointer<ecs_id_t>?,
    _ tr_out: UnsafeMutablePointer<UnsafePointer<ecs_table_record_t>?>?
) -> Int32 {
    // First try direct search
    let result = ecs_search_offset(world, table, offset, id, id_out)
    if result != -1 {
        subject_out?.pointee = 0
        return result
    }

    // TODO: Full traversal implementation requires looking up relationship targets
    // and recursively searching their tables. This needs the full entity/table
    // infrastructure to be connected.

    return -1
}

// MARK: - ID Helpers

/// Check if an id is a pair
public func ecs_id_is_pair(
    _ id: ecs_id_t
) -> Bool {
    return ECS_IS_PAIR(id)
}

/// Check if an id is a wildcard
public func ecs_id_is_wildcard(
    _ id: ecs_id_t
) -> Bool {
    if id == EcsWildcard || id == EcsAny {
        return true
    }

    if ECS_IS_PAIR(id) {
        let first = ECS_PAIR_FIRST(id)
        let second = ECS_PAIR_SECOND(id)
        return first == EcsWildcard || first == EcsAny ||
               second == EcsWildcard || second == EcsAny
    }

    return false
}

/// Check if an id is valid
public func ecs_id_is_valid(
    _ world: UnsafeRawPointer?,
    _ id: ecs_id_t
) -> Bool {
    if id == 0 { return false }
    if id & ECS_ID_FLAGS_MASK != 0 {
        // Has flags - must be a pair
        if !ECS_IS_PAIR(id) && !ECS_IS_VALUE_PAIR(id) {
            return false
        }
    }
    return true
}
