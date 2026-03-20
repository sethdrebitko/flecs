// Stage.swift - 1:1 translation of flecs stage.c
// Staging implementation for deferred operations and multithreading

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Get stage from a world pointer (resolves world-or-stage to stage).
public func flecs_stage_from_world(
    _ world: UnsafeMutablePointer<UnsafeMutablePointer<ecs_world_t>>) -> UnsafeMutablePointer<ecs_stage_t>?
{
    let w = world.pointee
    if flecs_poly_is_(UnsafeRawPointer(w), ecs_stage_t_magic) {
        return UnsafeMutableRawPointer(w).bindMemory(to: ecs_stage_t.self, capacity: 1)
    }
    // It's a real world - return stage[0]
    if w.pointee.stages == nil || w.pointee.stage_count <= 0 {
        return nil
    }
    if w.pointee.stages!.pointee == nil { return nil }
    world.pointee = w.pointee.stages!.pointee!.pointee.world ?? w
    return w.pointee.stages!.pointee!
}

/// Get stage from a readonly world pointer.
public func flecs_stage_from_readonly_world(
    _ world: UnsafePointer<ecs_world_t>) -> UnsafePointer<ecs_stage_t>?
{
    if flecs_poly_is_(UnsafeRawPointer(world), ecs_stage_t_magic) {
        return UnsafeRawPointer(world).assumingMemoryBound(to: ecs_stage_t.self)
    }
    if world.pointee.stages == nil || world.pointee.stage_count <= 0 {
        return nil
    }
    if world.pointee.stages!.pointee == nil { return nil }
    return UnsafePointer(world.pointee.stages!.pointee!)
}

/// Set the current system entity on a stage.
@discardableResult
public func flecs_stage_set_system(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ system: ecs_entity_t) -> ecs_entity_t
{
    let old = stage.pointee.system
    stage.pointee.system = system
    return old
}


/// Get the number of stages in the world.
public func ecs_get_stage_count(
    _ world: UnsafePointer<ecs_world_t>) -> Int32
{
    let w = ecs_get_world(UnsafeRawPointer(world))
    if w == nil { return 0 }
    return w!.pointee.stage_count
}

/// Get a stage by index.
public func ecs_get_stage(
    _ world: UnsafePointer<ecs_world_t>,
    _ stage_id: Int32) -> UnsafeMutableRawPointer?
{
    if world.pointee.stage_count <= stage_id { return nil }
    if world.pointee.stages == nil { return nil }
    return UnsafeMutableRawPointer(world.pointee.stages![Int(stage_id)])
}

/// Get the id of a stage.
public func ecs_stage_get_id(
    _ world: UnsafePointer<ecs_world_t>) -> Int32
{
    if flecs_poly_is_(UnsafeRawPointer(world), ecs_stage_t_magic) {
        let stage = UnsafeRawPointer(world)
            .assumingMemoryBound(to: ecs_stage_t.self)
        return stage.pointee.id
    } else if flecs_poly_is_(UnsafeRawPointer(world), ecs_world_t_magic) {
        return 0
    }
    return 0
}


/// Enter readonly mode. All mutations go through command buffers.
@discardableResult
public func ecs_readonly_begin(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ multi_threaded: Bool) -> Bool
{
    let is_readonly = ECS_BIT_IS_SET(world.pointee.flags, EcsWorldReadonly)

    world.pointee.flags |= EcsWorldReadonly
    if multi_threaded {
        world.pointee.flags |= EcsWorldMultiThreaded
    } else {
        world.pointee.flags &= ~EcsWorldMultiThreaded
    }

    return is_readonly
}

/// Exit readonly mode. Flushes command buffers.
public func ecs_readonly_end(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    if (world.pointee.flags & EcsWorldReadonly) == 0 { return }

    world.pointee.flags &= ~EcsWorldReadonly
    world.pointee.flags &= ~EcsWorldMultiThreaded

    // Would call flecs_stage_merge(world) in full implementation
}

/// Check if a world/stage is in readonly mode.
public func ecs_stage_is_readonly(
    _ stage: UnsafePointer<ecs_world_t>) -> Bool
{
    let world = ecs_get_world(UnsafeRawPointer(stage))
    if world == nil { return false }

    if flecs_poly_is_(UnsafeRawPointer(stage), ecs_stage_t_magic) {
        let s = UnsafeRawPointer(stage).assumingMemoryBound(to: ecs_stage_t.self)
        if s.pointee.id == -1 {
            return false
        }
    }

    if (world!.pointee.flags & EcsWorldReadonly) != 0 {
        if flecs_poly_is_(UnsafeRawPointer(stage), ecs_world_t_magic) {
            return true
        }
    } else {
        if flecs_poly_is_(UnsafeRawPointer(stage), ecs_stage_t_magic) {
            return true
        }
    }

    return false
}

/// Check if the world is in deferred mode.
public func ecs_is_deferred(
    _ world: UnsafePointer<ecs_world_t>) -> Bool
{
    let stage = flecs_stage_from_readonly_world(world)
    if stage == nil { return false }
    return stage!.pointee.defer > 0
}

/// Check if defer is suspended.
public func ecs_is_defer_suspended(
    _ world: UnsafePointer<ecs_world_t>) -> Bool
{
    let stage = flecs_stage_from_readonly_world(world)
    if stage == nil { return false }
    return stage!.pointee.defer < 0
}


/// Suspend readonly mode to allow direct mutations.
public func flecs_suspend_readonly(
    _ stage_world: UnsafePointer<ecs_world_t>,
    _ state: UnsafeMutablePointer<ecs_suspend_readonly_state_t>) -> UnsafeMutablePointer<ecs_world_t>?
{
    let world_ptr = ecs_get_world(UnsafeRawPointer(stage_world))
    if world_ptr == nil { return nil }
    let world = UnsafeMutablePointer(mutating: world_ptr!)

    let is_readonly = ECS_BIT_IS_SET(world.pointee.flags, EcsWorldReadonly)
    var temp_world = world
    let stage = flecs_stage_from_world(&temp_world)
    if stage == nil { return nil }

    if !is_readonly && stage!.pointee.defer == 0 {
        state.pointee.is_readonly = false
        state.pointee.is_deferred = false
        return world
    }

    state.pointee.is_readonly = is_readonly
    state.pointee.is_deferred = stage!.pointee.defer != 0
    state.pointee.cmd_flushing = stage!.pointee.cmd_flushing

    world.pointee.flags &= ~EcsWorldReadonly
    stage!.pointee.cmd_flushing = false

    state.pointee.defer_count = stage!.pointee.defer
    state.pointee.scope = stage!.pointee.scope
    state.pointee.with = stage!.pointee.with
    stage!.pointee.defer = 0

    return world
}

/// Resume readonly mode after a suspension.
public func flecs_resume_readonly(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ state: UnsafeMutablePointer<ecs_suspend_readonly_state_t>)
{
    var temp_world = world
    let stage = flecs_stage_from_world(&temp_world)
    if stage == nil { return }

    if state.pointee.is_readonly || state.pointee.is_deferred {
        if state.pointee.is_readonly {
            world.pointee.flags |= EcsWorldReadonly
        }
        stage!.pointee.defer = state.pointee.defer_count
        stage!.pointee.cmd_flushing = state.pointee.cmd_flushing
        stage!.pointee.scope = state.pointee.scope
        stage!.pointee.with = state.pointee.with
    }
}


/// Get world flags.
@inline(__always)
public func ecs_world_get_flags(
    _ world: UnsafePointer<ecs_world_t>) -> ecs_flags32_t
{
    let w = ecs_get_world(UnsafeRawPointer(world))
    if w == nil { return 0 }
    return w!.pointee.flags
}
