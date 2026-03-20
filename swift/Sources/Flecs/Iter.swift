// Iter.swift - 1:1 translation of flecs iter.c
// Iterator API: init, fini, field access, variables, pagination, workers

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


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
    if ptr != nil {
        ecs_os_free(ptr!)
    }
}


/// Initialize an iterator, optionally allocating field arrays.
public func flecs_iter_init(
    _ world: UnsafeRawPointer?,
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ alloc_resources: Bool)
{
    if alloc_resources && it.pointee.field_count > 0 {
        let count = Int(it.pointee.field_count)
        it.pointee.ids = ecs_os_calloc_n(ecs_id_t.self, Int32(count))!
        it.pointee.sources = ecs_os_calloc_n(ecs_entity_t.self, Int32(count))!
        it.pointee.trs = ecs_os_calloc_n(UnsafePointer<ecs_table_record_t>?.self, Int32(count))!
    }
}

/// Finalize an iterator, releasing resources.
public func ecs_iter_fini(
    _ it: UnsafeMutablePointer<ecs_iter_t>)
{
    if it.pointee.fini != nil {
        it.pointee.fini!(it)
    }

    it.pointee.flags &= ~EcsIterIsValid
}


/// Get a pointer to field data for the current iterator result.
public func ecs_field_w_size(
    _ it: UnsafePointer<ecs_iter_t>,
    _ size: Int,
    _ index: Int8) -> UnsafeMutableRawPointer?
{
    if (it.pointee.flags & EcsIterIsValid) == 0 { return nil }
    if !(index >= 0 && index < it.pointee.field_count) { return nil }
    if size == 0 { return nil }

    // If ptrs array is populated, use it directly
    if it.pointee.ptrs != nil {
        return it.pointee.ptrs![Int(index)]
    }

    // Otherwise resolve from table record
    if it.pointee.trs == nil || it.pointee.trs![Int(index)] == nil {
        return nil
    }
    let tr = it.pointee.trs![Int(index)]!

    var table: UnsafeMutablePointer<ecs_table_t>?
    var row: Int32 = 0

    let src = it.pointee.sources![Int(index)]
    if src == 0 {
        table = it.pointee.table
        row = it.pointee.offset
    } else {
        let r = flecs_entities_get(
            UnsafePointer(it.pointee.real_world!.assumingMemoryBound(
                to: ecs_world_t.self)), src)
        if r == nil { return nil }
        table = r!.pointee.table
        row = ECS_RECORD_TO_ROW(r!.pointee.row)
    }

    if table == nil { return nil }

    let column_index = tr.pointee.column
    if !(column_index >= 0 && column_index < table!.pointee.column_count) { return nil }

    let data = table!.pointee.data.columns![Int(column_index)].data
    if data == nil { return nil }
    return data! + Int(row) * size
}

/// Get a pointer to a specific row in a sparse field.
public func ecs_field_at_w_size(
    _ it: UnsafePointer<ecs_iter_t>,
    _ size: Int,
    _ index: Int8,
    _ row: Int32) -> UnsafeMutableRawPointer?
{
    if (it.pointee.flags & EcsIterIsValid) == 0 { return nil }
    if !(index >= 0 && index < it.pointee.field_count) { return nil }

    var cr: UnsafeMutablePointer<ecs_component_record_t>?
    if it.pointee.trs != nil && it.pointee.trs![Int(index)] != nil {
        cr = it.pointee.trs![Int(index)]!.pointee.hdr.cr
    } else {
        cr = flecs_components_get(
            UnsafePointer(it.pointee.real_world!.assumingMemoryBound(
                to: ecs_world_t.self)),
            it.pointee.ids![Int(index)])
    }

    if cr == nil { return nil }

    var src = it.pointee.sources![Int(index)]
    if src == 0 {
        let entities = it.pointee.table?.pointee.data.entities
        if entities == nil { return nil }
        src = entities![Int(row) + Int(it.pointee.offset)]
    }

    return flecs_sparse_get(cr!.pointee.sparse, Int32(size), src)
}


/// Check if a field is read-only.
public func ecs_field_is_readonly(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> Bool
{
    if (it.pointee.flags & EcsIterIsValid) == 0 { return false }
    if it.pointee.query == nil { return false }
    if it.pointee.query!.pointee.terms == nil { return false }
    if !(index >= 0 && index < it.pointee.field_count) { return false }

    let term = it.pointee.query!.pointee.terms![Int(index)]
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
    if (it.pointee.flags & EcsIterIsValid) == 0 { return false }
    if it.pointee.query == nil { return false }
    if it.pointee.query!.pointee.terms == nil { return false }
    if !(index >= 0 && index < it.pointee.field_count) { return false }
    return it.pointee.query!.pointee.terms![Int(index)].inout == EcsOut
}

/// Check if a field is set (matched by the query).
public func ecs_field_is_set(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> Bool
{
    if !(index >= 0 && index < it.pointee.field_count) { return false }
    return (it.pointee.set_fields & (1 << UInt32(index))) != 0
}

/// Check if a field is self (not inherited from another entity).
public func ecs_field_is_self(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> Bool
{
    if !(index >= 0 && index < it.pointee.field_count) { return false }
    return it.pointee.sources == nil || it.pointee.sources![Int(index)] == 0
}

/// Get the id matched for a field.
public func ecs_field_id(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> ecs_id_t
{
    if !(index >= 0 && index < it.pointee.field_count) { return 0 }
    return it.pointee.ids![Int(index)]
}

/// Get the column index for a field.
public func ecs_field_column(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> Int32
{
    if !(index >= 0 && index < it.pointee.field_count) { return -1 }
    if it.pointee.trs == nil || it.pointee.trs![Int(index)] == nil { return -1 }
    let tr = it.pointee.trs![Int(index)]!
    return Int32(tr.pointee.index)
}

/// Get the source entity for a field.
public func ecs_field_src(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> ecs_entity_t
{
    if !(index >= 0 && index < it.pointee.field_count) { return 0 }
    if it.pointee.sources == nil { return 0 }
    return it.pointee.sources![Int(index)]
}

/// Get the size of a field's component.
public func ecs_field_size(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int8) -> Int
{
    if !(index >= 0 && index < it.pointee.field_count) { return 0 }
    if it.pointee.sizes == nil { return 0 }
    return Int(it.pointee.sizes![Int(index)])
}


/// Get a string representation of the current iterator state.
public func ecs_iter_str(
    _ it: UnsafePointer<ecs_iter_t>) -> UnsafeMutablePointer<CChar>?
{
    if (it.pointee.flags & EcsIterIsValid) == 0 { return nil }
    if it.pointee.world == nil { return nil }
    let w = it.pointee.world!.assumingMemoryBound(to: ecs_world_t.self)

    var buf = ecs_strbuf_t()

    if it.pointee.field_count > 0 {
        ecs_strbuf_appendstr(&buf, "id:  ")
        for i in 0..<Int(it.pointee.field_count) {
            if i > 0 { ecs_strbuf_appendstr(&buf, ",") }
            let str = ecs_id_str(UnsafePointer(w), it.pointee.ids![i])
            if str != nil {
                ecs_strbuf_appendstr(&buf, str!)
                ecs_os_free(UnsafeMutableRawPointer(mutating: str!))
            }
        }
        ecs_strbuf_appendstr(&buf, "\n")

        ecs_strbuf_appendstr(&buf, "src: ")
        for i in 0..<Int(it.pointee.field_count) {
            if i > 0 { ecs_strbuf_appendstr(&buf, ",") }
            let src = it.pointee.sources != nil ? it.pointee.sources![i] : 0
            let str = ecs_get_path(UnsafePointer(w), src)
            if str != nil {
                ecs_strbuf_appendstr(&buf, str!)
                ecs_os_free(UnsafeMutableRawPointer(mutating: str!))
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
            if it.pointee.entities != nil {
                let str = ecs_get_path(UnsafePointer(w), it.pointee.entities![i])
                if str != nil {
                    ecs_strbuf_appendstr(&buf, "    - ")
                    ecs_strbuf_appendstr(&buf, str!)
                    ecs_strbuf_appendstr(&buf, "\n")
                    ecs_os_free(UnsafeMutableRawPointer(mutating: str!))
                }
            }
        }
    }

    return ecs_strbuf_get(&buf)
}


/// Advance iterator to next result (generic, calls stored next callback).
public func ecs_iter_next(
    _ iter: UnsafeMutablePointer<ecs_iter_t>) -> Bool
{
    if iter.pointee.next == nil { return false }
    return iter.pointee.next!(iter)
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


/// Get the number of variables in the iterator's query.
public func ecs_iter_get_var_count(
    _ it: UnsafePointer<ecs_iter_t>) -> Int32
{
    if it.pointee.query != nil {
        return it.pointee.query!.pointee.var_count
    }
    return 1
}

/// Get the name of a variable.
public func ecs_iter_get_var_name(
    _ it: UnsafePointer<ecs_iter_t>,
    _ var_id: Int32) -> UnsafePointer<CChar>?
{
    if var_id == 0 { return "this".withCString { strdup($0) } }
    if it.pointee.query == nil { return nil }
    if var_id >= it.pointee.query!.pointee.var_count { return nil }
    if it.pointee.query!.pointee.vars == nil { return nil }
    return it.pointee.query!.pointee.vars![Int(var_id)]
}

/// Get the vars array from an iterator.
public func ecs_iter_get_vars(
    _ it: UnsafePointer<ecs_iter_t>) -> UnsafeMutablePointer<ecs_var_t>?
{
    if it.pointee.query == nil { return nil }
    if it.pointee.chain_it != nil {
        return ecs_iter_get_vars(UnsafePointer(it.pointee.chain_it!))
    }
    return it.pointee.priv_.iter.query.vars
}

/// Get a variable's entity value.
public func ecs_iter_get_var(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32) -> ecs_entity_t
{
    if !(var_id >= 0 && var_id < ecs_iter_get_var_count(UnsafePointer(it))) { return 0 }
    let vars = ecs_iter_get_vars(UnsafePointer(it))
    if vars == nil { return 0 }

    let e = vars![Int(var_id)].entity
    if e != 0 { return e }

    // Try to get entity from table
    var table = vars![Int(var_id)].range.table
    if table == nil && var_id == 0 {
        table = it.pointee.table
    }
    if table == nil { return 0 }

    if vars![Int(var_id)].range.count == 1 || ecs_table_count(UnsafePointer(table!)) == 1 {
        return table!.pointee.data.entities![Int(vars![Int(var_id)].range.offset)]
    }

    return 0
}

/// Get a variable as a table.
public func ecs_iter_get_var_as_table(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32) -> UnsafeMutablePointer<ecs_table_t>?
{
    if !(var_id >= 0 && var_id < ecs_iter_get_var_count(UnsafePointer(it))) { return nil }
    let vars = ecs_iter_get_vars(UnsafePointer(it))
    if vars == nil { return nil }

    var table = vars![Int(var_id)].range.table
    if table == nil && var_id == 0 {
        table = it.pointee.table
    }

    if table == nil {
        let e = vars![Int(var_id)].entity
        if e != 0 {
            let r = flecs_entities_get(
                UnsafePointer(it.pointee.real_world!.assumingMemoryBound(
                    to: ecs_world_t.self)), e)
            if r != nil {
                let t = r!.pointee.table
                if t != nil {
                    if ecs_table_count(UnsafePointer(t!)) == 1 { return t }
                }
            }
        }
        return nil
    }

    if vars![Int(var_id)].range.offset != 0 { return nil }
    let count = vars![Int(var_id)].range.count
    if count == 0 || ecs_table_count(UnsafePointer(table!)) == count { return table }
    return nil
}

/// Get a variable as a table range.
public func ecs_iter_get_var_as_range(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32) -> ecs_table_range_t
{
    if !(var_id >= 0 && var_id < ecs_iter_get_var_count(UnsafePointer(it))) {
        return ecs_table_range_t()
    }
    let vars = ecs_iter_get_vars(UnsafePointer(it))
    if vars == nil {
        return ecs_table_range_t()
    }

    var table = vars![Int(var_id)].range.table
    if table == nil && var_id == 0 {
        table = it.pointee.table
    }

    if table == nil {
        let e = vars![Int(var_id)].entity
        if e != 0 {
            let r = flecs_entities_get(
                UnsafePointer(it.pointee.real_world!.assumingMemoryBound(
                    to: ecs_world_t.self)), e)
            if r != nil {
                return ecs_table_range_t(
                    table: r!.pointee.table,
                    offset: ECS_RECORD_TO_ROW(r!.pointee.row),
                    count: 1)
            }
        }
        return ecs_table_range_t()
    }

    var result = ecs_table_range_t()
    result.table = table
    result.offset = vars![Int(var_id)].range.offset
    result.count = vars![Int(var_id)].range.count
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
    if it.pointee.chain_it != nil {
        ecs_iter_set_var(it.pointee.chain_it!, var_id, entity)
        return
    }

    if !(var_id >= 0 && var_id < ecs_iter_get_var_count(UnsafePointer(it))) { return }
    if entity == 0 { return }
    if (it.pointee.flags & EcsIterIsValid) != 0 { return }
    let vars = ecs_iter_get_vars(UnsafePointer(it))
    if vars == nil { return }

    vars![Int(var_id)].entity = entity

    let r = flecs_entities_get(
        UnsafePointer(it.pointee.real_world!.assumingMemoryBound(
            to: ecs_world_t.self)), entity)
    if r != nil {
        vars![Int(var_id)].range.table = r!.pointee.table
        vars![Int(var_id)].range.offset = ECS_RECORD_TO_ROW(r!.pointee.row)
        vars![Int(var_id)].range.count = 1
    } else {
        vars![Int(var_id)].range = ecs_table_range_t()
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
    if it.pointee.chain_it != nil {
        ecs_iter_set_var_as_range(it.pointee.chain_it!, var_id, range)
        return
    }

    if !(var_id >= 0 && var_id < ecs_iter_get_var_count(UnsafePointer(it))) { return }
    if range.pointee.table == nil { return }
    if (it.pointee.flags & EcsIterIsValid) != 0 { return }
    let vars = ecs_iter_get_vars(UnsafePointer(it))
    if vars == nil { return }

    vars![Int(var_id)].range = range.pointee

    if range.pointee.count == 1 {
        vars![Int(var_id)].entity =
            range.pointee.table!.pointee.data.entities![Int(range.pointee.offset)]
    } else {
        vars![Int(var_id)].entity = 0
    }

    it.pointee.constrained_vars |= UInt64(1 << var_id)
}

/// Check if a variable is constrained.
public func ecs_iter_var_is_constrained(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ var_id: Int32) -> Bool
{
    if it.pointee.chain_it != nil {
        return ecs_iter_var_is_constrained(it.pointee.chain_it!, var_id)
    }
    return (it.pointee.constrained_vars & UInt64(1 << var_id)) != 0
}

/// Get the group id for the current iterator result.
public func ecs_iter_get_group(
    _ it: UnsafePointer<ecs_iter_t>) -> UInt64
{
    if it.pointee.chain_it != nil {
        return ecs_iter_get_group(UnsafePointer(it.pointee.chain_it!))
    }
    // Would look up group from qit->group->info.id
    return 0
}


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
        if it == nil || it!.pointee.chain_it == nil { return }
        ecs_iter_fini(it!.pointee.chain_it!)
    }
    result.chain_it = UnsafeMutablePointer(mutating: it)

    return result
}

/// Advance a page iterator.
public func ecs_page_next(
    _ it: UnsafeMutablePointer<ecs_iter_t>?) -> Bool
{
    if it == nil || it!.pointee.chain_it == nil { return false }
    let chain_it = it!.pointee.chain_it!

    while true {
        if !ecs_iter_next(chain_it) { return false }

        var page = it!.pointee.priv_.iter.page
        let count = chain_it.pointee.count

        // Copy public fields from chain
        it!.pointee.table = chain_it.pointee.table
        it!.pointee.count = chain_it.pointee.count
        it!.pointee.entities = chain_it.pointee.entities
        it!.pointee.offset = chain_it.pointee.offset

        if page.offset == 0 && page.limit == 0 {
            return it!.pointee.count > 0
        }

        if page.offset > 0 {
            if page.offset > count {
                page.offset -= count
                it!.pointee.priv_.iter.page = page
                it!.pointee.count = 0
                continue
            } else {
                it!.pointee.offset += page.offset
                it!.pointee.count -= page.offset
                it!.pointee.entities = it!.pointee.table!.pointee.data.entities!
                    + Int(it!.pointee.offset)
                page.offset = 0
            }
        }

        if page.remaining > 0 {
            if page.remaining > it!.pointee.count {
                page.remaining -= it!.pointee.count
            } else {
                it!.pointee.count = page.remaining
                page.remaining = 0
            }
        } else if page.limit > 0 {
            ecs_iter_fini(chain_it)
            return false
        }

        it!.pointee.priv_.iter.page = page
        if it!.pointee.count > 0 { return true }
    }
}


/// Create a worker iterator that splits results across workers.
public func ecs_worker_iter(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int32,
    _ count: Int32) -> ecs_iter_t
{
    if !(count > 0 && index >= 0 && index < count) { return ecs_iter_t() }

    var result = it.pointee
    result.priv_.stack_cursor = nil
    result.priv_.iter.worker.index = index
    result.priv_.iter.worker.count = count
    result.next = ecs_worker_next
    result.fini = { it in
        if it == nil || it!.pointee.chain_it == nil { return }
        ecs_iter_fini(it!.pointee.chain_it!)
    }
    result.chain_it = UnsafeMutablePointer(mutating: it)

    return result
}

/// Advance a worker iterator.
public func ecs_worker_next(
    _ it: UnsafeMutablePointer<ecs_iter_t>?) -> Bool
{
    if it == nil || it!.pointee.chain_it == nil { return false }
    let chain_it = it!.pointee.chain_it!

    let res_count = it!.pointee.priv_.iter.worker.count
    let res_index = it!.pointee.priv_.iter.worker.index

    while true {
        if !ecs_iter_next(chain_it) { return false }

        // Copy public fields
        it!.pointee.table = chain_it.pointee.table
        it!.pointee.count = chain_it.pointee.count
        it!.pointee.entities = chain_it.pointee.entities
        it!.pointee.offset = chain_it.pointee.offset

        let count = it!.pointee.count
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
            if it!.pointee.table == nil && res_index == 0 { return true }
            if it!.pointee.table == nil {
                ecs_iter_fini(chain_it)
                return false
            }
            continue
        }

        it!.pointee.count = per_worker
        it!.pointee.offset += first
        it!.pointee.frame_offset += first
        it!.pointee.entities = it!.pointee.table!.pointee.data.entities! + Int(it!.pointee.offset)

        return true
    }
}
