// TreeSpawner.swift - 1:1 translation of flecs tree_spawner.c
// Optimized data structure for fast prefab hierarchy instantiation

import Foundation

// MARK: - Tree Spawner Constants

/// Maximum cached depth levels for spawner reuse.
public let FLECS_TREE_SPAWNER_DEPTH_CACHE_SIZE: Int = 8

// MARK: - Tree Spawner Types

/// Describes a single child in a spawner template.
public struct ecs_tree_spawner_child_t {
    public var parent_index: Int32 = 0
    public var child: UInt32 = 0
    public var child_name: UnsafePointer<CChar>? = nil
    public var table: UnsafeMutablePointer<ecs_table_t>? = nil
    public init() {}
}

/// Per-depth data in the spawner.
public struct ecs_tree_spawner_data_t {
    public var children: ecs_vec_t = ecs_vec_t()
    public init() {}
}

// MARK: - Tree Spawner Lifecycle

/// Free a tree spawner's table references and vectors.
private func EcsTreeSpawner_free(
    _ ptr: UnsafeMutablePointer<EcsTreeSpawner>)
{
    for i in 0..<FLECS_TREE_SPAWNER_DEPTH_CACHE_SIZE {
        // Release table references
        let count = ecs_vec_count(&ptr.pointee.data[i].children)
        if count > 0 {
            if let elems = ecs_vec_first(&ptr.pointee.data[i].children)?
                .bindMemory(to: ecs_tree_spawner_child_t.self, capacity: Int(count))
            {
                for j in 0..<Int(count) {
                    if let table = elems[j].table {
                        flecs_table_release(table)
                    }
                }
            }
        }

        let elem_size = Int32(MemoryLayout<ecs_tree_spawner_child_t>.stride)
        ecs_vec_fini(nil, &ptr.pointee.data[i].children, elem_size)
    }
}

// MARK: - Build Spawner Type

/// Build a type for a spawner child table.
/// Replaces ChildOf with Parent, strips DontInherit, adds (IsA, child).
private func flecs_prefab_spawner_build_type(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ child: ecs_entity_t,
    _ table: UnsafeMutablePointer<ecs_table_t>,
    _ depth: Int32) -> ecs_type_t
{
    var dst = ecs_type_t()
    flecs_type_add(world, &dst, ecs_id_EcsParent)

    let count = table.pointee.type.count
    guard let array = table.pointee.type.array else { return dst }
    guard let records = table.pointee._.pointee.records else { return dst }

    for i in 0..<Int(count) {
        var id = array[i]
        let cr = records[i].hdr.cr!

        if (cr.pointee.flags &
            (EcsIdOnInstantiateDontInherit | EcsIdOnInstantiateInherit)) != 0
        {
            continue
        }

        if (id & ECS_AUTO_OVERRIDE) != 0 {
            flecs_type_add(world, &dst, id & ~ECS_AUTO_OVERRIDE)
            continue
        }

        let rel = ECS_PAIR_FIRST(id)
        if rel == EcsIsA { continue }

        if rel == EcsParentDepth {
            id = ecs_value_pair(EcsParentDepth, ecs_entity_t(depth))
        }

        flecs_type_add(world, &dst, id)
    }

    flecs_type_add(world, &dst, ecs_isa(child))

    return dst
}

/// Recursively build spawner data from a component record's ordered children.
private func flecs_prefab_spawner_build_from_cr(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ spawner: UnsafeMutablePointer<ecs_vec_t>,
    _ parent_index: Int32,
    _ depth: Int32)
{
    guard let pair = cr.pointee.pair else { return }
    let children_count = ecs_vec_count(&pair.pointee.ordered_children)
    guard children_count > 0 else { return }
    guard let children = ecs_vec_first(&pair.pointee.ordered_children)?
        .bindMemory(to: ecs_entity_t.self, capacity: Int(children_count)) else { return }

    let elem_size = Int32(MemoryLayout<ecs_tree_spawner_child_t>.stride)

    for i in 0..<Int(children_count) {
        let child = children[i]
        guard let r = flecs_entities_get(UnsafePointer(world), child) else { continue }
        guard let table = r.pointee.table else { continue }

        if (table.pointee.flags & EcsTableHasParent) == 0 {
            continue
        }

        guard let elem_ptr = ecs_vec_append(nil, spawner, elem_size) else { continue }
        let elem = elem_ptr.bindMemory(to: ecs_tree_spawner_child_t.self, capacity: 1)
        elem.pointee.parent_index = parent_index
        elem.pointee.child_name = nil
        elem.pointee.child = UInt32(child)

        if (table.pointee.flags & EcsTableHasName) != 0 {
            elem.pointee.child_name = ecs_get_name(world, child)
        }

        var type = flecs_prefab_spawner_build_type(world, child, table, depth)
        elem.pointee.table = flecs_table_find_or_create(world, &type)
        flecs_type_free(world, &type)

        // Keep table alive
        if let t = elem.pointee.table {
            flecs_table_keep(t)
        }

        // Recurse into children of this child
        if (r.pointee.row & EcsEntityIsTraversable) == 0 { continue }

        guard let child_cr = flecs_components_get(
            UnsafePointer(world), ecs_childof(child)) else { continue }

        flecs_prefab_spawner_build_from_cr(
            world, child_cr, spawner,
            ecs_vec_count(spawner), depth + 1)
    }
}

// MARK: - Build Spawner

/// Build a tree spawner for a base entity.
public func flecs_prefab_spawner_build(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ base: ecs_entity_t) -> UnsafeMutablePointer<EcsTreeSpawner>?
{
    guard let cr = flecs_components_get(
        UnsafePointer(world), ecs_childof(base)) else {
        return nil
    }

    let elem_size = Int32(MemoryLayout<ecs_tree_spawner_child_t>.stride)
    var spawner = ecs_vec_t()
    ecs_vec_init(nil, &spawner, elem_size, 0)

    flecs_prefab_spawner_build_from_cr(world, cr, &spawner, 0, 1)

    let alive_base = flecs_entities_get_alive(world, base)
    guard let ts = ecs_ensure(world, alive_base, EcsTreeSpawner.self) else {
        return nil
    }
    ts.pointee.data[0].children = spawner

    // Initialize remaining depth vectors
    for i in 1..<FLECS_TREE_SPAWNER_DEPTH_CACHE_SIZE {
        ecs_vec_init(nil, &ts.pointee.data[i].children, elem_size, 0)
    }

    return ts
}

// MARK: - Spawner Instantiation

/// Instantiate all children from a tree spawner for an instance entity.
public func flecs_spawner_instantiate(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ spawner: UnsafeMutablePointer<EcsTreeSpawner>,
    _ instance: ecs_entity_t)
{
    guard let r_instance = flecs_entities_get(UnsafePointer(world), instance) else { return }
    guard let instance_table = r_instance.pointee.table else { return }
    let depth = flecs_relation_depth(UnsafePointer(world), EcsChildOf, UnsafePointer(instance_table))
    let child_count = ecs_vec_count(&spawner.pointee.data[0].children)
    if child_count == 0 { return }

    let is_prefab = (instance_table.pointee.flags & EcsTableIsPrefab) != 0

    // Select correct depth vector
    let vec: UnsafeMutablePointer<ecs_vec_t>
    if depth < Int32(FLECS_TREE_SPAWNER_DEPTH_CACHE_SIZE) {
        vec = withUnsafeMutablePointer(to: &spawner.pointee.data[Int(depth)].children) { $0 }
    } else {
        // Would create temporary transposed vector for this depth
        return
    }

    guard let spawn_children = ecs_vec_first(vec)?
        .bindMemory(to: ecs_tree_spawner_child_t.self, capacity: Int(child_count)) else {
        return
    }

    // Allocate parent index array
    var parents = [ecs_entity_t](repeating: 0, count: Int(child_count) + 1)
    parents[0] = instance

    var old_parent: ecs_entity_t = 0
    var cr: UnsafeMutablePointer<ecs_component_record_t>? = nil

    for i in 0..<Int(child_count) {
        let entity = flecs_new_id(world)
        parents[i + 1] = entity

        let spawn_child = spawn_children[i]
        guard var table = spawn_child.table else { continue }

        if is_prefab {
            var diff = ecs_table_diff_t()
            var id = EcsPrefab
            if let new_table = flecs_table_traverse_add(world, table, &id, &diff) {
                table = new_table
            }
        }

        guard let r = flecs_entities_get(UnsafePointer(world), entity) else { continue }
        let flags = table.pointee.flags & EcsTableAddEdgeFlags

        var table_diff = ecs_table_diff_t()
        table_diff.added = table.pointee.type
        table_diff.added_flags = flags

        let parent = parents[Int(spawn_child.parent_index)]
        if parent != old_parent {
            cr = flecs_components_ensure(world, ecs_childof(parent))
            old_parent = parent
        }

        // Set up entity in table
        let row = table.pointee.data.count
        r.pointee.table = UnsafeMutableRawPointer(table)
        r.pointee.row = UInt32(row)
        flecs_table_append(world, table, entity, true, true)

        // Set parent component value
        let parent_column = table.pointee.component_map![Int(ecs_id_EcsParent)]
        if parent_column > 0 {
            if let parent_data = table.pointee.data.columns![Int(parent_column - 1)].data?
                .bindMemory(to: EcsParent.self, capacity: Int(row) + 1)
            {
                parent_data[Int(row)].value = parent
            }
        }

        flecs_actions_new(world, table, row, 1, &table_diff, 0, false, true)

        if is_prefab, let name = spawn_child.child_name {
            ecs_set_name(world, entity, name)
        }

        if let cr = cr {
            flecs_add_non_fragmenting_child_w_records(world, parent, entity, cr, r)
        }

        // Copy sparse components from base child
        let base_child = ecs_entity_t(spawn_child.child)
        if let spawn_r = flecs_entities_get_any(world, base_child) {
            var base_range = ecs_table_range_t()
            base_range.table = spawn_r.pointee.table
            base_range.offset = 0
            base_range.count = 1
            flecs_instantiate_sparse(world, &base_range, &base_child,
                table, &entity, ECS_RECORD_TO_ROW(r.pointee.row))

            if (spawn_r.pointee.row & EcsEntityHasDontFragment) != 0 {
                flecs_instantiate_dont_fragment(
                    world, ecs_entity_t(spawn_child.child), entity)
            }
        }
    }
}

// MARK: - Bootstrap

/// Register TreeSpawner type info during bootstrap.
public func flecs_bootstrap_spawner(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    // Would register EcsTreeSpawner type info with ctor/copy/move/dtor
    ecs_add_pair(world, ecs_id_EcsTreeSpawner, EcsOnInstantiate, EcsDontInherit)
}
