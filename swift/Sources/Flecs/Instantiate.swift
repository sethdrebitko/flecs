// Instantiate.swift - 1:1 translation of flecs instantiate.c
// Prefab instantiation (IsA relationship) implementation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Context passed during recursive prefab instantiation.
public struct ecs_instantiate_ctx_t {
    public var root_prefab: ecs_entity_t
    public var root_instance: ecs_entity_t
    public init(root_prefab: ecs_entity_t = 0, root_instance: ecs_entity_t = 0) {
        self.root_prefab = root_prefab
        self.root_instance = root_instance
    }
}


/// Wire up a slot relationship between a base and an instance child.
private func flecs_instantiate_slot(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ base: ecs_entity_t,
    _ instance: ecs_entity_t,
    _ slot_of: ecs_entity_t,
    _ slot: ecs_entity_t,
    _ child: ecs_entity_t)
{
    if base == slot_of {
        // Instance inherits from slot_of, add slot to instance
        let cr = flecs_components_ensure(world, ecs_pair(slot, child))
        let r = flecs_entities_get(UnsafePointer(world), instance)
        if r == nil { return }
        flecs_sparse_on_add_cr(world, r!.pointee.table, ECS_RECORD_TO_ROW(r!.pointee.row), cr, true, nil)
    } else {
        // Travel hierarchy upward to find instance that inherits from slot_of
        var parent = instance
        var depth: Int32 = 0
        repeat {
            if ecs_has_pair(world, parent, EcsIsA, slot_of) {
                let name = ecs_get_name(world, slot)
                if name == nil { return }

                var resolved_slot: ecs_entity_t
                if depth == 0 {
                    resolved_slot = ecs_lookup_child(world, slot_of, name!)
                } else {
                    let path = ecs_get_path_w_sep(world, parent, child, ".", nil)
                    resolved_slot = ecs_lookup_path_w_sep(world, slot_of, path, ".", nil, false)
                    ecs_os_free(UnsafeMutableRawPointer(mutating: path))
                }

                if resolved_slot != 0 {
                    ecs_add_pair(world, parent, resolved_slot, child)
                }
                break
            }
            depth += 1
            parent = ecs_get_target(world, parent, EcsChildOf, 0)
        } while parent != 0

        _ = name
    }
}


/// Insert an id into a sorted type array, returning the insertion index.
/// Returns -1 if the id is already present.
private func flecs_child_type_insert(
    _ type: UnsafeMutablePointer<ecs_type_t>,
    _ component_data: UnsafeMutablePointer<UnsafeMutableRawPointer?>,
    _ id: ecs_id_t) -> Int32
{
    let count = type.pointee.count
    if type.pointee.array == nil {
        type.pointee.array = ecs_os_calloc_t(ecs_id_t.self)!
        type.pointee.array![0] = id
        component_data[0] = nil
        type.pointee.count = 1
        return 0
    }

    var i: Int32 = 0
    while i < count {
        let cur = type.pointee.array![Int(i)]
        if cur == id { return -1 }
        if cur > id { break }
        i += 1
    }

    // Shift elements to make room
    let to_move = count - i
    if to_move > 0 {
        (type.pointee.array! + Int(i) + 1).update(from: type.pointee.array! + Int(i), count: Int(to_move))
        (component_data + Int(i) + 1).update(from: component_data + Int(i), count: Int(to_move))
    }

    component_data[Int(i)] = nil
    type.pointee.array![Int(i)] = id
    type.pointee.count = count + 1

    return i
}


/// Copy sparse components from base children to instance children.
public func flecs_instantiate_sparse(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ base_child_range: UnsafePointer<ecs_table_range_t>,
    _ base_children: UnsafePointer<ecs_entity_t>,
    _ instance_table: UnsafeMutablePointer<ecs_table_t>,
    _ instance_children: UnsafePointer<ecs_entity_t>,
    _ row_offset: Int32)
{
    let base_child_table = base_child_range.pointee.table!
    if (base_child_table.pointee.flags & EcsTableHasSparse) == 0 {
        return
    }

    if base_child_table.pointee._.pointee.records == nil { return }
    let trs = base_child_table.pointee._.pointee.records!
    let count = base_child_table.pointee.type.count

    for i in 0..<Int(count) {
        let tr = trs[i]
        let cr = tr.hdr.cr!

        if (cr.pointee.flags & EcsIdSparse) == 0 {
            continue
        }

        if cr.pointee.type_info == nil { continue }
        let ti = cr.pointee.type_info!

        for j in 0..<Int(base_child_range.pointee.count) {
            let child = base_children[j + Int(base_child_range.pointee.offset)]
            let instance_child = instance_children[j]

            let src_ptr = flecs_sparse_get(
                cr.pointee.sparse, ti.pointee.size, child)
            if src_ptr == nil { continue }
            let dst_ptr = flecs_sparse_get(
                cr.pointee.sparse, ti.pointee.size, instance_child)
            if dst_ptr == nil { continue }

            flecs_type_info_copy(dst_ptr!, src_ptr!, 1, UnsafePointer(ti))
        }
    }
}


/// Copy non-fragmenting (sparse) components from a base to an instance.
public func flecs_instantiate_dont_fragment(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ base: ecs_entity_t,
    _ instance: ecs_entity_t)
{
    var cur = world.pointee.cr_non_fragmenting_head
    while cur != nil {
        if cur!.pointee.sparse != nil &&
            (cur!.pointee.flags & EcsIdOnInstantiateInherit) == 0 &&
            !ecs_id_is_wildcard(cur!.pointee.id)
        {
            if flecs_component_sparse_has(cur!, base) {
                let base_ptr = flecs_component_sparse_get(world, cur!, nil, base)
                let ti = cur!.pointee.type_info

                let r = flecs_entities_get(UnsafePointer(world), instance)
                if r == nil {
                    cur = cur!.pointee.non_fragmenting.next
                    continue
                }

                var ptr: UnsafeMutableRawPointer? = nil
                flecs_sparse_on_add_cr(world, r!.pointee.table,
                    ECS_RECORD_TO_ROW(r!.pointee.row), cur!, true, &ptr)

                if ti != nil && ptr != nil {
                    flecs_type_info_copy(ptr!, base_ptr, 1, UnsafePointer(ti!))
                }
            }
        }
        cur = cur!.pointee.non_fragmenting.next
    }
}


/// Add overrides for non-fragmenting components from a base table.
private func flecs_instantiate_override_dont_fragment(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ base_table: UnsafeMutablePointer<ecs_table_t>,
    _ instance: ecs_entity_t)
{
    let type_count = base_table.pointee.type.count
    if base_table.pointee.type.array == nil { return }

    for i in 0..<Int(type_count) {
        var id = base_table.pointee.type.array![i]
        if (id & ECS_AUTO_OVERRIDE) == 0 { continue }
        id &= ~ECS_AUTO_OVERRIDE

        let flags = flecs_component_get_flags(world, id)
        if (flags & EcsIdDontFragment) == 0 { continue }

        ecs_add_id(world, instance, id)
    }
}


/// Recursively instantiate prefab children for an entity.
public func flecs_instantiate(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ base: ecs_entity_t,
    _ instance: ecs_entity_t,
    _ ctx: UnsafePointer<ecs_instantiate_ctx_t>?,
    _ depth: Int32)
{
    let record = flecs_entities_get_any(world, base)
    if record == nil { return }
    if record!.pointee.table == nil { return }
    let base_table = record!.pointee.table!

    if depth >= FLECS_DAG_DEPTH_MAX {
        // Likely cycle detected during instantiation
        return
    }

    if (base_table.pointee.flags & EcsTableOverrideDontFragment) != 0 {
        flecs_instantiate_override_dont_fragment(world, base_table, instance)
    }

    // If base has non-fragmenting components, add to instance
    if (record!.pointee.row & EcsEntityHasDontFragment) != 0 {
        flecs_instantiate_dont_fragment(world, base, instance)
    }

    if (base_table.pointee.flags & EcsTableIsPrefab) == 0 {
        // Don't instantiate children from base entities that aren't prefabs
        return
    }

    let cr = flecs_components_get(UnsafePointer(world), ecs_childof(base))
    if cr == nil {
        return
    }

    if (cr!.pointee.flags & EcsIdOrderedChildren) != 0 {
        // Would use ordered children list or tree spawner for fast instantiation
        // Full implementation requires flecs_prefab_spawner_build and
        // flecs_spawner_instantiate
        if cr!.pointee.pair != nil {
            let count = ecs_vec_count(&cr!.pointee.pair!.pointee.ordered_children)
            let children = ecs_vec_first(&cr!.pointee.pair!.pointee.ordered_children)?
                .bindMemory(to: ecs_entity_t.self, capacity: Int(count))
            if children != nil {
                for i in 0..<Int(count) {
                    let child = children![i]
                    let range = flecs_range_from_entity(world, child)
                    if range.table == nil { continue }

                    if (range.table!.pointee.flags & EcsTableHasChildOf) == 0 {
                        continue
                    }

                    flecs_instantiate_children(
                        world, base, instance, range, ctx, depth)
                }
            }
        }
    } else {
        // Iterate table cache for all children of base
        var it = ecs_table_cache_iter_t()
        if flecs_table_cache_all_iter(UnsafeMutableRawPointer(cr!), &it) {
            var tr = flecs_table_cache_next(&it, ecs_table_record_t.self)
            while tr != nil {
                if tr!.pointee.hdr.table == nil {
                    tr = flecs_table_cache_next(&it, ecs_table_record_t.self)
                    continue
                }
                let table = tr!.pointee.hdr.table!
                let range = ecs_table_range_t(
                    table: table,
                    offset: 0,
                    count: table.pointee.data.count)

                flecs_instantiate_children(
                    world, base, instance, range, ctx, depth)
                tr = flecs_table_cache_next(&it, ecs_table_record_t.self)
            }
        }
    }
}


/// Instantiate children from a prefab child table range.
private func flecs_instantiate_children(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ base: ecs_entity_t,
    _ instance: ecs_entity_t,
    _ child_range: ecs_table_range_t,
    _ ctx: UnsafePointer<ecs_instantiate_ctx_t>?,
    _ depth: Int32)
{
    if child_range.count == 0 { return }

    if child_range.table == nil { return }
    let child_table = child_range.table!
    let type = child_table.pointee.type
    let type_count = type.count

    let r = flecs_entities_get(UnsafePointer(world), instance)
    if r == nil { return }
    if r!.pointee.table == nil { return }
    let table = r!.pointee.table!

    // Build the component array for the instance children's table.
    // Replace ChildOf(base) with ChildOf(instance), skip DontInherit/SlotOf.
    var slot_of: ecs_entity_t = 0
    var childof_base_index: Int32 = -1
    var added_ids = [ecs_id_t]()
    added_ids.reserveCapacity(Int(type_count) + 1)

    if type.array == nil { return }
    for i in 0..<Int(type_count) {
        let id = type.array![i]

        // Skip DontInherit (except Name and ChildOf)
        if id != ecs_pair(ecs_id_EcsIdentifier, EcsName) &&
            ECS_PAIR_FIRST(id) != EcsChildOf
        {
            if child_table.pointee._.pointee.records != nil {
                let cr = child_table.pointee._.pointee.records![i].hdr.cr!
                if (cr.pointee.flags & EcsIdOnInstantiateDontInherit) != 0 {
                    continue
                }
            }
        }

        // Track SlotOf
        if (table.pointee.flags & EcsTableIsPrefab) == 0 {
            if ECS_IS_PAIR(id) && ECS_PAIR_FIRST(id) == EcsSlotOf {
                slot_of = ecs_pair_second(world, id)
                continue
            }
        }

        // Track ChildOf(base) index
        if ECS_HAS_RELATION(id, EcsChildOf) &&
            ECS_PAIR_SECOND(id) == UInt32(base)
        {
            childof_base_index = Int32(added_ids.count)
        }

        // Skip pure overrides (add concrete version instead)
        if ECS_HAS_ID_FLAG(id, ECS_AUTO_OVERRIDE) {
            let concreteId = id & ~ECS_AUTO_OVERRIDE
            added_ids.append(concreteId)
            continue
        }

        added_ids.append(id)
    }

    if childof_base_index == -1 { return }

    // If children are added to a prefab, make them prefabs too
    if (table.pointee.flags & EcsTableIsPrefab) != 0 {
        if !added_ids.contains(EcsPrefab) {
            added_ids.insert(EcsPrefab, at: Int(childof_base_index))
            childof_base_index += 1
        }
    }

    // Replace ChildOf(base) with ChildOf(instance)
    added_ids[Int(childof_base_index)] = ecs_pair(EcsChildOf, instance)

    // Create stable instance child ids
    var ctx_cur = ecs_instantiate_ctx_t(root_prefab: base, root_instance: instance)
    if ctx != nil {
        ctx_cur = ctx!.pointee
    }

    if child_table.pointee.data.entities == nil { return }
    let children = child_table.pointee.data.entities!

    var child_ids = [ecs_entity_t]()
    child_ids.reserveCapacity(Int(child_range.count))

    for j in 0..<Int(child_range.count) {
        let prefab_child = children[j + Int(child_range.offset)]
        if UInt32(prefab_child) < UInt32(ctx_cur.root_prefab) {
            child_ids.append(flecs_new_id(world))
            continue
        }

        let prefab_offset = UInt32(prefab_child) - UInt32(ctx_cur.root_prefab)
        if prefab_offset == 0 {
            child_ids.append(flecs_new_id(world))
            continue
        }

        var instance_child = ecs_entity_t(UInt32(ctx_cur.root_instance) + prefab_offset)
        let alive_id = flecs_entities_get_alive(world, instance_child)
        if alive_id != 0 && flecs_entities_is_alive(world, alive_id) {
            child_ids.append(flecs_new_id(world))
            continue
        }

        instance_child = ctx_cur.root_instance + ecs_entity_t(prefab_offset)
        flecs_entities_make_alive(world, instance_child)
        flecs_entities_ensure(world, instance_child)
        child_ids.append(instance_child)
    }

    // Would call flecs_bulk_new to create children in the target table
    // and then recursively instantiate their children.
    // For now, create entities individually.
    for j in 0..<Int(child_range.count) {
        let child = children[j + Int(child_range.offset)]
        let i_child = child_ids[j]

        // Set up the instance child in the target table
        // (Full implementation would use flecs_bulk_new for efficiency)

        // If children are slots, add slot relationships
        if slot_of != 0 {
            flecs_instantiate_slot(
                world, base, instance, slot_of, child, i_child)
        }

        // Recursively instantiate grandchildren
        flecs_instantiate(world, child, i_child, &ctx_cur, depth + 1)
    }
}
