// Iter.swift - 1:1 translation of flecs iter.c
// Iterator API: init, fini, field access, variables, pagination, workers

import Foundation

// MARK: - Iterator Memory

/// Allocate zero-initialized memory from the iterator stack.
public func flecs_iter_calloc(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ size: ecs_size_t,
    _ align: ecs_size_t) -> UnsafeMutableRawPointer?
{
    return ecs_os_calloc(Int32(size))
}

/// Free iterator-allocated memory.
public func flecs_iter_free(
    _ ptr: UnsafeMutableRawPointer?,
    _ size: ecs_size_t)
{
    if let ptr = ptr {
        ecs_os_free(ptr)
    }
}

// MARK: - Iterator Init/Fini

/// Initialize an iterator, optionally allocating field arrays.
public func flecs_iter_init(
    _ world: UnsafeRawPointer?,
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ alloc_resources: Bool)
{
    if alloc_resources && it.pointee.field_count > 0 {
        let count = Int(it.pointee.field_count)
        it.pointee.ids = UnsafeMutablePointer<ecs_id_t>.allocate(capacity: count)
        it.pointee.ids!.initialize(repeating: 0, count: count)
        it.pointee.sources = UnsafeMutablePointer<ecs_entity_t>.allocate(capacity: count)
        it.pointee.sources!.initialize(repeating: 0, count: count)
        it.pointee.trs = UnsafeMutablePointer<UnsafePointer<ecs_table_record_t>?>
            .allocate(capacity: count)
        it.pointee.trs!.initialize(repeating: nil, count: count)
    }
}

/// Finalize an iterator, releasing resources.
public func ecs_iter_fini(
    _ it: UnsafeMutablePointer<ecs_iter_t>)
{
    if let fini = it.pointee.fini {
        fini(it)
    }

    it.pointee.flags &= ~EcsIterIsValid
}

// MARK: - Field Access

/// Get a pointer to field data for the current iterator result.
public func ecs_field_w_size(
    _ it: UnsafePointer<ecs_iter_t>,
    _ size: Int,
    _ index: Int8) -> UnsafeMutableRawPointer?
{
    guard (it.pointee.flags & EcsIterIsValid) != 0 else { return nil }
    guard index >= 0 && index < it.pointee.field_count else { return nil }
    guard size != 0 else { return nil }

    // If ptrs array is populated, use it directly
    if let ptrs = it.pointee.ptrs {
        return ptrs[Int(index)]
    }

    // Otherwise resolve from table record
    guard let trs = it.pointee.trs, let tr = trs[Int(index)] else {
        return nil
    }

    var table: UnsafeMutablePointer<ecs_table_t>?
    var row: Int32 = 0

    let src = it.pointee.sources![Int(index)]
    if src == 0 {
        table = it.pointee.table
        row = it.pointee.offset
    } else {
        guard let r = flecs_entities_get(
            UnsafePointer(it.pointee.real_world!.assumingMemoryBound(
                to: ecs_world_t.self)), src) else { return nil }
        table = r.pointee.table
        row = ECS_RECORD_TO_ROW(r.pointee.row)
    }

    guard let table = table else { return nil }

    let column_index = tr.pointee.column
    guard column_index >= 0 && column_index < table.pointee.column_count else { return nil }

    guard let data = table.pointee.data.columns![Int(column_index)].data else { return nil }
    return data + Int(row) * size
}

/// Get a pointer to a specific row in a sparse field.
public func ecs_field_at_w_size(
    _ it: UnsafePointer<ecs_iter_t>,
    _ size: Int,
    _ index: Int8,
    _ row: Int32) -> UnsafeMutableRawPointer?
{
    guard (it.pointee.flags & EcsIterIsValid) != 0 else { return nil }
    guard index >= 0 && index < it.pointee.field_count else { return nil }

    var cr: UnsafeMutablePointer<ecs_component_record_t>?
    if let trs = it.pointee.trs, let tr = trs[Int(index)] {
        cr = tr.pointee.hdr.cr
    } else {
        cr = flecs_components_get(
            UnsafePointer(it.pointee.real_world!.assumingMemoryBound(
                to: ecs_world_t.self)),
            it.pointee.ids![Int(index)])
    }

    guard let cr = cr else { return nil }

    var src = it.pointee.sources![Int(index)]
    if src == 0 {
        guard let entities = it.pointee.table?.pointee.data.entities else { return nil }
        src = entities[Int(row) + Int(it.pointee.offset)]
    }

    return flecs_sparse_get(cr.pointee.sparse, Int32(size), src)
}

// MARK: - Field Metadata

/// Check if a field is read-only.
public func ecs_field_is_readonly(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> Bool
{
    guard (it.pointee.flags & EcsIterIsValid) != 0 else { return false }
    guard let query = it.pointee.query else { return false }
    guard let terms = query.pointee.terms else { return false }
    guard index >= 0 && index < it.pointee.field_count else { return false }

    let term = terms[Int(index)]
    if term.inout == EcsIn { return true }
    if term.inout == EcsInOutDefault {
        if !ecs_term_match_this(&term) { return true }
        if (term.src.id & EcsSelf) == 0 { return true }
    }
    return false
}

/// Check if a field is write-only.
public func ecs_field_is_writeonly(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> Bool
{
    guard (it.pointee.flags & EcsIterIsValid) != 0 else { return false }
    guard let query = it.pointee.query else { return false }
    guard let terms = query.pointee.terms else { return false }
    guard index >= 0 && index < it.pointee.field_count else { return false }
    return terms[Int(index)].inout == EcsOut
}

/// Check if a field is set (matched by the query).
public func ecs_field_is_set(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> Bool
{
    guard index >= 0 && index < it.pointee.field_count else { return false }
    return (it.pointee.set_fields & (1 << UInt32(index))) != 0
}

/// Check if a field is self (not inherited from another entity).
public func ecs_field_is_self(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> Bool
{
    guard index >= 0 && index < it.pointee.field_count else { return false }
    return it.pointee.sources == nil || it.pointee.sources![Int(index)] == 0
}

/// Get the id matched for a field.
public func ecs_field_id(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> ecs_id_t
{
    guard index >= 0 && index < it.pointee.field_count else { return 0 }
    return it.pointee.ids![Int(index)]
}

/// Get the column index for a field.
public func ecs_field_column(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> Int32
{
    guard index >= 0 && index < it.pointee.field_count else { return -1 }
    guard let trs = it.pointee.trs, let tr = trs[Int(index)] else { return -1 }
    return Int32(tr.pointee.index)
}

/// Get the source entity for a field.
public func ecs_field_src(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> ecs_entity_t
{
    guard index >= 0 && index < it.pointee.field_count else { return 0 }
    guard let sources = it.pointee.sources else { return 0 }
    return sources[Int(index)]
}

/// Get the size of a field's component.
public func ecs_field_size(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> Int
{
    guard index >= 0 && index < it.pointee.field_count else { return 0 }
    guard let sizes = it.pointee.sizes else { return 0 }
    return Int(sizes[Int(index)])
}

// MARK: - Iterator String

/// Get a string representation of the current iterator state.
public func ecs_iter_str(
    _ it: UnsafePointer<ecs_iter_t>) -> UnsafeMutablePointer<CChar>?
{
    guard (it.pointee.flags & EcsIterIsValid) != 0 else { return nil }
    guard let world = it.pointee.world else { return nil }
    let w = world.assumingMemoryBound(to: ecs_world_t.self)

    var buf = ecs_strbuf_t()

    if it.pointee.field_count > 0 {
        ecs_strbuf_appendstr(&buf, "id:  ")
        for i in 0..<Int(it.pointee.field_count) {
            if i > 0 { ecs_strbuf_appendstr(&buf, ",") }
            if let str = ecs_id_str(UnsafePointer(w), it.pointee.ids![i]) {
                ecs_strbuf_appendstr(&buf, str)
                ecs_os_free(UnsafeMutableRawPointer(mutating: str))
            }
        }
        ecs_strbuf_appendstr(&buf, "\n")

        ecs_strbuf_appendstr(&buf, "src: ")
        for i in 0..<Int(it.pointee.field_count) {
            if i > 0 { ecs_strbuf_appendstr(&buf, ",") }
            let src = it.pointee.sources != nil ? it.pointee.sources![i] : 0
            if let str = ecs_get_path(UnsafePointer(w), src) {
                ecs_strbuf_appendstr(&buf, str)
                ecs_os_free(UnsafeMutableRawPointer(mutating: str))
            }
        }
        ecs_strbuf_appendstr(&buf, "\n")

        ecs_strbuf_appendstr(&buf, "set: ")
        for i in 0..<Int(it.pointee.field_count) {
            if i > 0 { ecs_strbuf_appendstr(&buf, ",") }
            ecs_strbuf_appendstr(&buf, ecs_field_is_set(it, Int8(i)) ? "true" : "false")
        }
        ecs_strbuf_appendstr(&buf, "\n")
    }

    if it.pointee.count > 0 {
        ecs_strbuf_appendstr(&buf, "this:\n")
        for i in 0..<Int(it.pointee.count) {
            if let entities = it.pointee.entities {
                if let str = ecs_get_path(UnsafePointer(w), entities[i]) {
                    ecs_strbuf_appendstr(&buf, "    - ")
                    ecs_strbuf_appendstr(&buf, str)
                    ecs_strbuf_appendstr(&buf, "\n")
                    ecs_os_free(UnsafeMutableRawPointer(mutating: str))
                }
            }
        }
    }

    return ecs_strbuf_get(&buf)
}

// MARK: - Iterator Navigation

/// Advance iterator to next result (generic, calls stored next callback).
public func ecs_iter_next(
    _ iter: UnsafeMutablePointer<ecs_iter_t>) -> Bool
{
    guard let next = iter.pointee.next else { return false }
    return next(iter)
}

/// Count total entities matched by an iterator (consumes it).
public func ecs_iter_count(
    _ it: UnsafeMutablePointer<ecs_iter_t>) -> Int32
{
    it.pointee.flags |= EcsIterNoData
    var count: Int32 = 0
    while ecs_iter_next(it) {
        count += it.pointee.count
    }
    return count
}

/// Get the first entity matched by an iterator (consumes it).
public func ecs_iter_first(
    _ it: UnsafeMutablePointer<ecs_iter_t>) -> ecs_entity_t
{
    it.pointee.flags |= EcsIterNoData
    if ecs_iter_next(it) {
        let result = it.pointee.entities![0]
        ecs_iter_fini(it)
        return result
    }
    return 0
}

/// Check if an iterator has any results (consumes it).
public func ecs_iter_is_true(
    _ it: UnsafeMutablePointer<ecs_iter_t>) -> Bool
{
    it.pointee.flags |= EcsIterNoData
    let result = ecs_iter_next(it)
    if result { ecs_iter_fini(it) }
    return result
}

/// Skip the current result during iteration (for change detection).
public func ecs_iter_skip(
    _ it: UnsafeMutablePointer<ecs_iter_t>)
{
    it.pointee.flags |= EcsIterSkip
}

// MARK: - Iterator Variables

/// Get the number of variables in the iterator's query.
public func ecs_iter_get_var_count(
    _ it: UnsafePointer<ecs_iter_t>) -> Int32
{
    if let query = it.pointee.query {
        return query.pointee.var_count
    }
    return 1
}

/// Get the name of a variable.
public func ecs_iter_get_var_name(
    _ it: UnsafePointer<ecs_iter_t>,
    _ var_id: Int32) -> UnsafePointer<CChar>?
{
    if var_id == 0 { return "this".withCString { strdup($0) } }
    guard let query = it.pointee.query else { return nil }
    guard var_id < query.pointee.var_count else { return nil }
    guard let vars = query.pointee.vars else { return nil }
    return vars[Int(var_id)]
}

/// Get the vars array from an iterator.
public func ecs_iter_get_vars(
    _ it: UnsafePointer<ecs_iter_t>) -> UnsafeMutablePointer<ecs_var_t>?
{
    guard it.pointee.query != nil else { return nil }
    if let chain = it.pointee.chain_it {
        return ecs_iter_get_vars(UnsafePointer(chain))
    }
    return it.pointee.priv_.iter.query.vars
}

/// Get a variable's entity value.
public func ecs_iter_get_var(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32) -> ecs_entity_t
{
    guard var_id >= 0 && var_id < ecs_iter_get_var_count(UnsafePointer(it)) else { return 0 }
    guard let vars = ecs_iter_get_vars(UnsafePointer(it)) else { return 0 }

    let e = vars[Int(var_id)].entity
    if e != 0 { return e }

    // Try to get entity from table
    var table = vars[Int(var_id)].range.table
    if table == nil && var_id == 0 {
        table = it.pointee.table
    }
    guard let table = table else { return 0 }

    if vars[Int(var_id)].range.count == 1 || ecs_table_count(UnsafePointer(table)) == 1 {
        return table.pointee.data.entities![Int(vars[Int(var_id)].range.offset)]
    }

    return 0
}

/// Get a variable as a table.
public func ecs_iter_get_var_as_table(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32) -> UnsafeMutablePointer<ecs_table_t>?
{
    guard var_id >= 0 && var_id < ecs_iter_get_var_count(UnsafePointer(it)) else { return nil }
    guard let vars = ecs_iter_get_vars(UnsafePointer(it)) else { return nil }

    var table = vars[Int(var_id)].range.table
    if table == nil && var_id == 0 {
        table = it.pointee.table
    }

    guard let table = table else {
        let e = vars[Int(var_id)].entity
        if e != 0 {
            if let r = flecs_entities_get(
                UnsafePointer(it.pointee.real_world!.assumingMemoryBound(
                    to: ecs_world_t.self)), e)
            {
                if let t = r.pointee.table {
                    if ecs_table_count(UnsafePointer(t)) == 1 { return t }
                }
            }
        }
        return nil
    }

    if vars[Int(var_id)].range.offset != 0 { return nil }
    let count = vars[Int(var_id)].range.count
    if count == 0 || ecs_table_count(UnsafePointer(table)) == count { return table }
    return nil
}

/// Get a variable as a table range.
public func ecs_iter_get_var_as_range(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32) -> ecs_table_range_t
{
    guard var_id >= 0 && var_id < ecs_iter_get_var_count(UnsafePointer(it)) else {
        return ecs_table_range_t()
    }
    guard let vars = ecs_iter_get_vars(UnsafePointer(it)) else {
        return ecs_table_range_t()
    }

    var table = vars[Int(var_id)].range.table
    if table == nil && var_id == 0 {
        table = it.pointee.table
    }

    if table == nil {
        let e = vars[Int(var_id)].entity
        if e != 0 {
            if let r = flecs_entities_get(
                UnsafePointer(it.pointee.real_world!.assumingMemoryBound(
                    to: ecs_world_t.self)), e)
            {
                return ecs_table_range_t(
                    table: r.pointee.table,
                    offset: ECS_RECORD_TO_ROW(r.pointee.row),
                    count: 1)
            }
        }
        return ecs_table_range_t()
    }

    var result = ecs_table_range_t()
    result.table = table
    result.offset = vars[Int(var_id)].range.offset
    result.count = vars[Int(var_id)].range.count
    if result.count == 0 {
        result.count = ecs_table_count(UnsafePointer(table!))
    }
    return result
}

/// Set a variable to an entity value.
public func ecs_iter_set_var(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32,
    _ entity: ecs_entity_t)
{
    if let chain = it.pointee.chain_it {
        ecs_iter_set_var(chain, var_id, entity)
        return
    }

    guard var_id >= 0 && var_id < ecs_iter_get_var_count(UnsafePointer(it)) else { return }
    guard entity != 0 else { return }
    guard (it.pointee.flags & EcsIterIsValid) == 0 else { return }
    guard let vars = ecs_iter_get_vars(UnsafePointer(it)) else { return }

    vars[Int(var_id)].entity = entity

    if let r = flecs_entities_get(
        UnsafePointer(it.pointee.real_world!.assumingMemoryBound(
            to: ecs_world_t.self)), entity)
    {
        vars[Int(var_id)].range.table = r.pointee.table
        vars[Int(var_id)].range.offset = ECS_RECORD_TO_ROW(r.pointee.row)
        vars[Int(var_id)].range.count = 1
    } else {
        vars[Int(var_id)].range = ecs_table_range_t()
    }

    it.pointee.constrained_vars |= UInt64(1 << var_id)
}

/// Set a variable to a table.
public func ecs_iter_set_var_as_table(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32,
    _ table: UnsafePointer<ecs_table_t>)
{
    var range = ecs_table_range_t()
    range.table = UnsafeMutablePointer(mutating: table)
    ecs_iter_set_var_as_range(it, var_id, &range)
}

/// Set a variable to a table range.
public func ecs_iter_set_var_as_range(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32,
    _ range: UnsafePointer<ecs_table_range_t>)
{
    if let chain = it.pointee.chain_it {
        ecs_iter_set_var_as_range(chain, var_id, range)
        return
    }

    guard var_id >= 0 && var_id < ecs_iter_get_var_count(UnsafePointer(it)) else { return }
    guard range.pointee.table != nil else { return }
    guard (it.pointee.flags & EcsIterIsValid) == 0 else { return }
    guard let vars = ecs_iter_get_vars(UnsafePointer(it)) else { return }

    vars[Int(var_id)].range = range.pointee

    if range.pointee.count == 1 {
        vars[Int(var_id)].entity =
            range.pointee.table!.pointee.data.entities![Int(range.pointee.offset)]
    } else {
        vars[Int(var_id)].entity = 0
    }

    it.pointee.constrained_vars |= UInt64(1 << var_id)
}

/// Check if a variable is constrained.
public func ecs_iter_var_is_constrained(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32) -> Bool
{
    if let chain = it.pointee.chain_it {
        return ecs_iter_var_is_constrained(chain, var_id)
    }
    return (it.pointee.constrained_vars & UInt64(1 << var_id)) != 0
}

/// Get the group id for the current iterator result.
public func ecs_iter_get_group(
    _ it: UnsafePointer<ecs_iter_t>) -> UInt64
{
    if let chain = it.pointee.chain_it {
        return ecs_iter_get_group(UnsafePointer(chain))
    }
    // Would look up group from qit->group->info.id
    return 0
}

// MARK: - Page Iterator

/// Create a paginated iterator (offset + limit).
public func ecs_page_iter(
    _ it: UnsafePointer<ecs_iter_t>,
    _ offset: Int32,
    _ limit: Int32) -> ecs_iter_t
{
    var result = it.pointee
    result.priv_.stack_cursor = nil

    result.priv_.iter.page.offset = offset
    result.priv_.iter.page.limit = limit
    result.priv_.iter.page.remaining = limit
    result.next = ecs_page_next
    result.fini = { it in
        guard let chain = it?.pointee.chain_it else { return }
        ecs_iter_fini(chain)
    }
    result.chain_it = UnsafeMutablePointer(mutating: it)

    return result
}

/// Advance a page iterator.
public func ecs_page_next(
    _ it: UnsafeMutablePointer<ecs_iter_t>?) -> Bool
{
    guard let it = it, let chain_it = it.pointee.chain_it else { return false }

    while true {
        if !ecs_iter_next(chain_it) { return false }

        var page = it.pointee.priv_.iter.page
        let count = chain_it.pointee.count

        // Copy public fields from chain
        it.pointee.table = chain_it.pointee.table
        it.pointee.count = chain_it.pointee.count
        it.pointee.entities = chain_it.pointee.entities
        it.pointee.offset = chain_it.pointee.offset

        if page.offset == 0 && page.limit == 0 {
            return it.pointee.count > 0
        }

        if page.offset > 0 {
            if page.offset > count {
                page.offset -= count
                it.pointee.priv_.iter.page = page
                it.pointee.count = 0
                continue
            } else {
                it.pointee.offset += page.offset
                it.pointee.count -= page.offset
                it.pointee.entities = it.pointee.table!.pointee.data.entities!
                    + Int(it.pointee.offset)
                page.offset = 0
            }
        }

        if page.remaining > 0 {
            if page.remaining > it.pointee.count {
                page.remaining -= it.pointee.count
            } else {
                it.pointee.count = page.remaining
                page.remaining = 0
            }
        } else if page.limit > 0 {
            ecs_iter_fini(chain_it)
            return false
        }

        it.pointee.priv_.iter.page = page
        if it.pointee.count > 0 { return true }
    }
}

// MARK: - Worker Iterator

/// Create a worker iterator that splits results across workers.
public func ecs_worker_iter(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int32,
    _ count: Int32) -> ecs_iter_t
{
    guard count > 0 && index >= 0 && index < count else { return ecs_iter_t() }

    var result = it.pointee
    result.priv_.stack_cursor = nil
    result.priv_.iter.worker.index = index
    result.priv_.iter.worker.count = count
    result.next = ecs_worker_next
    result.fini = { it in
        guard let chain = it?.pointee.chain_it else { return }
        ecs_iter_fini(chain)
    }
    result.chain_it = UnsafeMutablePointer(mutating: it)

    return result
}

/// Advance a worker iterator.
public func ecs_worker_next(
    _ it: UnsafeMutablePointer<ecs_iter_t>?) -> Bool
{
    guard let it = it, let chain_it = it.pointee.chain_it else { return false }

    let res_count = it.pointee.priv_.iter.worker.count
    let res_index = it.pointee.priv_.iter.worker.index

    while true {
        if !ecs_iter_next(chain_it) { return false }

        // Copy public fields
        it.pointee.table = chain_it.pointee.table
        it.pointee.count = chain_it.pointee.count
        it.pointee.entities = chain_it.pointee.entities
        it.pointee.offset = chain_it.pointee.offset

        let count = it.pointee.count
        var per_worker = count / res_count
        var first = per_worker * res_index
        let remainder = count - per_worker * res_count

        if remainder > 0 {
            if res_index < remainder {
                per_worker += 1
                first += res_index
            } else {
                first += remainder
            }
        }

        if per_worker == 0 {
            if it.pointee.table == nil && res_index == 0 { return true }
            if it.pointee.table == nil {
                ecs_iter_fini(chain_it)
                return false
            }
            continue
        }

        it.pointee.count = per_worker
        it.pointee.offset += first
        it.pointee.frame_offset += first
        it.pointee.entities = it.pointee.table!.pointee.data.entities! + Int(it.pointee.offset)

        return true
    }
}
