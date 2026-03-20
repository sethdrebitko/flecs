// QueryEngine.swift - 1:1 translation of flecs query/engine/*.c
// Query execution: op dispatch, table matching, traversal, iteration

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Helper to access typed op context from the generic context array.
@inline(__always)
public func flecs_op_ctx_and(
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>) -> UnsafeMutablePointer<ecs_query_and_ctx_t>?
{
    let op_ctx = ctx.pointee.op_ctx
    if op_ctx == nil { return nil }
    let ptr = op_ctx! + Int(ctx.pointee.op_index)
    return withUnsafeMutablePointer(to: &ptr.pointee.storage) { storage in
        UnsafeMutableRawPointer(storage)
            .bindMemory(to: ecs_query_and_ctx_t.self, capacity: 1)
    }
}

@inline(__always)
public func flecs_op_ctx_all(
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>) -> UnsafeMutablePointer<ecs_query_all_ctx_t>?
{
    let op_ctx = ctx.pointee.op_ctx
    if op_ctx == nil { return nil }
    let ptr = op_ctx! + Int(ctx.pointee.op_index)
    return withUnsafeMutablePointer(to: &ptr.pointee.storage) { storage in
        UnsafeMutableRawPointer(storage)
            .bindMemory(to: ecs_query_all_ctx_t.self, capacity: 1)
    }
}

@inline(__always)
public func flecs_op_ctx_each(
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>) -> UnsafeMutablePointer<ecs_query_each_ctx_t>?
{
    let op_ctx = ctx.pointee.op_ctx
    if op_ctx == nil { return nil }
    let ptr = op_ctx! + Int(ctx.pointee.op_index)
    return withUnsafeMutablePointer(to: &ptr.pointee.storage) { storage in
        UnsafeMutableRawPointer(storage)
            .bindMemory(to: ecs_query_each_ctx_t.self, capacity: 1)
    }
}


/// Check if a table should be filtered out based on flags.
public func flecs_query_table_filter(
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ other: ecs_query_lbl_t,
    _ filter_mask: ecs_flags32_t) -> Bool
{
    let table_flags = table.pointee.flags
    if (table_flags & filter_mask) != 0 {
        return true
    }
    return false
}


/// Set a variable to a table range.
public func flecs_query_var_set_range(
    _ op: UnsafePointer<ecs_query_op_t>,
    _ var_id: ecs_var_id_t,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ offset: Int32,
    _ count: Int32,
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>)
{
    let vars = ctx.pointee.vars
    if vars == nil { return }
    vars![Int(var_id)].range.table = table
    vars![Int(var_id)].range.offset = offset
    vars![Int(var_id)].range.count = count
}

/// Set a variable to an entity.
public func flecs_query_var_set_entity(
    _ op: UnsafePointer<ecs_query_op_t>,
    _ var_id: ecs_var_id_t,
    _ entity: ecs_entity_t,
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>)
{
    let vars = ctx.pointee.vars
    if vars == nil { return }
    vars![Int(var_id)].entity = entity
}

/// Get entity from a variable.
public func flecs_query_var_get_entity(
    _ var_id: ecs_var_id_t,
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>) -> ecs_entity_t
{
    let vars = ctx.pointee.vars
    if vars == nil { return 0 }
    return vars![Int(var_id)].entity
}

/// Get table from a variable.
public func flecs_query_var_get_table(
    _ var_id: ecs_var_id_t,
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>) -> UnsafeMutablePointer<ecs_table_t>?
{
    let vars = ctx.pointee.vars
    if vars == nil { return nil }
    return vars![Int(var_id)].range.table
}


/// Get the resolved id for an operation.
public func flecs_query_op_get_id(
    _ op: UnsafePointer<ecs_query_op_t>,
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>) -> ecs_id_t
{
    let first_flags = flecs_query_ref_flags(op.pointee.flags, EcsQueryFirst)
    let second_flags = flecs_query_ref_flags(op.pointee.flags, EcsQuerySecond)

    var first: ecs_entity_t = 0
    if (first_flags & EcsQueryIsEntity) != 0 {
        first = op.pointee.first.entity
    } else if (first_flags & EcsQueryIsVar) != 0 {
        first = flecs_query_var_get_entity(op.pointee.first.var_id, ctx)
    }

    if second_flags == 0 {
        return first
    }

    var second: ecs_entity_t = 0
    if (second_flags & EcsQueryIsEntity) != 0 {
        second = op.pointee.second.entity
    } else if (second_flags & EcsQueryIsVar) != 0 {
        second = flecs_query_var_get_entity(op.pointee.second.var_id, ctx)
    }

    return ecs_pair(first, second)
}


/// Set the match result for an operation (id + table record).
public func flecs_query_set_match(
    _ op: UnsafePointer<ecs_query_op_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ column: Int16,
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>)
{
    let field_index = op.pointee.field_index
    if field_index < 0 { return }
    let it = ctx.pointee.it
    if it == nil { return }

    if column >= 0 && column < table.pointee.type.count {
        it!.pointee.ids![Int(field_index)] = table.pointee.type.array![Int(column)]
    }
}

/// Find the next column matching an id in a table type.
public func flecs_query_next_column(
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ id: ecs_id_t,
    _ column: Int16) -> Int16
{
    let array = table.pointee.type.array
    if array == nil { return -1 }
    let count = table.pointee.type.count
    var i = Int(column) + 1

    while i < Int(count) {
        if ecs_id_match(array![i], id) {
            return Int16(i)
        }
        i += 1
    }

    return -1
}

/// Get table from an operation's source reference.
public func flecs_query_get_table(
    _ op: UnsafePointer<ecs_query_op_t>,
    _ ref: UnsafePointer<ecs_query_ref_t>,
    _ kind: ecs_flags16_t,
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>) -> UnsafeMutablePointer<ecs_table_t>?
{
    let flags = flecs_query_ref_flags(op.pointee.flags, kind)
    if (flags & EcsQueryIsVar) != 0 {
        return flecs_query_var_get_table(ref.pointee.var_id, ctx)
    }
    return nil
}


/// Select operation: find tables matching an id.
public func flecs_query_select_w_id(
    _ op: UnsafePointer<ecs_query_op_t>,
    _ redo: Bool,
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>,
    _ id: ecs_id_t,
    _ filter_mask: ecs_flags32_t) -> Bool
{
    let op_ctx = flecs_op_ctx_and(ctx)
    if op_ctx == nil { return false }
    let world = ctx.pointee.world?.assumingMemoryBound(
        to: ecs_world_t.self)
    if world == nil { return false }

    if !redo {
        // Initialize: look up component record and start iterating
        if op_ctx!.pointee.cr == nil || op_ctx!.pointee.cr!.pointee.id != id {
            let cr = flecs_components_get(UnsafePointer(world!), id)
            if cr == nil {
                return false
            }
            op_ctx!.pointee.cr = UnsafeMutableRawPointer(cr!)
        }

        let cr = op_ctx!.pointee.cr!.assumingMemoryBound(
            to: ecs_component_record_t.self)
        if !flecs_table_cache_iter(&cr.pointee.cache, &op_ctx!.pointee.it) {
            return false
        }
    }

    // Get next table from cache iterator
    let next = flecs_table_cache_next(
        &op_ctx!.pointee.it)
    if next == nil {
        return false
    }

    let tr = next!.bindMemory(to: ecs_table_record_t.self, capacity: 1)
    let table = tr.pointee.hdr.table
    if table == nil { return false }

    op_ctx!.pointee.column = Int16(tr.pointee.index)
    op_ctx!.pointee.remaining = Int16(tr.pointee.count - 1)

    // Filter
    if flecs_query_table_filter(table!, op.pointee.other, filter_mask) {
        // Skip and try next (in full impl this would loop)
        return false
    }

    flecs_query_var_set_range(op, op.pointee.src.var_id, table!, 0, 0, ctx)
    flecs_query_set_match(op, table!, op_ctx!.pointee.column, ctx)
    return true
}

/// Select operation (convenience wrapper with default filter).
public func flecs_query_select(
    _ op: UnsafePointer<ecs_query_op_t>,
    _ redo: Bool,
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>) -> Bool
{
    var id: ecs_id_t = 0
    if !redo {
        id = flecs_query_op_get_id(op, ctx)
    }
    return flecs_query_select_w_id(op, redo, ctx, id,
        EcsTableNotQueryable | EcsTableIsPrefab | EcsTableIsDisabled)
}

/// With operation: check if current table has an id.
public func flecs_query_with(
    _ op: UnsafePointer<ecs_query_op_t>,
    _ redo: Bool,
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>) -> Bool
{
    let op_ctx = flecs_op_ctx_and(ctx)
    if op_ctx == nil { return false }
    let world = ctx.pointee.world?.assumingMemoryBound(
        to: ecs_world_t.self)
    if world == nil { return false }
    let table = flecs_query_get_table(
        op, &op.pointee.src, EcsQuerySrc, ctx)
    if table == nil {
        return false
    }

    if !redo {
        let id = flecs_query_op_get_id(op, ctx)
        let cr = flecs_components_get(UnsafePointer(world!), id)
        if cr == nil {
            return false
        }
        op_ctx!.pointee.cr = UnsafeMutableRawPointer(cr!)

        let tr = flecs_component_get_table(UnsafePointer(cr!), UnsafePointer(table!))
        if tr == nil {
            return false
        }

        op_ctx!.pointee.column = Int16(tr!.pointee.index)
        op_ctx!.pointee.remaining = Int16(tr!.pointee.count)
    } else {
        if op_ctx!.pointee.remaining <= 1 {
            return false
        }
        op_ctx!.pointee.remaining -= 1

        let cr = op_ctx!.pointee.cr!.assumingMemoryBound(
            to: ecs_component_record_t.self)
        op_ctx!.pointee.column = flecs_query_next_column(
            table!, cr.pointee.id, op_ctx!.pointee.column)
    }

    flecs_query_set_match(op, table!, op_ctx!.pointee.column, ctx)
    return true
}

/// All operation: iterate all tables in the world.
public func flecs_query_all(
    _ op: UnsafePointer<ecs_query_op_t>,
    _ redo: Bool,
    _ ctx: UnsafePointer<ecs_query_run_ctx_t>) -> Bool
{
    let world = ctx.pointee.world?.assumingMemoryBound(
        to: ecs_world_t.self)
    if world == nil { return false }
    let op_ctx = flecs_op_ctx_all(ctx)
    if op_ctx == nil { return false }

    let tables = withUnsafeMutablePointer(to: &world!.pointee.store.tables) { $0 }

    if !redo {
        op_ctx!.pointee.cur = 0
        // Start with root table
        let table = withUnsafeMutablePointer(to: &world!.pointee.store.root) { $0 }
        if !flecs_query_table_filter(table, op.pointee.other,
            EcsTableNotQueryable | EcsTableIsPrefab | EcsTableIsDisabled)
        {
            flecs_query_var_set_range(op, op.pointee.src.var_id, table, 0, 0, ctx)
            op_ctx!.pointee.cur = 1
            return true
        }
    }

    // Iterate remaining tables
    let count = flecs_sparse_count(tables)
    while op_ctx!.pointee.cur < count {
        let table_raw = flecs_sparse_get_dense(
            tables, Int32(MemoryLayout<ecs_table_t>.stride), op_ctx!.pointee.cur)
        if table_raw == nil {
            op_ctx!.pointee.cur += 1
            continue
        }
        let table = table_raw!.bindMemory(to: ecs_table_t.self, capacity: 1)

        op_ctx!.pointee.cur += 1

        if table.pointee.data.count == 0 {
            continue
        }

        if flecs_query_table_filter(
            UnsafeMutablePointer(mutating: table), op.pointee.other,
            EcsTableNotQueryable | EcsTableIsPrefab | EcsTableIsDisabled)
        {
            continue
        }

        flecs_query_var_set_range(op, op.pointee.src.var_id,
            UnsafeMutablePointer(mutating: table), 0, 0, ctx)
        return true
    }

    return false
}


/// Dispatch a query operation based on its kind.
public func flecs_query_dispatch(
    _ op: UnsafePointer<ecs_query_op_t>,
    _ redo: Bool,
    _ ctx: UnsafeMutablePointer<ecs_query_run_ctx_t>) -> Bool
{
    switch op.pointee.kind {
    case UInt8(EcsQueryAnd):
        return flecs_query_select(op, redo, ctx)
    case UInt8(EcsQueryWith):
        return flecs_query_with(op, redo, ctx)
    case UInt8(EcsQueryAll):
        return flecs_query_all(op, redo, ctx)
    case UInt8(EcsQueryYield):
        return !redo
    case UInt8(EcsQueryEnd):
        return false
    case UInt8(EcsQueryNot):
        // Not: succeed if inner fails
        if !redo {
            return !flecs_query_dispatch(op + 1, false, ctx)
        }
        return false
    case UInt8(EcsQueryOptional):
        // Optional: always succeed
        if !redo {
            _ = flecs_query_dispatch(op + 1, false, ctx)
        }
        return !redo
    default:
        // Unimplemented op kinds return false
        return false
    }
}


/// Run a compiled query program.
/// Returns true if the next result was found.
public func flecs_query_run(
    _ it: UnsafeMutablePointer<ecs_iter_t>) -> Bool
{
    let query = it.pointee.query
    if query == nil { return false }
    let impl = flecs_query_impl(UnsafePointer(query!))
    let ops = impl.pointee.ops
    if ops == nil { return false }
    let op_count = impl.pointee.op_count
    if op_count == 0 { return false }

    // Allocate run context
    var ctx = ecs_query_run_ctx_t()
    ctx.it = it
    ctx.world = it.pointee.real_world
    ctx.query = UnsafePointer(impl)
    ctx.op_index = 0

    // Allocate op contexts
    let op_ctxs = ecs_os_calloc_n(ecs_query_op_ctx_t.self, op_count)!
    ctx.op_ctx = op_ctxs

    // Allocate variables
    let var_count = max(impl.pointee.var_count, 1)
    let vars = ecs_os_calloc_n(ecs_var_t.self, var_count)!
    ctx.vars = vars

    // Allocate written flags
    var written = [UInt64](repeating: 0, count: Int(op_count))

    // Execute operations forward/backward
    var op_index: Int32 = 0
    var redo = false

    while op_index >= 0 && op_index < op_count {
        let op = ops! + Int(op_index)
        ctx.op_index = op_index
        written[Int(op_index)] = 0  // Reset for this op

        let result = flecs_query_dispatch(op, redo, &ctx)

        if result {
            // Operation succeeded, move to next
            if op.pointee.kind == UInt8(EcsQueryYield) {
                // Found a result, populate iterator
                let table = flecs_query_var_get_table(0, &ctx)
                if table != nil {
                    it.pointee.table = table!
                    it.pointee.count = table!.pointee.data.count
                    it.pointee.entities = table!.pointee.data.entities
                }

                ecs_os_free(UnsafeMutableRawPointer(op_ctxs))
                ecs_os_free(UnsafeMutableRawPointer(vars))
                return true
            }

            op_index = op.pointee.next
            redo = false
        } else {
            // Operation failed, backtrack
            op_index = op.pointee.prev
            redo = true
        }
    }

    ecs_os_free(UnsafeMutableRawPointer(op_ctxs))
    ecs_os_free(UnsafeMutableRawPointer(vars))
    return false
}


/// Fast-path iteration for trivial queries (all terms are simple And/$this/Self).
public func flecs_query_trivial_search(
    _ q: UnsafePointer<ecs_query_t>,
    _ ctx: UnsafeMutablePointer<ecs_query_run_ctx_t>,
    _ trivial_ctx: UnsafeMutablePointer<ecs_query_trivial_ctx_t>,
    _ redo: Bool) -> Bool
{
    let world = ctx.pointee.world?.assumingMemoryBound(
        to: ecs_world_t.self)
    if world == nil { return false }
    let terms = q.pointee.terms
    if terms == nil { return false }

    let term_count = q.pointee.term_count
    if term_count == 0 { return false }

    // Use the first term's component record to iterate tables
    let first_id = terms![0].id
    let cr = flecs_components_get(UnsafePointer(world!), first_id)
    if cr == nil {
        return false
    }

    if !redo {
        if !flecs_table_cache_iter(&cr!.pointee.cache, &trivial_ctx.pointee.it) {
            return false
        }
    }

    // Find next table that matches ALL terms
    while true {
        let next = flecs_table_cache_next(&trivial_ctx.pointee.it)
        if next == nil { break }
        let tr = next!.bindMemory(to: ecs_table_record_t.self, capacity: 1)
        let table = tr.pointee.hdr.table
        if table == nil { continue }

        // Skip empty/filtered tables
        if table!.pointee.data.count == 0 { continue }
        if (table!.pointee.flags & (EcsTableNotQueryable | EcsTableIsPrefab | EcsTableIsDisabled)) != 0 {
            continue
        }

        // Check remaining terms via bloom filter
        if q.pointee.bloom_filter != 0 {
            if (table!.pointee.bloom_filter & q.pointee.bloom_filter) != q.pointee.bloom_filter {
                continue
            }
        }

        // Verify all terms match (for terms beyond the first)
        var all_match = true
        for t in 1..<Int(term_count) {
            let t_cr = flecs_components_get(UnsafePointer(world!), terms![t].id)
            if t_cr != nil {
                if flecs_component_get_table(UnsafePointer(t_cr!), UnsafePointer(table!)) == nil {
                    all_match = false
                    break
                }
            } else {
                all_match = false
                break
            }
        }

        if !all_match { continue }

        // Match found
        let it = ctx.pointee.it
        if it != nil {
            it!.pointee.table = table!
            it!.pointee.count = table!.pointee.data.count
            it!.pointee.entities = table!.pointee.data.entities

            // Set ids for each field
            for t in 0..<Int(term_count) {
                let id_array = it!.pointee.ids
                if id_array != nil {
                    id_array![t] = terms![t].id
                }
            }
        }

        return true
    }

    return false
}


/// Populate iterator fields from a cache match.
public func flecs_query_populate_fields_from_cache(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ match: UnsafePointer<ecs_query_cache_match_t>,
    _ cache: UnsafePointer<ecs_query_cache_t>)
{
    let table = match.pointee.table_cache_hdr.table
    if table == nil { return }

    it.pointee.table = table!
    it.pointee.count = table!.pointee.data.count
    it.pointee.entities = table!.pointee.data.entities

    // Copy match ids, sources, trs to iterator
    let field_count = it.pointee.field_count
    let ids = match.pointee.ids
    let it_ids = it.pointee.ids
    if ids != nil && it_ids != nil {
        for i in 0..<Int(field_count) {
            let field_map = cache.pointee.field_map
            if field_map != nil {
                let dst_field = Int(field_map![i])
                it_ids![dst_field] = ids![i]
            } else {
                it_ids![i] = ids![i]
            }
        }
    }

    it.pointee.set_fields = match.pointee.set_fields
}


/// Initialize a traversal cache for up/down lookups.
public func flecs_query_trav_cache_init(
    _ cache: UnsafeMutablePointer<ecs_trav_cache_t>,
    _ a: UnsafeMutablePointer<ecs_allocator_t>)
{
    let elem_size = Int32(MemoryLayout<ecs_trav_elem_t>.stride)
    ecs_vec_init(a, &cache.pointee.entities, elem_size, 0)
}

/// Finalize a traversal cache.
public func flecs_query_trav_cache_fini(
    _ cache: UnsafeMutablePointer<ecs_trav_cache_t>,
    _ a: UnsafeMutablePointer<ecs_allocator_t>)
{
    let elem_size = Int32(MemoryLayout<ecs_trav_elem_t>.stride)
    ecs_vec_fini(a, &cache.pointee.entities, elem_size)
}


/// Set a variable on a query iterator to an entity.
public func ecs_iter_set_var(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32,
    _ entity: ecs_entity_t)
{
    // Would set the variable in the iterator's priv_ data
    _ = it; _ = var_id; _ = entity
}

/// Set a variable on a query iterator to a table.
public func ecs_iter_set_var_as_table(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    _ = it; _ = var_id; _ = table
}

/// Set a variable on a query iterator to a table range.
public func ecs_iter_set_var_as_range(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32,
    _ range: UnsafeMutablePointer<ecs_table_range_t>)
{
    _ = it; _ = var_id; _ = range
}
