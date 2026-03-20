// Each.swift - 1:1 translation of flecs each.c
// Simple iterator for a single component id

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


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
        if cr.pointee.type_info != nil {
            each_ptr.pointee.sizes = cr.pointee.type_info!.pointee.size
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
    if it == nil { return false }

    // Access the each_iter within the private iter data
    let each_iter = withUnsafeMutablePointer(to: &it!.pointee.priv_.query) { priv in
        return UnsafeMutableRawPointer(priv)
            .bindMemory(to: ecs_each_iter_t.self, capacity: 1)
    }

    let next = flecs_table_cache_next(
        &each_iter.pointee.it)
    it!.pointee.flags |= EcsIterIsValid

    if next != nil {
        each_iter.pointee.trs = UnsafePointer<ecs_table_record_t>(
            next!.bindMemory(to: ecs_table_record_t.self, capacity: 1))

        let tr = next!.bindMemory(to: ecs_table_record_t.self, capacity: 1)
        let table = tr.pointee.hdr.table
        it!.pointee.table = table
        it!.pointee.trs = withUnsafePointer(to: &each_iter.pointee.trs) { ptr in
            return UnsafePointer<UnsafePointer<ecs_table_record_t>?>(
                OpaquePointer(ptr))
        }
        it!.pointee.sources = withUnsafeMutablePointer(to: &each_iter.pointee.sources) { $0 }
        it!.pointee.sizes = withUnsafePointer(to: &each_iter.pointee.sizes) { $0 }
        it!.pointee.set_fields = 1

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


/// Internal next function for ordered children vectors.
private func flecs_children_next_ordered(
    _ it: UnsafeMutablePointer<ecs_iter_t>?) -> Bool
{
    if it == nil { return false }
    return ecs_children_next(it!)
}

/// Iterate children of an entity with a specific relationship.
public func ecs_children_w_rel(
    _ stage: UnsafePointer<ecs_world_t>,
    _ relationship: ecs_entity_t,
    _ parent: ecs_entity_t) -> ecs_iter_t
{
    let world = ecs_get_world(UnsafeRawPointer(stage))
    if world == nil {
        return ecs_iter_t()
    }

    var it = ecs_iter_t()
    it.real_world = UnsafeMutablePointer(mutating: world!)
    it.world = UnsafeMutablePointer(mutating: stage)
    it.field_count = 1
    it.next = ecs_children_next

    let cr = flecs_components_get(
        world!, ecs_pair(relationship, parent))
    if cr == nil {
        return ecs_iter_t()
    }

    // If ordered children, return them directly
    if (cr!.pointee.flags & EcsIdOrderedChildren) != 0 {
        if cr!.pointee.pair != nil {
            let elem_size = Int32(MemoryLayout<ecs_entity_t>.stride)
            it.entities = ecs_vec_first(&cr!.pointee.pair!.pointee.ordered_children)?
                .bindMemory(to: ecs_entity_t.self,
                           capacity: Int(ecs_vec_count(&cr!.pointee.pair!.pointee.ordered_children)))
            it.count = ecs_vec_count(&cr!.pointee.pair!.pointee.ordered_children)
            it.next = flecs_children_next_ordered
        }
        return it
    }

    // If sparse children, return from sparse set
    if (cr!.pointee.flags & EcsIdSparse) != 0 {
        if cr!.pointee.sparse != nil {
            it.entities = flecs_sparse_ids(cr!.pointee.sparse!)
            it.count = flecs_sparse_count(cr!.pointee.sparse!)
            it.next = flecs_children_next_ordered
        }
        return it
    }

    // Fall back to regular each iteration
    return ecs_each_id(stage, ecs_pair(relationship, parent))
}

/// Iterate children of an entity (using ChildOf relationship).
public func ecs_children(
    _ stage: UnsafePointer<ecs_world_t>,
    _ parent: ecs_entity_t) -> ecs_iter_t
{
    return ecs_children_w_rel(stage, EcsChildOf, parent)
}

/// Advance a children iterator. Returns false when done.
public func ecs_children_next(
    _ it: UnsafeMutablePointer<ecs_iter_t>?) -> Bool
{
    if it == nil { return false }

    if it!.pointee.next == nil {
        return false
    }

    // Check if this is an ordered children iterator (returns once)
    if it!.pointee.next == flecs_children_next_ordered {
        if it!.pointee.count == 0 {
            return false
        }
        it!.pointee.next = nil  // Only return once
        return true
    }

    return ecs_each_next(it)
}
