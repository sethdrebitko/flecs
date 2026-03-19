// InternalTypes.swift - Internal ECS types
import Foundation

// MARK: - Table Diff Builder
public struct ecs_table_diff_builder_t {
    public var added: ecs_vec_t = ecs_vec_t()
    public var removed: ecs_vec_t = ecs_vec_t()
    public var added_flags: ecs_flags32_t = 0
    public var removed_flags: ecs_flags32_t = 0
    public init() {}
}

// MARK: - Graph Edge Types
public struct ecs_graph_edge_hdr_t {
    public var prev: UnsafeMutablePointer<ecs_graph_edge_hdr_t>? = nil
    public var next: UnsafeMutablePointer<ecs_graph_edge_hdr_t>? = nil
    public init() {}
}

public struct ecs_graph_edge_t {
    public var hdr: ecs_graph_edge_hdr_t = ecs_graph_edge_hdr_t()
    public var from: UnsafeMutablePointer<ecs_table_t>? = nil
    public var to: UnsafeMutablePointer<ecs_table_t>? = nil
    public var diff: UnsafeMutablePointer<ecs_table_diff_t>? = nil
    public var id: ecs_id_t = 0
    public init() {}
}

public struct ecs_graph_edges_t {
    public var lo: UnsafeMutablePointer<ecs_graph_edge_t>? = nil
    public var hi: UnsafeMutablePointer<ecs_map_t>? = nil
    public init() {}
}

public struct ecs_graph_node_t {
    public var add: ecs_graph_edges_t = ecs_graph_edges_t()
    public var remove: ecs_graph_edges_t = ecs_graph_edges_t()
    public var refs: ecs_graph_edge_hdr_t = ecs_graph_edge_hdr_t()
    public init() {}
}

// MARK: - Table Types

public struct ecs_column_t {
    public var data: UnsafeMutableRawPointer? = nil
    public var ti: UnsafeMutablePointer<ecs_type_info_t>? = nil
    public init() {}
}

// Table overrides (simplified - union replaced with both fields)
public struct ecs_table_1_override_t {
    public var pair: UnsafePointer<ecs_pair_record_t>? = nil
    public var generation: Int32 = 0
    public init() {}
}

public struct ecs_table_n_overrides_t {
    public var tr: UnsafePointer<ecs_table_record_t>? = nil
    public var generations: UnsafeMutablePointer<Int32>? = nil
    public init() {}
}

public struct ecs_table_overrides_t {
    // In C this is a union of _1 and _n - we store both, only one is used
    public var is_1: ecs_table_1_override_t = ecs_table_1_override_t()
    public var is_n: ecs_table_n_overrides_t = ecs_table_n_overrides_t()
    public var refs: UnsafeMutablePointer<ecs_ref_t>? = nil
    public init() {}
}

public struct ecs_data_t {
    public var entities: UnsafeMutablePointer<ecs_entity_t>? = nil
    public var columns: UnsafeMutablePointer<ecs_column_t>? = nil
    public var overrides: UnsafeMutablePointer<ecs_table_overrides_t>? = nil
    public var count: Int32 = 0
    public var size: Int32 = 0
    public init() {}
}

public enum ecs_table_eventkind_t: Int32 {
    case triggersForId = 0
    case noTriggersForId = 1
}

public struct ecs_table_event_t {
    public var kind: ecs_table_eventkind_t = .triggersForId
    public var component: ecs_entity_t = 0
    public var event: ecs_entity_t = 0
    public init() {}
}

// Infrequently accessed table metadata
public struct ecs_table__t {
    public var hash: UInt64 = 0
    public var lock: Int32 = 0
    public var traversable_count: Int32 = 0
    public var generation: UInt16 = 0
    public var record_count: Int16 = 0
    public var bs_count: Int16 = 0
    public var bs_offset: Int16 = 0
    public var bs_columns: UnsafeMutableRawPointer? = nil  // ecs_bitset_t*
    public var records: UnsafeMutablePointer<ecs_table_record_t>? = nil
    public init() {}
}

public struct ecs_table_t {
    public var id: UInt64 = 0
    public var flags: ecs_flags32_t = 0
    public var column_count: Int16 = 0
    public var version: UInt16 = 0
    public var bloom_filter: UInt64 = 0
    public var trait_flags: ecs_flags32_t = 0
    public var keep: Int16 = 0
    public var childof_index: Int16 = 0
    public var type: ecs_type_t = ecs_type_t()
    public var data: ecs_data_t = ecs_data_t()
    public var node: ecs_graph_node_t = ecs_graph_node_t()
    public var component_map: UnsafeMutablePointer<Int16>? = nil
    public var dirty_state: UnsafeMutablePointer<Int32>? = nil
    public var column_map: UnsafeMutablePointer<Int16>? = nil
    public var _: UnsafeMutablePointer<ecs_table__t>? = nil
    public init() {}
}

// MARK: - Table Cache

public struct ecs_table_cache_list_t {
    public var first: UnsafeMutablePointer<ecs_table_cache_hdr_t>? = nil
    public var last: UnsafeMutablePointer<ecs_table_cache_hdr_t>? = nil
    public var count: Int32 = 0
    public init() {}
}

public struct ecs_table_cache_t {
    public var index: ecs_map_t = ecs_map_t()
    public var tables: ecs_table_cache_list_t = ecs_table_cache_list_t()
    public init() {}
}

// MARK: - Component Index Types

public struct ecs_id_record_elem_t {
    public var prev: UnsafeMutablePointer<ecs_component_record_t>? = nil
    public var next: UnsafeMutablePointer<ecs_component_record_t>? = nil
    public init() {}
}

public struct ecs_reachable_elem_t {
    public var tr: UnsafePointer<ecs_table_record_t>? = nil
    public var record: UnsafeMutablePointer<ecs_record_t>? = nil
    public var src: ecs_entity_t = 0
    public var id: ecs_id_t = 0
    public init() {}
}

public struct ecs_reachable_cache_t {
    public var generation: Int32 = 0
    public var current: Int32 = 0
    public var ids: ecs_vec_t = ecs_vec_t()
    public init() {}
}

public struct ecs_pair_record_t {
    public var name_index: UnsafeMutablePointer<ecs_hashmap_t>? = nil
    public var ordered_children: ecs_vec_t = ecs_vec_t()
    public var children_tables: ecs_map_t = ecs_map_t()
    public var disabled_tables: Int32 = 0
    public var prefab_tables: Int32 = 0
    public var depth: Int32 = 0
    public var first: ecs_id_record_elem_t = ecs_id_record_elem_t()
    public var second: ecs_id_record_elem_t = ecs_id_record_elem_t()
    public var trav: ecs_id_record_elem_t = ecs_id_record_elem_t()
    public var parent: UnsafeMutablePointer<ecs_component_record_t>? = nil
    public var reachable: ecs_reachable_cache_t = ecs_reachable_cache_t()
    public init() {}
}

public struct ecs_component_record_t {
    public var cache: ecs_table_cache_t = ecs_table_cache_t()
    public var id: ecs_id_t = 0
    public var flags: ecs_flags32_t = 0
    public var type_info: UnsafePointer<ecs_type_info_t>? = nil
    public var sparse: UnsafeMutableRawPointer? = nil
    public var dont_fragment_tables: ecs_vec_t = ecs_vec_t()
    public var pair: UnsafeMutablePointer<ecs_pair_record_t>? = nil
    public var non_fragmenting: ecs_id_record_elem_t = ecs_id_record_elem_t()
    public var refcount: Int32 = 0
    public init() {}
}

// MARK: - World Internal Types

public let ECS_TABLE_VERSION_ARRAY_BITMASK: Int = 0xff
public let ECS_TABLE_VERSION_ARRAY_SIZE: Int = ECS_TABLE_VERSION_ARRAY_BITMASK + 1

public struct ecs_world_allocators_t {
    public var graph_edge_lo: ecs_block_allocator_t = ecs_block_allocator_t()
    public var graph_edge: ecs_block_allocator_t = ecs_block_allocator_t()
    public var component_record: ecs_block_allocator_t = ecs_block_allocator_t()
    public var pair_record: ecs_block_allocator_t = ecs_block_allocator_t()
    public var table_diff: ecs_block_allocator_t = ecs_block_allocator_t()
    public var sparse_chunk: ecs_block_allocator_t = ecs_block_allocator_t()
    public var diff_builder: ecs_table_diff_builder_t = ecs_table_diff_builder_t()
    public var tree_spawner: ecs_vec_t = ecs_vec_t()
    public init() {}
}

public struct ecs_monitor_t {
    public var queries: ecs_vec_t = ecs_vec_t()
    public var is_dirty: Bool = false
    public init() {}
}

public struct ecs_monitor_set_t {
    public var monitors: ecs_map_t = ecs_map_t()
    public var is_dirty: Bool = false
    public init() {}
}

public struct ecs_marked_id_t {
    public var cr: UnsafeMutablePointer<ecs_component_record_t>? = nil
    public var id: ecs_id_t = 0
    public var action: ecs_entity_t = 0
    public var delete_id: Bool = false
    public init() {}
}

public struct ecs_store_t {
    public var entity_index: ecs_entity_index_t = ecs_entity_index_t()
    public var tables: ecs_sparse_t = ecs_sparse_t()
    public var table_map: ecs_hashmap_t = ecs_hashmap_t()
    public var root: ecs_table_t = ecs_table_t()
    public var records: ecs_vec_t = ecs_vec_t()
    public var marked_ids: ecs_vec_t = ecs_vec_t()
    public var deleted_components: ecs_vec_t = ecs_vec_t()
    public init() {}
}

public struct ecs_action_elem_t {
    public var action: ecs_fini_action_t? = nil
    public var ctx: UnsafeMutableRawPointer? = nil
    public init() {}
}

public typealias ecs_on_commands_action_t = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

// MARK: - Stage

public struct ecs_stage_allocators_t {
    public var iter_stack: ecs_stack_t = ecs_stack_t()
    public var cmd_entry_chunk: ecs_block_allocator_t = ecs_block_allocator_t()
    public var query_impl: ecs_block_allocator_t = ecs_block_allocator_t()
    public var query_cache: ecs_block_allocator_t = ecs_block_allocator_t()
    public init() {}
}

public struct ecs_stage_t {
    public var hdr: ecs_header_t = ecs_header_t()
    public var id: Int32 = 0
    public var defer: Int32 = 0
    public var cmd: UnsafeMutablePointer<ecs_commands_t>? = nil
    public var cmd_stack: (ecs_commands_t, ecs_commands_t) = (ecs_commands_t(), ecs_commands_t())
    public var cmd_flushing: Bool = false
    public var thread_ctx: UnsafeMutablePointer<ecs_world_t>? = nil
    public var world: UnsafeMutablePointer<ecs_world_t>? = nil
    public var thread: UInt = 0
    public var post_frame_actions: ecs_vec_t = ecs_vec_t()
    public var scope: ecs_entity_t = 0
    public var with: ecs_entity_t = 0
    public var base: ecs_entity_t = 0
    public var lookup_path: UnsafePointer<ecs_entity_t>? = nil
    public var system: ecs_entity_t = 0
    public var allocators: ecs_stage_allocators_t = ecs_stage_allocators_t()
    public var allocator: ecs_allocator_t = ecs_allocator_t()
    public var variables: ecs_vec_t = ecs_vec_t()
    public var operations: ecs_vec_t = ecs_vec_t()
    public init() {}
}

// MARK: - The World

// Note: ecs_world_t needs to reference ecs_table_t via store, but ecs_table_t is defined in this file.
// Forward reference issue resolved since both are in the same module.

// Use a class for ecs_world_t since it's heap-allocated and has reference semantics
public struct ecs_world_t {
    public var hdr: ecs_header_t = ecs_header_t()

    // Type metadata
    public var id_index_lo: UnsafeMutablePointer<UnsafeMutablePointer<ecs_component_record_t>?>? = nil
    public var id_index_hi: ecs_map_t = ecs_map_t()
    public var type_info: ecs_map_t = ecs_map_t()

    // Cached component records
    public var cr_wildcard: UnsafeMutablePointer<ecs_component_record_t>? = nil
    public var cr_wildcard_wildcard: UnsafeMutablePointer<ecs_component_record_t>? = nil
    public var cr_any: UnsafeMutablePointer<ecs_component_record_t>? = nil
    public var cr_isa_wildcard: UnsafeMutablePointer<ecs_component_record_t>? = nil
    public var cr_childof_0: UnsafeMutablePointer<ecs_component_record_t>? = nil
    public var cr_childof_wildcard: UnsafeMutablePointer<ecs_component_record_t>? = nil
    public var cr_identifier_name: UnsafeMutablePointer<ecs_component_record_t>? = nil
    public var cr_non_fragmenting_head: UnsafeMutablePointer<ecs_component_record_t>? = nil

    // Mixins
    public var self_: UnsafeMutablePointer<ecs_world_t>? = nil
    public var observable: ecs_observable_t = ecs_observable_t()

    public var event_id: Int32 = 0

    // NOTE: Fixed-size arrays in Swift tuples - 256 entries for table_version
    // We use UnsafeMutableBufferPointer or just allocate them
    public var table_version: UnsafeMutablePointer<UInt32>? = nil  // [ECS_TABLE_VERSION_ARRAY_SIZE]
    public var non_trivial_lookup: UnsafeMutablePointer<ecs_flags8_t>? = nil  // [FLECS_HI_COMPONENT_ID]
    public var non_trivial_set: UnsafeMutablePointer<ecs_flags8_t>? = nil  // [FLECS_HI_COMPONENT_ID]

    // Data storage
    public var store: ecs_store_t = ecs_store_t()

    // Component monitors
    public var monitors: ecs_monitor_set_t = ecs_monitor_set_t()

    // Systems
    public var pipeline: ecs_entity_t = 0

    // Identifiers
    public var aliases: ecs_hashmap_t = ecs_hashmap_t()
    public var symbols: ecs_hashmap_t = ecs_hashmap_t()

    // Staging
    public var stages: UnsafeMutablePointer<UnsafeMutablePointer<ecs_stage_t>?>? = nil
    public var stage_count: Int32 = 0

    // Component ids
    public var component_ids: ecs_vec_t = ecs_vec_t()

    // Prefab children
    public var prefab_child_indices: ecs_map_t = ecs_map_t()

    public var range_check_enabled: Bool = false

    // Command inspection
    public var on_commands: ecs_on_commands_action_t? = nil
    public var on_commands_active: ecs_on_commands_action_t? = nil
    public var on_commands_ctx: UnsafeMutableRawPointer? = nil
    public var on_commands_ctx_active: UnsafeMutableRawPointer? = nil

    // Multithreading
    public var worker_cond: UInt = 0
    public var sync_cond: UInt = 0
    public var sync_mutex: UInt = 0
    public var workers_running: Int32 = 0
    public var workers_waiting: Int32 = 0
    public var pq: UnsafeMutableRawPointer? = nil  // ecs_pipeline_state_t*
    public var workers_use_task_api: Bool = false

    // Exclusive access
    public var exclusive_access: UInt = 0
    public var exclusive_thread_name: UnsafePointer<CChar>? = nil

    // Time management
    public var world_start_time: ecs_time_t = ecs_time_t()
    public var frame_start_time: ecs_time_t = ecs_time_t()
    public var fps_sleep: ecs_ftime_t = 0

    // Metrics
    public var info: ecs_world_info_t = ecs_world_info_t()

    // Flags
    public var flags: ecs_flags32_t = 0
    public var default_query_flags: ecs_flags32_t = 0
    public var monitor_generation: Int32 = 0

    // Allocators
    public var allocators: ecs_world_allocators_t = ecs_world_allocators_t()
    public var allocator: ecs_allocator_t = ecs_allocator_t()

    public var ctx: UnsafeMutableRawPointer? = nil
    public var binding_ctx: UnsafeMutableRawPointer? = nil
    public var ctx_free: ecs_ctx_free_t? = nil
    public var binding_ctx_free: ecs_ctx_free_t? = nil

    public var fini_actions: ecs_vec_t = ecs_vec_t()

    public init() {}
}
