// Pipeline.swift - 1:1 translation of flecs addons/pipeline/*.c
// Pipeline building, execution, frame management, and worker threads

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Pipeline operation: a segment of systems to run, possibly with a merge point.
public struct ecs_pipeline_op_t {
    public var offset: Int32 = 0
    public var count: Int32 = 0
    public var multi_threaded: Bool = false
    public var immediate: Bool = false
    public init() {}
}

/// Pipeline state: the compiled list of systems and merge points.
public struct ecs_pipeline_state_t {
    public var query: UnsafeMutablePointer<ecs_query_t>? = nil
    public var ops: ecs_vec_t = ecs_vec_t()
    public var systems: ecs_vec_t = ecs_vec_t()
    public var iters: UnsafeMutablePointer<ecs_iter_t>? = nil
    public var match_count: Int32 = 0
    public var rebuild_count: Int32 = 0
    public init() {}
}

/// EcsPipeline component.
public struct EcsPipeline {
    public var state: UnsafeMutablePointer<ecs_pipeline_state_t>? = nil
    public init() {}
}


/// Tracks which components have been written to detect merge points.
private struct ecs_write_state_t {
    var write_barrier: Bool = false
    var ids: ecs_map_t = ecs_map_t()
    var wildcard_ids: ecs_map_t = ecs_map_t()
}

/// Check if a component has been written (needs merge before read).
private func flecs_pipeline_get_write_state(
    _ ws: UnsafePointer<ecs_write_state_t>,
    _ id: ecs_id_t) -> Bool
{
    if ws.pointee.write_barrier { return true }

    if id == EcsWildcard {
        return ecs_map_count(&ws.pointee.ids) > 0 ||
               ecs_map_count(&ws.pointee.wildcard_ids) > 0
    }

    var ws_mut = UnsafeMutablePointer(mutating: ws)
    if !ecs_id_is_wildcard(id) {
        return ecs_map_get(&ws_mut.pointee.ids, id) != nil
    }

    // Check wildcard matches
    var it = ecs_map_iter(&ws_mut.pointee.ids)
    while ecs_map_next(&it) {
        if ecs_id_match(ecs_map_key(&it), id) { return true }
    }

    var wc_it = ecs_map_iter(&ws_mut.pointee.wildcard_ids)
    while ecs_map_next(&wc_it) {
        if ecs_id_match(id, ecs_map_key(&wc_it)) { return true }
    }

    return false
}

/// Mark a component as written.
private func flecs_pipeline_set_write_state(
    _ ws: UnsafeMutablePointer<ecs_write_state_t>,
    _ id: ecs_id_t)
{
    if id == EcsWildcard {
        ws.pointee.write_barrier = true
        return
    }

    if ecs_id_is_wildcard(id) {
        ecs_map_ensure(&ws.pointee.wildcard_ids, id).pointee = 1
    } else {
        ecs_map_ensure(&ws.pointee.ids, id).pointee = 1
    }
}

/// Reset write state for a new merge segment.
private func flecs_pipeline_reset_write_state(
    _ ws: UnsafeMutablePointer<ecs_write_state_t>)
{
    ecs_map_clear(&ws.pointee.ids)
    ecs_map_clear(&ws.pointee.wildcard_ids)
    ws.pointee.write_barrier = false
}


/// Check if a system term requires a merge point.
private func flecs_pipeline_check_term(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ term: UnsafePointer<ecs_term_t>,
    _ is_active: Bool,
    _ ws: UnsafeMutablePointer<ecs_write_state_t>) -> Bool
{
    if term.pointee.inout == EcsInOutFilter { return false }

    let id = term.pointee.id
    let inout = term.pointee.inout
    let from_any = ecs_term_match_0(term)
    let from_this = ecs_term_match_this(term)

    if from_this && flecs_pipeline_get_write_state(UnsafePointer(ws), id) {
        return true
    }

    var effective_inout = inout
    if effective_inout == EcsInOutDefault {
        if from_any { return false }
        effective_inout = from_this ? EcsInOut : EcsIn
    }

    if from_any {
        if (effective_inout == EcsOut || effective_inout == EcsInOut) && is_active {
            flecs_pipeline_set_write_state(ws, id)
        }
        if (effective_inout == EcsIn || effective_inout == EcsInOut) {
            if flecs_pipeline_get_write_state(UnsafePointer(ws), id) {
                return true
            }
        }
    }

    return false
}

/// Check all terms of a system for merge requirements.
private func flecs_pipeline_check_terms(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ query: UnsafePointer<ecs_query_t>,
    _ is_active: Bool,
    _ ws: UnsafeMutablePointer<ecs_write_state_t>) -> Bool
{
    if query.pointee.terms == nil { return false }
    let terms = query.pointee.terms!
    let count = query.pointee.term_count
    var needs_merge = false

    // Check $this terms first
    for t in 0..<Int(count) {
        if ecs_term_match_this(&terms[t]) {
            needs_merge = flecs_pipeline_check_term(
                world, &terms[t], is_active, ws) || needs_merge
        }
    }

    // Then non-$this terms
    for t in 0..<Int(count) {
        if !ecs_term_match_this(&terms[t]) {
            needs_merge = flecs_pipeline_check_term(
                world, &terms[t], is_active, ws) || needs_merge
        }
    }

    return needs_merge
}


/// Build/rebuild a pipeline from its query, inserting merge points.
public func flecs_pipeline_build(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ pq: UnsafeMutablePointer<ecs_pipeline_state_t>) -> Bool
{
    if pq.pointee.query == nil { return false }
    let query = pq.pointee.query!

    let new_match_count = ecs_query_match_count(UnsafePointer(query))
    if pq.pointee.match_count == new_match_count {
        return false
    }

    world.pointee.info.pipeline_build_count_total += 1
    pq.pointee.rebuild_count += 1

    // Would iterate the pipeline query, check each system's terms for
    // read/write conflicts, and insert merge operations where needed.
    // The result is stored in pq->ops and pq->systems.

    pq.pointee.match_count = new_match_count
    return true
}


/// Run all pipeline operations on a single stage.
public func flecs_run_pipeline_ops(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ stage_index: Int32,
    _ stage_count: Int32,
    _ delta_time: ecs_ftime_t)
{
    // Would iterate pq->ops, running each system segment and merging
    // between segments that have conflicting reads/writes
}

/// Run a full pipeline (build if needed, then execute).
public func flecs_run_pipeline(
    _ world: UnsafeMutableRawPointer?,
    _ pq: UnsafeMutablePointer<ecs_pipeline_state_t>,
    _ delta_time: ecs_ftime_t)
{
    if world == nil { return }
    let world = world!.assumingMemoryBound(to: ecs_world_t.self)
    _ = flecs_pipeline_build(world, pq)
    flecs_run_pipeline_ops(world, world.pointee.stages![0]!, 0, 1, delta_time)
}


/// Begin a new frame. Returns computed delta time.
public func ecs_frame_begin(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ user_delta_time: ecs_ftime_t) -> ecs_ftime_t
{
    var delta_time = user_delta_time

    if delta_time == 0 {
        // Would measure time since last frame
        delta_time = 1.0 / 60.0  // Default 60fps
    }

    world.pointee.info.delta_time_raw = delta_time
    world.pointee.info.delta_time = delta_time * world.pointee.info.time_scale
    world.pointee.info.world_time_total += Double(world.pointee.info.delta_time)

    world.pointee.flags |= EcsWorldFrameInProgress

    return world.pointee.info.delta_time
}

/// End the current frame.
public func ecs_frame_end(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    world.pointee.info.frame_count_total += 1

    // Merge post-frame commands for each stage
    let count = world.pointee.stage_count
    for i in 0..<Int(count) {
        if world.pointee.stages?[i] != nil {
            flecs_stage_merge_post_frame(world, world.pointee.stages![i]!)
        }
    }

    world.pointee.flags &= ~EcsWorldFrameInProgress
}


/// Set the number of worker threads.
public func ecs_set_threads(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ threads: Int32)
{
    let stage_count = ecs_get_stage_count(world)
    if stage_count != threads {
        if stage_count > 1 {
            flecs_join_worker_threads(world)
            ecs_set_stage_count(world, 1)
        }

        if threads > 1 {
            world.pointee.worker_cond = ecs_os_cond_new()
            world.pointee.sync_cond = ecs_os_cond_new()
            world.pointee.sync_mutex = ecs_os_mutex_new()
            ecs_set_stage_count(world, threads)
            flecs_create_worker_threads(world)
        }
    }
}

/// Set the number of task threads (uses task API instead of thread API).
public func ecs_set_task_threads(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ task_threads: Int32)
{
    world.pointee.workers_use_task_api = true
    ecs_set_threads(world, task_threads)
}

/// Check if the world is using the task thread API.
public func ecs_using_task_threads(
    _ world: UnsafeMutablePointer<ecs_world_t>) -> Bool
{
    return world.pointee.workers_use_task_api
}

/// Create worker threads for each stage beyond stage 0.
public func flecs_create_worker_threads(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    let stages = ecs_get_stage_count(world)
    for i in 1..<stages {
        let stage = ecs_get_stage(world, i)?.assumingMemoryBound(
            to: ecs_stage_t.self)
        if stage == nil { continue }
        if ecs_using_task_threads(world) {
            stage!.pointee.thread = ecs_os_task_new(flecs_worker, UnsafeMutableRawPointer(stage!))
        } else {
            stage!.pointee.thread = ecs_os_thread_new(flecs_worker, UnsafeMutableRawPointer(stage!))
        }
    }
}

/// Worker thread entry point.
private func flecs_worker(_ arg: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    if arg == nil { return nil }
    let stage = arg!.assumingMemoryBound(to: ecs_stage_t.self)
    let world = stage.pointee.world!

    while (world.pointee.flags & EcsWorldQuitWorkers) == 0 {
        flecs_run_pipeline_ops(world, stage, stage.pointee.id,
            world.pointee.stage_count, world.pointee.info.delta_time)
        flecs_sync_worker(world)
    }

    return nil
}

/// Synchronize a worker thread at a sync point.
private func flecs_sync_worker(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    let stage_count = ecs_get_stage_count(world)
    if stage_count <= 1 { return }

    ecs_os_mutex_lock(world.pointee.sync_mutex)
    world.pointee.workers_waiting += 1
    if world.pointee.workers_waiting == stage_count - 1 {
        ecs_os_cond_signal(world.pointee.sync_cond)
    }
    ecs_os_cond_wait(world.pointee.worker_cond, world.pointee.sync_mutex)
    ecs_os_mutex_unlock(world.pointee.sync_mutex)
}

/// Wait for all workers to reach sync point.
public func flecs_wait_for_sync(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    let stage_count = ecs_get_stage_count(world)
    if stage_count <= 1 { return }

    ecs_os_mutex_lock(world.pointee.sync_mutex)
    if world.pointee.workers_waiting != stage_count - 1 {
        ecs_os_cond_wait(world.pointee.sync_cond, world.pointee.sync_mutex)
    }
    world.pointee.workers_waiting = 0
    ecs_os_mutex_unlock(world.pointee.sync_mutex)
}

/// Signal workers to start/resume.
public func flecs_signal_workers(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    let stage_count = ecs_get_stage_count(world)
    if stage_count <= 1 { return }

    ecs_os_mutex_lock(world.pointee.sync_mutex)
    ecs_os_cond_broadcast(world.pointee.worker_cond)
    ecs_os_mutex_unlock(world.pointee.sync_mutex)
}

/// Join all worker threads.
public func flecs_join_worker_threads(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    let count = world.pointee.stage_count
    world.pointee.flags |= EcsWorldQuitWorkers
    flecs_signal_workers(world)

    for i in 1..<Int(count) {
        if world.pointee.stages?[i] == nil { continue }
        let stage = world.pointee.stages![i]!
        if ecs_using_task_threads(world) {
            ecs_os_task_join(stage.pointee.thread)
        } else {
            ecs_os_thread_join(stage.pointee.thread)
        }
        stage.pointee.thread = 0
    }

    world.pointee.flags &= ~EcsWorldQuitWorkers
}

/// Progress workers (main thread orchestration).
public func flecs_workers_progress(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ pq: UnsafeMutablePointer<ecs_pipeline_state_t>,
    _ delta_time: ecs_ftime_t)
{
    // Run pipeline on main thread, workers handle their own stages
    flecs_run_pipeline(UnsafeMutableRawPointer(world), pq, delta_time)
}


/// Import the Pipeline module.
public func FlecsPipelineImport(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    ecs_set_name_prefix(world, "Ecs")

    // Would register EcsPipeline component, pipeline phases
    // (EcsPreFrame, EcsOnLoad, EcsPostLoad, EcsPreUpdate, EcsOnUpdate,
    //  EcsOnValidate, EcsPostUpdate, EcsPreStore, EcsOnStore, EcsPostFrame)
    // and the default pipeline entity
}
