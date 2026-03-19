// Query.swift - 1:1 translation of flecs query public API
// Query creation, iteration, and destruction

import Foundation

// MARK: - Query Public API

/// Initialize a query from a descriptor
public func ecs_query_init(
    _ world: UnsafeMutableRawPointer?,
    _ desc: UnsafePointer<ecs_query_desc_t>
) -> UnsafeMutablePointer<ecs_query_t>? {
    guard let world = world else { return nil }

    // Allocate query impl
    let impl = UnsafeMutablePointer<ecs_query_impl_t>.allocate(capacity: 1)
    impl.pointee = ecs_query_impl_t()

    let q = UnsafeMutablePointer<ecs_query_t>(&impl.pointee.pub)

    // Set header magic
    q.pointee.hdr.type = ecs_query_t_magic

    // Copy world reference
    q.pointee.world = world
    q.pointee.real_world = world

    // Copy entity
    q.pointee.entity = desc.pointee.entity

    // Count terms from descriptor
    var term_count: Int8 = 0
    withUnsafePointer(to: desc.pointee.terms) { termsPtr in
        let base = UnsafeRawPointer(termsPtr).assumingMemoryBound(to: ecs_term_t.self)
        for i in 0..<Int(FLECS_TERM_COUNT_MAX) {
            if base[i].id != 0 || base[i].first.id != 0 || base[i].src.id != 0 {
                term_count += 1
            } else {
                break
            }
        }
    }

    q.pointee.term_count = term_count
    q.pointee.field_count = term_count

    // Allocate and copy terms
    if term_count > 0 {
        let count = Int(term_count)
        q.pointee.terms = UnsafeMutablePointer<ecs_term_t>.allocate(capacity: count)
        withUnsafePointer(to: desc.pointee.terms) { termsPtr in
            let base = UnsafeRawPointer(termsPtr).assumingMemoryBound(to: ecs_term_t.self)
            for i in 0..<count {
                q.pointee.terms![i] = base[i]
            }
        }

        // Allocate sizes and ids arrays
        q.pointee.sizes = UnsafeMutablePointer<Int32>.allocate(capacity: count)
        q.pointee.sizes!.initialize(repeating: 0, count: count)

        q.pointee.ids = UnsafeMutablePointer<ecs_id_t>.allocate(capacity: count)
        q.pointee.ids!.initialize(repeating: 0, count: count)

        // Copy ids from terms
        for i in 0..<count {
            q.pointee.ids![i] = q.pointee.terms![i].id
        }
    }

    // Set cache kind
    q.pointee.cache_kind = desc.pointee.cache_kind

    // Copy flags
    q.pointee.flags = desc.pointee.flags | EcsQueryValid

    // Copy context
    q.pointee.ctx = desc.pointee.ctx
    q.pointee.binding_ctx = desc.pointee.binding_ctx
    impl.pointee.ctx_free = desc.pointee.ctx_free
    impl.pointee.binding_ctx_free = desc.pointee.binding_ctx_free

    return q
}

/// Destroy a query
public func ecs_query_fini(
    _ query: UnsafeMutablePointer<ecs_query_t>?
) {
    guard let query = query else { return }

    let count = Int(query.pointee.term_count)

    // Free terms
    if let terms = query.pointee.terms {
        terms.deinitialize(count: count)
        terms.deallocate()
    }

    // Free sizes
    if let sizes = query.pointee.sizes {
        sizes.deinitialize(count: count)
        sizes.deallocate()
    }

    // Free ids
    if let ids = query.pointee.ids {
        ids.deinitialize(count: count)
        ids.deallocate()
    }

    // Get impl and free context
    let impl = UnsafeMutableRawPointer(query).assumingMemoryBound(to: ecs_query_impl_t.self)

    if let ctx_free = impl.pointee.ctx_free, let ctx = query.pointee.ctx {
        ctx_free(ctx)
    }
    if let binding_ctx_free = impl.pointee.binding_ctx_free, let ctx = query.pointee.binding_ctx {
        binding_ctx_free(ctx)
    }

    // Free vars
    if let vars = impl.pointee.vars {
        vars.deinitialize(count: Int(impl.pointee.var_count))
        vars.deallocate()
    }

    // Free ops
    if let ops = impl.pointee.ops {
        ops.deinitialize(count: Int(impl.pointee.op_count))
        ops.deallocate()
    }

    // Free tokens
    if let tokens = impl.pointee.tokens {
        tokens.deallocate()
    }

    impl.deallocate()
}

/// Create an iterator for a query
public func ecs_query_iter(
    _ world: UnsafeRawPointer?,
    _ query: UnsafePointer<ecs_query_t>?
) -> ecs_iter_t {
    var it = ecs_iter_t()
    guard let query = query else { return it }

    it.world = UnsafeMutableRawPointer(mutating: world)
    it.real_world = UnsafeMutableRawPointer(mutating: world)
    it.query = query
    it.field_count = query.pointee.field_count
    it.system = query.pointee.entity

    // Set the next callback
    it.next = { itPtr in
        return ecs_query_next(itPtr)
    }

    // Initialize field arrays
    let field_count = Int(it.field_count)
    if field_count > 0 {
        it.ids = UnsafeMutablePointer<ecs_id_t>.allocate(capacity: field_count)
        it.ids!.initialize(repeating: 0, count: field_count)

        it.sources = UnsafeMutablePointer<ecs_entity_t>.allocate(capacity: field_count)
        it.sources!.initialize(repeating: 0, count: field_count)

        it.ptrs = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: field_count)
        it.ptrs!.initialize(repeating: nil, count: field_count)

        // Copy ids from query
        if let qids = query.pointee.ids {
            for i in 0..<field_count {
                it.ids![i] = qids[i]
            }
        }
    }

    it.flags = EcsIterIsValid
    return it
}

/// Advance the query iterator to the next result
public func ecs_query_next(
    _ it: UnsafeMutablePointer<ecs_iter_t>?
) -> Bool {
    guard let it = it else { return false }

    // Check if iterator is valid
    guard (it.pointee.flags & EcsIterIsValid) != 0 else { return false }

    // TODO: Full query iteration requires the query engine (compiler + execution)
    // which traverses table caches and evaluates query operations.
    // For now, mark as done.

    it.pointee.flags &= ~EcsIterIsValid
    return false
}

/// Get the string representation of a query
public func ecs_query_str(
    _ query: UnsafePointer<ecs_query_t>?
) -> UnsafeMutablePointer<CChar>? {
    guard let query = query else { return nil }

    var buf = ecs_strbuf_t()

    let term_count = Int(query.pointee.term_count)
    guard let terms = query.pointee.terms else { return nil }

    for i in 0..<term_count {
        if i > 0 {
            ecs_strbuf_appendstr(&buf, ", ")
        }

        let term = terms[i]

        // Basic representation
        if ECS_IS_PAIR(term.id) {
            ecs_strbuf_appendch(&buf, CChar(UInt8(ascii: "(")))
            var first = ECS_PAIR_FIRST(term.id)
            var second = ECS_PAIR_SECOND(term.id)
            let firstStr = String(first)
            let secondStr = String(second)
            firstStr.withCString { ecs_strbuf_appendstr(&buf, $0) }
            ecs_strbuf_appendch(&buf, CChar(UInt8(ascii: ",")))
            secondStr.withCString { ecs_strbuf_appendstr(&buf, $0) }
            ecs_strbuf_appendch(&buf, CChar(UInt8(ascii: ")")))
        } else {
            let idStr = String(term.id)
            idStr.withCString { ecs_strbuf_appendstr(&buf, $0) }
        }
    }

    return ecs_strbuf_get(&buf)
}

/// Check if query has matches
public func ecs_query_has(
    _ world: UnsafeRawPointer?,
    _ query: UnsafePointer<ecs_query_t>?,
    _ it_out: UnsafeMutablePointer<ecs_iter_t>?
) -> Bool {
    var it = ecs_query_iter(world, query)
    let result = ecs_query_next(&it)
    if result {
        if let it_out = it_out {
            it_out.pointee = it
        } else {
            ecs_iter_fini(&it)
        }
    }
    return result
}

/// Get the number of terms in a query
public func ecs_query_term_count(
    _ query: UnsafePointer<ecs_query_t>?
) -> Int32 {
    guard let query = query else { return 0 }
    return Int32(query.pointee.term_count)
}

/// Get the number of fields in a query
public func ecs_query_field_count(
    _ query: UnsafePointer<ecs_query_t>?
) -> Int32 {
    guard let query = query else { return 0 }
    return Int32(query.pointee.field_count)
}

/// Check if query is valid (has been properly initialized)
public func ecs_query_is_valid(
    _ query: UnsafePointer<ecs_query_t>?
) -> Bool {
    guard let query = query else { return false }
    return (query.pointee.flags & EcsQueryValid) != 0
}
