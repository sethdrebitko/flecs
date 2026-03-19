// World.swift - 1:1 translation of flecs world.c
// World creation, management, and destruction

import Foundation

// MARK: - World Creation

/// Create a new world
public func ecs_init() -> UnsafeMutablePointer<ecs_world_t> {
    ecs_os_set_api_defaults()

    let world = UnsafeMutablePointer<ecs_world_t>.allocate(capacity: 1)
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
    world.pointee.id_index_lo = UnsafeMutablePointer<UnsafeMutablePointer<ecs_component_record_t>?>
        .allocate(capacity: Int(FLECS_HI_ID_RECORD_ID))
    world.pointee.id_index_lo!.initialize(repeating: nil, count: Int(FLECS_HI_ID_RECORD_ID))

    // Allocate fixed-size arrays
    world.pointee.table_version = UnsafeMutablePointer<UInt32>.allocate(capacity: ECS_TABLE_VERSION_ARRAY_SIZE)
    world.pointee.table_version!.initialize(repeating: 0, count: ECS_TABLE_VERSION_ARRAY_SIZE)

    world.pointee.non_trivial_lookup = UnsafeMutablePointer<ecs_flags8_t>.allocate(capacity: Int(FLECS_HI_COMPONENT_ID))
    world.pointee.non_trivial_lookup!.initialize(repeating: 0, count: Int(FLECS_HI_COMPONENT_ID))

    world.pointee.non_trivial_set = UnsafeMutablePointer<ecs_flags8_t>.allocate(capacity: Int(FLECS_HI_COMPONENT_ID))
    world.pointee.non_trivial_set!.initialize(repeating: 0, count: Int(FLECS_HI_COMPONENT_ID))

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
    world.pointee.stages = UnsafeMutablePointer<UnsafeMutablePointer<ecs_stage_t>?>
        .allocate(capacity: 1)
    let stage = UnsafeMutablePointer<ecs_stage_t>.allocate(capacity: 1)
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

// MARK: - World Destruction

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
    if let stages = world.pointee.stages {
        for i in 0..<Int(world.pointee.stage_count) {
            if let stage = stages[i] {
                flecs_stage_fini(stage)
                stage.deallocate()
            }
        }
        stages.deallocate()
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
    if let lo = world.pointee.id_index_lo {
        // Free individual component records
        for i in 0..<Int(FLECS_HI_ID_RECORD_ID) {
            if let cr = lo[i] {
                cr.deallocate()
            }
        }
        lo.deinitialize(count: Int(FLECS_HI_ID_RECORD_ID))
        lo.deallocate()
    }

    // Free fixed arrays
    if let tv = world.pointee.table_version {
        tv.deinitialize(count: ECS_TABLE_VERSION_ARRAY_SIZE)
        tv.deallocate()
    }
    if let ntl = world.pointee.non_trivial_lookup {
        ntl.deinitialize(count: Int(FLECS_HI_COMPONENT_ID))
        ntl.deallocate()
    }
    if let nts = world.pointee.non_trivial_set {
        nts.deinitialize(count: Int(FLECS_HI_COMPONENT_ID))
        nts.deallocate()
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
    if let ctx_free = world.pointee.ctx_free, let ctx = world.pointee.ctx {
        ctx_free(ctx)
    }
    if let binding_ctx_free = world.pointee.binding_ctx_free, let ctx = world.pointee.binding_ctx {
        binding_ctx_free(ctx)
    }

    world.deallocate()
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

// MARK: - World API

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
    guard let world = world else { return false }
    let w = world.assumingMemoryBound(to: ecs_world_t.self)

    guard let stages = w.pointee.stages, let stage = stages[0] else { return false }

    stage.pointee.defer += 1
    return stage.pointee.defer > 1
}

/// Defer end
public func ecs_defer_end(
    _ world: UnsafeMutableRawPointer?
) -> Bool {
    guard let world = world else { return false }
    let w = world.assumingMemoryBound(to: ecs_world_t.self)

    guard let stages = w.pointee.stages, let stage = stages[0] else { return false }

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
    guard let world = world else { return 0 }
    let w = world.assumingMemoryBound(to: ecs_world_t.self)
    guard let stages = w.pointee.stages, let stage = stages[0] else { return 0 }
    return stage.pointee.scope
}

/// Set the scope of the world
public func ecs_set_scope(
    _ world: UnsafeMutableRawPointer?,
    _ scope: ecs_entity_t
) -> ecs_entity_t {
    guard let world = world else { return 0 }
    let w = world.assumingMemoryBound(to: ecs_world_t.self)
    guard let stages = w.pointee.stages, let stage = stages[0] else { return 0 }
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

// MARK: - Poly helpers

/// Validate that a poly object has the correct type
public func ecs_poly_is(
    _ poly: UnsafeRawPointer?,
    _ type: Int32
) -> Bool {
    guard let poly = poly else { return false }
    let hdr = poly.assumingMemoryBound(to: ecs_header_t.self)
    return hdr.pointee.type == type
}
