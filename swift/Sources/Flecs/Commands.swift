/// Commands.swift
/// Translation of commands.h/commands.c from flecs.
/// Command queue implementation for deferred operations.

import Foundation

// MARK: - Command Kind Enum

/// Types for deferred operations.
public enum ecs_cmd_kind_t: Int32 {
    case EcsCmdClone = 0
    case EcsCmdBulkNew
    case EcsCmdAdd
    case EcsCmdRemove
    case EcsCmdSet
    case EcsCmdSetDontFragment
    case EcsCmdEmplace
    case EcsCmdEnsure
    case EcsCmdModified
    case EcsCmdModifiedNoHook
    case EcsCmdAddModified
    case EcsCmdPath
    case EcsCmdDelete
    case EcsCmdClear
    case EcsCmdOnDeleteAction
    case EcsCmdEnable
    case EcsCmdDisable
    case EcsCmdEvent
    case EcsCmdSkip
}

// MARK: - Command Structs

/// Entity-specific metadata for a command in the queue.
public struct ecs_cmd_entry_t {
    public var first: Int32 = 0
    public var last: Int32 = 0              // If -1, a delete command was inserted
    public init() {}
}

/// Data for a single-entity command operation.
public struct ecs_cmd_1_t {
    public var value: UnsafeMutableRawPointer? = nil  // Component value (used by set / ensure)
    public var size: ecs_size_t = 0                   // Size of value
    public var clone_value: Bool = false               // Clone entity with value (used for clone)
    public init() {}
}

/// Data for a multi-entity command operation.
public struct ecs_cmd_n_t {
    public var entities: UnsafeMutablePointer<ecs_entity_t>? = nil
    public var count: Int32 = 0
    public init() {}
}

/// Union replacement for command data (single or multi entity).
/// In C this is `union { ecs_cmd_1_t _1; ecs_cmd_n_t _n; }`.
/// We use an enum with associated values to model this.
public struct ecs_cmd_is_t {
    // Store both variants; only one is meaningful at a time depending on cmd kind.
    public var _1: ecs_cmd_1_t = ecs_cmd_1_t()
    public var _n: ecs_cmd_n_t = ecs_cmd_n_t()
    public init() {}
}

/// A deferred command in the command queue.
public struct ecs_cmd_t {
    public var kind: ecs_cmd_kind_t = .EcsCmdSkip      // Command kind
    public var next_for_entity: Int32 = 0               // Next operation for entity
    public var id: ecs_id_t = 0                         // (Component) id
    public var entry: UnsafeMutablePointer<ecs_cmd_entry_t>? = nil
    public var entity: ecs_entity_t = 0                 // Entity id
    public var `is`: ecs_cmd_is_t = ecs_cmd_is_t()      // Data for single/multi entity operation
    public var system: ecs_entity_t = 0                 // System that enqueued the command
    public init() {}
}

/// Callback used to capture commands of a frame.
public typealias ecs_on_commands_action_t = @convention(c) (
    UnsafePointer<ecs_stage_t>?,
    UnsafePointer<ecs_vec_t>?,
    UnsafeMutableRawPointer?
) -> Void

// MARK: - Size constants for typed vec/sparse operations

@inline(__always)
internal var ecsCmdSize: ecs_size_t {
    return ecs_size_t(MemoryLayout<ecs_cmd_t>.stride)
}

@inline(__always)
internal var ecsCmdEntrySize: ecs_size_t {
    return ecs_size_t(MemoryLayout<ecs_cmd_entry_t>.stride)
}

// MARK: - Command Queue Init/Fini

/// Initialize command queue data structure for a stage.
public func flecs_commands_init(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ cmd: UnsafeMutablePointer<ecs_commands_t>)
{
    flecs_stack_init(&cmd.pointee.stack)
    ecs_vec_init(&stage.pointee.allocator, &cmd.pointee.queue, ecsCmdSize, 0)
    flecs_sparse_init(
        &cmd.pointee.entries,
        &stage.pointee.allocator,
        &stage.pointee.allocators.cmd_entry_chunk,
        ecsCmdEntrySize)
}

/// Free command queue data structure for a stage.
public func flecs_commands_fini(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ cmd: UnsafeMutablePointer<ecs_commands_t>)
{
    // Make sure stage has no unmerged data
    assert(ecs_vec_count(&cmd.pointee.queue) == 0,
           "Command queue should be empty before fini")

    flecs_stack_fini(&cmd.pointee.stack)
    ecs_vec_fini(&stage.pointee.allocator, &cmd.pointee.queue, ecsCmdSize)
    flecs_sparse_fini(&cmd.pointee.entries)
}

// MARK: - Command Creation

/// Create a new command in the queue.
public func flecs_cmd_new(
    _ stage: UnsafeMutablePointer<ecs_stage_t>) -> UnsafeMutablePointer<ecs_cmd_t>?
{
    guard let raw = ecs_vec_append(
        &stage.pointee.allocator,
        &stage.pointee.cmd.pointee.queue,
        ecsCmdSize) else {
        return nil
    }

    let cmd = raw.bindMemory(to: ecs_cmd_t.self, capacity: 1)
    cmd.pointee.is._1.value = nil
    cmd.pointee.id = 0
    cmd.pointee.next_for_entity = 0
    cmd.pointee.entry = nil
    cmd.pointee.system = stage.pointee.system
    return cmd
}

/// Create a new command in the queue, batched for a specific entity.
/// Links commands for the same entity together for efficient flushing.
public func flecs_cmd_new_batched(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ e: ecs_entity_t) -> UnsafeMutablePointer<ecs_cmd_t>?
{
    let cmds = &stage.pointee.cmd.pointee.queue

    let entryRaw = flecs_sparse_get(
        &stage.pointee.cmd.pointee.entries,
        ecsCmdEntrySize,
        e)
    var entry: UnsafeMutablePointer<ecs_cmd_entry_t>? = nil
    if let entryRaw = entryRaw {
        entry = entryRaw.bindMemory(to: ecs_cmd_entry_t.self, capacity: 1)
    }

    let cur = ecs_vec_count(cmds)
    guard let cmd = flecs_cmd_new(stage) else { return nil }
    var is_new = false

    if let entry = entry {
        if entry.pointee.first == -1 {
            // Existing but invalidated entry
            entry.pointee.first = cur
            cmd.pointee.entry = entry
        } else {
            let last = entry.pointee.last
            guard let arrRaw = ecs_vec_first(cmds) else {
                return cmd
            }
            let arr = arrRaw.bindMemory(to: ecs_cmd_t.self,
                                        capacity: Int(ecs_vec_count(cmds)))
            if arr[Int(last)].entity == e {
                let last_op = &arr[Int(last)]
                last_op.pointee.next_for_entity = cur
                if last == entry.pointee.first {
                    // Flip sign bit so flush logic can tell which command
                    // is the first for an entity
                    last_op.pointee.next_for_entity *= -1
                }
            } else {
                // Entity with different version was in the same queue.
                // Discard the old entry and create a new one.
                is_new = true
            }
        }
    } else {
        is_new = true
    }

    if is_new {
        guard let newEntryRaw = flecs_sparse_ensure_fast(
            &stage.pointee.cmd.pointee.entries,
            ecsCmdEntrySize,
            e) else {
            return cmd
        }
        let newEntry = newEntryRaw.bindMemory(to: ecs_cmd_entry_t.self, capacity: 1)
        newEntry.pointee.first = cur
        cmd.pointee.entry = newEntry
        entry = newEntry
    }

    entry?.pointee.last = cur

    return cmd
}

// MARK: - Defer Begin/End

/// Begin deferred mode. Returns true if this call transitioned from non-deferred to deferred.
public func flecs_defer_begin(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ stage: UnsafeMutablePointer<ecs_stage_t>) -> Bool
{
    if stage.pointee.defer < 0 { return false }
    stage.pointee.defer += 1
    return stage.pointee.defer == 1
}

/// Check if currently deferred and increment if not. Returns true if already deferred.
public func flecs_defer_cmd(
    _ stage: UnsafeMutablePointer<ecs_stage_t>) -> Bool
{
    if stage.pointee.defer != 0 {
        return stage.pointee.defer > 0
    }

    stage.pointee.defer += 1
    return false
}

/// Leave safe section. Run all deferred commands.
/// This is a stub implementation that handles the basic queue management.
/// Full implementation requires entity operations (flecs_add_id, flecs_remove_id, etc.)
/// which depend on other subsystems not yet translated.
public func flecs_defer_end(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ stage: UnsafeMutablePointer<ecs_stage_t>) -> Bool
{
    if stage.pointee.defer < 0 {
        // Suspending defer makes it possible to do operations on the storage
        // without flushing the commands in the queue
        return false
    }

    assert(stage.pointee.defer > 0, "defer count must be > 0")

    stage.pointee.defer -= 1
    if stage.pointee.defer == 0 && !stage.pointee.cmd_flushing {
        // Swap command buffers
        let commands = stage.pointee.cmd!
        let queue = &commands.pointee.queue

        if stage.pointee.cmd == &stage.pointee.cmd_stack.0 {
            stage.pointee.cmd = &stage.pointee.cmd_stack.1
        } else {
            stage.pointee.cmd = &stage.pointee.cmd_stack.0
        }

        let count = ecs_vec_count(queue)
        if count == 0 {
            return true
        }

        stage.pointee.cmd_flushing = true

        // TODO: Full command execution requires entity operations subsystem.
        // For now, discard all commands and clean up resources.
        if count > 0, let cmdsRaw = ecs_vec_first(queue) {
            let cmds = cmdsRaw.bindMemory(to: ecs_cmd_t.self, capacity: Int(count))
            for i in 0..<Int(count) {
                let cmd = &cmds[i]

                // Invalidate entry
                if let entry = cmd.pointee.entry {
                    entry.pointee.first = -1
                }

                // Free command resources
                let kind = cmd.pointee.kind
                if kind == .EcsCmdBulkNew {
                    if let entities = cmd.pointee.is._n.entities {
                        free(entities)
                    }
                } else if kind == .EcsCmdPath {
                    if let value = cmd.pointee.is._1.value {
                        free(value)
                        cmd.pointee.is._1.value = nil
                    }
                } else {
                    if let value = cmd.pointee.is._1.value {
                        flecs_stack_free(value, cmd.pointee.is._1.size)
                    }
                }
            }
        }

        stage.pointee.cmd_flushing = false

        flecs_stack_reset(&commands.pointee.stack)
        ecs_vec_clear(queue)

        return true
    }

    return false
}

// MARK: - Defer Purge

/// Discard commands from queue without executing them.
public func flecs_defer_purge(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ stage: UnsafeMutablePointer<ecs_stage_t>) -> Bool
{
    stage.pointee.defer -= 1
    if stage.pointee.defer == 0 {
        let commands = &stage.pointee.cmd.pointee.queue
        let count = ecs_vec_count(commands)

        if count > 0 {
            if let cmdsRaw = ecs_vec_first(commands) {
                let cmds = cmdsRaw.bindMemory(to: ecs_cmd_t.self, capacity: Int(count))
                for i in 0..<Int(count) {
                    flecs_discard_cmd(world, &cmds[i])
                }
            }

            ecs_vec_fini(&stage.pointee.allocator, &stage.pointee.cmd.pointee.queue, ecsCmdSize)
            ecs_vec_clear(commands)
            flecs_stack_reset(&stage.pointee.cmd.pointee.stack)
            flecs_sparse_clear(&stage.pointee.cmd.pointee.entries)
        }

        return true
    }

    return false
}

// MARK: - Discard Command

/// Discard a single command, freeing its resources without executing it.
public func flecs_discard_cmd(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cmd: UnsafeMutablePointer<ecs_cmd_t>)
{
    let kind = cmd.pointee.kind
    if kind == .EcsCmdBulkNew {
        if let entities = cmd.pointee.is._n.entities {
            free(entities)
        }
    } else if kind == .EcsCmdEvent {
        // Event commands store an event descriptor in value; free associated data.
        // Full cleanup would call flecs_free_cmd_event but that requires
        // type info lookups. For now free the stack allocation.
        if let value = cmd.pointee.is._1.value {
            flecs_stack_free(value, cmd.pointee.is._1.size)
        }
    } else {
        if let value = cmd.pointee.is._1.value {
            // TODO: Call type destructor via flecs_dtor_value when type info is available.
            flecs_stack_free(value, cmd.pointee.is._1.size)
        }
    }
}

// MARK: - Simple Defer Commands

/// Insert modified command.
public func flecs_defer_modified(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t) -> Bool
{
    if flecs_defer_cmd(stage) {
        if let cmd = flecs_cmd_new(stage) {
            cmd.pointee.kind = .EcsCmdModified
            cmd.pointee.id = id
            cmd.pointee.entity = entity
        }
        return true
    }
    return false
}

/// Insert clone command.
public func flecs_defer_clone(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ entity: ecs_entity_t,
    _ src: ecs_entity_t,
    _ clone_value: Bool) -> Bool
{
    if flecs_defer_cmd(stage) {
        if let cmd = flecs_cmd_new(stage) {
            cmd.pointee.kind = .EcsCmdClone
            cmd.pointee.id = src
            cmd.pointee.entity = entity
            cmd.pointee.is._1.clone_value = clone_value
        }
        return true
    }
    return false
}

/// Insert path command (sets entity path name).
public func flecs_defer_path(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ parent: ecs_entity_t,
    _ entity: ecs_entity_t,
    _ name: UnsafePointer<CChar>?) -> Bool
{
    if stage.pointee.defer > 0 {
        if let cmd = flecs_cmd_new(stage) {
            cmd.pointee.kind = .EcsCmdPath
            cmd.pointee.entity = entity
            cmd.pointee.id = parent
            // Duplicate the name string
            if let name = name {
                cmd.pointee.is._1.value = UnsafeMutableRawPointer(strdup(name))
            } else {
                cmd.pointee.is._1.value = nil
            }
        }
        return true
    }
    return false
}

/// Insert delete command.
public func flecs_defer_delete(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ entity: ecs_entity_t) -> Bool
{
    if flecs_defer_cmd(stage) {
        if let cmd = flecs_cmd_new(stage) {
            cmd.pointee.kind = .EcsCmdDelete
            cmd.pointee.entity = entity
        }
        return true
    }
    return false
}

/// Insert clear command.
public func flecs_defer_clear(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ entity: ecs_entity_t) -> Bool
{
    if flecs_defer_cmd(stage) {
        if let cmd = flecs_cmd_new_batched(stage, entity) {
            cmd.pointee.kind = .EcsCmdClear
            cmd.pointee.entity = entity
        }
        return true
    }
    return false
}

/// Insert delete_with/remove_all command.
public func flecs_defer_on_delete_action(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ id: ecs_id_t,
    _ action: ecs_entity_t) -> Bool
{
    if flecs_defer_cmd(stage) {
        if let cmd = flecs_cmd_new(stage) {
            cmd.pointee.kind = .EcsCmdOnDeleteAction
            cmd.pointee.id = id
            cmd.pointee.entity = action
        }
        return true
    }
    return false
}

/// Insert enable command (component toggling).
public func flecs_defer_enable(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t,
    _ enable: Bool) -> Bool
{
    if flecs_defer_cmd(stage) {
        if let cmd = flecs_cmd_new(stage) {
            cmd.pointee.kind = enable ? .EcsCmdEnable : .EcsCmdDisable
            cmd.pointee.entity = entity
            cmd.pointee.id = id
        }
        return true
    }
    return false
}

/// Insert bulk_new command.
public func flecs_defer_bulk_new(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ count: Int32,
    _ id: ecs_id_t,
    _ ids_out: UnsafeMutablePointer<UnsafePointer<ecs_entity_t>?>) -> Bool
{
    if flecs_defer_cmd(stage) {
        let ids = UnsafeMutablePointer<ecs_entity_t>.allocate(capacity: Int(count))

        // TODO: Use ecs_new (thread safe) to generate entity IDs.
        // For now, zero-initialize as placeholder.
        ids.initialize(repeating: 0, count: Int(count))

        ids_out.pointee = UnsafePointer(ids)

        if let cmd = flecs_cmd_new(stage) {
            cmd.pointee.kind = .EcsCmdBulkNew
            cmd.pointee.id = id
            cmd.pointee.is._n.entities = ids
            cmd.pointee.is._n.count = count
            cmd.pointee.entity = 0
        }
        return true
    }
    return false
}

/// Insert add component command.
public func flecs_defer_add(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t) -> Bool
{
    if flecs_defer_cmd(stage) {
        assert(id != 0, "id must not be 0")
        if let cmd = flecs_cmd_new_batched(stage, entity) {
            cmd.pointee.kind = .EcsCmdAdd
            cmd.pointee.id = id
            cmd.pointee.entity = entity
        }
        return true
    }
    return false
}

/// Insert remove component command.
public func flecs_defer_remove(
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t) -> Bool
{
    if flecs_defer_cmd(stage) {
        assert(id != 0, "id must not be 0")
        if let cmd = flecs_cmd_new_batched(stage, entity) {
            cmd.pointee.kind = .EcsCmdRemove
            cmd.pointee.id = id
            cmd.pointee.entity = entity
        }
        // Note: The C version also restores overridden component values here.
        // That requires table/record access which depends on other subsystems.
        // TODO: Implement override restoration when entity operations are available.
        return true
    }
    return false
}

// MARK: - Set/Ensure/Emplace Commands (Stubs)

/// Insert set component command.
/// Stub: allocates stack space for the value but does not look up existing components.
/// Full implementation requires flecs_get_mut and type info subsystems.
public func flecs_defer_set(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t,
    _ size: ecs_size_t,
    _ value: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
{
    assert(value != nil, "value must not be nil")
    assert(size != 0, "size must not be 0")

    guard let cmd = flecs_cmd_new_batched(stage, entity) else { return nil }
    cmd.pointee.entity = entity
    cmd.pointee.id = id

    // Allocate temporary storage on the command stack
    let stack = &stage.pointee.cmd.pointee.stack
    let alignment = size < 16 ? size : 16
    guard let cmd_value = flecs_stack_alloc(stack, size, alignment) else { return nil }

    cmd.pointee.kind = .EcsCmdSet
    cmd.pointee.is._1.size = size
    cmd.pointee.is._1.value = cmd_value

    // Copy value into command storage
    memcpy(cmd_value, value, Int(size))

    return cmd_value
}

/// Insert ensure component command.
/// Stub: allocates stack space and zero-initializes.
/// Full implementation requires flecs_get_mut and type info subsystems.
public func flecs_defer_ensure(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t,
    _ size: ecs_size_t) -> UnsafeMutableRawPointer?
{
    assert(size != 0, "size must not be 0")

    guard let cmd = flecs_cmd_new_batched(stage, entity) else { return nil }
    cmd.pointee.entity = entity
    cmd.pointee.id = id

    let stack = &stage.pointee.cmd.pointee.stack
    let alignment = size < 16 ? size : 16
    guard let ptr = flecs_stack_alloc(stack, size, alignment) else { return nil }

    cmd.pointee.kind = .EcsCmdEnsure
    cmd.pointee.is._1.size = size
    cmd.pointee.is._1.value = ptr

    // Zero-initialize (ctor substitute)
    memset(ptr, 0, Int(size))

    return ptr
}

/// Insert emplace component command.
/// Stub: allocates stack space for the value.
/// Full implementation requires flecs_get_mut and type info subsystems.
public func flecs_defer_emplace(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t,
    _ size: ecs_size_t,
    _ is_new: UnsafeMutablePointer<Bool>?) -> UnsafeMutableRawPointer?
{
    guard let cmd = flecs_cmd_new_batched(stage, entity) else { return nil }
    cmd.pointee.entity = entity
    cmd.pointee.id = id

    let stack = &stage.pointee.cmd.pointee.stack
    let alignment = size < 16 ? size : 16
    guard let cmd_value = flecs_stack_alloc(stack, size, alignment) else { return nil }

    cmd.pointee.kind = .EcsCmdEmplace
    cmd.pointee.is._1.size = size
    cmd.pointee.is._1.value = cmd_value
    is_new?.pointee = true

    return cmd_value
}

// MARK: - Enqueue Event

/// Insert event command.
/// Stub: copies the event descriptor to the command stack.
/// Full implementation requires type info for param handling.
public func flecs_enqueue(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ stage: UnsafeMutablePointer<ecs_stage_t>,
    _ desc: UnsafeMutablePointer<ecs_event_desc_t>)
{
    guard let cmd = flecs_cmd_new(stage) else { return }
    cmd.pointee.kind = .EcsCmdEvent
    cmd.pointee.entity = desc.pointee.entity

    let stack = &stage.pointee.cmd.pointee.stack
    let descSize = ecs_size_t(MemoryLayout<ecs_event_desc_t>.stride)
    let descAlign = ecs_size_t(MemoryLayout<ecs_event_desc_t>.alignment)
    guard let descCmdRaw = flecs_stack_alloc(stack, descSize, descAlign) else { return }
    let descCmd = descCmdRaw.bindMemory(to: ecs_event_desc_t.self, capacity: 1)
    descCmd.pointee = desc.pointee

    if let ids = desc.pointee.ids, ids.pointee.count != 0 {
        let typeSize = ecs_size_t(MemoryLayout<ecs_type_t>.stride)
        let typeAlign = ecs_size_t(MemoryLayout<ecs_type_t>.alignment)
        guard let typeCmdRaw = flecs_stack_alloc(stack, typeSize, typeAlign) else { return }
        let typeCmd = typeCmdRaw.bindMemory(to: ecs_type_t.self, capacity: 1)

        let id_count = ids.pointee.count
        typeCmd.pointee.count = id_count

        let idArraySize = ecs_size_t(MemoryLayout<ecs_id_t>.stride) * id_count
        let idArrayAlign = ecs_size_t(MemoryLayout<ecs_id_t>.alignment)
        guard let idArrayRaw = flecs_stack_alloc(stack, idArraySize, idArrayAlign) else { return }
        let idArray = idArrayRaw.bindMemory(to: ecs_id_t.self, capacity: Int(id_count))
        if let srcArray = ids.pointee.array {
            memcpy(idArray, srcArray, Int(MemoryLayout<ecs_id_t>.stride) * Int(id_count))
        }
        typeCmd.pointee.array = idArray

        descCmd.pointee.ids = UnsafePointer(typeCmd)
    } else {
        descCmd.pointee.ids = nil
    }

    cmd.pointee.is._1.value = descCmdRaw
    cmd.pointee.is._1.size = descSize

    // TODO: Handle param/const_param copying when type info subsystem is available.
    // The C version uses type info to do move_ctor/copy_ctor on the event param.
}

// MARK: - Public API Wrappers

/// Begin deferred mode (public API).
public func ecs_defer_begin(
    _ world: UnsafeMutablePointer<ecs_world_t>) -> Bool
{
    let stage = flecs_stage_from_world(world)
    return flecs_defer_begin(world, stage)
}

/// End deferred mode (public API).
public func ecs_defer_end(
    _ world: UnsafeMutablePointer<ecs_world_t>) -> Bool
{
    let stage = flecs_stage_from_world(world)
    return flecs_defer_end(world, stage)
}

/// Check if deferred mode is active.
public func ecs_is_deferred(
    _ world: UnsafeMutablePointer<ecs_world_t>) -> Bool
{
    let stage = flecs_stage_from_world(world)
    return stage.pointee.defer > 0
}

/// Suspend deferred mode (single-arg public API).
public func ecs_defer_suspend(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    let stage = flecs_stage_from_world(world)
    stage.pointee.defer = -stage.pointee.defer
}

/// Resume deferred mode (single-arg public API).
public func ecs_defer_resume(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    let stage = flecs_stage_from_world(world)
    stage.pointee.defer = -stage.pointee.defer
}

// MARK: - Command Flush

/// Flush a batch of commands for a single entity.
/// Computes the final table from accumulated add/remove operations,
/// moves the entity once, then applies set/modified commands.
private func flecs_cmd_batch_for_entity(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ diff: UnsafeMutablePointer<ecs_table_diff_builder_t>,
    _ entity: ecs_entity_t,
    _ cmds: UnsafeMutablePointer<ecs_cmd_t>,
    _ start: Int32)
{
    guard let r = flecs_entities_get(UnsafePointer(world), entity) else { return }
    guard var table = r.pointee.table else { return }

    world.pointee.info.cmd.batched_entity_count += 1

    var has_set = false
    var cur = start
    var next_for_entity: Int32

    // Phase 1: Compute destination table from add/remove commands
    repeat {
        let cmd = cmds + Int(cur)
        let id = cmd.pointee.id
        next_for_entity = cmd.pointee.next_for_entity
        if next_for_entity < 0 { next_for_entity *= -1 }

        // Validate id
        if id != 0 {
            if let cr = flecs_components_get(UnsafePointer(world), id) {
                if (cr.pointee.flags & EcsIdDontFragment) != 0 {
                    if cmd.pointee.kind == .EcsCmdSet {
                        cmd.pointee.kind = .EcsCmdSetDontFragment
                    }
                    continue
                }
            }
        }

        switch cmd.pointee.kind {
        case .EcsCmdAddModified:
            cmd.pointee.kind = .EcsCmdModified
            if let t = flecs_find_table_add(world, table, id, diff) {
                table = t
            }
            world.pointee.info.cmd.batched_command_count += 1

        case .EcsCmdAdd:
            if let t = flecs_find_table_add(world, table, id, diff) {
                table = t
            }
            world.pointee.info.cmd.batched_command_count += 1
            cmd.pointee.kind = .EcsCmdSkip

        case .EcsCmdSet, .EcsCmdEnsure:
            if let t = flecs_find_table_add(world, table, id, diff) {
                table = t
            }
            world.pointee.info.cmd.batched_command_count += 1
            has_set = true

        case .EcsCmdRemove:
            if let t = flecs_find_table_remove(world, table, id, diff) {
                table = t
            }
            world.pointee.info.cmd.batched_command_count += 1
            cmd.pointee.kind = .EcsCmdSkip

        case .EcsCmdClear:
            // Remove all components
            table = withUnsafeMutablePointer(to: &world.pointee.store.root) { $0 }
            world.pointee.info.cmd.batched_command_count += 1
            cmd.pointee.kind = .EcsCmdSkip

        default:
            break
        }

        cur = next_for_entity
    } while cur != 0

    // Phase 2: Move entity to destination table
    var table_diff = ecs_table_diff_t()
    flecs_table_diff_build_noalloc(diff, &table_diff)
    flecs_defer_begin(world, world.pointee.stages![0]!)
    flecs_commit(world, entity, r, table, &table_diff, true, 0)
    flecs_defer_end(world, world.pointee.stages![0]!)

    // Phase 3: Copy set values to final component storage
    if has_set {
        cur = start
        repeat {
            let cmd = cmds + Int(cur)
            next_for_entity = cmd.pointee.next_for_entity
            if next_for_entity < 0 { next_for_entity *= -1 }

            if cmd.pointee.kind == .EcsCmdSet || cmd.pointee.kind == .EcsCmdEnsure {
                if let value = cmd.pointee.is._1.value {
                    let dst = flecs_get_mut(world, entity, cmd.pointee.id, r,
                        cmd.pointee.is._1.size)
                    if let dst_ptr = dst.ptr, let ti = dst.ti {
                        flecs_type_info_copy(dst_ptr, value, 1, UnsafePointer(ti))
                    }
                }
            }

            cur = next_for_entity
        } while cur != 0
    }

    flecs_table_diff_builder_clear(diff)
}

/// Execute a single non-batched command.
private func flecs_cmd_execute(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cmd: UnsafeMutablePointer<ecs_cmd_t>)
{
    let entity = cmd.pointee.entity
    let id = cmd.pointee.id

    switch cmd.pointee.kind {
    case .EcsCmdAdd:
        if entity != 0 { ecs_add_id(world, entity, id) }
    case .EcsCmdRemove:
        if entity != 0 { ecs_remove_id(world, entity, id) }
    case .EcsCmdDelete:
        ecs_delete(world, entity)
    case .EcsCmdClear:
        ecs_clear(world, entity)
    case .EcsCmdClone:
        ecs_clone(world, entity, id, cmd.pointee.is._1.clone_value)
    case .EcsCmdSet, .EcsCmdSetDontFragment:
        // Set value on entity
        if let value = cmd.pointee.is._1.value {
            // Would call ecs_set_id with the value
        }
    case .EcsCmdEnsure:
        // Ensure + copy value
        if let value = cmd.pointee.is._1.value {
            // Would call ecs_ensure_id + copy
        }
    case .EcsCmdEmplace:
        // Emplace value (no ctor)
        break
    case .EcsCmdModified, .EcsCmdModifiedNoHook:
        // Signal modification
        ecs_modified_id(world, entity, id)
    case .EcsCmdEnable:
        ecs_enable_id(world, entity, id, true)
    case .EcsCmdDisable:
        ecs_enable_id(world, entity, id, false)
    case .EcsCmdOnDeleteAction:
        flecs_on_delete(world, id, entity, true, false)
    case .EcsCmdBulkNew:
        flecs_flush_bulk_new(world, cmd)
    case .EcsCmdPath:
        if let name = cmd.pointee.is._1.value?.assumingMemoryBound(
            to: CChar.self)
        {
            ecs_add_fullpath(world, entity, name)
            ecs_os_free(cmd.pointee.is._1.value)
            cmd.pointee.is._1.value = nil
        }
    case .EcsCmdEvent:
        if let desc = cmd.pointee.is._1.value?.bindMemory(
            to: ecs_event_desc_t.self, capacity: 1)
        {
            flecs_emit(world, world, desc)
        }
    case .EcsCmdSkip, .EcsCmdAddModified:
        break
    }
}

/// Flush bulk new command.
private func flecs_flush_bulk_new(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cmd: UnsafeMutablePointer<ecs_cmd_t>)
{
    guard let entities = cmd.pointee.is._n.entities else { return }

    if cmd.pointee.id != 0 {
        for i in 0..<Int(cmd.pointee.is._n.count) {
            ecs_add_id(world, entities[i], cmd.pointee.id)
        }
    }

    ecs_os_free(entities)
}

/// Remove an invalid id (e.g. target of deleted pair).
/// Returns true if entity should remain alive.
private func flecs_remove_invalid(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_id_t,
    _ id_out: UnsafeMutablePointer<ecs_id_t>) -> Bool
{
    if ECS_HAS_ID_FLAG(id, ECS_PAIR) {
        let rel = ECS_PAIR_FIRST(id)
        if !flecs_entities_is_valid(world, rel) {
            id_out.pointee = 0
            return true
        }
        let tgt = ECS_PAIR_SECOND(id)
        if !flecs_entities_is_valid(world, tgt) {
            if let cr = flecs_components_get(
                UnsafePointer(world), ecs_pair(rel, EcsWildcard))
            {
                let action = ECS_ID_ON_DELETE_TARGET(cr.pointee.flags)
                if action == EcsDelete { return false }
            }
            id_out.pointee = 0
            return true
        }
    } else {
        if !flecs_entities_is_valid(world, id & ECS_COMPONENT_MASK) {
            id_out.pointee = 0
            return true
        }
    }
    return true
}
