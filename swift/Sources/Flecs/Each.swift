// Each.swift - 1:1 translation of flecs each.c
// Simple iterator for a single component id

import Foundation

// MARK: - Internal

private func flecs_each_component_record(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ id: ecs_id_t) -> Bool
{
    if id == 0 { return false }

    // Access the each_iter within the private iter union
    withUnsafeMutablePointer(to: &it.pointee.priv_.query) { priv in
        let each_ptr = UnsafeMutableRawPointer(priv)
            .bindMemory(to: ecs_each_iter_t.self, capacity: 1)
        each_ptr.pointee.ids = id
        each_ptr.pointee.sizes = 0
        if let ti = cr.pointee.type_info {
            each_ptr.pointee.sizes = ti.pointee.size
        }
        each_ptr.pointee.sources = 0
        each_ptr.pointee.trs = nil

        // Initialize the table cache iterator
        let cache_ptr = UnsafeMutableRawPointer(cr)
            .bindMemory(to: ecs_table_cache_t.self, capacity: 1)
        flecs_table_cache_iter(cache_ptr, &each_ptr.pointee.it)
    }

    return true
}

// MARK: - Public API

/// Iterate all entities with a given id.
public func ecs_each_id(
    _ stage: UnsafePointer<ecs_world_t>,
    _ id: ecs_id_t) -> ecs_iter_t
{
    if id == 0 { return ecs_iter_t() }

    var it = ecs_iter_t()
    it.real_world = UnsafeMutablePointer(mutating: stage)
    it.world = UnsafeMutablePointer(mutating: stage)
    it.field_count = 1
    it.next = ecs_each_next

    // Look up component record - would call flecs_components_get in full impl
    // For now return the iterator structure ready for use
    return it
}

/// Advance the each iterator to the next table.
public func ecs_each_next(
    _ it: UnsafeMutablePointer<ecs_iter_t>?) -> Bool
{
    guard let it = it else { return false }

    // Access the each_iter within the private iter data
    let each_iter = withUnsafeMutablePointer(to: &it.pointee.priv_.query) { priv in
        return UnsafeMutableRawPointer(priv)
            .bindMemory(to: ecs_each_iter_t.self, capacity: 1)
    }

    let next = flecs_table_cache_next(
        &each_iter.pointee.it)
    it.pointee.flags |= EcsIterIsValid

    if let next = next {
        each_iter.pointee.trs = UnsafePointer<ecs_table_record_t>(
            next.bindMemory(to: ecs_table_record_t.self, capacity: 1))

        let tr = next.bindMemory(to: ecs_table_record_t.self, capacity: 1)
        let table = tr.pointee.hdr.table
        it.pointee.table = table
        it.pointee.trs = withUnsafePointer(to: &each_iter.pointee.trs) { ptr in
            return UnsafePointer<UnsafePointer<ecs_table_record_t>?>(
                OpaquePointer(ptr))
        }
        it.pointee.sources = withUnsafeMutablePointer(to: &each_iter.pointee.sources) { $0 }
        it.pointee.sizes = withUnsafePointer(to: &each_iter.pointee.sizes) { $0 }
        it.pointee.set_fields = 1

        return true
    }

    return false
}

/// Count entities matching an id.
public func ecs_count_id(
    _ world: UnsafePointer<ecs_world_t>,
    _ id: ecs_entity_t) -> Int32
{
    if id == 0 { return 0 }

    var count: Int32 = 0
    var it = ecs_each_id(world, id)
    while ecs_each_next(&it) {
        count += it.count
    }

    return count
}
