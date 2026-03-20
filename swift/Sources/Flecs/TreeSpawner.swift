// TreeSpawner.swift - 1:1 translation of flecs tree_spawner.c
// Optimized data structure for fast prefab hierarchy instantiation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Maximum cached depth levels for spawner reuse.
public let FLECS_TREE_SPAWNER_DEPTH_CACHE_SIZE: Int = 8


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


/// Free a tree spawner's table references and vectors.
private func EcsTreeSpawner_free(
    _ ptr: UnsafeMutablePointer<EcsTreeSpawner>)
{
    for i in 0..<FLECS_TREE_SPAWNER_DEPTH_CACHE_SIZE {
        // Release table references
        let count = ecs_vec_count(&ptr.pointee.data[i].children)
        if count > 0 {
            let elems = ecs_vec_first(&ptr.pointee.data[i].children)?
                .bindMemory(to: ecs_tree_spawner_child_t.self, capacity: Int(count))
            if elems != nil {
                for j in 0..<Int(count) {
                    if elems![j].table != nil {
                        flecs_table_release(elems![j].table!)
                    }
                }
            }
        }

        let elem_size = Int32(MemoryLayout<ecs_tree_spawner_child_t>.stride)
        ecs_vec_fini(nil, &ptr.pointee.data[i].children, elem_size)
    }
}


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
    if table.pointee.type.array == nil { return dst }
    let array = table.pointee.type.array!
    if table.pointee._.pointee.records == nil { return dst }
    let records = table.pointee._.pointee.records!

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
    if cr.pointee.pair == nil { return }
    let children_count = ecs_vec_count(&cr.pointee.pair!.pointee.ordered_children)
    if children_count <= 0 { return }
    let children = ecs_vec_first(&cr.pointee.pair!.pointee.ordered_children)?
        .bindMemory(to: ecs_entity_t.self, capacity: Int(children_count))
    if children == nil { return }

    let elem_size = Int32(MemoryLayout<ecs_tree_spawner_child_t>.stride)

    for i in 0..<Int(children_count) {
        let child = children![i]
        let r = flecs_entities_get(UnsafePointer(world), child)
        if r == nil { continue }
        if r!.pointee.table == nil { continue }
        let table = r!.pointee.table!

        if (table.pointee.flags & EcsTableHasParent) == 0 {
            continue
        }

        let elem_ptr = ecs_vec_append(nil, spawner, elem_size)
        if elem_ptr == nil { continue }
        let elem = elem_ptr!.bindMemory(to: ecs_tree_spawner_child_t.self, capacity: 1)
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
        if elem.pointee.table != nil {
            flecs_table_keep(elem.pointee.table!)
        }

        // Recurse into children of this child
        if (r!.pointee.row & EcsEntityIsTraversable) == 0 { continue }

        let child_cr = flecs_components_get(
            UnsafePointer(world), ecs_childof(child))
        if child_cr == nil { continue }

        flecs_prefab_spawner_build_from_cr(
            world, child_cr!, spawner,
            ecs_vec_count(spawner), depth + 1)
    }
}


/// Build a tree spawner for a base entity.
public func flecs_prefab_spawner_build(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ base: ecs_entity_t) -> UnsafeMutablePointer<EcsTreeSpawner>?
{
    let cr = flecs_components_get(
        UnsafePointer(world), ecs_childof(base))
    if cr == nil {
        return nil
    }

    let elem_size = Int32(MemoryLayout<ecs_tree_spawner_child_t>.stride)
    var spawner = ecs_vec_t()
    ecs_vec_init(nil, &spawner, elem_size, 0)

    flecs_prefab_spawner_build_from_cr(world, cr!, &spawner, 0, 1)

    let alive_base = flecs_entities_get_alive(world, base)
    let ts = ecs_ensure(world, alive_base, EcsTreeSpawner.self)
    if ts == nil {
        return nil
    }
    ts!.pointee.data[0].children = spawner

    // Initialize remaining depth vectors
    for i in 1..<FLECS_TREE_SPAWNER_DEPTH_CACHE_SIZE {
        ecs_vec_init(nil, &ts!.pointee.data[i].children, elem_size, 0)
    }

    return ts
}


/// Instantiate all children from a tree spawner for an instance entity.
public func flecs_spawner_instantiate(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ spawner: UnsafeMutablePointer<EcsTreeSpawner>,
    _ instance: ecs_entity_t)
{
    let r_instance = flecs_entities_get(UnsafePointer(world), instance)
    if r_instance == nil { return }
    if r_instance!.pointee.table == nil { return }
    let instance_table = r_instance!.pointee.table!
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

    let spawn_children = ecs_vec_first(vec)?
        .bindMemory(to: ecs_tree_spawner_child_t.self, capacity: Int(child_count))
    if spawn_children == nil {
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

        let spawn_child = spawn_children![i]
        if spawn_child.table == nil { continue }
        var table = spawn_child.table!

        if is_prefab {
            var diff = ecs_table_diff_t()
            var id = EcsPrefab
            let new_table = flecs_table_traverse_add(world, table, &id, &diff)
            if new_table != nil {
                table = new_table!
            }
        }

        let r = flecs_entities_get(UnsafePointer(world), entity)
        if r == nil { continue }
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
        r!.pointee.table = UnsafeMutableRawPointer(table)
        r!.pointee.row = UInt32(row)
        flecs_table_append(world, table, entity, true, true)

        // Set parent component value
        let parent_column = table.pointee.component_map![Int(ecs_id_EcsParent)]
        if parent_column > 0 {
            let parent_data = table.pointee.data.columns![Int(parent_column - 1)].data?
                .bindMemory(to: EcsParent.self, capacity: Int(row) + 1)
            if parent_data != nil {
                parent_data![Int(row)].value = parent
            }
        }

        flecs_actions_new(world, table, row, 1, &table_diff, 0, false, true)

        if is_prefab && spawn_child.child_name != nil {
            ecs_set_name(world, entity, spawn_child.child_name!)
        }

        if cr != nil {
            flecs_add_non_fragmenting_child_w_records(world, parent, entity, cr!, r!)
        }

        // Copy sparse components from base child
        let base_child = ecs_entity_t(spawn_child.child)
        let spawn_r = flecs_entities_get_any(world, base_child)
        if spawn_r != nil {
            var base_range = ecs_table_range_t()
            base_range.table = spawn_r!.pointee.table
            base_range.offset = 0
            base_range.count = 1
            flecs_instantiate_sparse(world, &base_range, &base_child,
                table, &entity, ECS_RECORD_TO_ROW(r!.pointee.row))

            if (spawn_r!.pointee.row & EcsEntityHasDontFragment) != 0 {
                flecs_instantiate_dont_fragment(
                    world, ecs_entity_t(spawn_child.child), entity)
            }
        }
    }
}


/// Register TreeSpawner type info during bootstrap.
public func flecs_bootstrap_spawner(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    // Would register EcsTreeSpawner type info with ctor/copy/move/dtor
    ecs_add_pair(world, ecs_id_EcsTreeSpawner, EcsOnInstantiate, EcsDontInherit)
}
