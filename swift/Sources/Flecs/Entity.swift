// Entity.swift - 1:1 translation of flecs entity.c public API
// Entity creation, component management, and lifecycle

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Create a new entity
public func ecs_new(
    _ world: UnsafeMutablePointer<ecs_world_t>
) -> ecs_entity_t {
    let entity = flecs_entity_index_new_id(&world.pointee.store.entity_index)
    return entity
}

/// Create a new entity with an id (component)
public func ecs_new_w(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t
) -> ecs_entity_t {
    let entity = ecs_new(world)
    if id != 0 {
        ecs_add_id(world, entity, id)
    }
    return entity
}

/// Create a new entity from a descriptor
public func ecs_entity_init(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ desc: UnsafePointer<ecs_entity_desc_t>
) -> ecs_entity_t {
    var entity = desc.pointee.id

    if entity == 0 {
        entity = ecs_new(world)
    } else {
        ecs_make_alive(world, entity)
    }

    // Set name if provided
    if desc.pointee.name != nil {
        ecs_set_name(world, entity, desc.pointee.name!)
    }

    // Set parent if provided
    if desc.pointee.parent != 0 {
        ecs_add_id(world, entity, ecs_pair(EcsChildOf, desc.pointee.parent))
    }

    // Add ids if provided
    if desc.pointee.add != nil {
        var i = 0
        while desc.pointee.add![i] != 0 {
            ecs_add_id(world, entity, desc.pointee.add![i])
            i += 1
        }
    }

    return entity
}


/// Make an entity alive (ensure it exists in the entity index)
public func ecs_make_alive(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t
) {
    flecs_entity_index_make_alive(&world.pointee.store.entity_index, entity)
}

/// Check if entity is alive
public func ecs_is_alive(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t
) -> Bool {
    return flecs_entity_index_is_alive(&world.pointee.store.entity_index, entity)
}

/// Check if entity is valid (exists or has no generation)
public func ecs_is_valid(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t
) -> Bool {
    if entity == 0 { return false }
    return flecs_entity_index_is_valid(&world.pointee.store.entity_index, entity)
}

/// Check if entity exists in the entity index
public func ecs_exists(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t
) -> Bool {
    return flecs_entity_index_exists(&world.pointee.store.entity_index, entity)
}

/// Get the alive version of an entity
public func ecs_get_alive(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t
) -> ecs_entity_t {
    return flecs_entity_index_get_alive(&world.pointee.store.entity_index, entity)
}

/// Delete an entity
public func ecs_delete(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t
) {
    guard ecs_is_alive(UnsafePointer(world), entity) else { return }

    // Get the record
    let record = flecs_entity_index_get(
        &world.pointee.store.entity_index, entity)
    if record == nil { return }

    // TODO: If entity is in a table, remove from table first
    // This requires the full table move/delete infrastructure

    // Remove from entity index (marks as dead, increments generation)
    flecs_entity_index_remove(&world.pointee.store.entity_index, entity)
}


/// Add a component/tag to an entity
public func ecs_add_id(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t
) {
    guard ecs_is_alive(UnsafePointer(world), entity) else { return }

    // Ensure the entity record exists
    let _ = flecs_entity_index_ensure(&world.pointee.store.entity_index, entity)

    // TODO: Full implementation:
    // 1. Get current table from record
    // 2. Find destination table (current + id) via table graph
    // 3. Move entity from current to destination table
    // 4. Fire OnAdd observers
    //
    // For now, we ensure the component record exists
    let _ = flecs_components_ensure(world, id)
}

/// Remove a component/tag from an entity
public func ecs_remove_id(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t
) {
    guard ecs_is_alive(UnsafePointer(world), entity) else { return }

    // TODO: Full implementation:
    // 1. Get current table from record
    // 2. Find destination table (current - id) via table graph
    // 3. Move entity from current to destination table
    // 4. Fire OnRemove observers
}

/// Check if an entity has a component/tag
public func ecs_has_id(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t
) -> Bool {
    guard ecs_is_alive(world, entity) else { return false }

    let record = flecs_entity_index_get(
        &UnsafeMutablePointer(mutating: world).pointee.store.entity_index, entity)
    if record == nil {
        return false
    }

    // If entity has no table, it has no components
    if record!.pointee.table == nil { return false }

    let table = record!.pointee.table!.assumingMemoryBound(to: ecs_table_t.self)
    return ecs_search(UnsafeRawPointer(world), table, id, nil) != -1
}

/// Get a pointer to a component
public func ecs_get_id(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t
) -> UnsafeRawPointer? {
    guard ecs_is_alive(world, entity) else { return nil }

    let record = flecs_entity_index_get(
        &UnsafeMutablePointer(mutating: world).pointee.store.entity_index, entity)
    if record == nil {
        return nil
    }

    if record!.pointee.table == nil { return nil }
    let table = record!.pointee.table!.assumingMemoryBound(to: ecs_table_t.self)

    // Find the column for this component
    var found_id: ecs_id_t = 0
    let column_index = ecs_search(UnsafeRawPointer(world), table, id, &found_id)
    if column_index == -1 { return nil }

    // TODO: Get data from the column using the row from the record
    // This requires: table.data.columns[column].data + row * size

    return nil
}

/// Get a mutable pointer to a component
public func ecs_ensure_id(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t
) -> UnsafeMutableRawPointer? {
    guard ecs_is_alive(UnsafePointer(world), entity) else { return nil }

    // Add the component if not present
    if !ecs_has_id(UnsafePointer(world), entity, id) {
        ecs_add_id(world, entity, id)
    }

    // TODO: Return mutable pointer to component data
    return nil
}

/// Set a component value (copies data)
public func ecs_set_id(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t,
    _ size: ecs_size_t,
    _ ptr: UnsafeRawPointer?
) -> ecs_entity_t {
    if ptr == nil { return entity }

    // Ensure the component exists on the entity
    let dst = ecs_ensure_id(world, entity, id)
    if dst == nil {
        return entity
    }

    // Copy data
    memcpy(dst!, ptr!, Int(size))

    // TODO: Fire OnSet observers

    return entity
}


/// Clear all components from an entity (but keep it alive)
public func ecs_clear(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t
) {
    guard ecs_is_alive(UnsafePointer(world), entity) else { return }

    // TODO: Move entity to root table (empty archetype)
    // This requires the full table infrastructure
}


/// Set the name of an entity
public func ecs_set_name(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ name: UnsafePointer<CChar>?
) -> ecs_entity_t {
    if name == nil { return entity }

    // Ensure entity is alive
    ecs_make_alive(world, entity)

    // TODO: Full implementation sets the EcsIdentifier(Name) component
    // and updates the name index. For now, store in a simple way.

    return entity
}

/// Get the name of an entity
public func ecs_get_name(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t
) -> UnsafePointer<CChar>? {
    guard ecs_is_alive(world, entity) else { return nil }

    // TODO: Look up EcsIdentifier(Name) component
    return nil
}

/// Get the symbol of an entity
public func ecs_get_symbol(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t
) -> UnsafePointer<CChar>? {
    guard ecs_is_alive(world, entity) else { return nil }

    // TODO: Look up EcsIdentifier(Symbol) component
    return nil
}


/// Get the target of a relationship pair for an entity
public func ecs_get_target(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ rel: ecs_entity_t,
    _ index: Int32
) -> ecs_entity_t {
    guard ecs_is_alive(world, entity) else { return 0 }

    let record = flecs_entity_index_get(
        &UnsafeMutablePointer(mutating: world).pointee.store.entity_index, entity)
    if record == nil {
        return 0
    }

    if record!.pointee.table == nil { return 0 }
    let table = record!.pointee.table!.assumingMemoryBound(to: ecs_table_t.self)

    // Search for (rel, *) pair
    let wc = ecs_pair(rel, EcsWildcard)
    var found_id: ecs_id_t = 0
    var current_index: Int32 = 0
    var offset: Int32 = 0

    while true {
        let result = ecs_search_offset(UnsafeRawPointer(world), table, offset, wc, &found_id)
        if result == -1 { return 0 }

        if current_index == index {
            return ECS_PAIR_SECOND(found_id)
        }

        current_index += 1
        offset = result + 1
    }
}

/// Get the parent of an entity (shorthand for ecs_get_target with EcsChildOf)
public func ecs_get_parent(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t
) -> ecs_entity_t {
    return ecs_get_target(world, entity, EcsChildOf, 0)
}


/// Enable or disable a component on an entity
public func ecs_enable_id(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t,
    _ enable: Bool
) {
    // TODO: Toggle bitset implementation
}

/// Check if a component is enabled on an entity
public func ecs_is_enabled_id(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t
) -> Bool {
    // TODO: Check toggle bitset
    return ecs_has_id(world, entity, id)
}


/// Delete all entities with a specific id
public func ecs_delete_with(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t
) {
    // TODO: Iterate all tables with this id and delete entities
}

/// Remove an id from all entities that have it
public func ecs_remove_all(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t
) {
    // TODO: Iterate all tables with this id and remove it
}


/// Register a component with size and alignment
public func ecs_component_init(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ desc: UnsafePointer<ecs_component_desc_t>
) -> ecs_entity_t {
    var entity = desc.pointee.entity
    if entity == 0 {
        entity = ecs_new(world)
    } else {
        ecs_make_alive(world, entity)
    }

    // Ensure component record exists
    let cr = flecs_components_ensure(world, entity)

    // Store type info
    let size = desc.pointee.type.size
    let alignment = desc.pointee.type.alignment

    if size > 0 {
        // Store in world type_info map
        if !ecs_map_is_init(&world.pointee.type_info) {
            ecs_map_init(&world.pointee.type_info, &world.pointee.allocator)
        }

        let ti_ptr = ecs_os_calloc_t(ecs_type_info_t.self)!
        ti_ptr.pointee = desc.pointee.type
        ti_ptr.pointee.component = entity

        ecs_map_ensure(&world.pointee.type_info, entity).pointee =
            ecs_map_val_t(UInt(bitPattern: ti_ptr))

        cr.pointee.type_info = UnsafePointer(ti_ptr)
    }

    return entity
}


/// Set type hooks for a component
public func ecs_set_hooks_id(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_entity_t,
    _ hooks: UnsafePointer<ecs_type_hooks_t>
) {
    // Look up type info
    let val = ecs_map_get(&world.pointee.type_info, id)
    if val == nil { return }
    let ti = UnsafeMutablePointer<ecs_type_info_t>(bitPattern: UInt(val!.pointee))
    if ti == nil { return }

    ti!.pointee.hooks = hooks.pointee
}

/// Get type hooks for a component
public func ecs_get_hooks_id(
    _ world: UnsafePointer<ecs_world_t>,
    _ id: ecs_entity_t
) -> UnsafePointer<ecs_type_hooks_t>? {
    var tiMap = UnsafeMutablePointer(mutating: world).pointee.type_info
    let val = ecs_map_get(&tiMap, id)
    if val == nil { return nil }
    let ti = UnsafePointer<ecs_type_info_t>(bitPattern: UInt(val!.pointee))
    if ti == nil { return nil }
    return withUnsafePointer(to: &UnsafeMutablePointer(mutating: ti!).pointee.hooks) { $0 }
}
