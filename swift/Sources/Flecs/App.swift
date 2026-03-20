// App.swift - 1:1 translation of flecs addons/app.c
// Application runner with configurable run/frame actions

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Application descriptor.
public struct ecs_app_desc_t {
    public var target_fps: ecs_ftime_t = 0
    public var delta_time: ecs_ftime_t = 0
    public var threads: Int32 = 0
    public var frames: Int32 = 0
    public var enable_rest: Bool = false
    public var enable_stats: Bool = false
    public var port: UInt16 = 0
    public var init: (@convention(c) (UnsafeMutablePointer<ecs_world_t>) -> Void)? = nil
    public init() {}
}

/// Run action: controls the main loop.
public typealias ecs_app_run_action_t =
    @convention(c) (UnsafeMutablePointer<ecs_world_t>, UnsafeMutablePointer<ecs_app_desc_t>) -> Int32

/// Frame action: controls what happens each frame.
public typealias ecs_app_frame_action_t =
    @convention(c) (UnsafeMutablePointer<ecs_world_t>, UnsafePointer<ecs_app_desc_t>) -> Int32


/// Default run action: loop calling frame action until quit.
private func flecs_default_run_action(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ desc: UnsafeMutablePointer<ecs_app_desc_t>) -> Int32
{
    if desc.pointee.`init` != nil {
        desc.pointee.`init`!(world)
    }

    var result: Int32 = 0
    if desc.pointee.frames > 0 {
        for _ in 0..<desc.pointee.frames {
            result = ecs_app_run_frame(world, UnsafePointer(desc))
            if result != 0 { break }
        }
    } else {
        repeat {
            result = ecs_app_run_frame(world, UnsafePointer(desc))
        } while result == 0
    }

    ecs_quit(world)
    return result == 1 ? 0 : result
}

/// Default frame action: call ecs_progress.
private func flecs_default_frame_action(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ desc: UnsafePointer<ecs_app_desc_t>) -> Int32
{
    return ecs_progress(world, desc.pointee.delta_time) ? 0 : 1
}


private var run_action: ecs_app_run_action_t = flecs_default_run_action
private var frame_action: ecs_app_frame_action_t = flecs_default_frame_action


/// Run the application with the given descriptor.
public func ecs_app_run(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ desc: UnsafeMutablePointer<ecs_app_desc_t>) -> Int32
{
    if desc.pointee.target_fps != 0 {
        ecs_set_target_fps(world, desc.pointee.target_fps)
    }
    if desc.pointee.threads > 0 {
        ecs_set_threads(world, desc.pointee.threads)
    }

    return run_action(world, desc)
}

/// Run a single frame.
public func ecs_app_run_frame(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ desc: UnsafePointer<ecs_app_desc_t>) -> Int32
{
    return frame_action(world, desc)
}

/// Override the default run action.
public func ecs_app_set_run_action(
    _ callback: @escaping ecs_app_run_action_t) -> Int32
{
    run_action = callback
    return 0
}

/// Override the default frame action.
public func ecs_app_set_frame_action(
    _ callback: @escaping ecs_app_frame_action_t) -> Int32
{
    frame_action = callback
    return 0
}
