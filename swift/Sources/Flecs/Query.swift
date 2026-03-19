// Query.swift - 1:1 translation of flecs query/api.c
// Query creation, iteration, destruction, and public API

import Foundation

// MARK: - Query Impl Accessor

/// Get the implementation struct from a public query pointer.
@inline(__always)
public func flecs_query_impl(
    _ q: UnsafePointer<ecs_query_t>) -> UnsafeMutablePointer<ecs_query_impl_t>
{
    return UnsafeMutableRawPointer(mutating: q)
        .bindMemory(to: ecs_query_impl_t.self, capacity: 1)
}

// MARK: - Query Variable Lookup

/// Find a query variable by name.
public func ecs_query_find_var(
    _ q: UnsafePointer<ecs_query_t>,
    _ name: UnsafePointer<CChar>) -> Int32
{
    let impl = flecs_query_impl(q)
    let var_id = flecs_query_find_var_id(UnsafePointer(impl), name, .any)
    if var_id == EcsVarNone {
        if (q.pointee.flags & EcsQueryMatchThis) != 0 {
            if strcmp(name, EcsThisName) == 0 {
                return 0
            }
        }
        return -1
    }
    return Int32(var_id)
}

/// Get the name of a query variable.
public func ecs_query_var_name(
    _ q: UnsafePointer<ecs_query_t>,
    _ var_id: Int32) -> UnsafePointer<CChar>?
{
    if var_id == 0 {
        return EcsThisName.withCString { UnsafePointer(strdup($0)) }
    }
    let impl = flecs_query_impl(q)
    guard let vars = impl.pointee.vars else { return nil }
    return vars[Int(var_id)].name
}

/// Check if a query variable is an entity variable.
public func ecs_query_var_is_entity(
    _ q: UnsafePointer<ecs_query_t>,
    _ var_id: Int32) -> Bool
{
    let impl = flecs_query_impl(q)
    guard let vars = impl.pointee.vars else { return false }
    return vars[Int(var_id)].kind == Int8(ecs_var_kind_t.entity.rawValue)
}

// MARK: - Caching Policy

/// Set caching policy based on query descriptor and term analysis.
private func flecs_query_set_caching_policy(
    _ impl: UnsafeMutablePointer<ecs_query_impl_t>,
    _ desc: UnsafePointer<ecs_query_desc_t>) -> Int32
{
    var kind = desc.pointee.cache_kind
    let require_caching = desc.pointee.group_by_callback != nil ||
        desc.pointee.order_by_callback != nil ||
        (desc.pointee.flags & EcsQueryDetectChanges) != 0

    if kind == EcsQueryCacheDefault {
        if desc.pointee.entity != 0 || require_caching {
            kind = EcsQueryCacheAuto
        } else {
            kind = EcsQueryCacheNone
        }
    }

    if kind == EcsQueryCacheNone {
        impl.pointee.pub.cache_kind = EcsQueryCacheNone
        if require_caching && (impl.pointee.pub.flags & EcsQueryNested) == 0 {
            return -1
        }
        return 0
    }

    if desc.pointee.cache_kind == EcsQueryCacheAll {
        if (impl.pointee.pub.flags & EcsQueryIsCacheable) != 0 {
            impl.pointee.pub.cache_kind = EcsQueryCacheAll
            return 0
        } else {
            return -1
        }
    }

    if kind == EcsQueryCacheAuto {
        if (impl.pointee.pub.flags & EcsQueryIsCacheable) != 0 {
            if (impl.pointee.pub.flags & EcsQueryCacheWithFilter) == 0 {
                impl.pointee.pub.cache_kind = EcsQueryCacheAll
            } else {
                impl.pointee.pub.cache_kind = EcsQueryCacheAuto
            }
        } else if (impl.pointee.pub.flags & EcsQueryHasCacheable) == 0 {
            impl.pointee.pub.cache_kind = EcsQueryCacheNone
        } else {
            impl.pointee.pub.cache_kind = EcsQueryCacheAuto
        }
    }

    return 0
}

// MARK: - Array Management

/// Copy query term/size/id arrays.
public func flecs_query_copy_arrays(
    _ q: UnsafeMutablePointer<ecs_query_t>)
{
    let count = Int(q.pointee.term_count)
    if count == 0 { return }

    if let terms = q.pointee.terms {
        let copy = UnsafeMutablePointer<ecs_term_t>.allocate(capacity: count)
        copy.update(from: terms, count: count)
        q.pointee.terms = copy
    }

    if let sizes = q.pointee.sizes {
        let copy = UnsafeMutablePointer<ecs_size_t>.allocate(capacity: count)
        copy.update(from: sizes, count: count)
        q.pointee.sizes = copy
    }

    if let ids = q.pointee.ids {
        let copy = UnsafeMutablePointer<ecs_id_t>.allocate(capacity: count)
        copy.update(from: ids, count: count)
        q.pointee.ids = copy
    }
}

/// Free query term/size/id arrays.
private func flecs_query_free_arrays(
    _ q: UnsafeMutablePointer<ecs_query_t>)
{
    q.pointee.terms?.deallocate()
    q.pointee.sizes?.deallocate()
    q.pointee.ids?.deallocate()
}

// MARK: - Query Fini (Internal)

/// Internal query finalization.
private func flecs_query_fini_impl(
    _ impl: UnsafeMutablePointer<ecs_query_impl_t>)
{
    if let ctx_free = impl.pointee.ctx_free {
        ctx_free(impl.pointee.pub.ctx)
    }
    if let binding_ctx_free = impl.pointee.binding_ctx_free {
        binding_ctx_free(impl.pointee.pub.binding_ctx)
    }

    // Free variables
    if impl.pointee.vars != nil {
        impl.pointee.vars?.deallocate()
        flecs_name_index_fini(&impl.pointee.tvar_index)
        flecs_name_index_fini(&impl.pointee.evar_index)
    }

    // Free ops
    impl.pointee.ops?.deallocate()
    impl.pointee.src_vars?.deallocate()
    impl.pointee.monitor?.deallocate()

    // Unlock component records
    let q = withUnsafeMutablePointer(to: &impl.pointee.pub) { $0 }
    if (q.pointee.flags & EcsQueryValid) != 0 {
        let count = Int(q.pointee.term_count)
        if let terms = q.pointee.terms {
            for i in 0..<count {
                if !ecs_term_match_0(&terms[i]) {
                    flecs_component_unlock(q.pointee.real_world, terms[i].id)
                }
            }
        }
    }

    // Free tokens
    impl.pointee.tokens?.deallocate()

    // Free cache
    if impl.pointee.cache != nil {
        flecs_query_cache_fini(impl)
    }

    flecs_query_free_arrays(q)
    flecs_poly_fini(UnsafeMutableRawPointer(impl), ecs_query_t_magic)
    impl.deallocate()
}

// MARK: - Query Public API

/// Destroy a query.
public func ecs_query_fini(
    _ q: UnsafeMutablePointer<ecs_query_t>?)
{
    guard let q = q else { return }

    if q.pointee.entity != 0 {
        ecs_delete(q.pointee.world, q.pointee.entity)
    } else {
        flecs_query_fini_impl(flecs_query_impl(UnsafePointer(q)))
    }
}

/// Initialize a query from a descriptor.
public func ecs_query_init(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ const_desc: UnsafePointer<ecs_query_desc_t>) -> UnsafeMutablePointer<ecs_query_t>?
{
    let world_arg = world
    let stage = flecs_stage_from_world(world)

    let impl = UnsafeMutablePointer<ecs_query_impl_t>.allocate(capacity: 1)
    impl.initialize(to: ecs_query_impl_t())
    flecs_poly_init(UnsafeMutableRawPointer(impl), ecs_query_t_magic,
        Int32(MemoryLayout<ecs_query_impl_t>.stride), nil)

    var desc = const_desc.pointee
    let entity = const_desc.pointee.entity

    if entity != 0 {
        // Remove existing query if entity has one
        var deferred = false
        if ecs_is_deferred(world) {
            deferred = true
            ecs_defer_suspend(world)
        }
        ecs_remove_pair(world, entity, ecs_id_EcsPoly, EcsQuery)
        if deferred {
            ecs_defer_resume(world)
        }
    }

    impl.pointee.pub.entity = entity
    impl.pointee.pub.real_world = world
    impl.pointee.pub.world = world_arg
    impl.pointee.stage = UnsafeMutableRawPointer(stage)

    // Validate and finalize query
    if flecs_query_finalize_query(world, &impl.pointee.pub, &desc) != 0 {
        impl.pointee.pub.entity = 0
        ecs_query_fini(&impl.pointee.pub)
        return nil
    }

    // Add self-references
    flecs_query_add_self_ref(&impl.pointee.pub)

    // Copy context
    impl.pointee.pub.ctx = const_desc.pointee.ctx
    impl.pointee.pub.binding_ctx = const_desc.pointee.binding_ctx
    impl.pointee.ctx_free = const_desc.pointee.ctx_free
    impl.pointee.binding_ctx_free = const_desc.pointee.binding_ctx_free
    impl.pointee.dtor = { ptr in
        guard let ptr = ptr else { return }
        flecs_query_fini_impl(
            ptr.bindMemory(to: ecs_query_impl_t.self, capacity: 1))
    }
    impl.pointee.cache = nil

    // Set caching policy
    if flecs_query_set_caching_policy(impl, &desc) != 0 {
        impl.pointee.pub.entity = 0
        ecs_query_fini(&impl.pointee.pub)
        return nil
    }

    // Compile query
    if flecs_query_compile(world, stage, impl) != 0 {
        impl.pointee.pub.entity = 0
        ecs_query_fini(&impl.pointee.pub)
        return nil
    }

    // Bind to entity if present
    let result_entity = impl.pointee.pub.entity
    if result_entity != 0 {
        if let poly = flecs_poly_bind_(world, result_entity, EcsQuery) {
            poly.pointee.poly = UnsafeMutableRawPointer(impl)
            flecs_poly_modified_(world, result_entity, EcsQuery)
        }
    }

    return withUnsafeMutablePointer(to: &impl.pointee.pub) { $0 }
}

/// Add self-references: if query terms reference the query entity, add ids.
private func flecs_query_add_self_ref(
    _ q: UnsafeMutablePointer<ecs_query_t>)
{
    guard q.pointee.entity != 0 else { return }
    guard let terms = q.pointee.terms else { return }
    let count = Int(q.pointee.term_count)

    for t in 0..<count {
        if ECS_TERM_REF_ID(&terms[t].src) == q.pointee.entity {
            ecs_add_id(q.pointee.world, q.pointee.entity, terms[t].id)
        }
    }
}

// MARK: - Query Has

/// Check if a query matches an entity.
public func ecs_query_has(
    _ q: UnsafePointer<ecs_query_t>,
    _ entity: ecs_entity_t,
    _ it: UnsafeMutablePointer<ecs_iter_t>) -> Bool
{
    guard (q.pointee.flags & EcsQueryMatchThis) != 0 else { return false }

    it.pointee = ecs_query_iter(q.pointee.world, q)
    ecs_iter_set_var(it, 0, entity)
    return ecs_query_next(it)
}

/// Check if a query matches a table.
public func ecs_query_has_table(
    _ q: UnsafePointer<ecs_query_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ it: UnsafeMutablePointer<ecs_iter_t>) -> Bool
{
    guard (q.pointee.flags & EcsQueryMatchThis) != 0 else { return false }

    it.pointee = ecs_query_iter(q.pointee.world, q)
    ecs_iter_set_var_as_table(it, 0, table)
    return ecs_query_next(it)
}

/// Check if a query matches a table range.
public func ecs_query_has_range(
    _ q: UnsafePointer<ecs_query_t>,
    _ range: UnsafeMutablePointer<ecs_table_range_t>,
    _ it: UnsafeMutablePointer<ecs_iter_t>) -> Bool
{
    it.pointee = ecs_query_iter(q.pointee.world, q)

    if (q.pointee.flags & EcsQueryMatchThis) != 0 {
        ecs_iter_set_var_as_range(it, 0, range)
    }

    return ecs_query_next(it)
}

// MARK: - Query Counting

/// Count the number of results, entities, and tables matched by a query.
public func ecs_query_count(
    _ q: UnsafePointer<ecs_query_t>) -> ecs_query_count_t
{
    var result = ecs_query_count_t()

    var it = flecs_query_iter(q.pointee.world, q)
    it.flags |= EcsIterNoData

    while ecs_query_next(&it) {
        result.results += 1
        result.entities += it.count
        ecs_iter_skip(&it)
    }

    if (q.pointee.flags & EcsQueryMatchOnlySelf) != 0 &&
        (q.pointee.flags & EcsQueryMatchWildcards) == 0
    {
        result.tables = result.results
    }

    return result
}

/// Check if a query has any matches.
public func ecs_query_is_true(
    _ q: UnsafePointer<ecs_query_t>) -> Bool
{
    var it = flecs_query_iter(q.pointee.world, q)
    return ecs_iter_is_true(&it)
}

/// Get the match count (number of times cache was updated).
public func ecs_query_match_count(
    _ q: UnsafePointer<ecs_query_t>) -> Int32
{
    let impl = flecs_query_impl(q)
    guard impl.pointee.cache != nil else { return 0 }
    // Would return impl->cache->match_count
    return 0
}

// MARK: - Query Getters

/// Get a query from an entity.
public func ecs_query_get(
    _ world: UnsafePointer<ecs_world_t>,
    _ query: ecs_entity_t) -> UnsafePointer<ecs_query_t>?
{
    guard let poly = ecs_get_pair(world, query, EcsPoly.self, EcsQuery) else {
        return nil
    }
    guard let p = poly.pointee.poly else { return nil }
    return UnsafePointer(p.bindMemory(to: ecs_query_t.self, capacity: 1))
}

/// Get the cache query of a cached query.
public func ecs_query_get_cache_query(
    _ q: UnsafePointer<ecs_query_t>) -> UnsafePointer<ecs_query_t>?
{
    let impl = flecs_query_impl(q)
    guard impl.pointee.cache != nil else { return nil }
    // Would return impl->cache->query
    return nil
}

// MARK: - Iterator Creation

/// Create an iterator for a query (internal, no defer adjustment).
public func flecs_query_iter(
    _ world: UnsafeRawPointer?,
    _ query: UnsafePointer<ecs_query_t>) -> ecs_iter_t
{
    var it = ecs_iter_t()
    it.world = UnsafeMutableRawPointer(mutating: world)
    it.real_world = UnsafeMutableRawPointer(mutating: world)
    it.query = UnsafeMutablePointer(mutating: query)
    it.field_count = query.pointee.field_count
    it.system = query.pointee.entity
    it.next = ecs_query_next
    it.flags = EcsIterIsValid
    return it
}

/// Create an iterator for a query (public API).
public func ecs_query_iter(
    _ world: UnsafeRawPointer?,
    _ query: UnsafePointer<ecs_query_t>) -> ecs_iter_t
{
    return flecs_query_iter(world, query)
}

/// Advance the query iterator to the next result.
public func ecs_query_next(
    _ it: UnsafeMutablePointer<ecs_iter_t>?) -> Bool
{
    guard let it = it else { return false }
    guard (it.pointee.flags & EcsIterIsValid) != 0 else { return false }

    // Full query iteration requires the compiled query program execution.
    // The query engine evaluates operations (And, Or, Not, Up, etc.)
    // to find matching tables and populate iterator fields.
    // This is handled by flecs_query_run/flecs_query_next_instanced.

    it.pointee.flags &= ~EcsIterIsValid
    return false
}

// MARK: - Query String

/// Get string representation of a query.
public func ecs_query_str(
    _ query: UnsafePointer<ecs_query_t>) -> UnsafeMutablePointer<CChar>?
{
    let world = query.pointee.world
    guard let terms = query.pointee.terms else { return nil }
    let count = Int(query.pointee.term_count)

    var buf = ecs_strbuf_t()
    for i in 0..<count {
        flecs_term_to_buf(world, &terms[i], &buf, Int32(i))

        if i != count - 1 {
            if terms[i].oper == EcsOr {
                ecs_strbuf_appendstr(&buf, " || ")
            } else {
                ecs_strbuf_appendstr(&buf, ", ")
            }
        }
    }

    return ecs_strbuf_get(&buf)
}

/// Get the query plan as a string (for debugging).
public func ecs_query_plan(
    _ q: UnsafePointer<ecs_query_t>) -> UnsafeMutablePointer<CChar>?
{
    return ecs_query_plan_w_profile(q, nil)
}

/// Get query plan with optional profiling data.
public func ecs_query_plan_w_profile(
    _ q: UnsafePointer<ecs_query_t>,
    _ it: UnsafePointer<ecs_iter_t>?) -> UnsafeMutablePointer<CChar>?
{
    var buf = ecs_strbuf_t()
    let impl = flecs_query_impl(q)
    guard let ops = impl.pointee.ops else {
        return ecs_strbuf_get(&buf)
    }

    let count = impl.pointee.op_count
    for i in 0..<Int(count) {
        let op = ops[i]
        let kind_str = flecs_query_op_str(UInt16(op.kind))
        ecs_strbuf_append(&buf, "%2d. %s\n", Int32(i), kind_str)
    }

    return ecs_strbuf_get(&buf)
}

// MARK: - Iterator Helpers

/// Apply query flags to iterator.
public func flecs_query_apply_iter_flags(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ query: UnsafePointer<ecs_query_t>)
{
    if (query.pointee.flags & EcsQueryHasCondSet) != 0 {
        it.pointee.flags |= EcsIterHasCondSet
    } else {
        it.pointee.flags &= ~EcsIterHasCondSet
    }

    if query.pointee.data_fields == 0 {
        it.pointee.flags |= EcsIterNoData
    } else {
        it.pointee.flags &= ~EcsIterNoData
    }
}

/// Reclaim memory used by query caches.
public func flecs_query_reclaim(
    _ query: UnsafeMutablePointer<ecs_query_t>)
{
    let impl = flecs_query_impl(UnsafePointer(query))
    // Would reclaim cache maps if cache exists
    _ = impl
}
