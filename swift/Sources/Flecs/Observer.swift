// Observer.swift - 1:1 translation of flecs observable/observer
// Event emission and observer management

import Foundation

// MARK: - Observable Init/Fini

public func flecs_observable_init(
    _ observable: UnsafeMutablePointer<ecs_observable_t>
) {
    observable.pointee = ecs_observable_t()
    let elemSize = ecs_size_t(MemoryLayout<ecs_event_record_t>.stride)
    flecs_sparse_init(&observable.pointee.events, nil, nil, elemSize)
    ecs_vec_init(nil, &observable.pointee.global_observers,
                 ecs_size_t(MemoryLayout<UnsafeMutableRawPointer?>.stride), 2)
}

public func flecs_observable_fini(
    _ observable: UnsafeMutablePointer<ecs_observable_t>
) {
    let ptrSize = ecs_size_t(MemoryLayout<UnsafeMutableRawPointer?>.stride)
    ecs_vec_fini(nil, &observable.pointee.global_observers, ptrSize)
    flecs_sparse_fini(&observable.pointee.events)
}

// MARK: - Event Record

public func flecs_event_record_get(
    _ o: UnsafePointer<ecs_observable_t>,
    _ event: ecs_entity_t
) -> UnsafeMutablePointer<ecs_event_record_t>? {
    // Check built-in events first
    if event == EcsOnAdd {
        return UnsafeMutablePointer(mutating: &UnsafeMutablePointer(mutating: o).pointee.on_add)
    }
    if event == EcsOnRemove {
        return UnsafeMutablePointer(mutating: &UnsafeMutablePointer(mutating: o).pointee.on_remove)
    }
    if event == EcsOnSet {
        return UnsafeMutablePointer(mutating: &UnsafeMutablePointer(mutating: o).pointee.on_set)
    }
    if event == EcsWildcard {
        return UnsafeMutablePointer(mutating: &UnsafeMutablePointer(mutating: o).pointee.on_wildcard)
    }

    let elemSize = ecs_size_t(MemoryLayout<ecs_event_record_t>.stride)
    var events = o.pointee.events
    guard let ptr = flecs_sparse_try_get(&events, elemSize, event) else {
        return nil
    }
    return ptr.assumingMemoryBound(to: ecs_event_record_t.self)
}

public func flecs_event_record_ensure(
    _ o: UnsafeMutablePointer<ecs_observable_t>,
    _ event: ecs_entity_t
) -> UnsafeMutablePointer<ecs_event_record_t> {
    if let existing = flecs_event_record_get(UnsafePointer(o), event) {
        return existing
    }

    let elemSize = ecs_size_t(MemoryLayout<ecs_event_record_t>.stride)
    let ptr = flecs_sparse_ensure(&o.pointee.events, elemSize, event)!
    let er = ptr.assumingMemoryBound(to: ecs_event_record_t.self)
    er.pointee = ecs_event_record_t()
    er.pointee.event = event
    return er
}

// MARK: - Event ID Record

public func flecs_event_id_record_get(
    _ er: UnsafePointer<ecs_event_record_t>,
    _ id: ecs_id_t
) -> UnsafeMutablePointer<ecs_event_id_record_t>? {
    var event_ids = er.pointee.event_ids
    if !ecs_map_is_init(&event_ids) {
        return nil
    }
    guard let val = ecs_map_get(&event_ids, id) else {
        return nil
    }
    return UnsafeMutablePointer<ecs_event_id_record_t>(
        bitPattern: UInt(val.pointee))
}

public func flecs_event_id_record_ensure(
    _ world: UnsafeMutableRawPointer?,
    _ er: UnsafeMutablePointer<ecs_event_record_t>,
    _ id: ecs_id_t
) -> UnsafeMutablePointer<ecs_event_id_record_t> {
    if let existing = flecs_event_id_record_get(UnsafePointer(er), id) {
        return existing
    }

    let eidr = UnsafeMutablePointer<ecs_event_id_record_t>.allocate(capacity: 1)
    eidr.pointee = ecs_event_id_record_t()

    if !ecs_map_is_init(&er.pointee.event_ids) {
        ecs_map_init(&er.pointee.event_ids, nil)
    }

    ecs_map_insert(&er.pointee.event_ids, id,
                   ecs_map_val_t(UInt(bitPattern: eidr)))

    return eidr
}

public func flecs_event_id_record_remove(
    _ er: UnsafeMutablePointer<ecs_event_record_t>,
    _ id: ecs_id_t
) {
    guard let eidr = flecs_event_id_record_get(UnsafePointer(er), id) else {
        return
    }

    eidr.deallocate()
    ecs_map_remove(&er.pointee.event_ids, id)

    if ecs_map_count(&er.pointee.event_ids) == 0 {
        ecs_map_fini(&er.pointee.event_ids)
    }
}

// MARK: - Observer Existence Check

public func flecs_observers_exist(
    _ observable: UnsafePointer<ecs_observable_t>,
    _ id: ecs_id_t,
    _ event: ecs_entity_t
) -> Bool {
    guard let er = flecs_event_record_get(observable, event) else {
        return false
    }
    return flecs_event_id_record_get(UnsafePointer(er), id) != nil
}

// MARK: - Emit (stub - full implementation requires table/entity operations)

public func flecs_emit(
    _ world: UnsafeMutableRawPointer?,
    _ stage: UnsafeMutableRawPointer?,
    _ desc: UnsafeMutablePointer<ecs_event_desc_t>
) {
    // TODO: Full emit implementation requires table iteration and observer invocation
    // This is the most complex function in the observer system (~1000 lines in C)
    // For now, this is a stub that will be fleshed out when the full ECS is integrated
}

// MARK: - Default Next Callback

public func flecs_default_next_callback(
    _ it: UnsafeMutablePointer<ecs_iter_t>?
) -> Bool {
    return false
}
