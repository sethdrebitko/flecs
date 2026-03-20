// World.swift - 1:1 translation of flecs world.c
// World creation, management, and destruction

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Create a new world
public func ecs_init() -> UnsafeMutablePointer<ecs_world_t> {
    ecs_os_set_api_defaults()

    let world = ecs_os_calloc_t(ecs_world_t.self)!
    world.pointee = ecs_world_t()

    // Set magic number
    world.pointee.hdr.type = ecs_world_t_magic
    world.pointee.self_ = world

    // Initialize allocators
    flecs_allocator_init(&world.pointee.allocator)

    // Initialize world allocators
    flecs_world_allocators_init(world)

    // Initialize entity index
    flecs_entity_index_init(
        &world.pointee.allocator,
        &world.pointee.store.entity_index)

    // Initialize maps
    ecs_map_init(&world.pointee.id_index_hi, &world.pointee.allocator)
    ecs_map_init(&world.pointee.type_info, &world.pointee.allocator)
    ecs_map_init(&world.pointee.prefab_child_indices, &world.pointee.allocator)

    // Initialize id_index_lo
    world.pointee.id_index_lo = ecs_os_calloc_n(UnsafeMutablePointer<ecs_component_record_t>?.self, FLECS_HI_ID_RECORD_ID)

    // Allocate fixed-size arrays
    world.pointee.table_version = ecs_os_calloc_n(UInt32.self, Int32(ECS_TABLE_VERSION_ARRAY_SIZE))

    world.pointee.non_trivial_lookup = ecs_os_calloc_n(ecs_flags8_t.self, FLECS_HI_COMPONENT_ID)

    world.pointee.non_trivial_set = ecs_os_calloc_n(ecs_flags8_t.self, FLECS_HI_COMPONENT_ID)

    // Initialize observable
    flecs_observable_init(&world.pointee.observable)

    // Initialize identifier hashmaps
    flecs_hashmap_init_(&world.pointee.aliases,
        ecs_size_t(MemoryLayout<ecs_hm_bucket_t>.stride),
        ecs_size_t(MemoryLayout<ecs_entity_t>.stride),
        ecs_size_t(MemoryLayout<ecs_entity_t>.stride),
        nil, nil, nil)

    flecs_hashmap_init_(&world.pointee.symbols,
        ecs_size_t(MemoryLayout<ecs_hm_bucket_t>.stride),
        ecs_size_t(MemoryLayout<ecs_entity_t>.stride),
        ecs_size_t(MemoryLayout<ecs_entity_t>.stride),
        nil, nil, nil)

    // Initialize sparse set for tables
    let tableSize = ecs_size_t(MemoryLayout<ecs_table_t>.stride)
    flecs_sparse_init(&world.pointee.store.tables, nil,
                      &world.pointee.allocator, tableSize)

    // Initialize stage
    world.pointee.stage_count = 1
    world.pointee.stages = ecs_os_calloc_t(UnsafeMutablePointer<ecs_stage_t>?.self)!
    let stage = ecs_os_calloc_t(ecs_stage_t.self)!
    stage.pointee = ecs_stage_t()
    stage.pointee.hdr.type = ecs_stage_t_magic
    stage.pointee.id = 0
    stage.pointee.world = world
    stage.pointee.thread_ctx = UnsafeMutableRawPointer(world)
        .assumingMemoryBound(to: ecs_world_t.self)

    // Initialize stage allocators
    flecs_allocator_init(&stage.pointee.allocator)
    flecs_stack_init(&stage.pointee.allocators.iter_stack)

    // Initialize command stacks
    flecs_commands_init_stage(stage)

    world.pointee.stages![0] = stage

    // Initialize root table
    world.pointee.store.root = ecs_table_t()

    // Initialize info
    world.pointee.info.time_scale = 1.0

    // Set world as initialized
    world.pointee.flags = EcsWorldInit

    // Initialize vecs
    let actionSize = ecs_size_t(MemoryLayout<ecs_action_elem_t>.stride)
    ecs_vec_init(nil, &world.pointee.fini_actions, actionSize, 0)

    let compIdSize = ecs_size_t(MemoryLayout<ecs_entity_t>.stride)
    ecs_vec_init(nil, &world.pointee.component_ids, compIdSize, 0)

    // Initialize component monitors
    ecs_map_init(&world.pointee.monitors.monitors, &world.pointee.allocator)

    return world
}

/// Helper to init command stacks on a stage
private func flecs_commands_init_stage(
    _ stage: UnsafeMutablePointer<ecs_stage_t>
) {
    stage.pointee.cmd_stack.0 = ecs_commands_t()
    stage.pointee.cmd_stack.1 = ecs_commands_t()

    let cmdSize = ecs_size_t(MemoryLayout<UInt8>.stride) // placeholder cmd element size
    ecs_vec_init(nil, &stage.pointee.cmd_stack.0.queue, cmdSize, 0)
    ecs_vec_init(nil, &stage.pointee.cmd_stack.1.queue, cmdSize, 0)

    stage.pointee.cmd = withUnsafeMutablePointer(to: &stage.pointee.cmd_stack.0) { $0 }
}

/// Helper to init world-level block allocators
private func flecs_world_allocators_init(
    _ world: UnsafeMutablePointer<ecs_world_t>
) {
    let a = &world.pointee.allocators

    let edgeLoSize = ecs_size_t(16) // Simplified sizes
    let edgeSize = ecs_size_t(MemoryLayout<ecs_graph_edge_t>.stride)
    let crSize = ecs_size_t(MemoryLayout<ecs_component_record_t>.stride)
    let prSize = ecs_size_t(MemoryLayout<ecs_pair_record_t>.stride)
    let diffSize = ecs_size_t(MemoryLayout<ecs_table_diff_t>.stride)

    flecs_ballocator_init(&a.pointee.graph_edge_lo, edgeLoSize)
    flecs_ballocator_init(&a.pointee.graph_edge, edgeSize)
    flecs_ballocator_init(&a.pointee.component_record, crSize)
    flecs_ballocator_init(&a.pointee.pair_record, prSize)
    flecs_ballocator_init(&a.pointee.table_diff, diffSize)
    flecs_ballocator_init(&a.pointee.sparse_chunk, 64) // Simplified

    // Init diff builder vecs
    let idSize = ecs_size_t(MemoryLayout<ecs_id_t>.stride)
    ecs_vec_init(nil, &a.pointee.diff_builder.added, idSize, 0)
    ecs_vec_init(nil, &a.pointee.diff_builder.removed, idSize, 0)
}


/// Destroy the world and free all resources
public func ecs_fini(
    _ world: UnsafeMutablePointer<ecs_world_t>
) {
    world.pointee.flags |= EcsWorldQuit | EcsWorldFini

    // Run fini actions
    let actionSize = ecs_size_t(MemoryLayout<ecs_action_elem_t>.stride)
    let actionCount = ecs_vec_count(&world.pointee.fini_actions)
    if actionCount > 0 {
        let actions = ecs_vec_first(&world.pointee.fini_actions)!
            .assumingMemoryBound(to: ecs_action_elem_t.self)
        for i in 0..<Int(actionCount) {
            actions[i].action?(UnsafeMutableRawPointer(world), actions[i].ctx)
        }
    }
    ecs_vec_fini(nil, &world.pointee.fini_actions, actionSize)

    // Clean up stages
    if world.pointee.stages != nil {
        for i in 0..<Int(world.pointee.stage_count) {
            if world.pointee.stages![i] != nil {
                flecs_stage_fini(world.pointee.stages![i]!)
                ecs_os_free(UnsafeMutableRawPointer(world.pointee.stages![i]!))
            }
        }
        ecs_os_free(UnsafeMutableRawPointer(world.pointee.stages!))
    }

    // Free observable
    flecs_observable_fini(&world.pointee.observable)

    // Free entity index
    flecs_entity_index_fini(&world.pointee.store.entity_index)

    // Free maps
    ecs_map_fini(&world.pointee.id_index_hi)
    ecs_map_fini(&world.pointee.type_info)
    ecs_map_fini(&world.pointee.prefab_child_indices)
    ecs_map_fini(&world.pointee.monitors.monitors)

    // Free sparse tables
    flecs_sparse_fini(&world.pointee.store.tables)

    // Free id_index_lo
    if world.pointee.id_index_lo != nil {
        // Free individual component records
        for i in 0..<Int(FLECS_HI_ID_RECORD_ID) {
            if world.pointee.id_index_lo![i] != nil {
                ecs_os_free(UnsafeMutableRawPointer(world.pointee.id_index_lo![i]!))
            }
        }
        world.pointee.id_index_lo!.deinitialize(count: Int(FLECS_HI_ID_RECORD_ID))
        ecs_os_free(UnsafeMutableRawPointer(world.pointee.id_index_lo!))
    }

    // Free fixed arrays
    if world.pointee.table_version != nil {
        world.pointee.table_version!.deinitialize(count: ECS_TABLE_VERSION_ARRAY_SIZE)
        ecs_os_free(UnsafeMutableRawPointer(world.pointee.table_version!))
    }
    if world.pointee.non_trivial_lookup != nil {
        world.pointee.non_trivial_lookup!.deinitialize(count: Int(FLECS_HI_COMPONENT_ID))
        ecs_os_free(UnsafeMutableRawPointer(world.pointee.non_trivial_lookup!))
    }
    if world.pointee.non_trivial_set != nil {
        world.pointee.non_trivial_set!.deinitialize(count: Int(FLECS_HI_COMPONENT_ID))
        ecs_os_free(UnsafeMutableRawPointer(world.pointee.non_trivial_set!))
    }

    // Free hashmaps
    flecs_hashmap_fini(&world.pointee.aliases)
    flecs_hashmap_fini(&world.pointee.symbols)

    // Free world allocators
    flecs_world_allocators_fini(world)

    // Free component ids vec
    let compIdSize = ecs_size_t(MemoryLayout<ecs_entity_t>.stride)
    ecs_vec_fini(nil, &world.pointee.component_ids, compIdSize)

    // Free general allocator
    flecs_allocator_fini(&world.pointee.allocator)

    // Free context
    if world.pointee.ctx_free != nil && world.pointee.ctx != nil {
        world.pointee.ctx_free!(world.pointee.ctx!)
    }
    if world.pointee.binding_ctx_free != nil && world.pointee.binding_ctx != nil {
        world.pointee.binding_ctx_free!(world.pointee.binding_ctx!)
    }

    ecs_os_free(UnsafeMutableRawPointer(world))
}

private func flecs_stage_fini(
    _ stage: UnsafeMutablePointer<ecs_stage_t>
) {
    let cmdSize = ecs_size_t(MemoryLayout<UInt8>.stride)
    ecs_vec_fini(nil, &stage.pointee.cmd_stack.0.queue, cmdSize)
    ecs_vec_fini(nil, &stage.pointee.cmd_stack.1.queue, cmdSize)

    flecs_stack_fini(&stage.pointee.allocators.iter_stack)
    flecs_allocator_fini(&stage.pointee.allocator)
}

private func flecs_world_allocators_fini(
    _ world: UnsafeMutablePointer<ecs_world_t>
) {
    let a = &world.pointee.allocators

    flecs_ballocator_fini(&a.pointee.graph_edge_lo)
    flecs_ballocator_fini(&a.pointee.graph_edge)
    flecs_ballocator_fini(&a.pointee.component_record)
    flecs_ballocator_fini(&a.pointee.pair_record)
    flecs_ballocator_fini(&a.pointee.table_diff)
    flecs_ballocator_fini(&a.pointee.sparse_chunk)

    let idSize = ecs_size_t(MemoryLayout<ecs_id_t>.stride)
    ecs_vec_fini(nil, &a.pointee.diff_builder.added, idSize)
    ecs_vec_fini(nil, &a.pointee.diff_builder.removed, idSize)
}


/// Check if world is valid
public func ecs_is_fini(
    _ world: UnsafePointer<ecs_world_t>
) -> Bool {
    return (world.pointee.flags & EcsWorldFini) != 0
}

/// Get the world info struct
public func ecs_get_world_info(
    _ world: UnsafePointer<ecs_world_t>
) -> UnsafePointer<ecs_world_info_t> {
    return withUnsafePointer(to: &UnsafeMutablePointer(mutating: world).pointee.info) { $0 }
}

/// Set a world context
public func ecs_set_ctx(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ ctx: UnsafeMutableRawPointer?,
    _ ctx_free: ecs_ctx_free_t?
) {
    world.pointee.ctx = ctx
    world.pointee.ctx_free = ctx_free
}

/// Get the world context
public func ecs_get_ctx(
    _ world: UnsafePointer<ecs_world_t>
) -> UnsafeMutableRawPointer? {
    return UnsafeMutablePointer(mutating: world).pointee.ctx
}

/// Set the world's target FPS
public func ecs_set_target_fps(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ fps: ecs_ftime_t
) {
    world.pointee.info.target_fps = fps
}

/// Enable/disable range checking
public func ecs_enable_range_check(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ enable: Bool
) -> Bool {
    let old = world.pointee.range_check_enabled
    world.pointee.range_check_enabled = enable
    return old
}

/// Begin a frame
public func ecs_frame_begin(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ delta_time: ecs_ftime_t
) -> ecs_ftime_t {
    world.pointee.info.frame_count_total += 1

    var dt = delta_time
    if dt == 0 {
        // TODO: Calculate delta from real time
        dt = 1.0 / 60.0
    }

    world.pointee.info.delta_time_raw = dt
    world.pointee.info.delta_time = dt * world.pointee.info.time_scale

    world.pointee.flags |= EcsWorldFrameInProgress

    return world.pointee.info.delta_time
}

/// End a frame
public func ecs_frame_end(
    _ world: UnsafeMutablePointer<ecs_world_t>
) {
    world.pointee.info.world_time_total_raw += Double(world.pointee.info.delta_time_raw)
    world.pointee.info.world_time_total += Double(world.pointee.info.delta_time)
    world.pointee.flags &= ~EcsWorldFrameInProgress
}

/// Begin readonly mode
public func ecs_readonly_begin(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ multi_threaded: Bool
) -> Bool {
    world.pointee.flags |= EcsWorldReadonly
    if multi_threaded {
        world.pointee.flags |= EcsWorldMultiThreaded
    }
    return true
}

/// End readonly mode
public func ecs_readonly_end(
    _ world: UnsafeMutablePointer<ecs_world_t>
) {
    world.pointee.flags &= ~(EcsWorldReadonly | EcsWorldMultiThreaded)

    // Merge stages
    // TODO: Implement command queue merge
}

/// Defer begin
public func ecs_defer_begin(
    _ world: UnsafeMutableRawPointer?
) -> Bool {
    if world == nil { return false }
    let w = world!.assumingMemoryBound(to: ecs_world_t.self)

    if w.pointee.stages == nil || w.pointee.stages![0] == nil { return false }
    let stage = w.pointee.stages![0]!

    stage.pointee.defer += 1
    return stage.pointee.defer > 1
}

/// Defer end
public func ecs_defer_end(
    _ world: UnsafeMutableRawPointer?
) -> Bool {
    if world == nil { return false }
    let w = world!.assumingMemoryBound(to: ecs_world_t.self)

    if w.pointee.stages == nil || w.pointee.stages![0] == nil { return false }
    let stage = w.pointee.stages![0]!

    stage.pointee.defer -= 1

    if stage.pointee.defer == 0 {
        // TODO: Flush command queue
        return true
    }

    return false
}

/// Register a fini action
public func ecs_atfini(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ action: ecs_fini_action_t?,
    _ ctx: UnsafeMutableRawPointer?
) {
    let actionSize = ecs_size_t(MemoryLayout<ecs_action_elem_t>.stride)
    let ptr = ecs_vec_append(nil, &world.pointee.fini_actions, actionSize)!
        .assumingMemoryBound(to: ecs_action_elem_t.self)
    ptr.pointee.action = action
    ptr.pointee.ctx = ctx
}

/// Get the scope of the world
public func ecs_get_scope(
    _ world: UnsafeRawPointer?
) -> ecs_entity_t {
    if world == nil { return 0 }
    let w = world!.assumingMemoryBound(to: ecs_world_t.self)
    if w.pointee.stages == nil || w.pointee.stages![0] == nil { return 0 }
    return w.pointee.stages![0]!.pointee.scope
}

/// Set the scope of the world
public func ecs_set_scope(
    _ world: UnsafeMutableRawPointer?,
    _ scope: ecs_entity_t
) -> ecs_entity_t {
    if world == nil { return 0 }
    let w = world!.assumingMemoryBound(to: ecs_world_t.self)
    if w.pointee.stages == nil || w.pointee.stages![0] == nil { return 0 }
    let stage = w.pointee.stages![0]!
    let old = stage.pointee.scope
    stage.pointee.scope = scope
    return old
}

/// Get entity count
public func ecs_count(
    _ world: UnsafePointer<ecs_world_t>
) -> Int32 {
    return flecs_entity_index_count(&world.pointee.store.entity_index)
}


/// Validate that a poly object has the correct type
public func ecs_poly_is(
    _ poly: UnsafeRawPointer?,
    _ type: Int32
) -> Bool {
    if poly == nil { return false }
    let hdr = poly!.assumingMemoryBound(to: ecs_header_t.self)
    return hdr.pointee.type == type
}
