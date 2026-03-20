// QueryTypes.swift - 1:1 translation of flecs query internal types
// Query operations, variables, compiler state, and execution context

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


public typealias ecs_var_id_t = UInt8
public typealias ecs_query_lbl_t = Int16
public typealias ecs_write_flags_t = ecs_flags64_t

public let EcsQueryMaxVarCount: Int32 = 64
public let EcsVarNone: ecs_var_id_t = UInt8.max
public let EcsThisName: String = "this"


public enum ecs_var_kind_t: Int32 {
    case entity = 0
    case table = 1
    case any = 2
}

public struct ecs_query_var_t {
    public var kind: Int8 = 0
    public var anonymous: Bool = false
    public var id: ecs_var_id_t = 0
    public var table_id: ecs_var_id_t = 0
    public var base_id: ecs_var_id_t = 0
    public var name: UnsafePointer<CChar>? = nil
    public var lookup: UnsafePointer<CChar>? = nil
    public init() {}
}


public enum ecs_query_op_kind_t: UInt8 {
    case all = 0
    case and = 1
    case andAny = 2
    case andWcTgt = 3
    case triv = 4
    case cache = 5
    case isCache = 6
    case up = 7
    case selfUp = 8
    case with = 9
    case withWcTgt = 10
    case trav = 11
    case andFrom = 12
    case orFrom = 13
    case notFrom = 14
    case ids = 15
    case idsRight = 16
    case idsLeft = 17
    case each = 18
    case store = 19
    case reset = 20
    case or = 21
    case optional = 22
    case ifVar = 23
    case ifSet = 24
    case not = 25
    case end = 26
    case predEq = 27
    case predNeq = 28
    case predEqName = 29
    case predNeqName = 30
    case predEqMatch = 31
    case predNeqMatch = 32
    case memberEq = 33
    case memberNeq = 34
    case toggle = 35
    case toggleOption = 36
    case sparse = 37
    case sparseNot = 38
    case sparseSelfUp = 39
    case sparseUp = 40
    case sparseWith = 41
    case tree = 42
    case treeWildcard = 43
    case treeWith = 44
    case treeUp = 45
    case treeSelfUp = 46
    case treePre = 47
    case treePost = 48
    case treeUpPre = 49
    case treeSelfUpPre = 50
    case treeUpPost = 51
    case treeSelfUpPost = 52
    case children = 53
    case childrenWc = 54
    case lookup = 55
    case setVars = 56
    case setThis = 57
    case setFixed = 58
    case setIds = 59
    case setId = 60
    case contain = 61
    case pairEq = 62
    case yield = 63
    case nothing = 64
}


public let EcsQueryIsEntity_: UInt8 = 1 << 0
public let EcsQueryIsVar_: UInt8 = 1 << 1
public let EcsQueryIsSelf_: UInt8 = 1 << 6

public let EcsQuerySrc_: UInt8 = 0
public let EcsQueryFirst_: UInt8 = 2
public let EcsQuerySecond_: UInt8 = 4


public struct ecs_query_ref_t {
    // Union: either a var id or an entity
    public var var_id: ecs_var_id_t = 0
    public var entity: ecs_entity_t = 0
    public init() {}
}


public struct ecs_query_op_t {
    public var kind: UInt8 = 0
    public var flags: ecs_flags8_t = 0
    public var field_index: Int8 = 0
    public var term_index: Int8 = 0
    public var prev: ecs_query_lbl_t = 0
    public var next: ecs_query_lbl_t = 0
    public var other: ecs_query_lbl_t = 0
    public var match_flags: ecs_flags16_t = 0
    public var src: ecs_query_ref_t = ecs_query_ref_t()
    public var first: ecs_query_ref_t = ecs_query_ref_t()
    public var second: ecs_query_ref_t = ecs_query_ref_t()
    public var written: ecs_flags64_t = 0
    public init() {}
}


public struct ecs_query_all_ctx_t {
    public var cur: Int32 = 0
    public var dummy_tr: ecs_table_record_t = ecs_table_record_t()
    public init() {}
}

public struct ecs_query_and_ctx_t {
    public var cr: UnsafeMutableRawPointer? = nil  // ecs_component_record_t*
    public var it: ecs_table_cache_iter_t = ecs_table_cache_iter_t()
    public var column: Int16 = 0
    public var remaining: Int16 = 0
    public var non_fragmenting: Bool = false
    public init() {}
}

public struct ecs_query_each_ctx_t {
    public var row: Int32 = 0
    public init() {}
}

public struct ecs_query_setthis_ctx_t {
    public var range: ecs_table_range_t = ecs_table_range_t()
    public init() {}
}

public struct ecs_query_ids_ctx_t {
    public var cur: UnsafeMutableRawPointer? = nil  // ecs_component_record_t*
    public init() {}
}

public struct ecs_query_ctrl_ctx_t {
    public var op_index: ecs_query_lbl_t = 0
    public var field_id: ecs_id_t = 0
    public var is_set: Bool = false
    public init() {}
}

public struct ecs_query_trivial_ctx_t {
    public var it: ecs_table_cache_iter_t = ecs_table_cache_iter_t()
    public var tr: UnsafePointer<ecs_table_record_t>? = nil
    public var start_from: Int32 = 0
    public var first_to_eval: Int32 = 0
    public init() {}
}

public struct ecs_query_eq_ctx_t {
    public var range: ecs_table_range_t = ecs_table_range_t()
    public var index: Int32 = 0
    public var name_col: Int16 = 0
    public var redo: Bool = false
    public init() {}
}

public struct ecs_query_toggle_ctx_t {
    public var range: ecs_table_range_t = ecs_table_range_t()
    public var cur: Int32 = 0
    public var block_index: Int32 = 0
    public var block: ecs_flags64_t = 0
    public var prev_set_fields: ecs_termset_t = 0
    public var optional_not: Bool = false
    public var has_bitset: Bool = false
    public init() {}
}

public struct ecs_query_optional_ctx_t {
    public var range: ecs_table_range_t = ecs_table_range_t()
    public init() {}
}

// Traversal types
public enum ecs_trav_direction_t: Int32 {
    case up = 1
    case down = 2
}

public struct ecs_trav_down_elem_t {
    public var range: ecs_table_range_t = ecs_table_range_t()
    public var leaf: Bool = false
    public init() {}
}

public struct ecs_trav_down_t {
    public var elems: ecs_vec_t = ecs_vec_t()
    public var ready: Bool = false
    public init() {}
}

public struct ecs_trav_up_t {
    public var src: ecs_entity_t = 0
    public var id: ecs_id_t = 0
    public var tr: UnsafeMutablePointer<ecs_table_record_t>? = nil
    public var ready: Bool = false
    public init() {}
}

public struct ecs_trav_up_cache_t {
    public var src: ecs_map_t = ecs_map_t()
    public var with: ecs_id_t = 0
    public var dir: ecs_trav_direction_t = .up
    public init() {}
}

public struct ecs_trav_elem_t {
    public var entity: ecs_entity_t = 0
    public var cr: UnsafeMutableRawPointer? = nil  // ecs_component_record_t*
    public var tr: UnsafePointer<ecs_table_record_t>? = nil
    public init() {}
}

public struct ecs_trav_cache_t {
    public var id: ecs_id_t = 0
    public var cr: UnsafeMutableRawPointer? = nil  // ecs_component_record_t*
    public var entities: ecs_vec_t = ecs_vec_t()
    public var up: Bool = false
    public init() {}
}

// In C this is a union. In Swift we store the largest variant and reinterpret.
public struct ecs_query_op_ctx_t {
    // We use a raw storage approach since Swift doesn't have C unions
    // Store the data as raw bytes sized to the largest variant
    public var storage: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                         UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                         UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                         UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

    public init() {}

    public mutating func withAndCtx<R>(_ body: (inout ecs_query_and_ctx_t) -> R) -> R {
        return withUnsafeMutablePointer(to: &storage) { ptr in
            let typed = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: ecs_query_and_ctx_t.self)
            return body(&typed.pointee)
        }
    }

    public mutating func withEachCtx<R>(_ body: (inout ecs_query_each_ctx_t) -> R) -> R {
        return withUnsafeMutablePointer(to: &storage) { ptr in
            let typed = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: ecs_query_each_ctx_t.self)
            return body(&typed.pointee)
        }
    }
}


public struct ecs_query_compile_ctrlflow_t {
    public var lbl_query: ecs_query_lbl_t = 0
    public var lbl_begin: ecs_query_lbl_t = 0
    public var lbl_cond_eval: ecs_query_lbl_t = 0
    public var written_or: ecs_write_flags_t = 0
    public var cond_written_or: ecs_write_flags_t = 0
    public var src_or: ecs_query_ref_t = ecs_query_ref_t()
    public var src_written_or: Bool = false
    public var in_or: Bool = false
    public init() {}
}

public struct ecs_query_compile_ctx_t {
    public var ops: UnsafeMutablePointer<ecs_vec_t>? = nil
    public var written: ecs_write_flags_t = 0
    public var cond_written: ecs_write_flags_t = 0
    public var ctrlflow: (ecs_query_compile_ctrlflow_t, ecs_query_compile_ctrlflow_t,
                          ecs_query_compile_ctrlflow_t, ecs_query_compile_ctrlflow_t,
                          ecs_query_compile_ctrlflow_t, ecs_query_compile_ctrlflow_t,
                          ecs_query_compile_ctrlflow_t, ecs_query_compile_ctrlflow_t) =
        (ecs_query_compile_ctrlflow_t(), ecs_query_compile_ctrlflow_t(),
         ecs_query_compile_ctrlflow_t(), ecs_query_compile_ctrlflow_t(),
         ecs_query_compile_ctrlflow_t(), ecs_query_compile_ctrlflow_t(),
         ecs_query_compile_ctrlflow_t(), ecs_query_compile_ctrlflow_t())
    public var cur: UnsafeMutablePointer<ecs_query_compile_ctrlflow_t>? = nil
    public var scope: Int32 = 0
    public var scope_is_not: ecs_flags32_t = 0
    public var oper: Int16 = 0  // ecs_oper_kind_t
    public var skipped: Int32 = 0
    public init() {}
}


public struct ecs_query_run_ctx_t {
    public var written: UnsafeMutablePointer<UInt64>? = nil
    public var op_index: ecs_query_lbl_t = 0
    public var vars: UnsafeMutablePointer<ecs_var_t>? = nil
    public var it: UnsafeMutablePointer<ecs_iter_t>? = nil
    public var op_ctx: UnsafeMutablePointer<ecs_query_op_ctx_t>? = nil
    public var world: UnsafeMutableRawPointer? = nil  // ecs_world_t*
    public var query: UnsafePointer<ecs_query_impl_t>? = nil
    public var query_vars: UnsafePointer<ecs_query_var_t>? = nil
    public var qit: UnsafeMutablePointer<ecs_query_iter_t>? = nil
    public init() {}
}


public struct ecs_query_impl_t {
    public var pub: ecs_query_t = ecs_query_t()
    public var stage: UnsafeMutableRawPointer? = nil  // ecs_stage_t*
    public var vars: UnsafeMutablePointer<ecs_query_var_t>? = nil
    public var var_count: Int32 = 0
    public var var_size: Int32 = 0
    public var tvar_index: ecs_hashmap_t = ecs_hashmap_t()
    public var evar_index: ecs_hashmap_t = ecs_hashmap_t()
    public var src_vars: UnsafeMutablePointer<ecs_var_id_t>? = nil
    public var ops: UnsafeMutablePointer<ecs_query_op_t>? = nil
    public var op_count: Int32 = 0
    public var tokens_len: Int16 = 0
    public var tokens: UnsafeMutablePointer<CChar>? = nil
    public var monitor: UnsafeMutablePointer<Int32>? = nil
    public var cache: UnsafeMutableRawPointer? = nil  // ecs_query_cache_t*
    public var ctx_free: ecs_ctx_free_t? = nil
    public var binding_ctx_free: ecs_ctx_free_t? = nil
    public var dtor: flecs_poly_dtor_t? = nil
    public init() {}
}

// Note: ecs_event_id_record_t is defined in Observable.swift
// Note: ecs_observer_impl_t is defined in Observer.swift
