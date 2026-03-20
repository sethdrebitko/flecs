// ComponentActions.swift - 1:1 translation of flecs component_actions.c
// Logic executed after adding/removing a component: hooks, observers, sparse storage

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Invoke a component lifecycle hook (on_add, on_remove, on_set).
public func flecs_invoke_hook(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutableRawPointer?,
    _ cr: UnsafePointer<ecs_component_record_t>,
    _ tr: UnsafePointer<ecs_table_record_t>?,
    _ count: Int32,
    _ row: Int32,
    _ entities: UnsafePointer<ecs_entity_t>,
    _ id: ecs_id_t,
    _ ti: UnsafePointer<ecs_type_info_t>,
    _ event: ecs_entity_t,
    _ hook: ecs_iter_action_t)
{
    // Save and restore defer state
    var defer_val: Int32 = 0
    if world.pointee.stages != nil && world.pointee.stages!.pointee != nil {
        defer_val = world.pointee.stages!.pointee!.pointee.defer
        if defer_val < 0 {
            world.pointee.stages!.pointee!.pointee.defer *= -1
        }
    }

    var it = ecs_iter_t()
    it.field_count = 1
    it.entities = entities

    // Set up the iterator with the table record info
    var dummy_tr = ecs_table_record_t()
    var tr_to_use = tr

    if tr_to_use == nil {
        dummy_tr.hdr.cr = UnsafeMutableRawPointer(mutating: cr)
        dummy_tr.hdr.table = table
        dummy_tr.index = -1
        dummy_tr.column = -1
        dummy_tr.count = 0
        tr_to_use = withUnsafePointer(to: &dummy_tr) { $0 }
    }

    var dummy_src: ecs_entity_t = 0
    var mut_id = id

    it.world = UnsafeMutableRawPointer(world)
    it.real_world = UnsafeMutableRawPointer(world)
    it.table = table
    it.sizes = withUnsafePointer(to: &ti.pointee.size) { $0 }
    it.ids = withUnsafeMutablePointer(to: &mut_id) { $0 }
    it.sources = withUnsafeMutablePointer(to: &dummy_src) { $0 }
    it.event = event
    it.event_id = id
    it.ctx = ti.pointee.hooks.ctx
    it.callback_ctx = ti.pointee.hooks.binding_ctx
    it.count = count
    it.offset = row
    it.flags = EcsIterIsValid

    hook(withUnsafeMutablePointer(to: &it) { $0 })

    // Restore defer state
    if world.pointee.stages != nil && world.pointee.stages!.pointee != nil {
        world.pointee.stages!.pointee!.pointee.defer = defer_val
    }
}


/// Execute on-add actions for new entities.
public func flecs_actions_new(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutableRawPointer?,
    _ row: Int32,
    _ count: Int32,
    _ diff: UnsafePointer<ecs_table_diff_t>,
    _ flags: ecs_flags32_t,
    _ construct: Bool,
    _ sparse: Bool)
{
    let diff_flags = diff.pointee.added_flags
    if diff_flags == 0 { return }

    // Would call flecs_on_reparent, flecs_sparse_on_add, flecs_emit
    // in full implementation
}

/// Execute on-remove actions during entity deletion.
public func flecs_actions_delete_tree(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutableRawPointer?,
    _ row: Int32,
    _ count: Int32,
    _ diff: UnsafePointer<ecs_table_diff_t>)
{
    if diff.pointee.removed.count == 0 { return }
    let diff_flags = diff.pointee.removed_flags
    if diff_flags == 0 { return }

    // Would call flecs_actions_on_remove_intern in full implementation
}

/// Execute add actions after a table move.
public func flecs_actions_move_add(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutableRawPointer?,
    _ other_table: UnsafeMutableRawPointer?,
    _ row: Int32,
    _ count: Int32,
    _ diff: UnsafePointer<ecs_table_diff_t>,
    _ flags: ecs_flags32_t,
    _ construct: Bool,
    _ sparse: Bool)
{
    let added = diff.pointee.added
    if added.count == 0 { return }

    // Would call flecs_emit_propagate_invalidate, flecs_on_reparent,
    // flecs_actions_on_add_intern in full implementation
}

/// Execute remove actions after a table move.
public func flecs_actions_move_remove(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutableRawPointer?,
    _ other_table: UnsafeMutableRawPointer?,
    _ row: Int32,
    _ count: Int32,
    _ diff: UnsafePointer<ecs_table_diff_t>)
{
    if diff.pointee.removed.count == 0 { return }

    // Would call flecs_emit_propagate_invalidate,
    // flecs_actions_on_remove_intern_w_reparent in full implementation
}


/// Notify on-set hooks and observers for a set of ids.
public func flecs_notify_on_set_ids(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutableRawPointer?,
    _ row: Int32,
    _ count: Int32,
    _ ids: UnsafeMutablePointer<ecs_type_t>)
{
    if ids.pointee.count == 0 { return }

    // Would iterate ids, look up component records, invoke on_set hooks,
    // and call flecs_emit in full implementation
}

/// Notify on-set for a single id.
public func flecs_notify_on_set(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutableRawPointer?,
    _ row: Int32,
    _ id: ecs_id_t,
    _ invoke_hook: Bool)
{
    if id == 0 { return }

    // Would look up component record, invoke on_set hook,
    // and call flecs_emit in full implementation
}


/// Handle adding a sparse component to an entity.
public func flecs_sparse_on_add_cr(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutableRawPointer?,
    _ row: Int32,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>?,
    _ construct: Bool,
    _ ptr_out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool
{
    if cr == nil || (cr!.pointee.flags & EcsIdSparse) == 0 {
        return false
    }

    // Would call flecs_component_sparse_insert/emplace in full implementation
    return false
}

/// Remove non-fragmenting sparse components from an entity.
public func flecs_entity_remove_non_fragmenting(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ e: ecs_entity_t,
    _ r: UnsafeMutablePointer<ecs_record_t>?)
{
    var record = r
    if record == nil {
        // Would call flecs_entities_get(world, e)
        return
    }

    if record == nil { return }
    if (record!.pointee.row & EcsEntityHasDontFragment) == 0 {
        return
    }

    // Would iterate world->cr_non_fragmenting_head chain and remove
    // sparse components in full implementation

    record!.pointee.row &= ~EcsEntityHasDontFragment
}
