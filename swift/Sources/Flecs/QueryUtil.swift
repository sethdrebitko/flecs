// QueryUtil.swift - 1:1 translation of flecs query/util.c
// Query utility functions: op strings, term analysis, plan formatting

import Foundation

// MARK: - Op Kind String

/// Get a human-readable string for a query operation kind.
public func flecs_query_op_str(_ kind: UInt16) -> UnsafePointer<CChar> {
    switch kind {
    case UInt16(EcsQueryAll):            return str("all         ")
    case UInt16(EcsQueryAnd):            return str("and         ")
    case UInt16(EcsQueryAndAny):         return str("and_any     ")
    case UInt16(EcsQueryAndWcTgt):       return str("and_wct     ")
    case UInt16(EcsQueryTriv):           return str("triv        ")
    case UInt16(EcsQueryCache):          return str("cache       ")
    case UInt16(EcsQueryIsCache):        return str("xcache      ")
    case UInt16(EcsQueryUp):             return str("up          ")
    case UInt16(EcsQuerySelfUp):         return str("selfup      ")
    case UInt16(EcsQueryWith):           return str("with        ")
    case UInt16(EcsQueryWithWcTgt):      return str("with_wct    ")
    case UInt16(EcsQueryTrav):           return str("trav        ")
    case UInt16(EcsQueryAndFrom):        return str("andfrom     ")
    case UInt16(EcsQueryOrFrom):         return str("orfrom      ")
    case UInt16(EcsQueryNotFrom):        return str("notfrom     ")
    case UInt16(EcsQueryIds):            return str("ids         ")
    case UInt16(EcsQueryIdsRight):       return str("idsr        ")
    case UInt16(EcsQueryIdsLeft):        return str("idsl        ")
    case UInt16(EcsQueryEach):           return str("each        ")
    case UInt16(EcsQueryStore):          return str("store       ")
    case UInt16(EcsQueryReset):          return str("reset       ")
    case UInt16(EcsQueryOr):             return str("or          ")
    case UInt16(EcsQueryOptional):       return str("option      ")
    case UInt16(EcsQueryIfVar):          return str("ifvar       ")
    case UInt16(EcsQueryIfSet):          return str("ifset       ")
    case UInt16(EcsQueryEnd):            return str("end         ")
    case UInt16(EcsQueryNot):            return str("not         ")
    case UInt16(EcsQueryYield):          return str("yield       ")
    case UInt16(EcsQueryNothing):        return str("nothing     ")
    default:                             return str("!invalid    ")
    }
}

/// Helper to return a static C string pointer.
@inline(__always)
private func str(_ s: StaticString) -> UnsafePointer<CChar> {
    return s.withUTF8Buffer { buf in
        return UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: CChar.self)
    }
}

// MARK: - Type Conversion Helpers

/// Convert int64 to query label (int16).
@inline(__always)
public func flecs_itolbl(_ val: Int64) -> ecs_query_lbl_t {
    return Int16(truncatingIfNeeded: val)
}

/// Convert int64 to var id (uint8).
@inline(__always)
public func flecs_itovar(_ val: Int64) -> ecs_var_id_t {
    return UInt8(truncatingIfNeeded: val)
}

/// Convert uint64 to var id (uint8).
@inline(__always)
public func flecs_utovar(_ val: UInt64) -> ecs_var_id_t {
    return UInt8(truncatingIfNeeded: val)
}

// MARK: - Term Analysis

/// Check if a term uses a builtin predicate (Eq, Match, Lookup).
public func flecs_term_is_builtin_pred(
    _ term: UnsafePointer<ecs_term_t>) -> Bool
{
    if (term.pointee.first.id & EcsIsEntity) != 0 {
        let id = ECS_TERM_REF_ID(&term.pointee.first)
        if id == EcsPredEq || id == EcsPredMatch || id == EcsPredLookup {
            return true
        }
    }
    return false
}

/// Get the variable name from a term reference.
public func flecs_term_ref_var_name(
    _ ref: UnsafePointer<ecs_term_ref_t>) -> UnsafePointer<CChar>?
{
    if (ref.pointee.id & EcsIsVariable) == 0 {
        return nil
    }
    if ECS_TERM_REF_ID(ref) == EcsThis {
        return EcsThisName.withCString { UnsafePointer(strdup($0)) }
    }
    return ref.pointee.name
}

/// Check if a term reference is a wildcard variable.
public func flecs_term_ref_is_wildcard(
    _ ref: UnsafePointer<ecs_term_ref_t>) -> Bool
{
    if (ref.pointee.id & EcsIsVariable) != 0 {
        let id = ECS_TERM_REF_ID(ref)
        return id == EcsWildcard || id == EcsAny
    }
    return false
}

/// Check if a term has a fixed id (not variable/wildcard/transitive).
public func flecs_term_is_fixed_id(
    _ q: UnsafePointer<ecs_query_t>,
    _ term: UnsafePointer<ecs_term_t>) -> Bool
{
    if (term.pointee.flags_ & (EcsTermTransitive | EcsTermIdInherited)) != 0 {
        return false
    }
    if term.pointee.oper == EcsOr { return false }

    // Check if previous term is Or
    if term != q.pointee.terms {
        let prev = term - 1
        if prev.pointee.oper == EcsOr { return false }
    }

    if ecs_id_is_wildcard(term.pointee.id) { return false }
    if (term.pointee.flags_ & (EcsTermMatchAny | EcsTermMatchAnySrc)) != 0 {
        return false
    }

    if term.pointee.oper == EcsNot || term.pointee.oper == EcsOptional {
        if term == q.pointee.terms { return false }
    }

    return true
}

/// Check if a term is part of an Or chain.
public func flecs_term_is_or(
    _ q: UnsafePointer<ecs_query_t>,
    _ term: UnsafePointer<ecs_term_t>) -> Bool
{
    let first_term = term == UnsafePointer(q.pointee.terms)
    return term.pointee.oper == EcsOr || (!first_term && (term - 1).pointee.oper == EcsOr)
}

// MARK: - Query Ref Flags

/// Extract ref flags (IsVar/IsEntity) for a given reference kind.
@inline(__always)
public func flecs_query_ref_flags(
    _ flags: ecs_flags16_t,
    _ kind: ecs_flags16_t) -> ecs_flags16_t
{
    return (flags >> kind) & (EcsQueryIsVar | EcsQueryIsEntity)
}

// MARK: - Written Variable Tracking

/// Check if a variable has been written to.
@inline(__always)
public func flecs_query_is_written(
    _ var_id: ecs_var_id_t,
    _ written: UInt64) -> Bool
{
    if var_id == EcsVarNone { return true }
    return (written & (1 << var_id)) != 0
}

/// Mark a variable as written.
@inline(__always)
public func flecs_query_write(
    _ var_id: ecs_var_id_t,
    _ written: UnsafeMutablePointer<UInt64>)
{
    written.pointee |= (1 << var_id)
}

/// Mark a variable as written in a compile context.
public func flecs_query_write_ctx(
    _ var_id: ecs_var_id_t,
    _ ctx: UnsafeMutablePointer<ecs_query_compile_ctx_t>,
    _ cond_write: Bool)
{
    let is_written = flecs_query_is_written(var_id, ctx.pointee.written)
    flecs_query_write(var_id, &ctx.pointee.written)
    if !is_written && cond_write {
        flecs_query_write(var_id, &ctx.pointee.cond_written)
    }
}

/// Check if a reference is written (entity or written variable).
public func flecs_ref_is_written(
    _ op: UnsafePointer<ecs_query_op_t>,
    _ ref: UnsafePointer<ecs_query_ref_t>,
    _ kind: ecs_flags16_t,
    _ written: UInt64) -> Bool
{
    let flags = flecs_query_ref_flags(op.pointee.flags, kind)
    if (flags & EcsQueryIsEntity) != 0 {
        return ref.pointee.entity != 0
    } else if (flags & EcsQueryIsVar) != 0 {
        return flecs_query_is_written(ref.pointee.var_id, written)
    }
    return false
}

// MARK: - Allocator Helper

/// Get the appropriate allocator for a query iterator.
public func flecs_query_get_allocator(
    _ it: UnsafePointer<ecs_iter_t>) -> UnsafeMutablePointer<ecs_allocator_t>?
{
    guard let world = it.pointee.world else { return nil }
    if flecs_poly_is_(UnsafeRawPointer(world), ecs_world_t_magic) {
        let w = world.assumingMemoryBound(to: ecs_world_t.self)
        return withUnsafeMutablePointer(to: &w.pointee.allocator) { $0 }
    } else {
        let s = world.assumingMemoryBound(to: ecs_stage_t.self)
        return withUnsafeMutablePointer(to: &s.pointee.allocator) { $0 }
    }
}

// MARK: - Term To String

/// Write a term to a string buffer.
public func flecs_term_to_buf(
    _ world: UnsafeMutableRawPointer?,
    _ term: UnsafePointer<ecs_term_t>,
    _ buf: UnsafeMutablePointer<ecs_strbuf_t>,
    _ t: Int32)
{
    let src_set = !ecs_term_match_0(term)
    let second_set = ecs_term_ref_is_set(&term.pointee.second)

    // InOut annotations
    if t == 0 || (term - 1).pointee.oper != EcsOr {
        if term.pointee.inout == EcsIn {
            ecs_strbuf_appendstr(buf, "[in] ")
        } else if term.pointee.inout == EcsInOut {
            ecs_strbuf_appendstr(buf, "[inout] ")
        } else if term.pointee.inout == EcsOut {
            ecs_strbuf_appendstr(buf, "[out] ")
        } else if term.pointee.inout == EcsInOutNone && term.pointee.oper != EcsNot {
            ecs_strbuf_appendstr(buf, "[none] ")
        }
    }

    // Operator prefix
    if term.pointee.oper == EcsNot {
        ecs_strbuf_appendstr(buf, "!")
    } else if term.pointee.oper == EcsOptional {
        ecs_strbuf_appendstr(buf, "?")
    }

    if !src_set {
        // No source - write as first() or first(#0, second)
        flecs_query_str_add_id(world, buf, term, &term.pointee.first, false)
        if !second_set {
            ecs_strbuf_appendstr(buf, "()")
        } else {
            ecs_strbuf_appendstr(buf, "(#0,")
            flecs_query_str_add_id(world, buf, term, &term.pointee.second, false)
            ecs_strbuf_appendstr(buf, ")")
        }
    } else {
        // Has source - write as first(src) or first(src, second)
        flecs_query_str_add_id(world, buf, term, &term.pointee.first, false)
        ecs_strbuf_appendstr(buf, "(")
        flecs_query_str_add_id(world, buf, term, &term.pointee.src, true)
        if second_set {
            ecs_strbuf_appendstr(buf, ",")
            flecs_query_str_add_id(world, buf, term, &term.pointee.second, false)
        }
        ecs_strbuf_appendstr(buf, ")")
    }
}

/// Write a term reference id/name to a string buffer.
private func flecs_query_str_add_id(
    _ world: UnsafeMutableRawPointer?,
    _ buf: UnsafeMutablePointer<ecs_strbuf_t>,
    _ term: UnsafePointer<ecs_term_t>,
    _ ref: UnsafePointer<ecs_term_ref_t>,
    _ is_src: Bool)
{
    let ref_id = ECS_TERM_REF_ID(ref)

    if (ref.pointee.id & EcsIsVariable) != 0 && !ecs_id_is_wildcard(ref_id) {
        ecs_strbuf_appendstr(buf, "$")
    }

    if ref_id != 0 {
        if let world = world {
            let w = world.assumingMemoryBound(to: ecs_world_t.self)
            if let path = ecs_get_path(UnsafePointer(w), ref_id) {
                ecs_strbuf_appendstr(buf, path)
                ecs_os_free(UnsafeMutableRawPointer(mutating: path))
            }
        } else {
            let s = String(ref_id)
            s.withCString { ecs_strbuf_appendstr(buf, $0) }
        }
    } else if let name = ref.pointee.name {
        ecs_strbuf_appendstr(buf, name)
    } else {
        ecs_strbuf_appendstr(buf, "#0")
    }

    // Traversal flags
    let flags = ECS_TERM_REF_FLAGS(ref)
    if is_src && (flags & EcsTraverseFlags) != EcsSelf {
        if (flags & EcsSelf) != 0 {
            ecs_strbuf_appendstr(buf, "|self")
        }
        if (flags & EcsUp) != 0 {
            ecs_strbuf_appendstr(buf, "|up")
        }
        if (flags & EcsCascade) != 0 {
            ecs_strbuf_appendstr(buf, "|cascade")
        }
    }
}

/// Get string representation of a single term.
public func ecs_term_str(
    _ world: UnsafePointer<ecs_world_t>,
    _ term: UnsafePointer<ecs_term_t>) -> UnsafeMutablePointer<CChar>?
{
    var buf = ecs_strbuf_t()
    flecs_term_to_buf(UnsafeMutableRawPointer(mutating: world), term, &buf, 0)
    return ecs_strbuf_get(&buf)
}

/// Set a query iterator id field.
public func flecs_query_iter_set_id(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ field: Int8,
    _ id: ecs_id_t) -> ecs_id_t
{
    it.pointee.ids![Int(field)] = id
    return id
}
