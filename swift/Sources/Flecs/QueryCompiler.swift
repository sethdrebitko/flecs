// QueryCompiler.swift - 1:1 translation of flecs query/compiler/compiler.c
// and query/compiler/compiler_term.c
// Query program compilation: variable management and op generation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Find a query variable by name and kind.
public func flecs_query_find_var_id(
    _ query: UnsafePointer<ecs_query_impl_t>,
    _ name: UnsafePointer<CChar>,
    _ kind: ecs_var_kind_t) -> ecs_var_id_t
{
    if kind == .table {
        if strcmp(name, EcsThisName) == 0 {
            if (query.pointee.pub.flags & EcsQueryHasTableThisVar) != 0 {
                return 0
            } else {
                return EcsVarNone
            }
        }

        if !flecs_name_index_is_init(&query.pointee.tvar_index) {
            return EcsVarNone
        }

        let index = flecs_name_index_find(&query.pointee.tvar_index, name, 0, 0)
        if index == 0 { return EcsVarNone }
        return flecs_utovar(index)
    }

    if kind == .entity {
        if !flecs_name_index_is_init(&query.pointee.evar_index) {
            return EcsVarNone
        }

        let index = flecs_name_index_find(&query.pointee.evar_index, name, 0, 0)
        if index == 0 { return EcsVarNone }
        return flecs_utovar(index)
    }

    // kind == .any: search entity first, then table
    let entity_id = flecs_query_find_var_id(query, name, .entity)
    if entity_id != EcsVarNone { return entity_id }
    return flecs_query_find_var_id(query, name, .table)
}


/// Add a variable to the query during compilation.
public func flecs_query_add_var(
    _ query: UnsafeMutablePointer<ecs_query_impl_t>,
    _ name: UnsafePointer<CChar>?,
    _ vars: UnsafeMutablePointer<ecs_vec_t>?,
    _ kind: ecs_var_kind_t) -> ecs_var_id_t
{
    var resolved_kind = kind

    // Check for lookup variables (contain '.')
    if name != nil {
        if strchr(name!, Int32(UInt8(ascii: "."))) != nil {
            resolved_kind = .entity  // Lookup vars are always entities
        }
    }

    // Check if variable already exists
    if name != nil {
        if resolved_kind == .any {
            var id = flecs_query_find_var_id(
                UnsafePointer(query), name!, .entity)
            if id != EcsVarNone { return id }
            id = flecs_query_find_var_id(
                UnsafePointer(query), name!, .table)
            if id != EcsVarNone { return id }
            resolved_kind = .table
        } else {
            let id = flecs_query_find_var_id(
                UnsafePointer(query), name!, resolved_kind)
            if id != EcsVarNone { return id }
        }
    }

    // Create new variable
    var result: ecs_var_id_t
    if vars != nil {
        let elem_size = Int32(MemoryLayout<ecs_query_var_t>.stride)
        let ptr_raw = ecs_vec_append(nil, vars!, elem_size)
        if ptr_raw == nil {
            return EcsVarNone
        }
        let ptr = ptr_raw!.bindMemory(to: ecs_query_var_t.self, capacity: 1)
        ptr.pointee = ecs_query_var_t()
        result = flecs_itovar(Int64(ecs_vec_count(vars!)))
        ptr.pointee.id = result
    } else {
        if query.pointee.var_count >= query.pointee.var_size {
            return EcsVarNone
        }
        let v = query.pointee.vars! + Int(query.pointee.var_count)
        v.pointee = ecs_query_var_t()
        result = flecs_itovar(Int64(query.pointee.var_count))
        v.pointee.id = result
        query.pointee.var_count += 1
    }

    // Set variable properties
    let v: UnsafeMutablePointer<ecs_query_var_t>
    if vars != nil {
        v = ecs_vec_first(vars!)!
            .bindMemory(to: ecs_query_var_t.self,
                       capacity: Int(ecs_vec_count(vars!))) + Int(result)
    } else {
        v = query.pointee.vars! + Int(result)
    }

    v.pointee.kind = Int8(resolved_kind.rawValue)
    v.pointee.name = name
    v.pointee.table_id = EcsVarNone
    v.pointee.base_id = 0
    v.pointee.lookup = nil

    // Register in name index
    if name != nil {
        let var_index: UnsafeMutablePointer<ecs_hashmap_t>
        if resolved_kind == .table {
            var_index = withUnsafeMutablePointer(to: &query.pointee.tvar_index) { $0 }
        } else {
            var_index = withUnsafeMutablePointer(to: &query.pointee.evar_index) { $0 }
        }
        flecs_name_index_init_if(var_index, nil)
        flecs_name_index_ensure(var_index, UInt64(v.pointee.id), name!, 0, 0)
        v.pointee.anonymous = name!.pointee == UInt8(ascii: "_")

        // Handle lookup variables (e.g. $this.wheel)
        let dot = strchr(name!, Int32(UInt8(ascii: ".")))
        if dot != nil {
            v.pointee.lookup = dot! + 1
        }
    }

    return result
}


/// Find the most specific variable (entity preferred over table when written).
public func flecs_query_most_specific_var(
    _ query: UnsafeMutablePointer<ecs_query_impl_t>,
    _ name: UnsafePointer<CChar>,
    _ kind: ecs_var_kind_t,
    _ ctx: UnsafeMutablePointer<ecs_query_compile_ctx_t>) -> ecs_var_id_t
{
    if kind == .table || kind == .entity {
        return flecs_query_find_var_id(UnsafePointer(query), name, kind)
    }

    let evar = flecs_query_find_var_id(UnsafePointer(query), name, .entity)
    if evar != EcsVarNone && flecs_query_is_written(evar, ctx.pointee.written) {
        return evar
    }

    let tvar = flecs_query_find_var_id(UnsafePointer(query), name, .table)
    if tvar != EcsVarNone && !flecs_query_is_written(tvar, ctx.pointee.written) {
        return tvar
    }

    return tvar != EcsVarNone ? tvar : evar
}


/// Insert an operation into the ops vector.
public func flecs_query_op_insert(
    _ op: UnsafePointer<ecs_query_op_t>,
    _ ctx: UnsafeMutablePointer<ecs_query_compile_ctx_t>) -> ecs_query_lbl_t
{
    let ops = ctx.pointee.ops
    if ops == nil { return -1 }
    let elem_size = Int32(MemoryLayout<ecs_query_op_t>.stride)
    let ptr_raw = ecs_vec_append(nil, ops!, elem_size)
    if ptr_raw == nil {
        return -1
    }
    let ptr = ptr_raw!.bindMemory(to: ecs_query_op_t.self, capacity: 1)
    ptr.pointee = op.pointee
    ptr.pointee.next = flecs_itolbl(Int64(ecs_vec_count(ops!)))
    return flecs_itolbl(Int64(ecs_vec_count(ops!)) - 1)
}


/// Compile a query into an executable program of operations.
/// This is the main entry point for the query compiler.
public func flecs_query_compile(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ stage: UnsafeMutableRawPointer?,
    _ impl: UnsafeMutablePointer<ecs_query_impl_t>) -> Int32
{
    let q = withUnsafeMutablePointer(to: &impl.pointee.pub) { $0 }
    let term_count = q.pointee.term_count
    if term_count == 0 { return 0 }

    // Initialize variables
    // The $this variable is always variable 0 for queries that match $this
    if (q.pointee.flags & EcsQueryMatchThis) != 0 {
        impl.pointee.var_count = 1
        impl.pointee.var_size = 1

        // Allocate vars array
        impl.pointee.vars = ecs_os_calloc_t(ecs_query_var_t.self)!
        impl.pointee.vars!.pointee = ecs_query_var_t()
        impl.pointee.vars![0].kind = Int8(ecs_var_kind_t.table.rawValue)
        impl.pointee.vars![0].name = EcsThisName.withCString { strdup($0) }
    }

    // Initialize compile context
    var ops_vec = ecs_vec_t()
    let elem_size = Int32(MemoryLayout<ecs_query_op_t>.stride)
    ecs_vec_init(nil, &ops_vec, elem_size, Int32(term_count) * 2)

    var ctx = ecs_query_compile_ctx_t()
    ctx.ops = withUnsafeMutablePointer(to: &ops_vec) { $0 }

    // Compile each term into operations
    let terms = q.pointee.terms
    if terms == nil {
        ecs_vec_fini(nil, &ops_vec, elem_size)
        return 0
    }

    for i in 0..<Int(term_count) {
        let term = terms![i]

        // Generate appropriate operation based on term properties
        var op = ecs_query_op_t()
        op.term_index = Int8(i)
        op.field_index = term.field_index

        // Select operation kind based on term flags and operator
        if (term.flags_ & EcsTermIsCacheable) != 0 &&
            q.pointee.cache_kind != EcsQueryCacheNone
        {
            op.kind = UInt8(EcsQueryCache)
        } else if (term.flags_ & EcsTermIsTrivial) != 0 {
            op.kind = UInt8(EcsQueryTriv)
        } else if term.oper == EcsNot {
            op.kind = UInt8(EcsQueryNot)
        } else if term.oper == EcsOptional {
            op.kind = UInt8(EcsQueryOptional)
        } else if term.oper == EcsOr {
            op.kind = UInt8(EcsQueryOr)
        } else if (term.src.id & EcsUp) != 0 {
            if (term.src.id & EcsSelf) != 0 {
                op.kind = UInt8(EcsQuerySelfUp)
            } else {
                op.kind = UInt8(EcsQueryUp)
            }
        } else {
            op.kind = UInt8(EcsQueryAnd)
        }

        // Set source reference
        if (term.src.id & EcsIsVariable) != 0 {
            op.flags |= UInt8(EcsQueryIsVar) << UInt8(EcsQuerySrc)
        } else if (term.src.id & EcsIsEntity) != 0 {
            op.flags |= UInt8(EcsQueryIsEntity) << UInt8(EcsQuerySrc)
            op.src.entity = ECS_TERM_REF_ID(&term.src)
        }

        // Set first reference
        if (term.first.id & EcsIsVariable) != 0 {
            op.flags |= UInt8(EcsQueryIsVar) << UInt8(EcsQueryFirst)
        } else if (term.first.id & EcsIsEntity) != 0 {
            op.flags |= UInt8(EcsQueryIsEntity) << UInt8(EcsQueryFirst)
            op.first.entity = ECS_TERM_REF_ID(&term.first)
        }

        // Set second reference
        if ecs_term_ref_is_set(&term.second) {
            if (term.second.id & EcsIsVariable) != 0 {
                op.flags |= UInt8(EcsQueryIsVar) << UInt8(EcsQuerySecond)
            } else if (term.second.id & EcsIsEntity) != 0 {
                op.flags |= UInt8(EcsQueryIsEntity) << UInt8(EcsQuerySecond)
                op.second.entity = ECS_TERM_REF_ID(&term.second)
            }
        }

        _ = flecs_query_op_insert(&op, &ctx)
    }

    // Add yield operation at the end
    var yield_op = ecs_query_op_t()
    yield_op.kind = UInt8(EcsQueryYield)
    _ = flecs_query_op_insert(&yield_op, &ctx)

    // Copy ops to query impl
    let op_count = ecs_vec_count(&ops_vec)
    if op_count > 0 {
        impl.pointee.ops = ecs_os_calloc_n(ecs_query_op_t.self, op_count)!
        let src = ecs_vec_first(&ops_vec)
        if src != nil {
            let src_typed = src!.bindMemory(to: ecs_query_op_t.self, capacity: Int(op_count))
            impl.pointee.ops!.update(from: src_typed, count: Int(op_count))
        }
        impl.pointee.op_count = op_count
    }

    ecs_vec_fini(nil, &ops_vec, elem_size)

    return 0
}


/// Finalize and validate a query (term validation, flag computation).
public func flecs_query_finalize_query(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ q: UnsafeMutablePointer<ecs_query_t>,
    _ desc: UnsafeMutablePointer<ecs_query_desc_t>) -> Int32
{
    let terms = q.pointee.terms
    if terms == nil { return -1 }
    let term_count = Int(q.pointee.term_count)
    if term_count == 0 { return -1 }

    // Compute query flags from terms
    var match_this = false
    var match_only_self = true
    var has_cacheable = false
    var is_cacheable = true

    for i in 0..<term_count {
        let term = terms![i]

        // Check if any term matches $this
        if (term.src.id & EcsIsVariable) != 0 {
            if ECS_TERM_REF_ID(&term.src) == EcsThis {
                match_this = true
            }
        }

        // Check traversal flags
        if (term.src.id & EcsUp) != 0 {
            match_only_self = false
        }

        // Check cacheability
        if (term.flags_ & EcsTermIsCacheable) != 0 {
            has_cacheable = true
        } else {
            is_cacheable = false
        }

        // Set term ids
        q.pointee.ids![i] = term.id

        // Set sizes from type info
        let cr = flecs_components_get(UnsafePointer(world), term.id)
        if cr != nil {
            let ti = cr!.pointee.type_info
            if ti != nil {
                q.pointee.sizes![i] = ti!.pointee.size
            }

            // Lock component record to prevent deletion while query is alive
            if !ecs_term_match_0(&term) {
                flecs_component_lock(world, term.id)
            }
        }
    }

    if match_this {
        q.pointee.flags |= EcsQueryMatchThis | EcsQueryHasTableThisVar
    }
    if match_only_self {
        q.pointee.flags |= EcsQueryMatchOnlySelf
    }
    if has_cacheable {
        q.pointee.flags |= EcsQueryHasCacheable
    }
    if is_cacheable {
        q.pointee.flags |= EcsQueryIsCacheable
    }

    q.pointee.flags |= EcsQueryValid

    return 0
}


/// Fast-path query finalization for simple single-term queries.
/// Returns true if the query was successfully finalized as simple.
public func flecs_query_finalize_simple(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ q: UnsafeMutablePointer<ecs_query_t>,
    _ desc: UnsafePointer<ecs_query_desc_t>) -> Bool
{
    // Count terms
    var term_count: Int32 = 0
    withUnsafePointer(to: desc.pointee.terms) { termsPtr in
        let base = UnsafeRawPointer(termsPtr).assumingMemoryBound(to: ecs_term_t.self)
        for i in 0..<Int(FLECS_TERM_COUNT_MAX) {
            if base[i].id != 0 || base[i].first.id != 0 {
                term_count += 1
            } else {
                break
            }
        }
    }

    if term_count == 0 { return false }

    q.pointee.term_count = Int8(term_count)
    q.pointee.field_count = Int8(term_count)

    // Allocate arrays
    let count = Int(term_count)
    q.pointee.terms = ecs_os_calloc_n(ecs_term_t.self, Int32(count))!
    q.pointee.sizes = ecs_os_calloc_n(ecs_size_t.self, Int32(count))!
    q.pointee.ids = ecs_os_calloc_n(ecs_id_t.self, Int32(count))!

    // Copy terms
    withUnsafePointer(to: desc.pointee.terms) { termsPtr in
        let base = UnsafeRawPointer(termsPtr).assumingMemoryBound(to: ecs_term_t.self)
        for i in 0..<count {
            q.pointee.terms![i] = base[i]
            q.pointee.ids![i] = base[i].id
        }
    }

    // Set default flags
    q.pointee.flags |= EcsQueryMatchThis | EcsQueryHasTableThisVar |
        EcsQueryMatchOnlySelf | EcsQueryIsTrivial | EcsQueryValid

    return true
}
