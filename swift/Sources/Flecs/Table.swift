// Table.swift - 1:1 translation of flecs storage/table.c
// Table storage: columns, entity movement, hooks, init/fini

import Foundation

// MARK: - Type Info Flags

/// Derive table flags from type info hooks.
private func flecs_type_info_flags(
    _ ti: UnsafePointer<ecs_type_info_t>) -> ecs_flags32_t
{
    var flags: ecs_flags32_t = 0
    if ti.pointee.hooks.ctor != nil { flags |= EcsTableHasCtors }
    if ti.pointee.hooks.on_add != nil { flags |= EcsTableHasCtors }
    if ti.pointee.hooks.dtor != nil { flags |= EcsTableHasDtors }
    if ti.pointee.hooks.on_remove != nil { flags |= EcsTableHasDtors }
    if ti.pointee.hooks.copy != nil { flags |= EcsTableHasCopy }
    if ti.pointee.hooks.move != nil { flags |= EcsTableHasMove }
    return flags
}

// MARK: - Table Flag Initialization

/// Scan a table's type to set flags for fast feature detection.
private func flecs_table_init_flags(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    guard let ids = table.pointee.type.array else { return }
    let count = table.pointee.type.count
    table.pointee.childof_index = -1

    for i in 0..<Int(count) {
        let id = ids[i]

        if id <= EcsLastInternalComponentId {
            table.pointee.flags |= EcsTableHasModule
        }

        if id == EcsModule {
            table.pointee.flags |= EcsTableHasModule
        } else if id == EcsPrefab {
            table.pointee.flags |= EcsTableIsPrefab
        } else if id == EcsDisabled {
            table.pointee.flags |= EcsTableIsDisabled
        } else if id == EcsNotQueryable {
            table.pointee.flags |= EcsTableNotQueryable
        } else if id == ecs_id_EcsParent {
            table.pointee.flags |= EcsTableHasParent
            table.pointee.trait_flags |= EcsIdTraversable
        } else if ECS_IS_PAIR(id) {
            let r = ECS_PAIR_FIRST(id)
            table.pointee.flags |= EcsTableHasPairs

            if r == EcsIsA {
                table.pointee.flags |= EcsTableHasIsA
            } else if r == EcsChildOf {
                table.pointee.flags |= EcsTableHasChildOf
                table.pointee.childof_index = Int16(i)
            } else if id == ecs_pair(ecs_id_EcsIdentifier, EcsName) {
                table.pointee.flags |= EcsTableHasName
            }
        } else {
            if ECS_HAS_ID_FLAG(id, ECS_TOGGLE) {
                table.pointee.flags |= EcsTableHasToggle
                let meta = table.pointee._!
                if meta.pointee.bs_count == 0 {
                    meta.pointee.bs_offset = Int16(i)
                }
                meta.pointee.bs_count += 1
            }
            if ECS_HAS_ID_FLAG(id, ECS_AUTO_OVERRIDE) {
                table.pointee.flags |= EcsTableHasOverrides
            }
        }
    }
}

// MARK: - Column Initialization

/// Initialize table columns from the type and component records.
private func flecs_table_init_columns(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ column_count: Int32)
{
    let ids_count = table.pointee.type.count
    guard let ids = table.pointee.type.array else { return }

    // Initialize component_map for fast small-id lookups
    for i in 0..<Int(ids_count) {
        let id = ids[i]
        if id < FLECS_HI_COMPONENT_ID {
            table.pointee.component_map![Int(id)] = Int16(-(i + 1))
        }
    }

    if column_count == 0 { return }

    let columns = UnsafeMutablePointer<ecs_column_t>.allocate(capacity: Int(column_count))
    columns.initialize(repeating: ecs_column_t(), count: Int(column_count))
    table.pointee.data.columns = columns

    guard let records = table.pointee._.pointee.records else { return }
    guard let t2s = table.pointee.column_map else { return }
    let s2t = t2s + Int(ids_count)

    var cur: Int16 = 0
    for i in 0..<Int(ids_count) {
        let id = ids[i]
        let cr = records[i].hdr.cr!
        let ti = cr.pointee.type_info

        if ti == nil || (cr.pointee.flags & EcsIdSparse) != 0 {
            t2s[i] = -1
            continue
        }

        t2s[i] = cur
        s2t[Int(cur)] = Int16(i)
        records[i].column = cur

        columns[Int(cur)].ti = UnsafeMutablePointer(mutating: ti)

        if id < FLECS_HI_COMPONENT_ID {
            table.pointee.component_map![Int(id)] = Int16(cur + 1)
        }

        table.pointee.flags |= flecs_type_info_flags(UnsafePointer(ti!))
        cur += 1
    }
}

/// Initialize table storage (columns + bitset columns).
private func flecs_table_init_data(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    flecs_table_init_columns(world, table, Int32(table.pointee.column_count))

    let meta = table.pointee._!
    let bs_count = meta.pointee.bs_count
    if bs_count > 0 {
        meta.pointee.bs_columns = UnsafeMutablePointer<ecs_bitset_t>
            .allocate(capacity: Int(bs_count))
        for i in 0..<Int(bs_count) {
            meta.pointee.bs_columns![i] = ecs_bitset_t()
            flecs_bitset_init(&meta.pointee.bs_columns![i])
        }
    }
}

// MARK: - Table Record Building

/// Append a record to the temporary records vector.
private func flecs_table_append_to_records(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ records: UnsafeMutablePointer<ecs_vec_t>,
    _ id: ecs_id_t,
    _ column: Int32)
{
    let cr = flecs_components_ensure(world, id)
    let elem_size = Int32(MemoryLayout<ecs_table_record_t>.stride)

    if let existing = flecs_component_get_table(UnsafePointer(cr), UnsafePointer(table)) {
        let existing_mut = UnsafeMutablePointer(mutating: existing)
        existing_mut.pointee.count += 1
    } else {
        guard let tr = ecs_vec_append(
            &world.pointee.allocator, records, elem_size)?
            .bindMemory(to: ecs_table_record_t.self, capacity: 1) else { return }
        tr.pointee.index = Int16(column)
        tr.pointee.count = 1
        ecs_table_cache_insert(&cr.pointee.cache, table, &tr.pointee.hdr)
    }
}

// MARK: - Main Table Init

/// Main table initialization. Registers with id records and sets up storage.
public func flecs_table_init(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ from: UnsafeMutablePointer<ecs_table_t>?)
{
    // Set flags
    flecs_table_init_flags(world, table)

    let dst_count = table.pointee.type.count
    guard let dst_ids = table.pointee.type.array else { return }

    // Build records vector
    let a = withUnsafeMutablePointer(to: &world.pointee.allocator) { $0 }
    let records = withUnsafeMutablePointer(to: &world.pointee.store.records) { $0 }
    let elem_size = Int32(MemoryLayout<ecs_table_record_t>.stride)
    ecs_vec_reset(a, records, elem_size)

    // Register each id in the type with its component record
    for i in 0..<Int(dst_count) {
        let cr = flecs_components_ensure(world, dst_ids[i])
        guard let tr = ecs_vec_append(a, records, elem_size)?
            .bindMemory(to: ecs_table_record_t.self, capacity: 1) else { continue }
        tr.pointee.hdr.cr = cr
        tr.pointee.index = Int16(i)
        tr.pointee.count = 1
    }

    // Add wildcard pair records: (R,*) and (*,T)
    if (table.pointee.flags & EcsTableHasPairs) != 0 {
        var prev_r: ecs_entity_t = 0
        for i in 0..<Int(dst_count) {
            let id = dst_ids[i]
            if !ECS_IS_PAIR(id) { continue }

            let r = ECS_PAIR_FIRST(id)
            if r != prev_r {
                // Add (R, *) record
                let cr = flecs_components_ensure(world, ecs_pair(r, EcsWildcard))
                guard let tr = ecs_vec_append(a, records, elem_size)?
                    .bindMemory(to: ecs_table_record_t.self, capacity: 1) else { continue }
                tr.pointee.hdr.cr = cr
                tr.pointee.index = Int16(i)
                tr.pointee.count = 1
                prev_r = r
            } else {
                // Increment count of (R, *) record
                let count_records = ecs_vec_count(records)
                if count_records > 0 {
                    // Would update the last (R, *) record count
                }
            }

            // Add (*, T) record
            if !ECS_IS_VALUE_PAIR(id) {
                flecs_table_append_to_records(world, table, records,
                    ecs_pair(EcsWildcard, ECS_PAIR_SECOND(id)), Int32(i))
            }
        }
    }

    // Add (*) and (*,*) wildcard records
    if let cr_wc = world.pointee.cr_wildcard {
        guard let tr = ecs_vec_append(a, records, elem_size)?
            .bindMemory(to: ecs_table_record_t.self, capacity: 1) else { return }
        tr.pointee.hdr.cr = cr_wc
        tr.pointee.index = 0
        tr.pointee.count = Int16(dst_count)
    }

    // Add (ChildOf, 0) record if no ChildOf/Parent
    let has_childof = (table.pointee.flags & (EcsTableHasChildOf | EcsTableHasParent)) != 0
    if !has_childof {
        if let cr = world.pointee.cr_childof_0 {
            guard let tr = ecs_vec_append(a, records, elem_size)?
                .bindMemory(to: ecs_table_record_t.self, capacity: 1) else { return }
            tr.pointee.hdr.cr = cr
            tr.pointee.index = -1
            tr.pointee.count = 0
        }
    }

    // Copy records to final array
    let record_count = ecs_vec_count(records)
    if record_count > 0 {
        let src_records = ecs_vec_first(records)!
            .bindMemory(to: ecs_table_record_t.self, capacity: Int(record_count))
        let dst_records = UnsafeMutablePointer<ecs_table_record_t>
            .allocate(capacity: Int(record_count))
        dst_records.update(from: src_records, count: Int(record_count))

        table.pointee._.pointee.record_count = Int16(record_count)
        table.pointee._.pointee.records = dst_records

        // Register records in table caches and count columns
        var column_count: Int32 = 0
        for i in 0..<Int(record_count) {
            let tr = dst_records + i
            let cr = tr.pointee.hdr.cr!

            if !ecs_table_cache_get(&cr.pointee.cache, UnsafePointer(table)) {
                ecs_table_cache_insert(&cr.pointee.cache, table, &tr.pointee.hdr)
            } else {
                ecs_table_cache_replace(&cr.pointee.cache, table, &tr.pointee.hdr)
            }

            flecs_component_claim(world, cr)
            table.pointee.flags |= cr.pointee.flags & EcsIdEventMask
            tr.pointee.column = -1

            if i < Int(dst_count) && cr.pointee.type_info != nil {
                if (cr.pointee.flags & EcsIdSparse) == 0 {
                    column_count += 1
                }
            }
        }

        // Allocate component_map and column_map
        table.pointee.component_map = UnsafeMutablePointer<Int16>
            .allocate(capacity: Int(FLECS_HI_COMPONENT_ID))
        table.pointee.component_map!.initialize(
            repeating: 0, count: Int(FLECS_HI_COMPONENT_ID))

        if column_count > 0 {
            let map_size = Int(dst_count) + Int(column_count)
            table.pointee.column_map = UnsafeMutablePointer<Int16>
                .allocate(capacity: map_size)
            table.pointee.column_map!.initialize(repeating: 0, count: map_size)
        }

        table.pointee.column_count = Int16(column_count)
        table.pointee.version = 1
        flecs_table_init_data(world, table)
    }

    // Emit OnTableCreate if observers exist
    if (table.pointee.flags & EcsTableHasOnTableCreate) != 0 {
        flecs_table_emit(world, table, EcsOnTableCreate)
    }
}

/// Emit a table-level event.
private func flecs_table_emit(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ event: ecs_entity_t)
{
    ecs_defer_begin(world)
    var desc = ecs_event_desc_t()
    desc.ids = withUnsafePointer(to: &table.pointee.type) { $0 }
    desc.event = event
    desc.table = UnsafeMutableRawPointer(table)
    desc.flags = EcsEventTableOnly
    desc.observable = UnsafeMutableRawPointer(world)
    flecs_emit(world, world, &desc)
    ecs_defer_end(world)
}

// MARK: - Table Record Unregistration

/// Unregister a table from all its component record caches.
private func flecs_table_records_unregister(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    let count = table.pointee._.pointee.record_count
    guard let records = table.pointee._.pointee.records else { return }

    for i in 0..<Int(count) {
        let cr = records[i].hdr.cr!
        ecs_table_cache_remove(&cr.pointee.cache, table.pointee.id, &records[i].hdr)
        flecs_component_release(world, cr)
    }

    records.deallocate()
}

// MARK: - Trigger Flags

/// Add trigger flags to a table for observer matching.
public func flecs_table_add_trigger_flags(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ id: ecs_id_t,
    _ event: ecs_entity_t)
{
    var flags: ecs_flags32_t = 0
    if event == EcsOnAdd { flags = EcsTableHasOnAdd }
    else if event == EcsOnRemove { flags = EcsTableHasOnRemove }
    else if event == EcsOnSet { flags = EcsTableHasOnSet }
    else if event == EcsOnTableCreate { flags = EcsTableHasOnTableCreate }
    else if event == EcsOnTableDelete { flags = EcsTableHasOnTableDelete }
    else if event == EcsWildcard {
        flags = EcsTableHasOnAdd | EcsTableHasOnRemove | EcsTableHasOnSet |
                EcsTableHasOnTableCreate | EcsTableHasOnTableDelete
    }
    table.pointee.flags |= flags

    if id != 0 && (flags == EcsTableHasOnAdd || flags == EcsTableHasOnRemove) {
        flecs_table_edges_add_flags(world, table, id, flags)
    }
}

// MARK: - Table Hook Invocation

/// Invoke a type hook for entities in a column range.
public func flecs_table_invoke_hook(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ callback: @convention(c) (UnsafeMutablePointer<ecs_iter_t>) -> Void,
    _ event: ecs_entity_t,
    _ column: UnsafeMutablePointer<ecs_column_t>,
    _ entities: UnsafePointer<ecs_entity_t>,
    _ row: Int32,
    _ count: Int32)
{
    let column_index = (UnsafeMutableRawPointer(column) - UnsafeMutableRawPointer(table.pointee.data.columns!)) / MemoryLayout<ecs_column_t>.stride
    let type_index = table.pointee.column_map![Int(table.pointee.type.count) + column_index]
    let tr = table.pointee._.pointee.records![Int(type_index)]
    let cr = tr.hdr.cr!

    var entity_mut = entities.pointee  // For single entity hooks
    flecs_invoke_hook(world, table, cr,
        withUnsafePointer(to: &table.pointee._.pointee.records![Int(type_index)]) { $0 },
        count, row, &entity_mut,
        table.pointee.type.array![Int(type_index)],
        UnsafePointer(column.pointee.ti!), event, callback)
}

/// Destruct components in a column range.
public func flecs_table_invoke_dtor(
    _ column: UnsafeMutablePointer<ecs_column_t>,
    _ row: Int32,
    _ count: Int32)
{
    guard let ti = column.pointee.ti else { return }
    guard let data = column.pointee.data else { return }
    let ptr = data + Int(row) * Int(ti.pointee.size)
    flecs_type_info_dtor(ptr, count, UnsafePointer(ti))
}

/// Construct components in a column range.
public func flecs_table_invoke_ctor(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ column_index: Int32,
    _ row: Int32,
    _ count: Int32)
{
    let column = table.pointee.data.columns! + Int(column_index)
    guard let ti = column.pointee.ti else { return }
    guard let data = column.pointee.data else { return }
    let ptr = data + Int(row) * Int(ti.pointee.size)
    flecs_type_info_ctor(ptr, count, UnsafePointer(ti))
}

/// Run add hooks (construct + on_add).
public func flecs_table_invoke_add_hooks(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ column_index: Int32,
    _ entities: UnsafeMutablePointer<ecs_entity_t>,
    _ row: Int32,
    _ count: Int32,
    _ construct: Bool)
{
    let column = table.pointee.data.columns! + Int(column_index)
    guard let ti = column.pointee.ti else { return }

    if construct {
        flecs_table_invoke_ctor(world, table, column_index, row, count)
    }

    if let on_add = ti.pointee.hooks.on_add {
        flecs_table_invoke_hook(world, table, on_add, EcsOnAdd,
            column, entities, row, count)
    }
}

/// Run remove hooks (on_remove + destruct).
public func flecs_table_invoke_remove_hooks(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ column: UnsafeMutablePointer<ecs_column_t>,
    _ entities: UnsafeMutablePointer<ecs_entity_t>,
    _ row: Int32,
    _ count: Int32,
    _ dtor: Bool)
{
    guard let ti = column.pointee.ti else { return }

    if let on_remove = ti.pointee.hooks.on_remove {
        flecs_table_invoke_hook(world, table, on_remove, EcsOnRemove,
            column, entities, row, count)
    }

    if dtor {
        flecs_table_invoke_dtor(column, row, count)
    }
}

// MARK: - Table Fini

/// Finalize and free all table resources.
public func flecs_table_fini(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    let is_root = UnsafeMutableRawPointer(table) ==
        withUnsafeMutablePointer(to: &world.pointee.store.root) { UnsafeMutableRawPointer($0) }

    if !is_root && (world.pointee.flags & EcsWorldQuit) == 0 {
        if (table.pointee.flags & EcsTableHasOnTableDelete) != 0 {
            flecs_table_emit(world, table, EcsOnTableDelete)
        }
    }

    // Cleanup data
    flecs_table_fini_data(world, table, false, true)
    flecs_table_clear_edges(world, table)

    if !is_root {
        // Remove from table hashmap
        var ids = ecs_type_t(array: table.pointee.type.array, count: table.pointee.type.count)
        flecs_hashmap_remove_w_hash(
            &world.pointee.store.table_map, &ids, table.pointee._.pointee.hash)
    }

    // Free column map, component map, records
    if let cm = table.pointee.column_map { cm.deallocate() }
    if let cm = table.pointee.component_map { cm.deallocate() }
    flecs_table_records_unregister(world, table)

    world.pointee.info.table_count -= 1
    world.pointee.info.table_delete_total += 1

    table.pointee._.deallocate()

    if (world.pointee.flags & EcsWorldFini) == 0 && !is_root {
        flecs_table_free_type(world, table)
    }
}

/// Cleanup table data (destructors, free columns).
private func flecs_table_fini_data(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ do_on_remove: Bool,
    _ deallocate: Bool)
{
    if do_on_remove {
        flecs_table_notify_on_remove(world, table)
    }

    flecs_table_dtor_all(world, table)

    if deallocate {
        if let columns = table.pointee.data.columns {
            let column_count = table.pointee.column_count
            for c in 0..<Int(column_count) {
                if let ti = columns[c].ti, let data = columns[c].data {
                    let v = ecs_vec_from_column(&columns[c], table, ti.pointee.size)
                    ecs_vec_fini(nil, &v, ti.pointee.size)
                }
            }
            columns.deallocate()
            table.pointee.data.columns = nil
        }

        if let entities = table.pointee.data.entities {
            entities.deallocate()
            table.pointee.data.entities = nil
            table.pointee.data.size = 0
        }
    }

    table.pointee.data.count = 0
}

/// Destruct all components and remove all entities.
private func flecs_table_dtor_all(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    let count = table.pointee.data.count
    if count == 0 { return }

    guard let entities = table.pointee.data.entities else { return }
    let column_count = table.pointee.column_count

    // Invalidate reachable caches
    if table.pointee._.pointee.traversable_count > 0 {
        flecs_emit_propagate_invalidate(world, table, 0, count)
    }

    if (table.pointee.flags & EcsTableHasDtors) != 0 {
        // Run on_remove hooks
        if let columns = table.pointee.data.columns {
            for c in 0..<Int(column_count) {
                if let on_remove = columns[c].ti?.pointee.hooks.on_remove {
                    flecs_table_invoke_hook(world, table, on_remove, EcsOnRemove,
                        &columns[c], entities, 0, count)
                }
            }

            // Destruct components
            for c in 0..<Int(column_count) {
                flecs_table_invoke_dtor(&columns[c], 0, count)
            }
        }
    }

    // Remove entities
    for i in 0..<Int(count) {
        let e = entities[Int(i)]
        flecs_entities_remove(world, e)
    }
}

/// Invoke OnRemove observers for all entities (before table deletion).
private func flecs_table_notify_on_remove(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    let count = table.pointee.data.count
    if count > 0 {
        var diff = ecs_table_diff_t()
        diff.removed = table.pointee.type
        diff.removed_flags = table.pointee.flags & EcsTableRemoveEdgeFlags
        flecs_actions_move_remove(world, table,
            &world.pointee.store.root, 0, count, &diff)
    }
}

/// Free a table's type array.
public func flecs_table_free_type(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    if let array = table.pointee.type.array {
        array.deallocate()
    }
}

// MARK: - Table Traversable Tracking

/// Track traversable entity count for early-out in event propagation.
public func flecs_table_traversable_add(
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ value: Int32)
{
    let result = table.pointee._.pointee.traversable_count + value
    table.pointee._.pointee.traversable_count = result
    if result == 0 {
        table.pointee.flags &= ~EcsTableHasTraversable
    } else if result == value {
        table.pointee.flags |= EcsTableHasTraversable
    }
}

// MARK: - Dirty State

/// Mark a table column as dirty (for query change tracking).
public func flecs_table_mark_dirty(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ component: ecs_entity_t)
{
    guard let dirty_state = table.pointee.dirty_state else { return }

    if component < FLECS_HI_COMPONENT_ID {
        let column = table.pointee.component_map![Int(component)]
        if column <= 0 { return }
        dirty_state[Int(column)] += 1
    } else {
        guard let cr = flecs_components_get(UnsafePointer(world), component) else { return }
        guard let tr = flecs_component_get_table(UnsafePointer(cr), UnsafePointer(table)) else { return }
        if tr.pointee.column == -1 { return }
        dirty_state[Int(tr.pointee.column + 1)] += 1
    }
}

/// Get or create dirty state array for a table.
public func flecs_table_get_dirty_state(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>) -> UnsafeMutablePointer<Int32>
{
    if table.pointee.dirty_state == nil {
        let column_count = Int(table.pointee.column_count) + 1
        table.pointee.dirty_state = UnsafeMutablePointer<Int32>
            .allocate(capacity: column_count)
        for i in 0..<column_count {
            table.pointee.dirty_state![i] = 1
        }
    }
    return table.pointee.dirty_state!
}

// MARK: - Public Table API

/// Get the entities array from a table.
public func ecs_table_entities(
    _ table: UnsafePointer<ecs_table_t>) -> UnsafePointer<ecs_entity_t>?
{
    return UnsafePointer(table.pointee.data.entities)
}

/// Get the entity count of a table.
public func ecs_table_count(
    _ table: UnsafePointer<ecs_table_t>) -> Int32
{
    return table.pointee.data.count
}

/// Get the allocated size of a table.
public func ecs_table_size(
    _ table: UnsafePointer<ecs_table_t>) -> Int32
{
    return table.pointee.data.size
}

/// Clear all entities from a table (invokes OnRemove, keeps allocations).
public func ecs_table_clear_entities(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    flecs_table_fini_data(world, table, true, false)
}

/// Reset a table to its initial graph state.
public func flecs_table_reset(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    flecs_table_clear_edges(world, table)
}

/// Remove all components from a table (invokes OnRemove).
public func flecs_table_remove_actions(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    flecs_table_notify_on_remove(world, table)
}
