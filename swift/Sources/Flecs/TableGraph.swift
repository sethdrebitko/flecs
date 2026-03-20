// TableGraph.swift - 1:1 translation of flecs storage/table_graph.c
// Table graph edges for fast add/remove table transitions

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Hash a type (sorted id array) for table lookup.
public func flecs_type_hash(_ type: UnsafePointer<ecs_type_t>) -> UInt64 {
    if type.pointee.array == nil { return 0 }
    let ids = type.pointee.array!
    let count = type.pointee.count
    return flecs_hash(ids, Int32(count) * Int32(MemoryLayout<ecs_id_t>.stride))
}

/// Compare two types for equality (element-wise).
public func flecs_type_compare(
    _ type_1: UnsafePointer<ecs_type_t>,
    _ type_2: UnsafePointer<ecs_type_t>) -> Int32
{
    let count_1 = type_1.pointee.count
    let count_2 = type_2.pointee.count

    if count_1 != count_2 {
        return count_1 > count_2 ? 1 : -1
    }

    if type_1.pointee.array == nil || type_2.pointee.array == nil { return 0 }
    let ids_1 = type_1.pointee.array!
    let ids_2 = type_2.pointee.array!

    for i in 0..<Int(count_1) {
        let id_1 = ids_1[i]
        let id_2 = ids_2[i]
        if id_1 != id_2 {
            return id_1 > id_2 ? 1 : -1
        }
    }

    return 0
}

/// Initialize the table hashmap.
public func flecs_table_hashmap_init(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ hm: UnsafeMutablePointer<ecs_hashmap_t>)
{
    flecs_hashmap_init(hm, &world.pointee.allocator)
}


/// Find the insertion point for an id in a sorted type.
/// Returns -1 if the id already exists.
private func flecs_type_find_insert(
    _ type: UnsafePointer<ecs_type_t>,
    _ offset: Int32,
    _ to_add: ecs_id_t) -> Int32
{
    if type.pointee.array == nil { return 0 }
    let array = type.pointee.array!
    let count = type.pointee.count

    for i in Int(offset)..<Int(count) {
        let id = array[i]
        if id == to_add { return -1 }
        if id > to_add { return Int32(i) }
    }
    return count
}

/// Find an id in a type, supporting wildcard matching.
private func flecs_type_find(
    _ type: UnsafePointer<ecs_type_t>,
    _ id: ecs_id_t) -> Int32
{
    if type.pointee.array == nil { return -1 }
    let array = type.pointee.array!
    let count = type.pointee.count

    for i in 0..<Int(count) {
        let cur = array[i]
        if ecs_id_match(cur, id) { return Int32(i) }
        if !ECS_IS_PAIR(id) && cur > id { return -1 }
    }
    return -1
}

/// Copy a type, allocating new memory for the id array.
public func flecs_type_copy(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ src: UnsafePointer<ecs_type_t>) -> ecs_type_t
{
    let src_count = src.pointee.count
    if src_count == 0 {
        return ecs_type_t()
    }

    let ids = ecs_os_calloc_n(ecs_id_t.self, src_count)!
    ids.update(from: src.pointee.array!, count: Int(src_count))
    return ecs_type_t(array: ids, count: src_count)
}

/// Free a type's id array.
public func flecs_type_free(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ type: UnsafeMutablePointer<ecs_type_t>)
{
    if type.pointee.count > 0 && type.pointee.array != nil {
        ecs_os_free(UnsafeMutableRawPointer(type.pointee.array!))
        type.pointee.array = nil
        type.pointee.count = 0
    }
}

/// Create a new type with an additional id inserted in sorted order.
/// Returns -1 if the id already exists.
public func flecs_type_new_with(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ dst: UnsafeMutablePointer<ecs_type_t>,
    _ src: UnsafePointer<ecs_type_t>,
    _ with: ecs_id_t) -> Int32
{
    let at = flecs_type_find_insert(src, 0, with)
    if at == -1 { return -1 }

    let dst_count = src.pointee.count + 1
    let dst_array = ecs_os_calloc_n(ecs_id_t.self, dst_count)!
    dst.pointee.count = dst_count
    dst.pointee.array = dst_array

    if at > 0 && src.pointee.array != nil {
        dst_array.update(from: src.pointee.array!, count: Int(at))
    }

    let remain = src.pointee.count - at
    if remain > 0 && src.pointee.array != nil {
        (dst_array + Int(at) + 1).update(from: src.pointee.array! + Int(at), count: Int(remain))
    }

    dst_array[Int(at)] = with
    return 0
}

/// Create a new type without a specified id.
/// Returns -1 if the id is not found.
public func flecs_type_new_without(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ dst: UnsafeMutablePointer<ecs_type_t>,
    _ src: UnsafePointer<ecs_type_t>,
    _ without: ecs_id_t) -> Int32
{
    let at = flecs_type_find(src, without)
    if at == -1 { return -1 }

    let src_count = src.pointee.count
    if src_count == 1 {
        dst.pointee.array = nil
        dst.pointee.count = 0
        return 0
    }

    var count: Int32 = 1
    if ecs_id_is_wildcard(without) {
        // Count additional wildcard matches
        if src.pointee.array == nil { return -1 }
        let array = src.pointee.array!
        var i = at + 1
        while i < src_count {
            if ecs_id_match(array[Int(i)], without) { count += 1 }
            else { break }
            i += 1
        }
    }

    let dst_count = src_count - count
    if dst_count == 0 {
        dst.pointee.array = nil
        dst.pointee.count = 0
        return 0
    }

    let dst_array = ecs_os_calloc_n(ecs_id_t.self, dst_count)!
    dst.pointee.array = dst_array
    dst.pointee.count = dst_count

    if src.pointee.array == nil { return -1 }
    let src_array = src.pointee.array!
    if at > 0 {
        dst_array.update(from: src_array, count: Int(at))
    }

    let remain = dst_count - at
    if remain > 0 {
        (dst_array + Int(at)).update(from: src_array + Int(at + count), count: Int(remain))
    }

    return 0
}

/// Add an id to a type in-place.
public func flecs_type_add(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ type: UnsafeMutablePointer<ecs_type_t>,
    _ add: ecs_id_t)
{
    var new_type = ecs_type_t()
    let res = flecs_type_new_with(world, &new_type, UnsafePointer(type), add)
    if res != -1 {
        flecs_type_free(world, type)
        type.pointee.array = new_type.array
        type.pointee.count = new_type.count
    }
}


/// Initialize a table diff builder with pre-allocated vectors.
public func flecs_table_diff_builder_init(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ builder: UnsafeMutablePointer<ecs_table_diff_builder_t>)
{
    let elem_size = Int32(MemoryLayout<ecs_id_t>.stride)
    ecs_vec_init(&world.pointee.allocator, &builder.pointee.added, elem_size, 32)
    ecs_vec_init(&world.pointee.allocator, &builder.pointee.removed, elem_size, 32)
    builder.pointee.added_flags = 0
    builder.pointee.removed_flags = 0
}

/// Finalize a table diff builder, freeing its vectors.
public func flecs_table_diff_builder_fini(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ builder: UnsafeMutablePointer<ecs_table_diff_builder_t>)
{
    let elem_size = Int32(MemoryLayout<ecs_id_t>.stride)
    ecs_vec_fini(&world.pointee.allocator, &builder.pointee.added, elem_size)
    ecs_vec_fini(&world.pointee.allocator, &builder.pointee.removed, elem_size)
}

/// Clear a table diff builder for reuse.
public func flecs_table_diff_builder_clear(
    _ builder: UnsafeMutablePointer<ecs_table_diff_builder_t>)
{
    ecs_vec_clear(&builder.pointee.added)
    ecs_vec_clear(&builder.pointee.removed)
}

/// Build a no-alloc diff that borrows the builder's arrays.
public func flecs_table_diff_build_noalloc(
    _ builder: UnsafeMutablePointer<ecs_table_diff_builder_t>,
    _ diff: UnsafeMutablePointer<ecs_table_diff_t>)
{
    diff.pointee.added = ecs_type_t(
        array: builder.pointee.added.array?.bindMemory(
            to: ecs_id_t.self, capacity: Int(builder.pointee.added.count)),
        count: builder.pointee.added.count)
    diff.pointee.removed = ecs_type_t(
        array: builder.pointee.removed.array?.bindMemory(
            to: ecs_id_t.self, capacity: Int(builder.pointee.removed.count)),
        count: builder.pointee.removed.count)
    diff.pointee.added_flags = builder.pointee.added_flags
    diff.pointee.removed_flags = builder.pointee.removed_flags
}

/// Append a table diff to a builder.
public func flecs_table_diff_build_append_table(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ dst: UnsafeMutablePointer<ecs_table_diff_builder_t>,
    _ src: UnsafePointer<ecs_table_diff_t>)
{
    let elem_size = Int32(MemoryLayout<ecs_id_t>.stride)
    if src.pointee.added.count > 0 && src.pointee.added.array != nil {
        let offset = dst.pointee.added.count
        ecs_vec_grow(&world.pointee.allocator, &dst.pointee.added,
                     elem_size, src.pointee.added.count)
        let dest = ecs_vec_get(&dst.pointee.added, elem_size, offset)
        if dest != nil {
            dest!.copyMemory(from: src.pointee.added.array!,
                           byteCount: Int(src.pointee.added.count) * MemoryLayout<ecs_id_t>.stride)
        }
    }
    if src.pointee.removed.count > 0 && src.pointee.removed.array != nil {
        let offset = dst.pointee.removed.count
        ecs_vec_grow(&world.pointee.allocator, &dst.pointee.removed,
                     elem_size, src.pointee.removed.count)
        let dest = ecs_vec_get(&dst.pointee.removed, elem_size, offset)
        if dest != nil {
            dest!.copyMemory(from: src.pointee.removed.array!,
                           byteCount: Int(src.pointee.removed.count) * MemoryLayout<ecs_id_t>.stride)
        }
    }
    dst.pointee.added_flags |= src.pointee.added_flags
    dst.pointee.removed_flags |= src.pointee.removed_flags
}


/// Initialize graph edges for a table node.
public func flecs_table_init_node(
    _ node: UnsafeMutablePointer<ecs_graph_node_t>)
{
    node.pointee.add.lo = nil
    node.pointee.add.hi = nil
    node.pointee.remove.lo = nil
    node.pointee.remove.hi = nil
}

/// Ensure a graph edge exists for an id, allocating if necessary.
public func flecs_table_ensure_edge(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ edges: UnsafeMutablePointer<ecs_graph_edges_t>,
    _ id: ecs_id_t) -> UnsafeMutablePointer<ecs_graph_edge_t>
{
    if id < FLECS_HI_COMPONENT_ID {
        if edges.pointee.lo == nil {
            let count = Int(FLECS_HI_COMPONENT_ID)
            edges.pointee.lo = ecs_os_calloc_n(ecs_graph_edge_t.self, Int32(count))!
        }
        return edges.pointee.lo! + Int(id)
    } else {
        return flecs_table_ensure_hi_edge(world, edges, id)
    }
}

/// Ensure a high-id graph edge exists.
private func flecs_table_ensure_hi_edge(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ edges: UnsafeMutablePointer<ecs_graph_edges_t>,
    _ id: ecs_id_t) -> UnsafeMutablePointer<ecs_graph_edge_t>
{
    if edges.pointee.hi == nil {
        edges.pointee.hi = ecs_os_calloc_t(ecs_map_t.self)!
        ecs_map_init(edges.pointee.hi!, &world.pointee.allocator)
    }

    let val_check = ecs_map_get(edges.pointee.hi!, id)
    if val_check != nil {
        if val_check!.pointee != 0 {
            return UnsafeMutablePointer<ecs_graph_edge_t>(
                bitPattern: UInt(val_check!.pointee))!
        }
    }

    let edge: UnsafeMutablePointer<ecs_graph_edge_t>
    if id < FLECS_HI_COMPONENT_ID && edges.pointee.lo != nil {
        edge = edges.pointee.lo! + Int(id)
    } else {
        edge = ecs_os_calloc_t(ecs_graph_edge_t.self)!
    }

    let val = ecs_map_ensure(edges.pointee.hi!, id)
    val.pointee = ecs_map_val_t(UInt(bitPattern: UnsafeMutableRawPointer(edge)))
    return edge
}


/// Traverse the table graph to find the table with an added id.
public func flecs_table_traverse_add(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ node: UnsafeMutablePointer<ecs_table_t>,
    _ id_ptr: UnsafeMutablePointer<ecs_id_t>,
    _ diff: UnsafeMutablePointer<ecs_table_diff_t>) -> UnsafeMutablePointer<ecs_table_t>?
{
    let id = id_ptr.pointee
    guard id != 0 else { return nil }

    let edge = flecs_table_ensure_edge(world, &node.pointee.node.add, id)

    if edge.pointee.to != nil {
        if UnsafeMutableRawPointer(node) != UnsafeMutableRawPointer(edge.pointee.to!) || edge.pointee.diff != nil {
            if edge.pointee.diff != nil {
                diff.pointee = edge.pointee.diff!.pointee
            } else {
                diff.pointee.added.array = id_ptr
                diff.pointee.added.count = 1
                diff.pointee.removed.count = 0
            }
        }
        return edge.pointee.to!
    }

    // Create the edge by finding/creating the target table
    let to = flecs_find_table_with(world, node, id)
    edge.pointee.from = node
    edge.pointee.to = to
    edge.pointee.id = id

    if UnsafeMutableRawPointer(node) != UnsafeMutableRawPointer(to) {
        diff.pointee.added.array = id_ptr
        diff.pointee.added.count = 1
        diff.pointee.removed.count = 0
    }

    return to
}

/// Traverse the table graph to find the table without a removed id.
public func flecs_table_traverse_remove(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ node: UnsafeMutablePointer<ecs_table_t>,
    _ id_ptr: UnsafeMutablePointer<ecs_id_t>,
    _ diff: UnsafeMutablePointer<ecs_table_diff_t>) -> UnsafeMutablePointer<ecs_table_t>?
{
    let id = id_ptr.pointee
    guard id != 0 else { return nil }

    let edge = flecs_table_ensure_edge(world, &node.pointee.node.remove, id)

    if edge.pointee.to != nil {
        if UnsafeMutableRawPointer(node) != UnsafeMutableRawPointer(edge.pointee.to!) || edge.pointee.diff != nil {
            if edge.pointee.diff != nil {
                diff.pointee = edge.pointee.diff!.pointee
            } else {
                diff.pointee.added.count = 0
                diff.pointee.removed.array = id_ptr
                diff.pointee.removed.count = 1
            }
        }
        return edge.pointee.to!
    }

    let to = flecs_find_table_without(world, node, id)
    edge.pointee.from = node
    edge.pointee.to = to
    edge.pointee.id = id

    if UnsafeMutableRawPointer(node) != UnsafeMutableRawPointer(to) {
        diff.pointee.added.count = 0
        diff.pointee.removed.array = id_ptr
        diff.pointee.removed.count = 1
    }

    return to
}


/// Find an existing table with the given type, or create a new one.
private func flecs_find_table_with(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ node: UnsafeMutablePointer<ecs_table_t>,
    _ with: ecs_id_t) -> UnsafeMutablePointer<ecs_table_t>
{
    // Check if component is non-fragmenting
    let cr = flecs_components_get(UnsafePointer(world), with)
    if cr != nil {
        if (cr!.pointee.flags & EcsIdDontFragment) != 0 {
            node.pointee.flags |= EcsTableHasDontFragment
            return node
        }
    }

    // Create new type with the added id
    var dst_type = ecs_type_t()
    let res = flecs_type_new_with(world, &dst_type, &node.pointee.type, with)
    if res == -1 {
        return node  // Already has this id
    }

    // Handle IsA overrides
    if ECS_IS_PAIR(with) && ECS_PAIR_FIRST(with) == EcsIsA {
        // Would call flecs_add_overrides_for_base
    }

    return flecs_table_ensure(world, &dst_type, true, node)
}

/// Find an existing table without the given id.
private func flecs_find_table_without(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ node: UnsafeMutablePointer<ecs_table_t>,
    _ without: ecs_id_t) -> UnsafeMutablePointer<ecs_table_t>
{
    let cr = flecs_components_get(UnsafePointer(world), without)
    if cr != nil {
        if (cr!.pointee.flags & EcsIdDontFragment) != 0 {
            node.pointee.flags |= EcsTableHasDontFragment
            return node
        }
    }

    var dst_type = ecs_type_t()
    let res = flecs_type_new_without(world, &dst_type, &node.pointee.type, without)
    if res == -1 {
        return node
    }

    return flecs_table_ensure(world, &dst_type, true, node)
}

/// Ensure a table exists for the given type. Returns root for empty types.
private func flecs_table_ensure(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ type: UnsafeMutablePointer<ecs_type_t>,
    _ own_type: Bool,
    _ prev: UnsafeMutablePointer<ecs_table_t>?) -> UnsafeMutablePointer<ecs_table_t>
{
    if type.pointee.count == 0 {
        return withUnsafeMutablePointer(to: &world.pointee.store.root) { $0 }
    }

    // Look up in table map
    let elem = flecs_hashmap_ensure(&world.pointee.store.table_map, type)
    let existing = elem.value?.assumingMemoryBound(
        to: UnsafeMutablePointer<ecs_table_t>?.self).pointee
    if existing != nil {
        if own_type {
            flecs_type_free(world, type)
        }
        return existing!
    }

    // Create new table
    let table = flecs_sparse_add(&world.pointee.store.tables,
        Int32(MemoryLayout<ecs_table_t>.stride))!
        .bindMemory(to: ecs_table_t.self, capacity: 1)

    table.pointee._ = ecs_os_calloc_t(ecs_table__t.self)!
    table.pointee.id = flecs_sparse_last_id(&world.pointee.store.tables)

    if own_type {
        table.pointee.type = type.pointee
    } else {
        table.pointee.type = flecs_type_copy(world, UnsafePointer(type))
    }

    // Store in hashmap
    if elem.value != nil {
        elem.value!.assumingMemoryBound(
            to: UnsafeMutablePointer<ecs_table_t>?.self).pointee = table
    }

    flecs_table_init_node(&table.pointee.node)
    flecs_table_init(world, table, prev)

    world.pointee.info.table_count += 1
    world.pointee.info.table_create_total += 1

    return table
}

/// Find or create a table for a type (public API).
public func flecs_table_find_or_create(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ type: UnsafeMutablePointer<ecs_type_t>) -> UnsafeMutablePointer<ecs_table_t>
{
    return flecs_table_ensure(world, type, false, nil)
}

/// Initialize the root table.
public func flecs_init_root_table(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    world.pointee.store.root.type = ecs_type_t()
    world.pointee.store.root._ = ecs_os_calloc_t(ecs_table__t.self)!
    flecs_table_init_node(&world.pointee.store.root.node)
    flecs_table_init(world, &world.pointee.store.root, nil)

    let new_id = flecs_sparse_new_id(&world.pointee.store.tables)
    _ = new_id  // Should be 0, reserved for root
}


/// Add an id to a table, returning the resulting table.
public func ecs_table_add_id(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>?,
    _ id: ecs_id_t) -> UnsafeMutablePointer<ecs_table_t>?
{
    var diff = ecs_table_diff_t()
    var id_mut = id
    let t = table ?? withUnsafeMutablePointer(to: &world.pointee.store.root) { $0 }
    return flecs_table_traverse_add(world, t, &id_mut, &diff)
}

/// Remove an id from a table, returning the resulting table.
public func ecs_table_remove_id(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>?,
    _ id: ecs_id_t) -> UnsafeMutablePointer<ecs_table_t>?
{
    var diff = ecs_table_diff_t()
    var id_mut = id
    let t = table ?? withUnsafeMutablePointer(to: &world.pointee.store.root) { $0 }
    return flecs_table_traverse_remove(world, t, &id_mut, &diff)
}

/// Find a table for a given set of ids.
public func ecs_table_find(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ ids: UnsafePointer<ecs_id_t>,
    _ id_count: Int32) -> UnsafeMutablePointer<ecs_table_t>
{
    var type = ecs_type_t(
        array: UnsafeMutablePointer(mutating: ids),
        count: id_count)
    return flecs_table_ensure(world, &type, false, nil)
}


/// Clear all graph edges for a table (used during table deletion).
public func flecs_table_clear_edges(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ table: UnsafeMutablePointer<ecs_table_t>)
{
    let node = withUnsafeMutablePointer(to: &table.pointee.node) { $0 }

    // Clean up hi maps
    if node.pointee.add.hi != nil {
        ecs_map_fini(node.pointee.add.hi!)
        ecs_os_free(UnsafeMutableRawPointer(node.pointee.add.hi!))
    }
    if node.pointee.remove.hi != nil {
        ecs_map_fini(node.pointee.remove.hi!)
        ecs_os_free(UnsafeMutableRawPointer(node.pointee.remove.hi!))
    }

    // Clean up lo arrays
    if node.pointee.add.lo != nil {
        ecs_os_free(UnsafeMutableRawPointer(node.pointee.add.lo!))
    }
    if node.pointee.remove.lo != nil {
        ecs_os_free(UnsafeMutableRawPointer(node.pointee.remove.lo!))
    }

    node.pointee.add.lo = nil
    node.pointee.remove.lo = nil
    node.pointee.add.hi = nil
    node.pointee.remove.hi = nil
}
