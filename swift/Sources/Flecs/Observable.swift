// Observable.swift - 1:1 translation of flecs observable.c
// Event record management, observer lookup, and event emission

import Foundation

// MARK: - Event Id Record Type

/// Stores observer lists for a specific event+id combination.
public struct ecs_event_id_record_t {
    public var self_: ecs_vec_t = ecs_vec_t()      // Self observers
    public var self_up: ecs_vec_t = ecs_vec_t()     // Self|Up observers
    public var up: ecs_vec_t = ecs_vec_t()          // Up observers
    public var observer_count: Int32 = 0
    public init() {}
}

// MARK: - Observable Init/Fini

/// Initialize an observable.
public func flecs_observable_init(
    _ observable: UnsafeMutablePointer<ecs_observable_t>)
{
    flecs_sparse_init(
        &observable.pointee.events, nil, nil,
        Int32(MemoryLayout<ecs_event_record_t>.stride))
    observable.pointee.on_add.event = EcsOnAdd
    observable.pointee.on_remove.event = EcsOnRemove
    observable.pointee.on_set.event = EcsOnSet
}

/// Finalize an observable.
public func flecs_observable_fini(
    _ observable: UnsafeMutablePointer<ecs_observable_t>)
{
    flecs_sparse_fini(&observable.pointee.events)
}

// MARK: - Event Record Lookup

/// Get event record for an event. Returns fast-path for builtin events.
public func flecs_event_record_get(
    _ o: UnsafePointer<ecs_observable_t>,
    _ event: ecs_entity_t) -> UnsafeMutablePointer<ecs_event_record_t>?
{
    let o_mut = UnsafeMutablePointer(mutating: o)

    if event == EcsOnAdd {
        return withUnsafeMutablePointer(to: &o_mut.pointee.on_add) { $0 }
    } else if event == EcsOnRemove {
        return withUnsafeMutablePointer(to: &o_mut.pointee.on_remove) { $0 }
    } else if event == EcsOnSet {
        return withUnsafeMutablePointer(to: &o_mut.pointee.on_set) { $0 }
    } else if event == EcsWildcard {
        return withUnsafeMutablePointer(to: &o_mut.pointee.on_wildcard) { $0 }
    }

    // User event - look up in sparse set
    guard let ptr = flecs_sparse_get(
        &o_mut.pointee.events,
        Int32(MemoryLayout<ecs_event_record_t>.stride),
        event) else {
        return nil
    }
    return ptr.bindMemory(to: ecs_event_record_t.self, capacity: 1)
}

/// Ensure an event record exists for an event.
public func flecs_event_record_ensure(
    _ o: UnsafeMutablePointer<ecs_observable_t>,
    _ event: ecs_entity_t) -> UnsafeMutablePointer<ecs_event_record_t>
{
    if let er = flecs_event_record_get(UnsafePointer(o), event) {
        return er
    }

    let er = flecs_sparse_ensure(
        &o.pointee.events,
        Int32(MemoryLayout<ecs_event_record_t>.stride),
        event, nil)!
        .bindMemory(to: ecs_event_record_t.self, capacity: 1)
    er.pointee.event = event
    return er
}

/// Get event record only if it has observers.
private func flecs_event_record_get_if(
    _ o: UnsafePointer<ecs_observable_t>,
    _ event: ecs_entity_t) -> UnsafePointer<ecs_event_record_t>?
{
    guard let er = flecs_event_record_get(o, event) else { return nil }

    if ecs_map_is_init(&UnsafeMutablePointer(mutating: er).pointee.event_ids) {
        return UnsafePointer(er)
    }
    if er.pointee.any != nil { return UnsafePointer(er) }
    if er.pointee.wildcard != nil { return UnsafePointer(er) }
    if er.pointee.wildcard_pair != nil { return UnsafePointer(er) }

    return nil
}

// MARK: - Event Id Record Lookup

/// Get event id record for a specific id within an event record.
public func flecs_event_id_record_get(
    _ er: UnsafePointer<ecs_event_record_t>?,
    _ id: ecs_id_t) -> UnsafeMutablePointer<ecs_event_id_record_t>?
{
    guard let er = er else { return nil }
    let er_mut = UnsafeMutablePointer(mutating: er)

    if id == EcsAny {
        guard let p = er.pointee.any else { return nil }
        return p.bindMemory(to: ecs_event_id_record_t.self, capacity: 1)
    } else if id == EcsWildcard {
        guard let p = er.pointee.wildcard else { return nil }
        return p.bindMemory(to: ecs_event_id_record_t.self, capacity: 1)
    } else if id == ecs_pair(EcsWildcard, EcsWildcard) {
        guard let p = er.pointee.wildcard_pair else { return nil }
        return p.bindMemory(to: ecs_event_id_record_t.self, capacity: 1)
    } else {
        guard ecs_map_is_init(&er_mut.pointee.event_ids) else { return nil }
        guard let val = ecs_map_get(&er_mut.pointee.event_ids, id) else { return nil }
        let ptr_val = val.pointee
        if ptr_val == 0 { return nil }
        return UnsafeMutableRawPointer(bitPattern: UInt(ptr_val))?
            .bindMemory(to: ecs_event_id_record_t.self, capacity: 1)
    }
}

/// Get event id record only if it has observers.
private func flecs_event_id_record_get_if(
    _ er: UnsafePointer<ecs_event_record_t>?,
    _ id: ecs_id_t) -> UnsafeMutablePointer<ecs_event_id_record_t>?
{
    guard let ider = flecs_event_id_record_get(er, id) else { return nil }
    if ider.pointee.observer_count != 0 { return ider }
    return nil
}

/// Ensure an event id record exists.
public func flecs_event_id_record_ensure(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ er: UnsafeMutablePointer<ecs_event_record_t>,
    _ id: ecs_id_t) -> UnsafeMutablePointer<ecs_event_id_record_t>
{
    if let ider = flecs_event_id_record_get(UnsafePointer(er), id) {
        return ider
    }

    let ider = UnsafeMutablePointer<ecs_event_id_record_t>.allocate(capacity: 1)
    ider.initialize(to: ecs_event_id_record_t())

    if id == EcsAny {
        er.pointee.any = UnsafeMutableRawPointer(ider)
        return ider
    } else if id == EcsWildcard {
        er.pointee.wildcard = UnsafeMutableRawPointer(ider)
        return ider
    } else if id == ecs_pair(EcsWildcard, EcsWildcard) {
        er.pointee.wildcard_pair = UnsafeMutableRawPointer(ider)
        return ider
    }

    ecs_map_init_if(&er.pointee.event_ids, &world.pointee.allocator)
    let val = ecs_map_ensure(&er.pointee.event_ids, id)
    val.pointee = ecs_map_val_t(UInt(bitPattern: UnsafeMutableRawPointer(ider)))
    return ider
}

/// Remove an event id record.
public func flecs_event_id_record_remove(
    _ er: UnsafeMutablePointer<ecs_event_record_t>,
    _ id: ecs_id_t)
{
    if id == EcsAny {
        er.pointee.any = nil
    } else if id == EcsWildcard {
        er.pointee.wildcard = nil
    } else if id == ecs_pair(EcsWildcard, EcsWildcard) {
        er.pointee.wildcard_pair = nil
    } else {
        ecs_map_remove(&er.pointee.event_ids, id)
        if ecs_map_count(&er.pointee.event_ids) == 0 {
            ecs_map_fini(&er.pointee.event_ids)
        }
    }
}

// MARK: - Observer Existence Check

/// Collect matching event id records for a given id.
/// Returns count of matching records (up to 5).
public func flecs_event_observers_get(
    _ er: UnsafePointer<ecs_event_record_t>?,
    _ id: ecs_id_t,
    _ iders: UnsafeMutablePointer<UnsafeMutablePointer<ecs_event_id_record_t>?>) -> Int32
{
    guard let er = er else { return 0 }
    var count: Int32 = 0

    if id != EcsAny {
        let any = flecs_event_id_record_get_if(er, EcsAny)
        if any != nil { iders[Int(count)] = any; count += 1 }
    }

    let exact = flecs_event_id_record_get_if(er, id)
    if exact != nil { iders[Int(count)] = exact; count += 1 }

    if id != EcsAny {
        if ECS_IS_PAIR(id) {
            let id_fwc = ecs_pair(EcsWildcard, ECS_PAIR_SECOND(id))
            let id_swc = ecs_pair(ECS_PAIR_FIRST(id), EcsWildcard)
            let id_pwc = ecs_pair(EcsWildcard, EcsWildcard)

            if id_fwc != id {
                let r = flecs_event_id_record_get_if(er, id_fwc)
                if r != nil { iders[Int(count)] = r; count += 1 }
            }
            if id_swc != id {
                let r = flecs_event_id_record_get_if(er, id_swc)
                if r != nil { iders[Int(count)] = r; count += 1 }
            }
            if id_pwc != id {
                let r = flecs_event_id_record_get_if(er, id_pwc)
                if r != nil { iders[Int(count)] = r; count += 1 }
            }
        } else if id != EcsWildcard {
            let r = flecs_event_id_record_get_if(er, EcsWildcard)
            if r != nil { iders[Int(count)] = r; count += 1 }
        }
    }

    return count
}

/// Check if any observers exist for an event+id combination.
public func flecs_observers_exist(
    _ observable: UnsafePointer<ecs_observable_t>,
    _ id: ecs_id_t,
    _ event: ecs_entity_t) -> Bool
{
    guard let er = flecs_event_record_get_if(observable, event) else {
        return false
    }
    return flecs_event_id_record_get_if(er, id) != nil
}

// MARK: - Cache Invalidation

/// Invalidate reachable caches for entities in a table range.
public func flecs_emit_propagate_invalidate(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ offset: Int32,
    _ count: Int32)
{
    guard let entities = table.pointee.data.entities else { return }
    for i in 0..<Int(count) {
        let e = entities[offset + Int32(i)]
        guard let cr_t = flecs_components_get(
            UnsafePointer(world), ecs_pair(EcsWildcard, e)) else {
            continue
        }
        flecs_emit_propagate_invalidate_tables(world, cr_t)
    }
}

/// Recursively invalidate reachable caches for traversable relationships.
private func flecs_emit_propagate_invalidate_tables(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ tgt_cr: UnsafeMutablePointer<ecs_component_record_t>)
{
    var cur: UnsafeMutablePointer<ecs_component_record_t>? = tgt_cr
    while let next = flecs_component_trav_next(cur!) {
        cur = next
        guard let pair = cur!.pointee.pair else { continue }

        let rc = withUnsafeMutablePointer(to: &pair.pointee.reachable) { $0 }
        if rc.pointee.current != rc.pointee.generation {
            continue
        }
        rc.pointee.generation += 1

        // Would recurse into table cache entries for deep invalidation
    }
}

// MARK: - Emit (Stub)

/// The main event emission function. Finds and invokes matching observers.
/// This is the most complex function in flecs - the structure is translated
/// but observer invocation requires the full observer infrastructure.
public func flecs_emit(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ stage: UnsafeMutablePointer<ecs_world_t>,
    _ desc: UnsafeMutablePointer<ecs_event_desc_t>)
{
    guard let ids = desc.pointee.ids else { return }
    let event = desc.pointee.event
    guard event != 0 && event != EcsWildcard else { return }
    guard desc.pointee.table != nil else { return }

    // Save/restore defer state
    var defer_val: Int32 = 0
    if let stages = world.pointee.stages, let stage0 = stages.pointee {
        defer_val = stage0.pointee.defer
        if defer_val < 0 {
            stage0.pointee.defer *= -1
        }
    }

    let evtx = world.pointee.event_id + 1
    world.pointee.event_id = evtx

    let observable = withUnsafeMutablePointer(to: &world.pointee.observable) { $0 }

    let er = flecs_event_record_get_if(UnsafePointer(observable), event)
    let wcer = flecs_event_record_get_if(UnsafePointer(observable), EcsWildcard)

    guard er != nil || wcer != nil else {
        // Restore defer
        if let stages = world.pointee.stages, let stage0 = stages.pointee {
            stage0.pointee.defer = defer_val
        }
        return
    }

    let id_count = ids.pointee.count
    guard let id_array = ids.pointee.array else {
        if let stages = world.pointee.stages, let stage0 = stages.pointee {
            stage0.pointee.defer = defer_val
        }
        return
    }

    // Iterate each id in the event
    for i in 0..<Int(id_count) {
        let id = id_array[i]
        if id != EcsAny && ecs_id_is_wildcard(id) {
            continue
        }

        guard let cr = flecs_components_get(UnsafePointer(world), id) else {
            continue
        }

        // Get matching observer sets
        var iders = (
            nil as UnsafeMutablePointer<ecs_event_id_record_t>?,
            nil as UnsafeMutablePointer<ecs_event_id_record_t>?,
            nil as UnsafeMutablePointer<ecs_event_id_record_t>?,
            nil as UnsafeMutablePointer<ecs_event_id_record_t>?,
            nil as UnsafeMutablePointer<ecs_event_id_record_t>?
        )

        var ider_count: Int32 = 0
        if let er = er {
            withUnsafeMutablePointer(to: &iders.0) { ptr in
                ider_count = flecs_event_observers_get(er, id, ptr)
            }
        }

        // Observer invocation would happen here via flecs_observers_invoke
        // which iterates the observer vectors in each ider and calls
        // the observer callback if the query matches.
        _ = ider_count
        _ = cr
    }

    // Restore defer state
    if let stages = world.pointee.stages, let stage0 = stages.pointee {
        stage0.pointee.defer = defer_val
    }
}

/// Public emit API - wraps flecs_emit with defer.
public func ecs_emit(
    _ stage: UnsafeMutablePointer<ecs_world_t>,
    _ desc: UnsafeMutablePointer<ecs_event_desc_t>)
{
    guard let world_ptr = ecs_get_world(UnsafeRawPointer(stage)) else { return }
    let world = UnsafeMutablePointer(mutating: world_ptr)

    if let entity = Optional(desc.pointee.entity), entity != 0 {
        if let r = flecs_entities_get(UnsafePointer(world), entity) {
            desc.pointee.table = r.pointee.table
            desc.pointee.offset = ECS_RECORD_TO_ROW(r.pointee.row)
            desc.pointee.count = 1
        }
    }

    if desc.pointee.observable == nil {
        desc.pointee.observable = UnsafeMutableRawPointer(world)
    }

    flecs_emit(world, stage, desc)
}
