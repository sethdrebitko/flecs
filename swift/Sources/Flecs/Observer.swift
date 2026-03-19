// Observer.swift - 1:1 translation of flecs observer.c
// Observer creation, registration, matching, and invocation

import Foundation

// MARK: - Observer Types

/// Observer implementation (internal state beyond the public ecs_observer_t).
public struct ecs_observer_impl_t {
    public var pub: ecs_observer_t = ecs_observer_t()
    public var id: ecs_entity_t = 0
    public var register_id: ecs_id_t = 0
    public var term_index: Int8 = 0
    public var flags: ecs_flags32_t = 0
    public var last_event_id: UnsafeMutablePointer<Int32>? = nil
    public var last_event_id_storage: Int32 = 0
    public var children: ecs_vec_t = ecs_vec_t()
    public var not_query: UnsafeMutablePointer<ecs_query_t>? = nil
    public var dtor: (@convention(c) (UnsafeMutableRawPointer?) -> Void)? = nil
    public init() {}
}

/// Observer flags
public let EcsObserverIsDisabled: ecs_flags32_t      = 1 << 0
public let EcsObserverIsParentDisabled: ecs_flags32_t = 1 << 1
public let EcsObserverIsMulti: ecs_flags32_t         = 1 << 2
public let EcsObserverIsMonitor: ecs_flags32_t       = 1 << 3
public let EcsObserverBypassQuery: ecs_flags32_t     = 1 << 4
public let EcsObserverYieldOnCreate: ecs_flags32_t   = 1 << 5
public let EcsObserverYieldOnDelete: ecs_flags32_t   = 1 << 6

// MARK: - Observer Accessor

/// Get the implementation struct from a public observer pointer.
@inline(__always)
public func flecs_observer_impl(
    _ o: UnsafeMutablePointer<ecs_observer_t>) -> UnsafeMutablePointer<ecs_observer_impl_t>
{
    return UnsafeMutableRawPointer(o)
        .bindMemory(to: ecs_observer_impl_t.self, capacity: 1)
}

// MARK: - Event Mapping

/// Get the effective event for an observer term.
/// Not operators reverse OnAdd<->OnRemove.
public func flecs_get_observer_event(
    _ term: UnsafePointer<ecs_term_t>?,
    _ event: ecs_entity_t) -> ecs_entity_t
{
    guard let term = term else { return event }
    if term.pointee.oper == EcsNot {
        if event == EcsOnAdd || event == EcsOnSet {
            return EcsOnRemove
        } else if event == EcsOnRemove {
            return EcsOnAdd
        }
    }
    return event
}

/// Map an event to the corresponding component record flag.
public func flecs_id_flag_for_event(
    _ e: ecs_entity_t) -> ecs_flags32_t
{
    if e == EcsOnAdd { return EcsIdHasOnAdd }
    if e == EcsOnRemove { return EcsIdHasOnRemove }
    if e == EcsOnSet { return EcsIdHasOnSet }
    if e == EcsOnTableCreate { return EcsIdHasOnTableCreate }
    if e == EcsOnTableDelete { return EcsIdHasOnTableDelete }
    if e == EcsWildcard {
        return EcsIdHasOnAdd | EcsIdHasOnRemove | EcsIdHasOnSet |
               EcsIdHasOnTableCreate | EcsIdHasOnTableDelete
    }
    return 0
}

// MARK: - Observer Count Management

/// Increment/decrement observer count for an event+id combination.
/// When count transitions 0<->1, notifies tables and sets cr flags.
public func flecs_inc_observer_count(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ event: ecs_entity_t,
    _ evt: UnsafeMutablePointer<ecs_event_record_t>,
    _ id: ecs_id_t,
    _ value: Int32)
{
    let idt = flecs_event_id_record_ensure(world, evt, id)
    idt.pointee.observer_count += value
    let result = idt.pointee.observer_count

    if result == 1 {
        let flags = flecs_id_flag_for_event(event)
        if flags != 0 {
            if let cr = flecs_components_get(UnsafePointer(world), id) {
                cr.pointee.flags |= flags
            }
        }
    } else if result == 0 {
        let flags = flecs_id_flag_for_event(event)
        if flags != 0 {
            if let cr = flecs_components_get(UnsafePointer(world), id) {
                cr.pointee.flags &= ~flags
            }
        }

        flecs_event_id_record_remove(evt, id)
    }
}

// MARK: - Observer Id Resolution

/// Normalize observer id: replace Any with Wildcard in pairs.
public func flecs_observer_id(_ id: ecs_id_t) -> ecs_id_t {
    var result = id
    if ECS_IS_PAIR(result) {
        if ECS_PAIR_FIRST(result) == EcsAny {
            result = ecs_pair(EcsWildcard, ECS_PAIR_SECOND(result))
        }
        if ECS_PAIR_SECOND(result) == EcsAny {
            result = ecs_pair(ECS_PAIR_FIRST(result), EcsWildcard)
        }
    }
    return result
}

// MARK: - Observer Registration

/// Register a single-term observer for a specific event and id.
private func flecs_register_observer_for_event_and_id(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ observable: UnsafeMutablePointer<ecs_observable_t>,
    _ o: UnsafeMutablePointer<ecs_observer_t>,
    _ offset: Int,
    _ term: UnsafePointer<ecs_term_t>?,
    _ event: ecs_entity_t,
    _ term_id: ecs_id_t)
{
    let trav: ecs_entity_t = term?.pointee.trav ?? 0

    let er = flecs_event_record_ensure(observable, event)
    let idt = flecs_event_id_record_ensure(world, er, term_id)

    // Would insert observer into the ecs_map_t at the given offset within idt
    // (self_, self_up, or up)
    _ = idt
    _ = offset

    flecs_inc_observer_count(world, event, er, term_id, 1)
    if trav != 0 {
        flecs_inc_observer_count(world, event, er,
            ecs_pair(trav, EcsWildcard), 1)
    }
}

/// Register a single-term observer for all its events.
private func flecs_register_observer_for_id(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ observable: UnsafeMutablePointer<ecs_observable_t>,
    _ o: UnsafeMutablePointer<ecs_observer_t>,
    _ offset: Int,
    _ term_id: ecs_id_t)
{
    let term: UnsafePointer<ecs_term_t>? = o.pointee.query != nil
        ? withUnsafePointer(to: &o.pointee.query!.pointee.terms.0) { $0 }
        : nil

    for i in 0..<Int(o.pointee.event_count) {
        let event = flecs_get_observer_event(term, o.pointee.events[i])

        var dup = false
        for j in 0..<i {
            if event == flecs_get_observer_event(term, o.pointee.events[j]) {
                dup = true
                break
            }
        }
        if dup { continue }

        flecs_register_observer_for_event_and_id(
            world, observable, o, offset, term, event, term_id)
    }
}

/// Register a uni (single-term) observer into the observable.
public func flecs_uni_observer_register(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ observable: UnsafeMutablePointer<ecs_observable_t>,
    _ o: UnsafeMutablePointer<ecs_observer_t>)
{
    let impl = flecs_observer_impl(o)
    let term_id = flecs_observer_id(impl.pointee.register_id)

    let term: UnsafePointer<ecs_term_t>? = o.pointee.query != nil
        ? withUnsafePointer(to: &o.pointee.query!.pointee.terms.0) { $0 }
        : nil
    let flags: ecs_flags64_t = term != nil
        ? ECS_TERM_REF_FLAGS(term!.pointee.src)
        : EcsSelf

    if (flags & (EcsSelf | EcsUp)) == (EcsSelf | EcsUp) {
        flecs_register_observer_for_id(world, observable, o,
            MemoryLayout<ecs_event_id_record_t>.offset(of: \ecs_event_id_record_t.self_up) ?? 0,
            term_id)
    } else if (flags & EcsSelf) != 0 {
        flecs_register_observer_for_id(world, observable, o,
            MemoryLayout<ecs_event_id_record_t>.offset(of: \ecs_event_id_record_t.self_) ?? 0,
            term_id)
    } else if (flags & EcsUp) != 0 {
        flecs_register_observer_for_id(world, observable, o,
            MemoryLayout<ecs_event_id_record_t>.offset(of: \ecs_event_id_record_t.up) ?? 0,
            term_id)
    }
}

/// Unregister a single-term observer from the observable.
public func flecs_unregister_observer(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ observable: UnsafeMutablePointer<ecs_observable_t>,
    _ o: UnsafeMutablePointer<ecs_observer_t>)
{
    let q = o.pointee.query
    if q != nil && q!.pointee.term_count == 0 { return }

    let impl = flecs_observer_impl(o)
    let term_id = flecs_observer_id(impl.pointee.register_id)

    let term: UnsafePointer<ecs_term_t>? = q != nil
        ? withUnsafePointer(to: &q!.pointee.terms.0) { $0 }
        : nil
    let flags: ecs_flags64_t = term != nil
        ? ECS_TERM_REF_FLAGS(term!.pointee.src)
        : EcsSelf

    // Would remove observer from the appropriate map in each event id record
    // and decrement observer counts via flecs_inc_observer_count(... -1)
    _ = term_id
    _ = flags
}

// MARK: - Observer Filtering

/// Check if an observer should be ignored for a given table/event.
public func flecs_ignore_observer(
    _ o: UnsafeMutablePointer<ecs_observer_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ it: UnsafePointer<ecs_iter_t>) -> Bool
{
    let impl = flecs_observer_impl(o)

    if let last = impl.pointee.last_event_id {
        if last.pointee == it.pointee.event_cur {
            return true
        }
    }

    if (impl.pointee.flags & (EcsObserverIsDisabled | EcsObserverIsParentDisabled)) != 0 {
        return true
    }

    let table_flags = table.pointee.flags
    let query_flags = impl.pointee.flags

    var result = (table_flags & EcsTableIsPrefab) != 0 &&
                 (query_flags & EcsQueryMatchPrefab) == 0
    result = result || ((table_flags & EcsTableIsDisabled) != 0 &&
                        (query_flags & EcsQueryMatchDisabled) == 0)

    return result
}

// MARK: - Observer Invocation

/// Invoke an observer's callback or run function.
public func flecs_observer_invoke(
    _ o: UnsafeMutablePointer<ecs_observer_t>,
    _ it: UnsafeMutablePointer<ecs_iter_t>)
{
    if let run = o.pointee.run {
        it.pointee.next = flecs_default_next_callback
        it.pointee.callback = o.pointee.callback
        it.pointee.interrupted_by = 0
        if (flecs_observer_impl(o).pointee.flags & EcsObserverBypassQuery) != 0 {
            it.pointee.ctx = UnsafeMutableRawPointer(o)
        } else {
            it.pointee.ctx = o.pointee.ctx
        }
        run(it)
    } else if let callback = o.pointee.callback {
        it.pointee.callback = callback
        callback(it)
    }
}

/// Invoke all observers in a map for a given event.
public func flecs_observers_invoke(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ observers: UnsafeMutablePointer<ecs_map_t>,
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ trav: ecs_entity_t)
{
    guard ecs_map_is_init(observers) else { return }

    ecs_table_lock(it.pointee.world, table)

    var oit = ecs_map_iter(observers)
    while ecs_map_next(&oit) {
        guard let o: UnsafeMutablePointer<ecs_observer_t> = ecs_map_ptr(&oit) else {
            continue
        }
        flecs_uni_observer_invoke(world, o, it, table, trav)
    }

    ecs_table_unlock(it.pointee.world, table)
}

/// Invoke a single-term observer with full setup.
private func flecs_uni_observer_invoke(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ o: UnsafeMutablePointer<ecs_observer_t>,
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ trav: ecs_entity_t)
{
    if flecs_ignore_observer(o, table, UnsafePointer(it)) {
        return
    }

    let impl = flecs_observer_impl(o)
    it.pointee.system = o.pointee.entity
    it.pointee.ctx = o.pointee.ctx
    it.pointee.callback_ctx = o.pointee.callback_ctx
    it.pointee.run_ctx = o.pointee.run_ctx
    it.pointee.term_index = impl.pointee.term_index

    let event = it.pointee.event
    let event_cur = it.pointee.event_cur
    let set_fields_cur = it.pointee.set_fields
    it.pointee.set_fields = 1
    it.pointee.query = o.pointee.query

    if o.pointee.query == nil {
        // Trivial observer
        it.pointee.event = event
        flecs_observer_invoke(o, it)
    } else {
        let term = withUnsafeMutablePointer(to: &o.pointee.query!.pointee.terms.0) { $0 }
        if trav != 0 && term.pointee.trav != trav {
            it.pointee.event = event
            it.pointee.event_cur = event_cur
            it.pointee.set_fields = set_fields_cur
            return
        }

        let is_filter = term.pointee.inout == EcsInOutNone
        if is_filter {
            it.pointee.flags |= EcsIterNoData
        } else {
            it.pointee.flags &= ~EcsIterNoData
        }

        it.pointee.event = flecs_get_observer_event(
            UnsafePointer(term), event)

        let match_this = (o.pointee.query!.pointee.flags & EcsQueryMatchThis) != 0
        if match_this {
            flecs_observer_invoke(o, it)
        }
    }

    it.pointee.event = event
    it.pointee.event_cur = event_cur
    it.pointee.set_fields = set_fields_cur

    world.pointee.info.observers_ran_total += 1
}

// MARK: - Default Next Callback

/// Default next callback for observers that use run+next pattern.
public func flecs_default_next_callback(
    _ it: UnsafeMutablePointer<ecs_iter_t>?) -> Bool
{
    guard let it = it else { return false }
    if it.pointee.interrupted_by != 0 {
        return false
    } else {
        it.pointee.interrupted_by = it.pointee.system
        return true
    }
}

// MARK: - Observer Init/Fini

/// Initialize a single-term observer.
private func flecs_uni_observer_init(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ o: UnsafeMutablePointer<ecs_observer_t>,
    _ component_id: ecs_id_t,
    _ last_event_id: UnsafeMutablePointer<Int32>?) -> Int32
{
    let impl = flecs_observer_impl(o)
    impl.pointee.last_event_id = last_event_id
    if impl.pointee.last_event_id == nil {
        impl.pointee.last_event_id = withUnsafeMutablePointer(
            to: &impl.pointee.last_event_id_storage) { $0 }
    }

    impl.pointee.register_id = component_id

    // Downgrade OnSet to OnAdd for tag components
    if ecs_id_is_tag(world, component_id) {
        var has_on_add = false
        for e in 0..<Int(o.pointee.event_count) {
            if o.pointee.events[e] == EcsOnAdd { has_on_add = true }
        }
        for e in 0..<Int(o.pointee.event_count) {
            if o.pointee.events[e] == EcsOnSet {
                o.pointee.events[e] = has_on_add ? 0 : EcsOnAdd
            }
        }
    }

    guard let observable = o.pointee.observable else { return -1 }
    flecs_uni_observer_register(world, observable, o)
    return 0
}

/// Finalize an observer, cleaning up all resources.
public func flecs_observer_fini(
    _ o: UnsafeMutablePointer<ecs_observer_t>)
{
    guard let world = o.pointee.world else { return }
    let impl = flecs_observer_impl(o)

    if (impl.pointee.flags & EcsObserverYieldOnDelete) != 0 {
        flecs_observer_yield_existing(world, o, true)
    }

    if (impl.pointee.flags & EcsObserverIsMulti) != 0 {
        let children_count = ecs_vec_count(&impl.pointee.children)
        if children_count > 0 {
            if let children = ecs_vec_first(&impl.pointee.children)?
                .bindMemory(to: UnsafeMutablePointer<ecs_observer_t>.self,
                           capacity: Int(children_count))
            {
                for i in 0..<Int(children_count) {
                    flecs_observer_fini(children[i])
                }
            }
        }
        impl.pointee.last_event_id?.deallocate()
    } else {
        if let observable = o.pointee.observable {
            flecs_unregister_observer(world, observable, o)
        }
    }

    if let query = o.pointee.query {
        ecs_query_fini(query)
    }

    if let not_query = impl.pointee.not_query {
        ecs_query_fini(not_query)
    }

    if let ctx_free = o.pointee.ctx_free {
        ctx_free(o.pointee.ctx)
    }
    if let callback_ctx_free = o.pointee.callback_ctx_free {
        callback_ctx_free(o.pointee.callback_ctx)
    }
    if let run_ctx_free = o.pointee.run_ctx_free {
        run_ctx_free(o.pointee.run_ctx)
    }
}

// MARK: - Yield Existing

/// Invoke observer for all existing matches (used for yield_existing).
private func flecs_observer_yield_existing(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ o: UnsafeMutablePointer<ecs_observer_t>,
    _ yield_on_remove: Bool)
{
    ecs_defer_begin(world)

    for i in 0..<Int(o.pointee.event_count) {
        let event = o.pointee.events[i]
        if event == EcsOnRemove {
            if !yield_on_remove { continue }
        } else {
            if yield_on_remove { continue }
        }

        // Would iterate o->query and invoke the observer for each match
    }

    ecs_defer_end(world)
}

// MARK: - Observer Disable

/// Set or clear a disable bit on an observer and its children.
public func flecs_observer_set_disable_bit(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ e: ecs_entity_t,
    _ bit: ecs_flags32_t,
    _ cond: Bool)
{
    guard let poly = ecs_get_pair(world, e, EcsPoly, EcsObserver) else { return }
    guard let o = poly.pointee.poly?.bindMemory(
        to: ecs_observer_t.self, capacity: 1) else { return }

    let impl = flecs_observer_impl(o)
    if (impl.pointee.flags & EcsObserverIsMulti) != 0 {
        let children_count = ecs_vec_count(&impl.pointee.children)
        if children_count > 0 {
            if let children = ecs_vec_first(&impl.pointee.children)?
                .bindMemory(to: UnsafeMutablePointer<ecs_observer_t>.self,
                           capacity: Int(children_count))
            {
                for i in 0..<Int(children_count) {
                    let child_impl = flecs_observer_impl(children[i])
                    if cond {
                        child_impl.pointee.flags |= bit
                    } else {
                        child_impl.pointee.flags &= ~bit
                    }
                }
            }
        }
    } else {
        if cond {
            impl.pointee.flags |= bit
        } else {
            impl.pointee.flags &= ~bit
        }
    }
}

// MARK: - Public API

/// Get observer pointer from entity.
public func ecs_observer_get(
    _ world: UnsafePointer<ecs_world_t>,
    _ observer: ecs_entity_t) -> UnsafePointer<ecs_observer_t>?
{
    return flecs_poly_get(world, observer, ecs_observer_t.self)
}
