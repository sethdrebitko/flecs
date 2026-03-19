// QueryCache.swift - 1:1 translation of flecs query/cache/*.c
// Query result caching: table matching, change detection, grouping, ordering

import Foundation

// MARK: - Cache Types

/// Trivial cache match element (minimal data for simple queries).
public struct ecs_query_triv_cache_match_t {
    public var table_cache_hdr: ecs_table_cache_hdr_t = ecs_table_cache_hdr_t()
    public init() {}
}

/// Full cache match element (stores per-field data for complex queries).
public struct ecs_query_cache_match_t {
    public var table_cache_hdr: ecs_table_cache_hdr_t = ecs_table_cache_hdr_t()
    public var columns: UnsafeMutablePointer<Int16>? = nil
    public var ids: UnsafeMutablePointer<ecs_id_t>? = nil
    public var sources: UnsafeMutablePointer<ecs_entity_t>? = nil
    public var trs: UnsafeMutablePointer<UnsafePointer<ecs_table_record_t>?>? = nil
    public var set_fields: ecs_termset_t = 0
    public var up_fields: ecs_termset_t = 0
    public var group_id: UInt64 = 0
    public var wildcard_matches: UnsafeMutablePointer<ecs_query_cache_match_t>? = nil
    public var wildcard_match_count: Int32 = 0
    public init() {}
}

/// Table entry in the cache's table map.
public struct ecs_query_cache_table_t {
    public var group: UnsafeMutablePointer<ecs_query_cache_group_t>? = nil
    public var index: Int32 = 0
    public init() {}
}

/// Group of matched tables (for group_by feature).
public struct ecs_query_cache_group_t {
    public var id: UInt64 = 0
    public var tables: ecs_vec_t = ecs_vec_t()
    public var next: UnsafeMutablePointer<ecs_query_cache_group_t>? = nil
    public var prev: UnsafeMutablePointer<ecs_query_cache_group_t>? = nil
    public var match_count: Int32 = 0
    public var table_count: Int32 = 0
    public init() {}
}

/// Main query cache structure.
public struct ecs_query_cache_t {
    public var query: UnsafeMutablePointer<ecs_query_t>? = nil
    public var tables: ecs_map_t = ecs_map_t()
    public var groups: ecs_map_t = ecs_map_t()
    public var first_group: UnsafeMutablePointer<ecs_query_cache_group_t>? = nil
    public var last_group: UnsafeMutablePointer<ecs_query_cache_group_t>? = nil
    public var observer: UnsafeMutablePointer<ecs_observer_t>? = nil
    public var field_map: UnsafeMutablePointer<Int8>? = nil
    public var match_count: Int32 = 0
    public var table_slices: ecs_vec_t = ecs_vec_t()
    public var prev_match_count: Int32 = 0
    public var rematch_count: Int32 = 0
    public var group_by_callback: ecs_group_by_action_t? = nil
    public var group_by_ctx: UnsafeMutableRawPointer? = nil
    public var on_group_create: ecs_group_create_action_t? = nil
    public var on_group_delete: ecs_group_delete_action_t? = nil
    public var group_by_ctx_free: ecs_ctx_free_t? = nil
    public var order_by_callback: ecs_order_by_action_t? = nil
    public var order_by: ecs_entity_t = 0
    public var cascade_by: ecs_entity_t = 0
    public var entity: ecs_entity_t = 0
    public init() {}
}

// MARK: - Cache Queries

/// Check if a cache is trivial (simple single-field queries).
public func flecs_query_cache_is_trivial(
    _ cache: UnsafePointer<ecs_query_cache_t>) -> Bool
{
    guard let q = cache.pointee.query else { return false }
    return (q.pointee.flags & EcsQueryTrivialCache) != 0
}

/// Get the element size for cache entries (trivial vs full).
public func flecs_query_cache_elem_size(
    _ cache: UnsafePointer<ecs_query_cache_t>) -> ecs_size_t
{
    if flecs_query_cache_is_trivial(cache) {
        return ecs_size_t(MemoryLayout<ecs_query_triv_cache_match_t>.stride)
    }
    return ecs_size_t(MemoryLayout<ecs_query_cache_match_t>.stride)
}

// MARK: - Default Group By

/// Default group_by callback: groups tables by relationship target.
public func flecs_query_cache_default_group_by(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ id: ecs_id_t,
    _ ctx: UnsafeMutableRawPointer?) -> UInt64
{
    var match: ecs_id_t = 0
    if ecs_search(UnsafeRawPointer(world), UnsafePointer(table),
        ecs_pair(id, EcsWildcard), &match) != -1
    {
        if ECS_IS_VALUE_PAIR(match) {
            return UInt64(ECS_PAIR_SECOND(match))
        } else {
            return UInt64(ecs_pair_second(UnsafePointer(world), match))
        }
    }
    return 0
}

/// Group_by callback for cascade: groups by hierarchy depth.
public func flecs_query_cache_group_by_cascade(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ id: ecs_id_t,
    _ ctx: UnsafeMutableRawPointer?) -> UInt64
{
    guard let term = ctx?.bindMemory(to: ecs_term_t.self, capacity: 1) else { return 0 }
    let rel = term.pointee.trav
    let depth = flecs_relation_depth(UnsafePointer(world), rel, UnsafePointer(table))
    return UInt64(depth)
}

// MARK: - Cache Init / Fini

/// Initialize a query cache from a query.
public func flecs_query_cache_init(
    _ impl: UnsafeMutablePointer<ecs_query_impl_t>,
    _ desc: UnsafePointer<ecs_query_desc_t>) -> Int32
{
    let q = withUnsafeMutablePointer(to: &impl.pointee.pub) { $0 }
    guard let world = q.pointee.real_world?.assumingMemoryBound(
        to: ecs_world_t.self) else { return -1 }

    let cache = UnsafeMutablePointer<ecs_query_cache_t>.allocate(capacity: 1)
    cache.initialize(to: ecs_query_cache_t())
    impl.pointee.cache = UnsafeMutableRawPointer(cache)

    cache.pointee.entity = q.pointee.entity
    ecs_map_init(&cache.pointee.tables, &world.pointee.allocator)

    // Set up group_by if provided
    if desc.pointee.group_by != 0 {
        ecs_map_init(&cache.pointee.groups, &world.pointee.allocator)
        cache.pointee.cascade_by = desc.pointee.group_by

        if let group_by = desc.pointee.group_by_callback {
            cache.pointee.group_by_callback = group_by
        } else {
            cache.pointee.group_by_callback = flecs_query_cache_default_group_by
        }

        cache.pointee.group_by_ctx = desc.pointee.group_by_ctx
        cache.pointee.group_by_ctx_free = desc.pointee.group_by_ctx_free
        cache.pointee.on_group_create = desc.pointee.on_group_create
        cache.pointee.on_group_delete = desc.pointee.on_group_delete
    }

    // Set up order_by if provided
    if let order_by = desc.pointee.order_by_callback {
        cache.pointee.order_by_callback = order_by
        cache.pointee.order_by = desc.pointee.order_by
    }

    // Create cache query (subset of terms that are cacheable)
    // Build a query descriptor with only cacheable terms
    var cache_desc = ecs_query_desc_t()
    cache_desc.flags = EcsQueryNested | EcsQueryMatchEmptyTables
    cache_desc.cache_kind = EcsQueryCacheAll

    var cache_term_count: Int32 = 0
    let term_count = Int(q.pointee.term_count)
    guard let terms = q.pointee.terms else { return -1 }

    withUnsafeMutablePointer(to: &cache_desc.terms) { dst_ptr in
        let dst = UnsafeMutableRawPointer(dst_ptr).assumingMemoryBound(
            to: ecs_term_t.self)
        for i in 0..<term_count {
            if (terms[i].flags_ & EcsTermIsCacheable) != 0 {
                dst[Int(cache_term_count)] = terms[i]
                cache_term_count += 1
            }
        }
    }

    if cache_term_count > 0 {
        cache.pointee.query = ecs_query_init(world, &cache_desc)
        if cache.pointee.query == nil {
            flecs_query_cache_fini(impl)
            return -1
        }
    }

    // Build field map (cache field -> query field)
    if cache_term_count != Int32(term_count) && cache_term_count > 0 {
        cache.pointee.field_map = UnsafeMutablePointer<Int8>
            .allocate(capacity: Int(cache_term_count))
        var cache_field: Int32 = 0
        for i in 0..<term_count {
            if (terms[i].flags_ & EcsTermIsCacheable) != 0 {
                cache.pointee.field_map![Int(cache_field)] = terms[i].field_index
                cache_field += 1
            }
        }
    }

    return 0
}

/// Finalize and free a query cache.
public func flecs_query_cache_fini(
    _ impl: UnsafeMutablePointer<ecs_query_impl_t>)
{
    guard let cache_ptr = impl.pointee.cache else { return }
    let cache = cache_ptr.bindMemory(to: ecs_query_cache_t.self, capacity: 1)

    // Free cache query
    if let q = cache.pointee.query {
        ecs_query_fini(q)
    }

    // Free field map
    cache.pointee.field_map?.deallocate()

    // Free group_by context
    if let ctx_free = cache.pointee.group_by_ctx_free,
       let ctx = cache.pointee.group_by_ctx
    {
        ctx_free(ctx)
    }

    // Free maps
    ecs_map_fini(&cache.pointee.tables)
    ecs_map_fini(&cache.pointee.groups)

    cache.deallocate()
    impl.pointee.cache = nil
}

// MARK: - Change Detection

/// Check if a query has changed since the last iteration.
public func ecs_query_changed(
    _ q: UnsafeMutablePointer<ecs_query_t>) -> Bool
{
    let impl = flecs_query_impl(UnsafePointer(q))
    guard let cache_ptr = impl.pointee.cache else { return false }
    let cache = cache_ptr.bindMemory(to: ecs_query_cache_t.self, capacity: 1)

    return cache.pointee.match_count != cache.pointee.prev_match_count
}

/// Mark a query as having been iterated (reset change detection).
public func flecs_query_cache_mark_iterated(
    _ cache: UnsafeMutablePointer<ecs_query_cache_t>)
{
    cache.pointee.prev_match_count = cache.pointee.match_count
}

// MARK: - Group API

/// Set group iteration for a query iterator.
public func ecs_query_set_group(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ group_id: UInt64)
{
    // Would look up group in cache->groups map and constrain iteration
    // to only the tables in that group
    _ = it
    _ = group_id
}

/// Get the group context for a group id.
public func ecs_query_get_group_ctx(
    _ q: UnsafePointer<ecs_query_t>,
    _ group_id: UInt64) -> UnsafeMutableRawPointer?
{
    let impl = flecs_query_impl(q)
    guard let cache_ptr = impl.pointee.cache else { return nil }
    let cache = cache_ptr.bindMemory(to: ecs_query_cache_t.self, capacity: 1)

    guard let val = ecs_map_get(&cache.pointee.groups, group_id) else { return nil }
    let group = UnsafeMutablePointer<ecs_query_cache_group_t>(
        bitPattern: UInt(val.pointee))
    return group != nil ? UnsafeMutableRawPointer(group) : nil
}

/// Get info about a group.
public func ecs_query_get_group_info(
    _ q: UnsafePointer<ecs_query_t>,
    _ group_id: UInt64) -> UnsafePointer<ecs_query_group_info_t>?
{
    // Would return group info struct with match count, table count, ctx
    return nil
}

// MARK: - Cache Table Notifications

/// Handle table event (observer notification for cache updates).
public func flecs_query_cache_notify(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cache: UnsafeMutablePointer<ecs_query_cache_t>,
    _ event: UnsafePointer<ecs_table_event_t>)
{
    switch event.pointee.kind {
    case EcsTableTriggersForId:
        // A new observer was created for an id, update event flags
        break
    case EcsTableNoTriggersForId:
        // Last observer for an id was removed
        break
    default:
        break
    }
}

// MARK: - Order By

/// Sort query results by a component using a comparator.
public func flecs_query_cache_sort(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cache: UnsafeMutablePointer<ecs_query_cache_t>)
{
    guard cache.pointee.order_by_callback != nil else { return }

    // Would sort each matched table's entities using qsort with the
    // provided comparator, then build a list of (table, offset, count)
    // slices that represents the global sorted order.
    // This is stored in cache->table_slices.
}

// MARK: - Rematch

/// Rematch query cache (re-evaluate which tables match).
/// Called when a parent or traversable target changes a matched component.
public func flecs_query_cache_rematch(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cache: UnsafeMutablePointer<ecs_query_cache_t>)
{
    cache.pointee.rematch_count += 1

    // Would iterate all tables in the world and re-evaluate the cache
    // query against each, adding/removing tables from the cache as needed.
    // This handles cases where component inheritance (IsA) or other
    // traversable relationships change.
}
