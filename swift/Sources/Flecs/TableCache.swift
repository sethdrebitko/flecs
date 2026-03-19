// TableCache.swift
// Translation of flecs/src/storage/table_cache.c

// MARK: - Private helpers

/// Read the `id` field from an ecs_table_t raw pointer.
/// ecs_table_t layout: first field is `uint64_t id` at offset 0.
private func flecs_table_id(_ table: UnsafeMutableRawPointer) -> UInt64 {
    return table.load(as: UInt64.self)
}

/// Read `data.count` from an ecs_table_t raw pointer.
/// ecs_table_t layout (64-bit):
///   offset  0: id (UInt64)
///   offset  8: flags (UInt32)
///   offset 12: column_count (Int16)
///   offset 14: version (UInt16)
///   offset 16: bloom_filter (UInt64)
///   offset 24: trait_flags (UInt32)
///   offset 28: keep (Int16)
///   offset 30: childof_index (Int16)
///   offset 32: type.array (pointer, 8 bytes)
///   offset 40: type.count (Int32, 4 bytes) + 4 padding
///   offset 48: data.entities (pointer, 8 bytes)
///   offset 56: data.columns (pointer, 8 bytes)
///   offset 64: data.overrides (pointer, 8 bytes)
///   offset 72: data.count (Int32)
private func flecs_table_data_count(_ table: UnsafeMutableRawPointer) -> Int32 {
    return table.load(fromByteOffset: 72, as: Int32.self)
}

// MARK: - Private linked list operations

private func flecs_table_cache_list_remove(
    _ cache: UnsafeMutablePointer<ecs_table_cache_t>,
    _ elem: UnsafeMutablePointer<ecs_table_cache_hdr_t>)
{
    let next = elem.pointee.next
    let prev = elem.pointee.prev

    if let next = next {
        next.pointee.prev = prev
    }
    if let prev = prev {
        prev.pointee.next = next
    }

    cache.pointee.tables.count -= 1

    if cache.pointee.tables.first == elem {
        cache.pointee.tables.first = next
    }
    if cache.pointee.tables.last == elem {
        cache.pointee.tables.last = prev
    }
}

private func flecs_table_cache_list_insert(
    _ cache: UnsafeMutablePointer<ecs_table_cache_t>,
    _ elem: UnsafeMutablePointer<ecs_table_cache_hdr_t>)
{
    let last = cache.pointee.tables.last
    cache.pointee.tables.last = elem
    cache.pointee.tables.count += 1
    if cache.pointee.tables.count == 1 {
        cache.pointee.tables.first = elem
    }

    elem.pointee.next = nil
    elem.pointee.prev = last

    if let last = last {
        last.pointee.next = elem
    }
}

// MARK: - Public API

public func ecs_table_cache_init(
    _ world: UnsafeMutableRawPointer?,
    _ cache: UnsafeMutablePointer<ecs_table_cache_t>)
{
    // In the C code: ecs_map_init(&cache->index, &world->allocator)
    // The allocator parameter is accepted but we use malloc/free directly via ecs_map_init.
    // We pass nil for the allocator since our map implementation uses malloc/free.
    ecs_map_init(&cache.pointee.index, nil)
}

public func ecs_table_cache_fini(
    _ cache: UnsafeMutablePointer<ecs_table_cache_t>)
{
    ecs_map_fini(&cache.pointee.index)
}

public func ecs_table_cache_insert(
    _ cache: UnsafeMutablePointer<ecs_table_cache_t>,
    _ table: UnsafeMutableRawPointer?,
    _ result: UnsafeMutablePointer<ecs_table_cache_hdr_t>)
{
    // result->cr = (ecs_component_record_t*)cache
    result.pointee.cr = UnsafeMutableRawPointer(cache)
    // result->table = table
    result.pointee.table = table

    flecs_table_cache_list_insert(cache, result)

    guard let table = table else { return }
    let tableId = flecs_table_id(table)
    // ecs_map_insert_ptr(&cache->index, table->id, result)
    let ptrVal = ecs_map_val_t(UInt(bitPattern: UnsafeMutableRawPointer(result)))
    ecs_map_insert(&cache.pointee.index, tableId, ptrVal)
}

public func ecs_table_cache_replace(
    _ cache: UnsafeMutablePointer<ecs_table_cache_t>,
    _ table: UnsafeMutableRawPointer?,
    _ elem: UnsafeMutablePointer<ecs_table_cache_hdr_t>)
{
    guard let table = table else { return }
    let tableId = flecs_table_id(table)

    // ecs_map_get_ref -> ecs_map_get, which returns a pointer to the map value
    guard let r = ecs_map_get(&cache.pointee.index, tableId) else { return }

    // old = *r (the pointer stored in the map)
    let oldRaw = UnsafeMutableRawPointer(bitPattern: UInt(r.pointee))
    guard let oldPtr = oldRaw else { return }
    let old = oldPtr.assumingMemoryBound(to: ecs_table_cache_hdr_t.self)

    let prev = old.pointee.prev
    let next = old.pointee.next

    if let prev = prev {
        prev.pointee.next = elem
    }
    if let next = next {
        next.pointee.prev = elem
    }

    if cache.pointee.tables.first == old {
        cache.pointee.tables.first = elem
    }
    if cache.pointee.tables.last == old {
        cache.pointee.tables.last = elem
    }

    // *r = elem
    r.pointee = ecs_map_val_t(UInt(bitPattern: UnsafeMutableRawPointer(elem)))
    elem.pointee.prev = prev
    elem.pointee.next = next
}

@discardableResult
public func ecs_table_cache_remove(
    _ cache: UnsafeMutablePointer<ecs_table_cache_t>,
    _ table_id: UInt64,
    _ elem: UnsafeMutablePointer<ecs_table_cache_hdr_t>) -> UnsafeMutableRawPointer?
{
    flecs_table_cache_list_remove(cache, elem)
    ecs_map_remove(&cache.pointee.index, table_id)
    return UnsafeMutableRawPointer(elem)
}

public func ecs_table_cache_get(
    _ cache: UnsafePointer<ecs_table_cache_t>,
    _ table: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
{
    guard let table = table else { return nil }
    let tableId = flecs_table_id(table)
    // Compute pointer to the index field within the cache struct
    let indexPtr = UnsafeRawPointer(cache).assumingMemoryBound(to: ecs_map_t.self)
    return ecs_map_get_deref_(indexPtr, tableId)
}

public func flecs_table_cache_count(
    _ cache: UnsafePointer<ecs_table_cache_t>) -> Int32
{
    return cache.pointee.tables.count
}

public func flecs_table_cache_iter(
    _ cache: UnsafePointer<ecs_table_cache_t>,
    _ out: UnsafeMutablePointer<ecs_table_cache_iter_t>) -> Bool
{
    out.pointee.next = UnsafePointer(cache.pointee.tables.first)
    out.pointee.cur = nil
    out.pointee.iter_fill = true
    out.pointee.iter_empty = false
    return out.pointee.next != nil
}

public func flecs_table_cache_empty_iter(
    _ cache: UnsafePointer<ecs_table_cache_t>,
    _ out: UnsafeMutablePointer<ecs_table_cache_iter_t>) -> Bool
{
    out.pointee.next = UnsafePointer(cache.pointee.tables.first)
    out.pointee.cur = nil
    out.pointee.iter_fill = false
    out.pointee.iter_empty = true
    return out.pointee.next != nil
}

public func flecs_table_cache_all_iter(
    _ cache: UnsafePointer<ecs_table_cache_t>,
    _ out: UnsafeMutablePointer<ecs_table_cache_iter_t>) -> Bool
{
    out.pointee.next = UnsafePointer(cache.pointee.tables.first)
    out.pointee.cur = nil
    out.pointee.iter_fill = true
    out.pointee.iter_empty = true
    return out.pointee.next != nil
}

public func flecs_table_cache_next_(
    _ it: UnsafeMutablePointer<ecs_table_cache_iter_t>) -> UnsafePointer<ecs_table_cache_hdr_t>?
{
    while true {
        guard let next = it.pointee.next else {
            it.pointee.cur = nil
            return nil
        }

        it.pointee.cur = next
        it.pointee.next = next.pointee.next

        if let table = next.pointee.table {
            let count = flecs_table_data_count(table)
            if count > 0 {
                // Table has entities (non-empty / "fill")
                if !it.pointee.iter_fill {
                    continue
                }
            } else {
                // Table is empty
                if !it.pointee.iter_empty {
                    continue
                }
            }
        }

        return next
    }
}
