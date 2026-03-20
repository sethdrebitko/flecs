// EntityIndex.swift - 1:1 translation of flecs entity_index.h/c
// Stores the table and row for entity IDs with paged lookup

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


public let FLECS_ENTITY_PAGE_SIZE: Int32 = 1 << FLECS_ENTITY_PAGE_BITS // 1024
public let FLECS_ENTITY_PAGE_MASK: Int32 = FLECS_ENTITY_PAGE_SIZE - 1


public struct ecs_entity_index_page_t {
    // Array of records, one per slot in the page
    public var records: UnsafeMutablePointer<ecs_record_t>? = nil

    public init() {}

    public static func allocate() -> UnsafeMutablePointer<ecs_entity_index_page_t> {
        let page = ecs_os_calloc_t(ecs_entity_index_page_t.self)!
        page.pointee = ecs_entity_index_page_t()
        page.pointee.records = ecs_os_calloc_n(ecs_record_t.self, FLECS_ENTITY_PAGE_SIZE)!
        return page
    }

    public static func deallocate(_ page: UnsafeMutablePointer<ecs_entity_index_page_t>) {
        if page.pointee.records != nil {
            ecs_os_free(UnsafeMutableRawPointer(page.pointee.records))
        }
        ecs_os_free(UnsafeMutableRawPointer(page))
    }
}

public struct ecs_entity_index_t {
    public var dense: ecs_vec_t = ecs_vec_t()
    public var pages: ecs_vec_t = ecs_vec_t()
    public var alive_count: Int32 = 0
    public var max_id: UInt64 = 0
    public var allocator: UnsafeMutablePointer<ecs_allocator_t>? = nil
    public init() {}
}


private func flecs_entity_index_ensure_page(
    _ index: UnsafeMutablePointer<ecs_entity_index_t>,
    _ id: UInt32
) -> UnsafeMutablePointer<ecs_entity_index_page_t> {
    let page_index = Int32(id >> UInt32(FLECS_ENTITY_PAGE_BITS))

    if page_index >= ecs_vec_count(&index.pointee.pages) {
        let ptrSize = ecs_size_t(MemoryLayout<UnsafeMutablePointer<ecs_entity_index_page_t>?>.stride)
        ecs_vec_set_min_count_zeromem(index.pointee.allocator, &index.pointee.pages, ptrSize, page_index + 1)
    }

    let ptrSize = ecs_size_t(MemoryLayout<UnsafeMutablePointer<ecs_entity_index_page_t>?>.stride)
    let page_ptr = ecs_vec_get(&index.pointee.pages, ptrSize, page_index)!
        .assumingMemoryBound(to: UnsafeMutablePointer<ecs_entity_index_page_t>?.self)

    if page_ptr.pointee == nil {
        page_ptr.pointee = ecs_entity_index_page_t.allocate()
    }

    return page_ptr.pointee!
}


public func flecs_entity_index_init(
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ index: UnsafeMutablePointer<ecs_entity_index_t>
) {
    index.pointee.allocator = allocator
    index.pointee.alive_count = 1

    let u64Size = ecs_size_t(MemoryLayout<UInt64>.stride)
    ecs_vec_init(allocator, &index.pointee.dense, u64Size, 1)
    ecs_vec_set_count(allocator, &index.pointee.dense, u64Size, 1)

    let ptrSize = ecs_size_t(MemoryLayout<UnsafeMutablePointer<ecs_entity_index_page_t>?>.stride)
    ecs_vec_init(allocator, &index.pointee.pages, ptrSize, 0)
}

public func flecs_entity_index_fini(
    _ index: UnsafeMutablePointer<ecs_entity_index_t>
) {
    let u64Size = ecs_size_t(MemoryLayout<UInt64>.stride)
    ecs_vec_fini(index.pointee.allocator, &index.pointee.dense, u64Size)

    let count = ecs_vec_count(&index.pointee.pages)
    let ptrSize = ecs_size_t(MemoryLayout<UnsafeMutablePointer<ecs_entity_index_page_t>?>.stride)

    if count > 0 {
        let pages = ecs_vec_first(&index.pointee.pages)!
            .assumingMemoryBound(to: UnsafeMutablePointer<ecs_entity_index_page_t>?.self)
        for i in 0..<Int(count) {
            if pages[i] != nil {
                ecs_entity_index_page_t.deallocate(pages[i]!)
            }
        }
    }

    ecs_vec_fini(index.pointee.allocator, &index.pointee.pages, ptrSize)
}

public func flecs_entity_index_get_any(
    _ index: UnsafePointer<ecs_entity_index_t>,
    _ entity: UInt64
) -> UnsafeMutablePointer<ecs_record_t>? {
    let id = UInt32(truncatingIfNeeded: entity)
    let page_index = Int32(id >> UInt32(FLECS_ENTITY_PAGE_BITS))

    let ptrSize = ecs_size_t(MemoryLayout<UnsafeMutablePointer<ecs_entity_index_page_t>?>.stride)
    var pagesVec = index.pointee.pages
    let page_ptr = ecs_vec_get(&pagesVec, ptrSize, page_index)!
        .assumingMemoryBound(to: UnsafeMutablePointer<ecs_entity_index_page_t>?.self)
    if page_ptr.pointee == nil { return nil }

    let offset = Int(id & UInt32(FLECS_ENTITY_PAGE_MASK))
    let r = page_ptr.pointee!.pointee.records!.advanced(by: offset)

    if r.pointee.dense == 0 { return nil }
    return r
}

public func flecs_entity_index_get(
    _ index: UnsafePointer<ecs_entity_index_t>,
    _ entity: UInt64
) -> UnsafeMutablePointer<ecs_record_t>? {
    let r = flecs_entity_index_get_any(index, entity)
    if r == nil { return nil }
    if r!.pointee.dense >= index.pointee.alive_count { return nil }
    return r!
}

public func flecs_entity_index_try_get_any(
    _ index: UnsafePointer<ecs_entity_index_t>,
    _ entity: UInt64
) -> UnsafeMutablePointer<ecs_record_t>? {
    let id = UInt32(truncatingIfNeeded: entity)
    let page_index = Int32(id >> UInt32(FLECS_ENTITY_PAGE_BITS))

    var pagesVec = index.pointee.pages
    if page_index >= ecs_vec_count(&pagesVec) {
        return nil
    }

    let ptrSize = ecs_size_t(MemoryLayout<UnsafeMutablePointer<ecs_entity_index_page_t>?>.stride)
    let page_ptr = ecs_vec_get(&pagesVec, ptrSize, page_index)!
        .assumingMemoryBound(to: UnsafeMutablePointer<ecs_entity_index_page_t>?.self)
    if page_ptr.pointee == nil { return nil }

    let offset = Int(id & UInt32(FLECS_ENTITY_PAGE_MASK))
    let r = page_ptr.pointee!.pointee.records!.advanced(by: offset)

    if r.pointee.dense == 0 { return nil }
    return r
}

public func flecs_entity_index_try_get(
    _ index: UnsafePointer<ecs_entity_index_t>,
    _ entity: UInt64
) -> UnsafeMutablePointer<ecs_record_t>? {
    let r = flecs_entity_index_try_get_any(index, entity)
    if r == nil { return nil }
    if r!.pointee.dense >= index.pointee.alive_count { return nil }

    let u64Size = ecs_size_t(MemoryLayout<UInt64>.stride)
    var denseVec = index.pointee.dense
    let stored = ecs_vec_get(&denseVec, u64Size, r!.pointee.dense)!
        .assumingMemoryBound(to: UInt64.self).pointee
    if stored != entity { return nil }

    return r!
}

public func flecs_entity_index_ensure(
    _ index: UnsafeMutablePointer<ecs_entity_index_t>,
    _ entity: UInt64
) -> UnsafeMutablePointer<ecs_record_t> {
    let id = UInt32(truncatingIfNeeded: entity)
    let page = flecs_entity_index_ensure_page(index, id)

    let offset = Int(id & UInt32(FLECS_ENTITY_PAGE_MASK))
    let r = page.pointee.records!.advanced(by: offset)

    if r.pointee.dense == 0 {
        // New entity - add to dense array
        let u64Size = ecs_size_t(MemoryLayout<UInt64>.stride)
        let dense_count = ecs_vec_count(&index.pointee.dense)
        let dense_ptr = ecs_vec_append(index.pointee.allocator, &index.pointee.dense, u64Size)!
            .assumingMemoryBound(to: UInt64.self)
        dense_ptr.pointee = entity
        r.pointee.dense = dense_count

        if UInt64(id) >= index.pointee.max_id {
            index.pointee.max_id = UInt64(id)
        }
    }

    return r
}

public func flecs_entity_index_remove(
    _ index: UnsafeMutablePointer<ecs_entity_index_t>,
    _ entity: UInt64
) {
    let r = flecs_entity_index_try_get(
        UnsafePointer(index), entity)
    if r == nil { return }

    let dense_index = r!.pointee.dense
    let alive_count = index.pointee.alive_count

    if dense_index < alive_count {
        // Swap with last alive
        index.pointee.alive_count -= 1
        let last_alive = index.pointee.alive_count

        let u64Size = ecs_size_t(MemoryLayout<UInt64>.stride)
        let dense_arr = ecs_vec_first(&index.pointee.dense)!
            .assumingMemoryBound(to: UInt64.self)

        let last_entity = dense_arr[Int(last_alive)]

        // Swap dense entries
        dense_arr[Int(dense_index)] = last_entity
        dense_arr[Int(last_alive)] = entity

        // Update the record of the swapped entity
        let last_r = flecs_entity_index_get_any(
            UnsafePointer(index), last_entity)
        if last_r != nil {
            last_r!.pointee.dense = dense_index
        }

        // Increment generation
        let new_entity = ECS_GENERATION_INC(entity)
        dense_arr[Int(last_alive)] = new_entity

        r!.pointee.dense = last_alive
    }

    // Clear record
    r!.pointee.table = nil
    r!.pointee.row = 0
}

public func flecs_entity_index_make_alive(
    _ index: UnsafeMutablePointer<ecs_entity_index_t>,
    _ entity: UInt64
) {
    let r = flecs_entity_index_ensure(index, entity)
    let dense_index = r.pointee.dense

    if dense_index >= index.pointee.alive_count {
        // Swap with first not-alive
        let alive_count = index.pointee.alive_count

        let u64Size = ecs_size_t(MemoryLayout<UInt64>.stride)
        let dense_arr = ecs_vec_first(&index.pointee.dense)!
            .assumingMemoryBound(to: UInt64.self)

        let first_not_alive = dense_arr[Int(alive_count)]

        // Swap
        dense_arr[Int(dense_index)] = first_not_alive
        dense_arr[Int(alive_count)] = entity

        // Update record of swapped entity
        let other_r = flecs_entity_index_get_any(
            UnsafePointer(index), first_not_alive)
        if other_r != nil {
            other_r!.pointee.dense = dense_index
        }

        r.pointee.dense = alive_count
        index.pointee.alive_count += 1
    }
}

public func flecs_entity_index_is_alive(
    _ index: UnsafePointer<ecs_entity_index_t>,
    _ entity: UInt64
) -> Bool {
    return flecs_entity_index_try_get(index, entity) != nil
}

public func flecs_entity_index_is_valid(
    _ index: UnsafePointer<ecs_entity_index_t>,
    _ entity: UInt64
) -> Bool {
    let id = UInt32(truncatingIfNeeded: entity)
    if id == 0 { return false }

    // If it has a generation, it must match
    if ECS_GENERATION(entity) != 0 {
        return flecs_entity_index_is_alive(index, entity)
    }
    return true
}

public func flecs_entity_index_exists(
    _ index: UnsafePointer<ecs_entity_index_t>,
    _ entity: UInt64
) -> Bool {
    return flecs_entity_index_try_get_any(index, entity) != nil
}

public func flecs_entity_index_get_alive(
    _ index: UnsafePointer<ecs_entity_index_t>,
    _ entity: UInt64
) -> UInt64 {
    let r = flecs_entity_index_try_get_any(index, entity)
    if r == nil { return 0 }

    let u64Size = ecs_size_t(MemoryLayout<UInt64>.stride)
    var denseVec = index.pointee.dense
    let stored = ecs_vec_get(&denseVec, u64Size, r!.pointee.dense)!
        .assumingMemoryBound(to: UInt64.self).pointee
    return stored
}

public func flecs_entity_index_new_id(
    _ index: UnsafeMutablePointer<ecs_entity_index_t>
) -> UInt64 {
    let dense_count = ecs_vec_count(&index.pointee.dense)
    let alive_count = index.pointee.alive_count

    if alive_count < dense_count {
        // Recycle
        let u64Size = ecs_size_t(MemoryLayout<UInt64>.stride)
        let dense_arr = ecs_vec_first(&index.pointee.dense)!
            .assumingMemoryBound(to: UInt64.self)
        let entity = dense_arr[Int(alive_count)]
        index.pointee.alive_count += 1
        return entity
    }

    // Create new
    index.pointee.max_id += 1
    let entity = index.pointee.max_id
    let _ = flecs_entity_index_ensure(index, entity)
    flecs_entity_index_make_alive(index, entity)
    return entity
}

public func flecs_entity_index_count(
    _ index: UnsafePointer<ecs_entity_index_t>
) -> Int32 {
    return index.pointee.alive_count - 1 // Subtract the reserved 0 slot
}

public func flecs_entity_index_size(
    _ index: UnsafePointer<ecs_entity_index_t>
) -> Int32 {
    return ecs_vec_count(UnsafeMutablePointer(mutating: &UnsafeMutablePointer(mutating: index).pointee.dense))
}

public func flecs_entity_index_not_alive_count(
    _ index: UnsafePointer<ecs_entity_index_t>
) -> Int32 {
    var denseVec = index.pointee.dense
    return ecs_vec_count(&denseVec) - index.pointee.alive_count
}

public func flecs_entity_index_clear(
    _ index: UnsafeMutablePointer<ecs_entity_index_t>
) {
    let ptrSize = ecs_size_t(MemoryLayout<UnsafeMutablePointer<ecs_entity_index_page_t>?>.stride)
    let count = ecs_vec_count(&index.pointee.pages)
    if count > 0 {
        let pages = ecs_vec_first(&index.pointee.pages)!
            .assumingMemoryBound(to: UnsafeMutablePointer<ecs_entity_index_page_t>?.self)
        for i in 0..<Int(count) {
            if pages[i] != nil {
                ecs_entity_index_page_t.deallocate(pages[i]!)
            }
        }
    }
    ecs_vec_clear(&index.pointee.pages)

    let u64Size = ecs_size_t(MemoryLayout<UInt64>.stride)
    ecs_vec_set_count(index.pointee.allocator, &index.pointee.dense, u64Size, 1)
    index.pointee.alive_count = 1
    index.pointee.max_id = 0
}

public func flecs_entity_index_ids(
    _ index: UnsafePointer<ecs_entity_index_t>
) -> UnsafePointer<UInt64>? {
    var denseVec = index.pointee.dense
    let first = ecs_vec_first(&denseVec)
    if first == nil { return nil }
    return first!.assumingMemoryBound(to: UInt64.self)
}
