// System.swift - 1:1 translation of flecs addons/system/system.c
// System creation, execution, and lifecycle

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// System implementation (poly object with query + callbacks).
public struct ecs_system_t {
    public var hdr: ecs_header_t = ecs_header_t()
    public var entity: ecs_entity_t = 0
    public var query: UnsafeMutablePointer<ecs_query_t>? = nil

    public var run: ecs_run_action_t? = nil
    public var action: ecs_iter_action_t? = nil

    public var ctx: UnsafeMutableRawPointer? = nil
    public var callback_ctx: UnsafeMutableRawPointer? = nil
    public var run_ctx: UnsafeMutableRawPointer? = nil

    public var ctx_free: ecs_ctx_free_t? = nil
    public var callback_ctx_free: ecs_ctx_free_t? = nil
    public var run_ctx_free: ecs_ctx_free_t? = nil

    public var tick_source: ecs_entity_t = 0
    public var multi_threaded: Bool = false
    public var immediate: Bool = false

    public var time_spent: ecs_ftime_t = 0
    public var name: UnsafePointer<CChar>? = nil

    public var group_id: UInt64 = 0
    public var group_id_set: Bool = false

    public var dtor: flecs_poly_dtor_t? = nil

    public init() {}
}


/// Descriptor for creating a system.
public struct ecs_system_desc_t {
    public var _canary: Int32 = 0
    public var entity: ecs_entity_t = 0
    public var query: ecs_query_desc_t = ecs_query_desc_t()
    public var run: ecs_run_action_t? = nil
    public var callback: ecs_iter_action_t? = nil
    public var ctx: UnsafeMutableRawPointer? = nil
    public var callback_ctx: UnsafeMutableRawPointer? = nil
    public var run_ctx: UnsafeMutableRawPointer? = nil
    public var ctx_free: ecs_ctx_free_t? = nil
    public var callback_ctx_free: ecs_ctx_free_t? = nil
    public var run_ctx_free: ecs_ctx_free_t? = nil
    public var interval: ecs_ftime_t = 0
    public var rate: Int32 = 0
    public var tick_source: ecs_entity_t = 0
    public var multi_threaded: Bool = false
    public var immediate: Bool = false
    public var phase: ecs_entity_t = 0
    public init() {}
}


/// Run a system with full worker/stage support.
public func flecs_run_system(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ stage: UnsafeMutablePointer<ecs_stage_t>?,
    _ system: ecs_entity_t,
    _ system_data: UnsafeMutablePointer<ecs_system_t>,
    _ stage_index: Int32,
    _ stage_count: Int32,
    _ delta_time: ecs_ftime_t,
    _ param: UnsafeMutableRawPointer?) -> ecs_entity_t
{
    var time_elapsed = delta_time
    let tick_source = system_data.pointee.tick_source

    // Check tick source
    if tick_source != 0 {
        let tick = ecs_get(world, tick_source, EcsTickSource.self)
        if tick == nil {
            return 0
        }
        if !tick!.pointee.tick { return 0 }
        time_elapsed = tick!.pointee.time_elapsed
    }

    // Create query iterator
    let thread_ctx: UnsafeMutableRawPointer
    if stage != nil {
        thread_ctx = stage!.pointee.thread_ctx ?? UnsafeMutableRawPointer(world)
    } else {
        thread_ctx = UnsafeMutableRawPointer(world)
    }

    var qit = ecs_query_iter(UnsafeRawPointer(thread_ctx), system_data.pointee.query)
    qit.system = system
    qit.delta_time = delta_time
    qit.delta_system_time = time_elapsed
    qit.param = param ?? system_data.pointee.ctx
    qit.ctx = system_data.pointee.ctx
    qit.callback_ctx = system_data.pointee.callback_ctx
    qit.run_ctx = system_data.pointee.run_ctx

    if system_data.pointee.group_id_set {
        ecs_query_set_group(&qit, system_data.pointee.group_id)
    }

    let old_system = flecs_stage_set_system(
        stage ?? world.pointee.stages![0]!, system)

    if system_data.pointee.run != nil {
        qit.callback = system_data.pointee.action
        qit.next = flecs_default_next_callback
        system_data.pointee.run!(&qit)
    } else if system_data.pointee.action != nil {
        qit.callback = system_data.pointee.action!
        while ecs_query_next(&qit) {
            system_data.pointee.action!(&qit)
        }
    }

    flecs_stage_set_system(stage ?? world.pointee.stages![0]!, old_system)

    return qit.interrupted_by
}

/// Run a system (public API).
public func ecs_run(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ system: ecs_entity_t,
    _ delta_time: ecs_ftime_t,
    _ param: UnsafeMutableRawPointer?) -> ecs_entity_t
{
    let system_data = flecs_poly_get_(
        UnsafePointer(world), system, EcsSystem)?.bindMemory(
        to: ecs_system_t.self, capacity: 1)
    if system_data == nil { return 0 }

    let stage = flecs_stage_from_world(world)
    flecs_defer_begin(world, stage)
    let result = flecs_run_system(
        world, stage, system, system_data!, 0, 0, delta_time, param)
    flecs_defer_end(world, stage)
    return result
}

/// Run a system on a specific worker stage.
public func ecs_run_worker(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ system: ecs_entity_t,
    _ stage_index: Int32,
    _ stage_count: Int32,
    _ delta_time: ecs_ftime_t,
    _ param: UnsafeMutableRawPointer?) -> ecs_entity_t
{
    let system_data = flecs_poly_get_(
        UnsafePointer(world), system, EcsSystem)?.bindMemory(
        to: ecs_system_t.self, capacity: 1)
    if system_data == nil { return 0 }

    let stage = flecs_stage_from_world(world)
    flecs_defer_begin(world, stage)
    let result = flecs_run_system(
        world, stage, system, system_data!, stage_index, stage_count,
        delta_time, param)
    flecs_defer_end(world, stage)
    return result
}


/// Create or update a system.
public func ecs_system_init(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ desc: UnsafePointer<ecs_system_desc_t>) -> ecs_entity_t
{
    var entity = desc.pointee.entity
    if entity == 0 {
        entity = ecs_new(world)
    }

    let poly = flecs_poly_bind_(world, entity, EcsSystem); if poly == nil { return 0 }

    if poly!.pointee.poly == nil {
        // New system
        guard desc.pointee.callback != nil || desc.pointee.run != nil else { return 0 }

        let system = ecs_os_calloc_t(ecs_system_t.self)!
        system.pointee = ecs_system_t()
        poly!.pointee.poly = UnsafeMutableRawPointer(system)

        // Create query
        var query_desc = desc.pointee.query
        query_desc.entity = entity
        let query = ecs_query_init(world, &query_desc); if query == nil {
            ecs_delete(world, entity)
            return 0
        }

        // Set phase
        if desc.pointee.phase != 0 {
            ecs_add_id(world, entity, desc.pointee.phase)
            ecs_add_pair(world, entity, EcsDependsOn, desc.pointee.phase)
        }

        system.pointee.entity = entity
        system.pointee.query = query!
        system.pointee.run = desc.pointee.run
        system.pointee.action = desc.pointee.callback
        system.pointee.ctx = desc.pointee.ctx
        system.pointee.callback_ctx = desc.pointee.callback_ctx
        system.pointee.run_ctx = desc.pointee.run_ctx
        system.pointee.ctx_free = desc.pointee.ctx_free
        system.pointee.callback_ctx_free = desc.pointee.callback_ctx_free
        system.pointee.run_ctx_free = desc.pointee.run_ctx_free
        system.pointee.tick_source = desc.pointee.tick_source
        system.pointee.multi_threaded = desc.pointee.multi_threaded
        system.pointee.immediate = desc.pointee.immediate
        system.pointee.name = ecs_get_path(UnsafePointer(world), entity)
        system.pointee.dtor = { ptr in
            if ptr == nil { return }
            let sys = ptr!.bindMemory(to: ecs_system_t.self, capacity: 1)
            flecs_system_fini(sys)
        }
    } else {
        // Update existing system
        let system = poly!.pointee.poly!.bindMemory(
            to: ecs_system_t.self, capacity: 1)

        if desc.pointee.run != nil { system.pointee.run = desc.pointee.run! }
        if desc.pointee.callback != nil { system.pointee.action = desc.pointee.callback! }
        if desc.pointee.ctx != nil { system.pointee.ctx = desc.pointee.ctx! }
        if desc.pointee.callback_ctx != nil { system.pointee.callback_ctx = desc.pointee.callback_ctx! }
        if desc.pointee.run_ctx != nil { system.pointee.run_ctx = desc.pointee.run_ctx! }
        if desc.pointee.ctx_free != nil { system.pointee.ctx_free = desc.pointee.ctx_free! }
        if desc.pointee.callback_ctx_free != nil { system.pointee.callback_ctx_free = desc.pointee.callback_ctx_free! }
        if desc.pointee.run_ctx_free != nil { system.pointee.run_ctx_free = desc.pointee.run_ctx_free! }
        if desc.pointee.multi_threaded { system.pointee.multi_threaded = true }
        if desc.pointee.immediate { system.pointee.immediate = true }
    }

    flecs_poly_modified_(world, entity, EcsSystem)
    return entity
}

/// Finalize a system, cleaning up resources.
private func flecs_system_fini(
    _ sys: UnsafeMutablePointer<ecs_system_t>)
{
    if sys.pointee.ctx_free != nil && sys.pointee.ctx != nil {
        sys.pointee.ctx_free!(sys.pointee.ctx!)
    }
    if sys.pointee.callback_ctx_free != nil && sys.pointee.callback_ctx != nil {
        sys.pointee.callback_ctx_free!(sys.pointee.callback_ctx!)
    }
    if sys.pointee.run_ctx_free != nil && sys.pointee.run_ctx != nil {
        sys.pointee.run_ctx_free!(sys.pointee.run_ctx!)
    }
    if sys.pointee.name != nil {
        ecs_os_free(UnsafeMutableRawPointer(mutating: sys.pointee.name!))
    }
    ecs_os_free(UnsafeMutableRawPointer(sys))
}

/// Get system data from an entity.
public func ecs_system_get(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t) -> UnsafePointer<ecs_system_t>?
{
    let poly = flecs_poly_get_(world, entity, EcsSystem); if poly == nil { return nil }
    return poly!.bindMemory(to: ecs_system_t.self, capacity: 1)
}

/// Set the group id for a system.
public func ecs_system_set_group(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ system: ecs_entity_t,
    _ group_id: UInt64)
{
    let system_data = flecs_poly_get_(
        UnsafePointer(world), system, EcsSystem)?.bindMemory(
        to: ecs_system_t.self, capacity: 1)
    if system_data == nil { return }
    system_data!.pointee.group_id = group_id
    system_data!.pointee.group_id_set = true
}


/// Import the System module.
public func FlecsSystemImport(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    ecs_set_name_prefix(world, "Ecs")
    // Would register EcsSystem tag, EcsTickSource component
    ecs_add_pair(world, EcsSystem, EcsOnInstantiate, EcsDontInherit)
}
