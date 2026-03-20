// QueryValidator.swift - 1:1 translation of flecs query/validator.c
// Query term validation, finalization, and normalization

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Context passed through validation for error reporting.
public struct ecs_query_validator_ctx_t {
    public var world: UnsafeMutablePointer<ecs_world_t>? = nil
    public var query: UnsafeMutablePointer<ecs_query_t>? = nil
    public var desc: UnsafePointer<ecs_query_desc_t>? = nil
    public var term: UnsafePointer<ecs_term_t>? = nil
    public var term_index: Int32 = 0
    public init() {}
}


/// Log a query validation error with context.
private func flecs_query_validator_error(
    _ ctx: UnsafePointer<ecs_query_validator_ctx_t>,
    _ msg: String)
{
    // In a full implementation, this formats the error with the query expression
    // and highlights the offending term. For now, just log.
    ecs_err("query validation error: %s", msg)
}


/// Finalize flags on a term reference (EcsIsEntity / EcsIsVariable).
private func flecs_term_ref_finalize_flags(
    _ ref: UnsafeMutablePointer<ecs_term_ref_t>,
    _ ctx: UnsafeMutablePointer<ecs_query_validator_ctx_t>,
    _ refname: UnsafePointer<CChar>) -> Int32
{
    // Can't have both entity and variable
    if (ref.pointee.id & EcsIsEntity) != 0 && (ref.pointee.id & EcsIsVariable) != 0 {
        return -1
    }

    // Handle $ prefix in names
    let name = ref.pointee.name
    if name != nil && name!.pointee == UInt8(ascii: "$") {
        if (name! + 1).pointee == 0 {
            if (ref.pointee.id & EcsIsName) == 0 { return -1 }
        } else {
            ref.pointee.name = name! + 1
            ref.pointee.id |= EcsIsVariable
        }
    }

    // Default: set IsEntity or IsVariable based on content
    if (ref.pointee.id & (EcsIsEntity | EcsIsVariable | EcsIsName)) == 0 {
        if ECS_TERM_REF_ID(ref) != 0 || ref.pointee.name != nil {
            let ref_id = ECS_TERM_REF_ID(ref)
            if ref_id == EcsThis || ref_id == EcsWildcard ||
               ref_id == EcsAny || ref_id == EcsVariable
            {
                ref.pointee.id |= EcsIsVariable
            } else {
                ref.pointee.id |= EcsIsEntity
            }
        }
    }

    return 0
}


/// Resolve a term reference name to an entity id.
private func flecs_term_ref_lookup(
    _ world: UnsafePointer<ecs_world_t>,
    _ scope: ecs_entity_t,
    _ ref: UnsafeMutablePointer<ecs_term_ref_t>,
    _ ctx: UnsafeMutablePointer<ecs_query_validator_ctx_t>) -> Int32
{
    let name = ref.pointee.name
    if name == nil { return 0 }

    if (ref.pointee.id & EcsIsVariable) != 0 {
        if strcmp(name!, "this") == 0 {
            ref.pointee.id = EcsThis | ECS_TERM_REF_FLAGS(ref)
            ref.pointee.name = nil
        }
        return 0
    }

    if (ref.pointee.id & EcsIsName) != 0 {
        return ref.pointee.name != nil ? 0 : -1
    }

    // Check for #0
    if name!.pointee == UInt8(ascii: "#") && (name! + 1).pointee == UInt8(ascii: "0") &&
        (name! + 2).pointee == 0
    {
        if ECS_TERM_REF_ID(ref) != 0 { return -1 }
        ref.pointee.name = nil
        return 0
    }

    // Look up entity by name
    var e: ecs_entity_t = 0
    if scope != 0 {
        e = ecs_lookup_child(world, scope, name!)
    }
    if e == 0 {
        e = ecs_lookup(world, name!)
    }
    if e == 0 {
        e = ecs_lookup_symbol(world, name!, false, false)
    }

    if e == 0 {
        let q = ctx.pointee.query
        if q != nil &&
            (q!.pointee.flags & EcsQueryAllowUnresolvedByName) != 0
        {
            ref.pointee.id |= EcsIsName
            ref.pointee.id &= ~EcsIsEntity
            return 0
        }
        return -1
    }

    let ref_id = ECS_TERM_REF_ID(ref)
    if ref_id != 0 && ref_id != e {
        return -1
    }

    ref.pointee.id = e | ECS_TERM_REF_FLAGS(ref)

    // Check for builtin wildcards
    if strcmp(name!, "*") == 0 || strcmp(name!, "_") == 0 || strcmp(name!, "$") == 0 {
        ref.pointee.id &= ~EcsIsEntity
        ref.pointee.id |= EcsIsVariable
    }

    if (ref.pointee.id & EcsIsName) == 0 && ECS_TERM_REF_ID(ref) != 0 {
        if !ecs_is_alive(world, ECS_TERM_REF_ID(ref)) {
            return -1
        }
        ref.pointee.name = nil
    }

    return 0
}


/// Finalize all references in a term (src, first, second).
private func flecs_term_refs_finalize(
    _ world: UnsafePointer<ecs_world_t>,
    _ term: UnsafeMutablePointer<ecs_term_t>,
    _ ctx: UnsafeMutablePointer<ecs_query_validator_ctx_t>) -> Int32
{
    let src = withUnsafeMutablePointer(to: &term.pointee.src) { $0 }
    let first = withUnsafeMutablePointer(to: &term.pointee.first) { $0 }
    let second = withUnsafeMutablePointer(to: &term.pointee.second) { $0 }

    // Default traversal flags
    if (first.pointee.id & EcsTraverseFlags) == 0 {
        first.pointee.id |= EcsSelf
    }
    if (second.pointee.id & EcsTraverseFlags) == 0 {
        if ECS_TERM_REF_ID(second) != 0 || second.pointee.name != nil ||
            (second.pointee.id & EcsIsEntity) != 0
        {
            second.pointee.id |= EcsSelf
        }
    }

    // Source defaults to $this
    if ECS_TERM_REF_ID(src) == 0 && src.pointee.name == nil &&
        (src.pointee.id & EcsIsEntity) == 0
    {
        src.pointee.id = EcsThis | ECS_TERM_REF_FLAGS(src) | EcsIsVariable
    }

    // Finalize flags
    if flecs_term_ref_finalize_flags(src, ctx, "src") != 0 { return -1 }
    if flecs_term_ref_finalize_flags(first, ctx, "first") != 0 { return -1 }
    if flecs_term_ref_finalize_flags(second, ctx, "second") != 0 { return -1 }

    // Lookup names
    if flecs_term_ref_lookup(world, 0, src, ctx) != 0 { return -1 }
    if flecs_term_ref_lookup(world, 0, first, ctx) != 0 { return -1 }

    // Lookup second with potential OneOf scope
    var oneof: ecs_entity_t = 0
    if (first.pointee.id & EcsIsEntity) != 0 {
        let first_id = ECS_TERM_REF_ID(first)
        if first_id != 0 {
            oneof = flecs_get_oneof(world, first_id)
        }
    }
    if flecs_term_ref_lookup(world, oneof, second, ctx) != 0 { return -1 }

    // Reset traversal for 0 source
    if ECS_TERM_REF_ID(src) == 0 && (src.pointee.id & EcsIsEntity) != 0 {
        src.pointee.id &= ~EcsTraverseFlags
        term.pointee.trav = 0
    }

    // Wildcard source produces no data
    if (src.pointee.id & EcsIsVariable) != 0 &&
        ecs_id_is_wildcard(ECS_TERM_REF_ID(src))
    {
        term.pointee.inout = EcsInOutNone
    }

    return 0
}


/// Get entity from a term ref (returns Wildcard for variables).
private func flecs_term_ref_get_entity(
    _ ref: UnsafePointer<ecs_term_ref_t>) -> ecs_entity_t
{
    if (ref.pointee.id & EcsIsEntity) != 0 {
        return ECS_TERM_REF_ID(ref)
    } else if (ref.pointee.id & EcsIsVariable) != 0 {
        return ECS_TERM_REF_ID(ref) != EcsAny ? EcsWildcard : EcsAny
    }
    return 0
}

/// Populate term.id from first/second refs.
private func flecs_term_populate_id(
    _ term: UnsafeMutablePointer<ecs_term_t>) -> Int32
{
    let first = flecs_term_ref_get_entity(&term.pointee.first)
    let second = flecs_term_ref_get_entity(&term.pointee.second)
    var flags = term.pointee.id & ECS_ID_FLAGS_MASK

    if (first & ECS_ID_FLAGS_MASK) != 0 { return -1 }
    if (second & ECS_ID_FLAGS_MASK) != 0 { return -1 }

    if second != 0 || (term.pointee.second.id & EcsIsEntity) != 0 {
        flags |= ECS_PAIR
    }

    if second == 0 && !ECS_HAS_ID_FLAG(flags, ECS_PAIR) {
        term.pointee.id = first | flags
    } else {
        term.pointee.id = ecs_pair(first, second) | flags
    }

    return 0
}

/// Populate term first/second from term.id.
private func flecs_term_populate_from_id(
    _ world: UnsafePointer<ecs_world_t>,
    _ term: UnsafeMutablePointer<ecs_term_t>,
    _ ctx: UnsafeMutablePointer<ecs_query_validator_ctx_t>) -> Int32
{
    if ECS_HAS_ID_FLAG(term.pointee.id, ECS_PAIR) {
        let first = ECS_PAIR_FIRST(term.pointee.id)
        let second = ECS_PAIR_SECOND(term.pointee.id)
        if first == 0 { return -1 }

        let term_first = flecs_term_ref_get_entity(&term.pointee.first)
        if term_first == 0 {
            let first_alive = ecs_get_alive(world, first)
            term.pointee.first.id = (first_alive != 0 ? first_alive : first) |
                ECS_TERM_REF_FLAGS(&term.pointee.first)
        }

        let term_second = flecs_term_ref_get_entity(&term.pointee.second)
        if term_second == 0 && second != 0 {
            let second_alive = ecs_get_alive(world, second)
            term.pointee.second.id = (second_alive != 0 ? second_alive : second) |
                ECS_TERM_REF_FLAGS(&term.pointee.second)
        }
    } else {
        let first = term.pointee.id & ECS_COMPONENT_MASK
        if first == 0 { return -1 }

        let term_first = flecs_term_ref_get_entity(&term.pointee.first)
        if term_first == 0 {
            let first_alive = ecs_get_alive(world, first)
            term.pointee.first.id = (first_alive != 0 ? first_alive : first) |
                ECS_TERM_REF_FLAGS(&term.pointee.first)
        }
    }

    return 0
}


/// Finalize a single term: resolve refs, populate id, set flags.
public func flecs_term_finalize(
    _ world: UnsafePointer<ecs_world_t>,
    _ term: UnsafeMutablePointer<ecs_term_t>,
    _ ctx: UnsafeMutablePointer<ecs_query_validator_ctx_t>) -> Int32
{
    ctx.pointee.term = UnsafePointer(term)

    // Populate from id if set
    if (term.pointee.id & ~ECS_ID_FLAGS_MASK) != 0 {
        if flecs_term_populate_from_id(world, term, ctx) != 0 { return -1 }
    }

    // Finalize refs
    if flecs_term_refs_finalize(world, term, ctx) != 0 { return -1 }

    // Populate id from refs if not set
    if (term.pointee.id & ~ECS_ID_FLAGS_MASK) == 0 {
        if flecs_term_populate_id(term) != 0 { return -1 }
    }

    // Set MatchAny/MatchAnySrc flags
    if (term.pointee.first.id & EcsIsVariable) != 0 &&
        ECS_TERM_REF_ID(&term.pointee.first) == EcsAny
    {
        term.pointee.flags_ |= EcsTermMatchAny
    }
    if (term.pointee.second.id & EcsIsVariable) != 0 &&
        ECS_TERM_REF_ID(&term.pointee.second) == EcsAny
    {
        term.pointee.flags_ |= EcsTermMatchAny
    }
    if (term.pointee.src.id & EcsIsVariable) != 0 &&
        ECS_TERM_REF_ID(&term.pointee.src) == EcsAny
    {
        term.pointee.flags_ |= EcsTermMatchAnySrc
    }

    // Default traversal
    let src = withUnsafeMutablePointer(to: &term.pointee.src) { $0 }
    let src_id = ECS_TERM_REF_ID(src)
    if src_id != 0 || src.pointee.name != nil {
        if (src.pointee.id & EcsTraverseFlags) == 0 {
            let cr_flags = flecs_component_get_flags(world, term.pointee.id)
            if (cr_flags & EcsIdOnInstantiateInherit) != 0 {
                src.pointee.id |= EcsSelf | EcsUp
                if term.pointee.trav == 0 {
                    term.pointee.trav = EcsIsA
                }
            } else {
                src.pointee.id |= EcsSelf
            }
        }

        if (src.pointee.id & EcsCascade) != 0 {
            src.pointee.id |= EcsUp
        }
        if (src.pointee.id & EcsUp) != 0 && term.pointee.trav == 0 {
            term.pointee.trav = EcsChildOf
        }
    }

    // Compute trivial/cacheable
    var cacheable = true
    var trivial = true

    if term.pointee.oper != EcsAnd || (term.pointee.flags_ & EcsTermIsOr) != 0 {
        trivial = false
    }
    if ecs_id_is_wildcard(term.pointee.id) { trivial = false }
    if !ecs_term_match_this(term) { trivial = false }
    if (term.pointee.flags_ & EcsTermTransitive) != 0 { trivial = false; cacheable = false }
    if (term.pointee.flags_ & EcsTermIdInherited) != 0 { trivial = false; cacheable = false }
    if (term.pointee.flags_ & EcsTermReflexive) != 0 { trivial = false; cacheable = false }
    if (term.pointee.flags_ & EcsTermIsMember) != 0 { trivial = false; cacheable = false }
    if (term.pointee.flags_ & EcsTermIsToggle) != 0 { trivial = false }
    if (term.pointee.flags_ & EcsTermDontFragment) != 0 { trivial = false; cacheable = false }
    if (src.pointee.id & EcsSelf) == 0 { trivial = false }
    if ECS_TERM_REF_ID(src) != EcsThis { cacheable = false }

    if trivial { term.pointee.flags_ |= EcsTermIsTrivial }
    if cacheable { term.pointee.flags_ |= EcsTermIsCacheable }

    return 0
}


/// Check if a term reference is set.
public func ecs_term_ref_is_set(
    _ ref: UnsafePointer<ecs_term_ref_t>) -> Bool
{
    return ECS_TERM_REF_ID(ref) != 0 || ref.pointee.name != nil ||
        (ref.pointee.id & EcsIsEntity) != 0
}

/// Check if a term is initialized (has id or first ref set).
public func ecs_term_is_initialized(
    _ term: UnsafePointer<ecs_term_t>) -> Bool
{
    return term.pointee.id != 0 || ecs_term_ref_is_set(&term.pointee.first)
}

/// Check if a term matches $this.
public func ecs_term_match_this(
    _ term: UnsafePointer<ecs_term_t>) -> Bool
{
    return (term.pointee.src.id & EcsIsVariable) != 0 &&
        ECS_TERM_REF_ID(&term.pointee.src) == EcsThis
}

/// Check if a term matches 0 (no source).
public func ecs_term_match_0(
    _ term: UnsafePointer<ecs_term_t>) -> Bool
{
    return ECS_TERM_REF_ID(&term.pointee.src) == 0 &&
        (term.pointee.src.id & EcsIsEntity) != 0
}


/// Finalize all terms in a query. This is the main validation entry point.
public func flecs_query_finalize_terms(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ q: UnsafeMutablePointer<ecs_query_t>,
    _ desc: UnsafePointer<ecs_query_desc_t>) -> Int32
{
    let term_count = q.pointee.term_count
    let terms = q.pointee.terms
    if terms == nil { return -1 }
    var field_count: Int8 = 0
    var cacheable_terms: Int32 = 0
    var cacheable = true

    var ctx = ecs_query_validator_ctx_t()
    ctx.world = world
    ctx.query = q
    ctx.desc = desc

    q.pointee.flags |= EcsQueryMatchOnlyThis

    // Mark Or chains
    for i in 0..<Int(term_count) {
        if terms![i].oper == EcsOr {
            terms![i].flags_ |= EcsTermIsOr
            if i + 1 < Int(term_count) {
                terms![i + 1].flags_ |= EcsTermIsOr
            }
        }
    }

    // Finalize each term
    for i in 0..<Int(term_count) {
        let prev_is_or = i > 0 && terms![i - 1].oper == EcsOr
        ctx.term_index = Int32(i)

        if flecs_term_finalize(UnsafePointer(world), &terms![i], &ctx) != 0 {
            return -1
        }

        // Track cacheability
        if (terms![i].flags_ & EcsTermIsCacheable) != 0 {
            if !prev_is_or || (i > 0 && (terms![i - 1].flags_ & EcsTermIsCacheable) != 0) {
                cacheable_terms += 1
            }
        }

        // Track field count (Or chains share a field)
        if !prev_is_or {
            field_count += 1
        }
        terms![i].field_index = Int8(field_count - 1)

        // Track MatchThis
        if ecs_term_match_this(&terms![i]) {
            q.pointee.flags |= EcsQueryMatchThis
        } else {
            q.pointee.flags &= ~EcsQueryMatchOnlyThis
        }

        // Track wildcards
        if ecs_id_is_wildcard(terms![i].id) {
            q.pointee.flags |= EcsQueryMatchWildcards
        }

        // Toggle check
        if (terms![i].flags_ & EcsTermIsToggle) != 0 {
            cacheable = false
        }

        // Nodata / inout handling
        if terms![i].oper == EcsNot && terms![i].inout == EcsInOutDefault {
            terms![i].inout = EcsInOutNone
        }

        // Sparse handling
        if (terms![i].flags_ & EcsTermIsSparse) != 0 {
            cacheable = false
        }
    }

    q.pointee.field_count = field_count

    // Populate ids and sizes from terms
    if field_count > 0 {
        for i in 0..<Int(term_count) {
            let field = Int(terms![i].field_index)
            q.pointee.ids![field] = terms![i].id

            if !ecs_term_match_0(&terms![i]) {
                flecs_component_lock(world, terms![i].id)
            }

            let cr = flecs_components_get(UnsafePointer(world), terms![i].id)
            if cr != nil {
                let ti = cr!.pointee.type_info
                if ti != nil {
                    q.pointee.sizes![field] = ti!.pointee.size
                }
            }
        }
    }

    // Set query-level cacheability flags
    if cacheable_terms > 0 {
        q.pointee.flags |= EcsQueryHasCacheable
    }
    if cacheable && cacheable_terms == Int32(term_count) {
        q.pointee.flags |= EcsQueryIsCacheable
    }

    // Check trivial
    if (q.pointee.flags & EcsQueryMatchOnlyThis) != 0 {
        var is_trivial = true
        q.pointee.flags |= EcsQueryMatchOnlySelf
        for i in 0..<Int(term_count) {
            if (terms![i].src.id & EcsUp) != 0 {
                q.pointee.flags &= ~EcsQueryMatchOnlySelf
            }
            if (terms![i].flags_ & EcsTermIsTrivial) == 0 {
                is_trivial = false
            }
        }
        if term_count > 0 && is_trivial {
            q.pointee.flags |= EcsQueryIsTrivial
        }
    }

    return 0
}


/// Top-level query finalization: populate terms, validate, tokenize.
public func flecs_query_finalize_query(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ q: UnsafeMutablePointer<ecs_query_t>,
    _ desc: UnsafeMutablePointer<ecs_query_desc_t>) -> Int32
{
    q.pointee.flags |= desc.pointee.flags

    // Allocate temporary term/size/id arrays
    let max_terms = Int(FLECS_TERM_COUNT_MAX)
    let terms_buf = ecs_os_calloc_n(ecs_term_t.self, Int32(max_terms))!
    let sizes_buf = ecs_os_calloc_n(ecs_size_t.self, Int32(max_terms))!
    let ids_buf = ecs_os_calloc_n(ecs_id_t.self, Int32(max_terms))!

    q.pointee.terms = terms_buf
    q.pointee.sizes = sizes_buf
    q.pointee.ids = ids_buf

    // Count and copy terms from descriptor
    var term_count: Int8 = 0
    withUnsafePointer(to: desc.pointee.terms) { termsPtr in
        let base = UnsafeRawPointer(termsPtr).assumingMemoryBound(to: ecs_term_t.self)
        for i in 0..<max_terms {
            if !ecs_term_is_initialized(&base[i]) { break }
            terms_buf[i] = base[i]
            term_count += 1
        }
    }
    q.pointee.term_count = term_count

    // Finalize terms
    if flecs_query_finalize_terms(world, q, UnsafePointer(desc)) != 0 {
        flecs_query_copy_arrays(q)
        return -1
    }

    // Copy arrays to owned memory
    flecs_query_copy_arrays(q)
    q.pointee.flags |= EcsQueryValid

    return 0
}
