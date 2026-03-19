// Structs.swift - 1:1 translation of flecs core structs
// All public API struct types and function pointer typealiases

import Foundation

// MARK: - Function Pointer Types

public typealias ecs_run_action_t = @convention(c) (UnsafeMutablePointer<ecs_iter_t>?) -> Void
public typealias ecs_iter_action_t = @convention(c) (UnsafeMutablePointer<ecs_iter_t>?) -> Void
public typealias ecs_iter_next_action_t = @convention(c) (UnsafeMutablePointer<ecs_iter_t>?) -> Bool
public typealias ecs_iter_fini_action_t = @convention(c) (UnsafeMutablePointer<ecs_iter_t>?) -> Void
public typealias ecs_order_by_action_t = @convention(c) (ecs_entity_t, UnsafeRawPointer?, ecs_entity_t, UnsafeRawPointer?) -> Int32
public typealias ecs_sort_table_action_t = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<ecs_entity_t>?, UnsafeMutableRawPointer?, Int32, Int32, Int32, ecs_order_by_action_t?) -> Void
public typealias ecs_group_by_action_t = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, ecs_id_t, UnsafeMutableRawPointer?) -> UInt64
public typealias ecs_group_create_action_t = @convention(c) (UnsafeMutableRawPointer?, UInt64, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
public typealias ecs_group_delete_action_t = @convention(c) (UnsafeMutableRawPointer?, UInt64, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
public typealias ecs_module_action_t = @convention(c) (UnsafeMutableRawPointer?) -> Void
public typealias ecs_fini_action_t = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
public typealias ecs_ctx_free_t = @convention(c) (UnsafeMutableRawPointer?) -> Void
public typealias ecs_compare_action_t = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> Int32
public typealias ecs_hash_value_action_t = @convention(c) (UnsafeRawPointer?) -> UInt64
public typealias ecs_xtor_t = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<ecs_type_info_t>?) -> Void
public typealias ecs_copy_t = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, UnsafePointer<ecs_type_info_t>?) -> Void
public typealias ecs_move_t = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, UnsafePointer<ecs_type_info_t>?) -> Void
public typealias ecs_cmp_t = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafePointer<ecs_type_info_t>?) -> Int32
public typealias ecs_equals_t = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafePointer<ecs_type_info_t>?) -> Bool
public typealias flecs_poly_dtor_t = @convention(c) (UnsafeMutableRawPointer?) -> Void

// MARK: - Core Structs

public struct ecs_type_t {
    public var array: UnsafeMutablePointer<ecs_id_t>? = nil
    public var count: Int32 = 0
    public init() {}
}

public struct ecs_header_t {
    public var type: Int32 = 0
    public var refcount: Int32 = 0
    public var mixins: UnsafeMutableRawPointer? = nil
    public init() {}
}

public struct ecs_term_ref_t {
    public var id: ecs_entity_t = 0
    public var name: UnsafePointer<CChar>? = nil
    public init() {}
}

public struct ecs_term_t {
    public var id: ecs_id_t = 0
    public var src: ecs_term_ref_t = ecs_term_ref_t()
    public var first: ecs_term_ref_t = ecs_term_ref_t()
    public var second: ecs_term_ref_t = ecs_term_ref_t()
    public var trav: ecs_entity_t = 0
    public var inout: Int16 = 0
    public var oper: Int16 = 0
    public var field_index: Int8 = 0
    public var flags_: ecs_flags16_t = 0
    public init() {}
}

public struct ecs_value_t {
    public var type: ecs_entity_t = 0
    public var ptr: UnsafeMutableRawPointer? = nil
    public init() {}
}

public struct ecs_table_range_t {
    public var table: UnsafeMutableRawPointer? = nil
    public var offset: Int32 = 0
    public var count: Int32 = 0
    public init() {}
}

public struct ecs_var_t {
    public var range: ecs_table_range_t = ecs_table_range_t()
    public var entity: ecs_entity_t = 0
    public init() {}
}

public struct ecs_ref_t {
    public var entity: ecs_entity_t = 0
    public var id: ecs_entity_t = 0
    public var table_id: UInt64 = 0
    public var table_version_fast: UInt32 = 0
    public var table_version: UInt16 = 0
    public var record: UnsafeMutableRawPointer? = nil
    public var ptr: UnsafeMutableRawPointer? = nil
    public init() {}
}

// MARK: - Type Hooks

public struct ecs_type_hooks_t {
    public var ctor: ecs_xtor_t? = nil
    public var dtor: ecs_xtor_t? = nil
    public var copy: ecs_copy_t? = nil
    public var move: ecs_move_t? = nil
    public var copy_ctor: ecs_copy_t? = nil
    public var move_ctor: ecs_move_t? = nil
    public var ctor_move_dtor: ecs_move_t? = nil
    public var move_dtor: ecs_move_t? = nil
    public var cmp: ecs_cmp_t? = nil
    public var equals: ecs_equals_t? = nil
    public var flags: ecs_flags32_t = 0
    public var on_add: ecs_iter_action_t? = nil
    public var on_set: ecs_iter_action_t? = nil
    public var on_remove: ecs_iter_action_t? = nil
    public var on_replace: ecs_iter_action_t? = nil
    public var ctx: UnsafeMutableRawPointer? = nil
    public var binding_ctx: UnsafeMutableRawPointer? = nil
    public var lifecycle_ctx: UnsafeMutableRawPointer? = nil
    public var ctx_free: ecs_ctx_free_t? = nil
    public var binding_ctx_free: ecs_ctx_free_t? = nil
    public var lifecycle_ctx_free: ecs_ctx_free_t? = nil
    public init() {}
}

public struct ecs_type_info_t {
    public var size: ecs_size_t = 0
    public var alignment: ecs_size_t = 0
    public var hooks: ecs_type_hooks_t = ecs_type_hooks_t()
    public var component: ecs_entity_t = 0
    public var name: UnsafePointer<CChar>? = nil
    public init() {}
}

// MARK: - Record & Table Record

public struct ecs_record_t {
    public var table: UnsafeMutableRawPointer? = nil
    public var row: UInt32 = 0
    public var dense: Int32 = 0
    public init() {}
}

public struct ecs_table_cache_hdr_t {
    public var cr: UnsafeMutableRawPointer? = nil
    public var table: UnsafeMutableRawPointer? = nil
    public var prev: UnsafeMutablePointer<ecs_table_cache_hdr_t>? = nil
    public var next: UnsafeMutablePointer<ecs_table_cache_hdr_t>? = nil
    public init() {}
}

public struct ecs_table_record_t {
    public var hdr: ecs_table_cache_hdr_t = ecs_table_cache_hdr_t()
    public var index: Int16 = 0
    public var count: Int16 = 0
    public var column: Int16 = 0
    public init() {}
}

public struct ecs_table_diff_t {
    public var added: ecs_type_t = ecs_type_t()
    public var removed: ecs_type_t = ecs_type_t()
    public var added_flags: ecs_flags32_t = 0
    public var removed_flags: ecs_flags32_t = 0
    public init() {}
}

// MARK: - Query

public struct ecs_query_t {
    public var hdr: ecs_header_t = ecs_header_t()
    public var terms: UnsafeMutablePointer<ecs_term_t>? = nil
    public var sizes: UnsafeMutablePointer<Int32>? = nil
    public var ids: UnsafeMutablePointer<ecs_id_t>? = nil
    public var bloom_filter: UInt64 = 0
    public var flags: ecs_flags32_t = 0
    public var var_count: Int8 = 0
    public var term_count: Int8 = 0
    public var field_count: Int8 = 0
    public var fixed_fields: ecs_termset_t = 0
    public var var_fields: ecs_termset_t = 0
    public var static_id_fields: ecs_termset_t = 0
    public var data_fields: ecs_termset_t = 0
    public var write_fields: ecs_termset_t = 0
    public var read_fields: ecs_termset_t = 0
    public var row_fields: ecs_termset_t = 0
    public var shared_readonly_fields: ecs_termset_t = 0
    public var set_fields: ecs_termset_t = 0
    public var cache_kind: EcsQueryCacheKind = .default
    public var vars: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? = nil
    public var ctx: UnsafeMutableRawPointer? = nil
    public var binding_ctx: UnsafeMutableRawPointer? = nil
    public var entity: ecs_entity_t = 0
    public var real_world: UnsafeMutableRawPointer? = nil
    public var world: UnsafeMutableRawPointer? = nil
    public var eval_count: Int32 = 0
    public init() {}
}

// MARK: - Observer

public struct ecs_observer_t {
    public var hdr: ecs_header_t = ecs_header_t()
    public var query: UnsafeMutablePointer<ecs_query_t>? = nil
    public var events: (ecs_entity_t, ecs_entity_t, ecs_entity_t, ecs_entity_t, ecs_entity_t, ecs_entity_t, ecs_entity_t, ecs_entity_t) = (0, 0, 0, 0, 0, 0, 0, 0)
    public var event_count: Int32 = 0
    public var callback: ecs_iter_action_t? = nil
    public var run: ecs_run_action_t? = nil
    public var ctx: UnsafeMutableRawPointer? = nil
    public var callback_ctx: UnsafeMutableRawPointer? = nil
    public var run_ctx: UnsafeMutableRawPointer? = nil
    public var ctx_free: ecs_ctx_free_t? = nil
    public var callback_ctx_free: ecs_ctx_free_t? = nil
    public var run_ctx_free: ecs_ctx_free_t? = nil
    public var observable: UnsafeMutableRawPointer? = nil
    public var world: UnsafeMutableRawPointer? = nil
    public var entity: ecs_entity_t = 0
    public init() {}
}

// MARK: - Descriptor Structs

public struct ecs_entity_desc_t {
    public var _canary: Int32 = 0
    public var id: ecs_entity_t = 0
    public var parent: ecs_entity_t = 0
    public var name: UnsafePointer<CChar>? = nil
    public var sep: UnsafePointer<CChar>? = nil
    public var root_sep: UnsafePointer<CChar>? = nil
    public var symbol: UnsafePointer<CChar>? = nil
    public var use_low_id: Bool = false
    public var add: UnsafePointer<ecs_id_t>? = nil
    public var set: UnsafePointer<ecs_value_t>? = nil
    public var add_expr: UnsafePointer<CChar>? = nil
    public init() {}
}

public struct ecs_bulk_desc_t {
    public var _canary: Int32 = 0
    public var entities: UnsafeMutablePointer<ecs_entity_t>? = nil
    public var count: Int32 = 0
    public var ids: (ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t,
                     ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t,
                     ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t,
                     ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t, ecs_id_t) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    public var data: UnsafeMutablePointer<UnsafeMutableRawPointer?>? = nil
    public var table: UnsafeMutableRawPointer? = nil
    public init() {}
}

public struct ecs_component_desc_t {
    public var _canary: Int32 = 0
    public var entity: ecs_entity_t = 0
    public var type: ecs_type_info_t = ecs_type_info_t()
    public init() {}
}

public struct ecs_query_desc_t {
    public var _canary: Int32 = 0
    // Store terms as a fixed-size tuple of 32
    public var terms: (ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t,
                       ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t,
                       ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t,
                       ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t, ecs_term_t)
    public var expr: UnsafePointer<CChar>? = nil
    public var cache_kind: EcsQueryCacheKind = .default
    public var flags: ecs_flags32_t = 0
    public var order_by_callback: ecs_order_by_action_t? = nil
    public var order_by_table_callback: ecs_sort_table_action_t? = nil
    public var order_by: ecs_entity_t = 0
    public var group_by: ecs_id_t = 0
    public var group_by_callback: ecs_group_by_action_t? = nil
    public var on_group_create: ecs_group_create_action_t? = nil
    public var on_group_delete: ecs_group_delete_action_t? = nil
    public var group_by_ctx: UnsafeMutableRawPointer? = nil
    public var group_by_ctx_free: ecs_ctx_free_t? = nil
    public var ctx: UnsafeMutableRawPointer? = nil
    public var binding_ctx: UnsafeMutableRawPointer? = nil
    public var ctx_free: ecs_ctx_free_t? = nil
    public var binding_ctx_free: ecs_ctx_free_t? = nil
    public var entity: ecs_entity_t = 0

    public init() {
        let t = ecs_term_t()
        self.terms = (t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t)
    }
}

public struct ecs_observer_desc_t {
    public var _canary: Int32 = 0
    public var entity: ecs_entity_t = 0
    public var query: ecs_query_desc_t = ecs_query_desc_t()
    public var events: (ecs_entity_t, ecs_entity_t, ecs_entity_t, ecs_entity_t, ecs_entity_t, ecs_entity_t, ecs_entity_t, ecs_entity_t) = (0,0,0,0,0,0,0,0)
    public var yield_existing: Bool = false
    public var global_observer: Bool = false
    public var callback: ecs_iter_action_t? = nil
    public var run: ecs_run_action_t? = nil
    public var ctx: UnsafeMutableRawPointer? = nil
    public var ctx_free: ecs_ctx_free_t? = nil
    public var callback_ctx: UnsafeMutableRawPointer? = nil
    public var callback_ctx_free: ecs_ctx_free_t? = nil
    public var run_ctx: UnsafeMutableRawPointer? = nil
    public var run_ctx_free: ecs_ctx_free_t? = nil
    public var last_event_id: UnsafeMutablePointer<Int32>? = nil
    public var term_index_: Int8 = 0
    public var flags_: ecs_flags32_t = 0
    public init() {}
}

public struct ecs_event_desc_t {
    public var event: ecs_entity_t = 0
    public var ids: UnsafePointer<ecs_type_t>? = nil
    public var table: UnsafeMutableRawPointer? = nil
    public var other_table: UnsafeMutableRawPointer? = nil
    public var offset: Int32 = 0
    public var count: Int32 = 0
    public var entity: ecs_entity_t = 0
    public var param: UnsafeMutableRawPointer? = nil
    public var const_param: UnsafeRawPointer? = nil
    public var observable: UnsafeMutableRawPointer? = nil
    public var flags: ecs_flags32_t = 0
    public init() {}
}

// MARK: - Iterator Private Types

public struct ecs_page_iter_t {
    public var offset: Int32 = 0
    public var limit: Int32 = 0
    public var remaining: Int32 = 0
    public init() {}
}

public struct ecs_worker_iter_t {
    public var index: Int32 = 0
    public var count: Int32 = 0
    public init() {}
}

public struct ecs_table_cache_iter_t {
    public var cur: UnsafePointer<ecs_table_cache_hdr_t>? = nil
    public var next: UnsafePointer<ecs_table_cache_hdr_t>? = nil
    public var iter_fill: Bool = false
    public var iter_empty: Bool = false
    public init() {}
}

public struct ecs_each_iter_t {
    public var it: ecs_table_cache_iter_t = ecs_table_cache_iter_t()
    public var ids: ecs_id_t = 0
    public var sources: ecs_entity_t = 0
    public var sizes: ecs_size_t = 0
    public var columns: Int32 = 0
    public var trs: UnsafePointer<ecs_table_record_t>? = nil
    public init() {}
}

public struct ecs_query_op_profile_t {
    public var count: (Int32, Int32) = (0, 0)
    public init() {}
}

// Simplified query iter - stores raw bytes for the complex union
public struct ecs_query_iter_t {
    public var vars: UnsafeMutablePointer<ecs_var_t>? = nil
    public var query_vars: UnsafeRawPointer? = nil
    public var ops: UnsafeRawPointer? = nil
    public var op_ctx: UnsafeMutableRawPointer? = nil
    public var written: UnsafeMutablePointer<UInt64>? = nil
    public var group: UnsafeMutableRawPointer? = nil
    public var tables: UnsafeMutablePointer<ecs_vec_t>? = nil
    public var all_tables: UnsafeMutablePointer<ecs_vec_t>? = nil
    public var elem: UnsafeMutableRawPointer? = nil
    public var cur: Int32 = 0
    public var all_cur: Int32 = 0
    public var profile: UnsafeMutablePointer<ecs_query_op_profile_t>? = nil
    public var op: Int16 = 0
    public var iter_single_group: Bool = false
    public init() {}
}

public struct ecs_commands_t {
    public var queue: ecs_vec_t = ecs_vec_t()
    public var stack: ecs_stack_t = ecs_stack_t()
    public var entries: ecs_sparse_t = ecs_sparse_t()
    public init() {}
}

// The iter private data uses a union in C; we use the largest variant
public struct ecs_iter_private_t {
    public var query: ecs_query_iter_t = ecs_query_iter_t()
    public var entity_iter: UnsafeMutableRawPointer? = nil
    public var stack_cursor: UnsafeMutableRawPointer? = nil
    public init() {}
}

// MARK: - The Main Iterator

public struct ecs_iter_t {
    // World
    public var world: UnsafeMutableRawPointer? = nil
    public var real_world: UnsafeMutableRawPointer? = nil

    // Matched data
    public var offset: Int32 = 0
    public var count: Int32 = 0
    public var entities: UnsafePointer<ecs_entity_t>? = nil
    public var ptrs: UnsafeMutablePointer<UnsafeMutableRawPointer?>? = nil
    public var trs: UnsafePointer<UnsafePointer<ecs_table_record_t>?>? = nil
    public var sizes: UnsafePointer<ecs_size_t>? = nil
    public var table: UnsafeMutableRawPointer? = nil
    public var other_table: UnsafeMutableRawPointer? = nil
    public var ids: UnsafeMutablePointer<ecs_id_t>? = nil
    public var sources: UnsafeMutablePointer<ecs_entity_t>? = nil
    public var constrained_vars: ecs_flags64_t = 0
    public var set_fields: ecs_termset_t = 0
    public var ref_fields: ecs_termset_t = 0
    public var row_fields: ecs_termset_t = 0
    public var up_fields: ecs_termset_t = 0

    // Input information
    public var system: ecs_entity_t = 0
    public var event: ecs_entity_t = 0
    public var event_id: ecs_id_t = 0
    public var event_cur: Int32 = 0

    // Query information
    public var field_count: Int8 = 0
    public var term_index: Int8 = 0
    public var query: UnsafePointer<ecs_query_t>? = nil

    // Context
    public var param: UnsafeMutableRawPointer? = nil
    public var ctx: UnsafeMutableRawPointer? = nil
    public var binding_ctx: UnsafeMutableRawPointer? = nil
    public var callback_ctx: UnsafeMutableRawPointer? = nil
    public var run_ctx: UnsafeMutableRawPointer? = nil

    // Time
    public var delta_time: ecs_ftime_t = 0
    public var delta_system_time: ecs_ftime_t = 0

    // Iterator counters
    public var frame_offset: Int32 = 0

    // Misc
    public var flags: ecs_flags32_t = 0
    public var interrupted_by: ecs_entity_t = 0
    public var priv_: ecs_iter_private_t = ecs_iter_private_t()

    // Chained iterators
    public var next: ecs_iter_next_action_t? = nil
    public var callback: ecs_iter_action_t? = nil
    public var fini: ecs_iter_fini_action_t? = nil
    public var chain_it: UnsafeMutablePointer<ecs_iter_t>? = nil

    public init() {}
}

// MARK: - Built-in Component Types

public struct EcsIdentifier {
    public var value: UnsafeMutablePointer<CChar>? = nil
    public var length: ecs_size_t = 0
    public var hash: UInt64 = 0
    public var index_hash: UInt64 = 0
    public var index: UnsafeMutableRawPointer? = nil // ecs_hashmap_t*
    public init() {}
}

public struct EcsComponent {
    public var size: ecs_size_t = 0
    public var alignment: ecs_size_t = 0
    public init() {}
}

public struct EcsPoly {
    public var poly: UnsafeMutableRawPointer? = nil
    public init() {}
}

public struct EcsDefaultChildComponent {
    public var component: ecs_id_t = 0
    public init() {}
}

public struct EcsParent {
    public var value: ecs_entity_t = 0
    public init() {}
}

// MARK: - World Info

public struct ecs_build_info_t {
    public var compiler: UnsafePointer<CChar>? = nil
    public var addons: UnsafePointer<UnsafePointer<CChar>?>? = nil
    public var flags: UnsafePointer<UnsafePointer<CChar>?>? = nil
    public var version: UnsafePointer<CChar>? = nil
    public var version_major: Int16 = 0
    public var version_minor: Int16 = 0
    public var version_patch: Int16 = 0
    public var debug: Bool = false
    public var sanitize: Bool = false
    public var perf_trace: Bool = false
    public init() {}
}

public struct ecs_world_info_cmd_t {
    public var add_count: Int64 = 0
    public var remove_count: Int64 = 0
    public var delete_count: Int64 = 0
    public var clear_count: Int64 = 0
    public var set_count: Int64 = 0
    public var ensure_count: Int64 = 0
    public var modified_count: Int64 = 0
    public var discard_count: Int64 = 0
    public var event_count: Int64 = 0
    public var other_count: Int64 = 0
    public var batched_entity_count: Int64 = 0
    public var batched_command_count: Int64 = 0
    public init() {}
}

public struct ecs_world_info_t {
    public var last_component_id: ecs_entity_t = 0
    public var min_id: ecs_entity_t = 0
    public var max_id: ecs_entity_t = 0

    public var delta_time_raw: ecs_ftime_t = 0
    public var delta_time: ecs_ftime_t = 0
    public var time_scale: ecs_ftime_t = 0
    public var target_fps: ecs_ftime_t = 0
    public var frame_time_total: ecs_ftime_t = 0
    public var system_time_total: ecs_ftime_t = 0
    public var emit_time_total: ecs_ftime_t = 0
    public var merge_time_total: ecs_ftime_t = 0
    public var rematch_time_total: ecs_ftime_t = 0
    public var world_time_total: Double = 0
    public var world_time_total_raw: Double = 0

    public var frame_count_total: Int64 = 0
    public var merge_count_total: Int64 = 0
    public var eval_comp_monitors_total: Int64 = 0
    public var rematch_count_total: Int64 = 0

    public var id_create_total: Int64 = 0
    public var id_delete_total: Int64 = 0
    public var table_create_total: Int64 = 0
    public var table_delete_total: Int64 = 0
    public var pipeline_build_count_total: Int64 = 0
    public var systems_ran_total: Int64 = 0
    public var observers_ran_total: Int64 = 0
    public var queries_ran_total: Int64 = 0

    public var tag_id_count: Int32 = 0
    public var component_id_count: Int32 = 0
    public var pair_id_count: Int32 = 0
    public var table_count: Int32 = 0
    public var creation_time: UInt32 = 0

    public var cmd: ecs_world_info_cmd_t = ecs_world_info_cmd_t()

    public var name_prefix: UnsafePointer<CChar>? = nil

    public init() {}
}

public struct ecs_query_group_info_t {
    public var id: UInt64 = 0
    public var match_count: Int32 = 0
    public var table_count: Int32 = 0
    public var ctx: UnsafeMutableRawPointer? = nil
    public init() {}
}

// MARK: - Observable

public struct ecs_event_record_t {
    public var any: UnsafeMutableRawPointer? = nil
    public var wildcard: UnsafeMutableRawPointer? = nil
    public var wildcard_pair: UnsafeMutableRawPointer? = nil
    public var event_ids: ecs_map_t = ecs_map_t()
    public var event: ecs_entity_t = 0
    public init() {}
}

public struct ecs_observable_t {
    public var on_add: ecs_event_record_t = ecs_event_record_t()
    public var on_remove: ecs_event_record_t = ecs_event_record_t()
    public var on_set: ecs_event_record_t = ecs_event_record_t()
    public var on_wildcard: ecs_event_record_t = ecs_event_record_t()
    public var events: ecs_sparse_t = ecs_sparse_t()
    public var global_observers: ecs_vec_t = ecs_vec_t()
    public var last_observer_id: UInt64 = 0
    public init() {}
}

// MARK: - Suspend/Resume Readonly

public struct ecs_suspend_readonly_state_t {
    public var is_readonly: Bool = false
    public var is_deferred: Bool = false
    public var cmd_flushing: Bool = false
    public var defer_count: Int32 = 0
    public var scope: ecs_entity_t = 0
    public var with: ecs_entity_t = 0
    public var cmd_stack: (ecs_commands_t, ecs_commands_t) = (ecs_commands_t(), ecs_commands_t())
    public var cmd: UnsafeMutablePointer<ecs_commands_t>? = nil
    public var stage: UnsafeMutableRawPointer? = nil
    public init() {}
}

// MARK: - Parent Record

public struct ecs_parent_record_t {
    public var entity: UInt32 = 0
    public var count: Int32 = 0
    public init() {}
}

// MARK: - Table Records Result

public struct ecs_table_records_t {
    public var array: UnsafePointer<ecs_table_record_t>? = nil
    public var count: Int32 = 0
    public init() {}
}
