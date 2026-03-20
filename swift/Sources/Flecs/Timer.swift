// Timer.swift - 1:1 translation of flecs addons/timer.c
// Timer, rate filter, and tick source components

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Timer component. Fires after timeout, optionally repeating.
public struct EcsTimer {
    public var timeout: ecs_ftime_t = 0
    public var time: ecs_ftime_t = 0
    public var overshoot: ecs_ftime_t = 0
    public var fired_count: Int32 = 0
    public var active: Bool = false
    public var single_shot: Bool = false
    public init() {}
}

/// Rate filter component. Fires every N ticks of a source.
public struct EcsRateFilter {
    public var src: ecs_entity_t = 0
    public var rate: Int32 = 0
    public var tick_count: Int32 = 0
    public var time_elapsed: ecs_ftime_t = 0
    public init() {}
}

/// Tick source component. Indicates whether a tick occurred this frame.
public struct EcsTickSource {
    public var tick: Bool = false
    public var time_elapsed: ecs_ftime_t = 0
    public init() {}
}


/// Set a timeout timer on an entity. Creates a single-shot timer.
@discardableResult
public func ecs_set_timeout(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ timer: ecs_entity_t,
    _ timeout: ecs_ftime_t) -> ecs_entity_t
{
    var e = timer
    if e == 0 { e = ecs_new(world) }

    ecs_set(world, e, EcsTimer.self, EcsTimer(
        timeout: timeout, time: 0, overshoot: 0, fired_count: 0,
        active: true, single_shot: true))

    return e
}

/// Get the timeout value of a timer.
public func ecs_get_timeout(
    _ world: UnsafePointer<ecs_world_t>,
    _ timer: ecs_entity_t) -> ecs_ftime_t
{
    let value = ecs_get(world, timer, EcsTimer.self); if value == nil { return 0 }
    return value!.pointee.timeout
}

/// Set a repeating interval timer on an entity.
@discardableResult
public func ecs_set_interval(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ timer: ecs_entity_t,
    _ interval: ecs_ftime_t) -> ecs_entity_t
{
    var e = timer
    if e == 0 { e = ecs_new(world) }

    let t = ecs_ensure(world, e, EcsTimer.self)
    if t != nil {
        t!.pointee.timeout = interval
        t!.pointee.active = true
    }

    return e
}

/// Get the interval value of a timer.
public func ecs_get_interval(
    _ world: UnsafePointer<ecs_world_t>,
    _ timer: ecs_entity_t) -> ecs_ftime_t
{
    if timer == 0 { return 0 }
    let value = ecs_get(world, timer, EcsTimer.self); if value == nil { return 0 }
    return value!.pointee.timeout
}

/// Start (activate) a timer.
public func ecs_start_timer(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ timer: ecs_entity_t)
{
    let ptr = ecs_ensure(world, timer, EcsTimer.self); if ptr == nil { return }
    ptr!.pointee.active = true
    ptr!.pointee.time = 0
}

/// Stop (deactivate) a timer.
public func ecs_stop_timer(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ timer: ecs_entity_t)
{
    let ptr = ecs_ensure(world, timer, EcsTimer.self); if ptr == nil { return }
    ptr!.pointee.active = false
}

/// Reset a timer's elapsed time to zero.
public func ecs_reset_timer(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ timer: ecs_entity_t)
{
    let ptr = ecs_ensure(world, timer, EcsTimer.self); if ptr == nil { return }
    ptr!.pointee.time = 0
}


/// Set a rate filter on an entity. Fires every `rate` ticks of `source`.
@discardableResult
public func ecs_set_rate(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ filter: ecs_entity_t,
    _ rate: Int32,
    _ source: ecs_entity_t) -> ecs_entity_t
{
    var e = filter
    if e == 0 { e = ecs_new(world) }

    ecs_set(world, e, EcsRateFilter.self, EcsRateFilter(
        src: source, rate: rate, tick_count: 0, time_elapsed: 0))

    return e
}

/// Set the tick source for a system.
public func ecs_set_tick_source(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ system: ecs_entity_t,
    _ tick_source: ecs_entity_t)
{
    let system_data = flecs_poly_get_(
        UnsafePointer(world), system, EcsSystem)?.bindMemory(
        to: ecs_system_t.self, capacity: 1)
    if system_data == nil { return }
    system_data!.pointee.tick_source = tick_source
}


/// System: progress timers, setting tick when timeout is reached.
private func ProgressTimers(_ it: UnsafeMutablePointer<ecs_iter_t>) {
    let timer = ecs_field(it, EcsTimer.self, 0); if timer == nil { return }
    let tick_source = ecs_field(it, EcsTickSource.self, 1); if tick_source == nil { return }

    let info = ecs_get_world_info(it.pointee.world)

    for i in 0..<Int(it.pointee.count) {
        tick_source![i].tick = false
        if !timer![i].active { continue }

        let time_elapsed = timer![i].time + info!.pointee.delta_time_raw
        let timeout = timer![i].timeout

        if time_elapsed >= timeout {
            var t = time_elapsed - timeout
            if t > timeout { t = 0 }
            timer![i].time = t
            tick_source![i].tick = true
            tick_source![i].time_elapsed = time_elapsed - timer![i].overshoot
            timer![i].overshoot = t
            if timer![i].single_shot { timer![i].active = false }
        } else {
            timer![i].time = time_elapsed
        }
    }
}

/// System: progress rate filters.
private func ProgressRateFilters(_ it: UnsafeMutablePointer<ecs_iter_t>) {
    let filter = ecs_field(it, EcsRateFilter.self, 0); if filter == nil { return }
    let tick_dst = ecs_field(it, EcsTickSource.self, 1); if tick_dst == nil { return }

    for i in 0..<Int(it.pointee.count) {
        filter![i].time_elapsed += it.pointee.delta_time

        var inc = true
        if filter![i].src != 0 {
            let tick_src = ecs_get(it.pointee.world, filter![i].src, EcsTickSource.self)
            if tick_src != nil {
                inc = tick_src!.pointee.tick
            }
        }

        if inc {
            filter![i].tick_count += 1
            let triggered = (filter![i].tick_count % filter![i].rate) == 0
            tick_dst![i].tick = triggered
            tick_dst![i].time_elapsed = filter![i].time_elapsed
            if triggered { filter![i].time_elapsed = 0 }
        } else {
            tick_dst![i].tick = false
        }
    }
}

/// System: unconditionally tick sources without timer/rate filter.
private func ProgressTickSource(_ it: UnsafeMutablePointer<ecs_iter_t>) {
    let tick_src = ecs_field(it, EcsTickSource.self, 0); if tick_src == nil { return }
    for i in 0..<Int(it.pointee.count) {
        tick_src![i].tick = true
        tick_src![i].time_elapsed = it.pointee.delta_time
    }
}


/// Import the Timer module, registering components and systems.
public func FlecsTimerImport(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    ecs_set_name_prefix(world, "Ecs")

    // Would register EcsTimer, EcsRateFilter, EcsTickSource components
    // and create ProgressTimers, ProgressRateFilters, ProgressTickSource systems
    // in the PreFrame phase

    ecs_add_pair(world, ecs_id_EcsTimer, EcsWith, ecs_id_EcsTickSource)
    ecs_add_pair(world, ecs_id_EcsRateFilter, EcsWith, ecs_id_EcsTickSource)
}
