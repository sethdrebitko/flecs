/// Sparse.swift
/// Translation of ecs_sparse_t and its operations from flecs.
/// Sparse set data structure with paging for O(1) access with stable pointers.

import Foundation

// MARK: - Constants

// FLECS_SPARSE_PAGE_BITS defined in Types.swift
public let FLECS_SPARSE_PAGE_SIZE: Int32 = 1 << FLECS_SPARSE_PAGE_BITS  // 64

@inline(__always)
public func FLECS_SPARSE_PAGE(_ index: UInt64) -> Int32 {
    return Int32(UInt32(truncatingIfNeeded: index) >> UInt32(FLECS_SPARSE_PAGE_BITS))
}

@inline(__always)
public func FLECS_SPARSE_OFFSET(_ index: UInt64) -> Int32 {
    return Int32(UInt32(truncatingIfNeeded: index) & UInt32(FLECS_SPARSE_PAGE_SIZE - 1))
}

// MARK: - Types

/// A page in the sparse set containing a sparse-to-dense mapping and data.
public struct ecs_sparse_page_t {
    public var sparse: UnsafeMutablePointer<Int32>?
    public var data: UnsafeMutableRawPointer?

    public init() {
        self.sparse = nil
        self.data = nil
    }
}

/// A sparse set data structure for O(1) access with stable pointers.
public struct ecs_sparse_t {
    public var dense: ecs_vec_t
    public var pages: ecs_vec_t
    public var size: ecs_size_t        // element size
    public var count: Int32            // alive count
    public var max_id: UInt64
    public var allocator: UnsafeMutablePointer<ecs_allocator_t>?
    public var page_allocator: UnsafeMutablePointer<ecs_block_allocator_t>?

    public init() {
        self.dense = ecs_vec_t()
        self.pages = ecs_vec_t()
        self.size = 0
        self.count = 0
        self.max_id = 0
        self.allocator = nil
        self.page_allocator = nil
    }
}

// MARK: - Internal helpers

private let sparsePageSize = Int32(MemoryLayout<ecs_sparse_page_t>.stride)
private let uint64Size = Int32(MemoryLayout<UInt64>.stride)

/// Get pointer to data at a given offset within a page's data array.
@inline(__always)
private func SPARSE_DATA(
    _ array: UnsafeMutableRawPointer?,
    _ size: ecs_size_t,
    _ offset: Int32) -> UnsafeMutableRawPointer?
{
    guard let array = array else { return nil }
    return array.advanced(by: Int(size) * Int(offset))
}

private func flecs_sparse_page_new(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>,
    _ page_index: Int32) -> UnsafeMutablePointer<ecs_sparse_page_t>
{
    let count = ecs_vec_count(&sparse.pointee.pages)

    if count <= page_index {
        ecs_vec_set_count(sparse.pointee.allocator, &sparse.pointee.pages,
            sparsePageSize, page_index + 1)
        let pages = ecs_vec_first(&sparse.pointee.pages)!
            .bindMemory(to: ecs_sparse_page_t.self, capacity: Int(page_index + 1))
        for i in Int(count)...Int(page_index) {
            pages[i] = ecs_sparse_page_t()
        }
    }

    let pages = ecs_vec_first(&sparse.pointee.pages)!
        .bindMemory(to: ecs_sparse_page_t.self, capacity: Int(page_index + 1))

    let result = &pages[Int(page_index)]

    // Allocate sparse array (int32 * page_size), zero-initialized
    if let ca = sparse.pointee.page_allocator {
        result.pointee.sparse = flecs_bcalloc(ca)?.bindMemory(
            to: Int32.self, capacity: Int(FLECS_SPARSE_PAGE_SIZE))
    } else {
        result.pointee.sparse = calloc(Int(FLECS_SPARSE_PAGE_SIZE), MemoryLayout<Int32>.size)?
            .bindMemory(to: Int32.self, capacity: Int(FLECS_SPARSE_PAGE_SIZE))
    }

    // Allocate data array, zero-initialized
    if sparse.pointee.size > 0 {
        let data_bytes = Int(sparse.pointee.size) * Int(FLECS_SPARSE_PAGE_SIZE)
        result.pointee.data = calloc(1, data_bytes)
    } else {
        result.pointee.data = nil
    }

    return result
}

private func flecs_sparse_page_free(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>,
    _ page: UnsafeMutablePointer<ecs_sparse_page_t>)
{
    if let ca = sparse.pointee.page_allocator {
        flecs_bfree(ca, UnsafeMutableRawPointer(page.pointee.sparse))
    } else {
        free(page.pointee.sparse)
    }
    free(page.pointee.data)
    page.pointee.sparse = nil
    page.pointee.data = nil
}

private func flecs_sparse_get_page(
    _ sparse: UnsafePointer<ecs_sparse_t>,
    _ page_index: Int32) -> UnsafeMutablePointer<ecs_sparse_page_t>?
{
    if page_index < 0 {
        return nil
    }
    // Access pages vec through a mutable pointer cast (safe: we only read)
    let sparse_mut = UnsafeMutablePointer(mutating: sparse)
    if page_index >= ecs_vec_count(&sparse_mut.pointee.pages) {
        return nil
    }
    guard let raw = ecs_vec_get(&sparse_mut.pointee.pages, sparsePageSize, page_index) else {
        return nil
    }
    return raw.bindMemory(to: ecs_sparse_page_t.self, capacity: 1)
}

private func flecs_sparse_get_or_create_page(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>,
    _ page_index: Int32) -> UnsafeMutablePointer<ecs_sparse_page_t>
{
    if let page = flecs_sparse_get_page(UnsafePointer(sparse), page_index),
       page.pointee.sparse != nil {
        return page
    }
    return flecs_sparse_page_new(sparse, page_index)
}

private func flecs_sparse_grow_dense(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>)
{
    _ = ecs_vec_append(sparse.pointee.allocator, &sparse.pointee.dense, uint64Size)
}

private func flecs_sparse_assign_index(
    _ page: UnsafeMutablePointer<ecs_sparse_page_t>,
    _ dense_array: UnsafeMutablePointer<UInt64>,
    _ id: UInt64,
    _ dense: Int32)
{
    page.pointee.sparse![Int(FLECS_SPARSE_OFFSET(id))] = dense
    dense_array[Int(dense)] = id
}

private func flecs_sparse_inc_id(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>) -> UInt64
{
    sparse.pointee.max_id &+= 1
    return sparse.pointee.max_id
}

/// Get the dense array as a typed pointer.
@inline(__always)
private func sparse_dense_ptr(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>) -> UnsafeMutablePointer<UInt64>?
{
    return ecs_vec_first(&sparse.pointee.dense)?
        .bindMemory(to: UInt64.self, capacity: Int(ecs_vec_count(&sparse.pointee.dense)))
}

/// Get the dense array as a typed pointer (const variant).
@inline(__always)
private func sparse_dense_ptr_const(
    _ sparse: UnsafePointer<ecs_sparse_t>) -> UnsafeMutablePointer<UInt64>?
{
    let m = UnsafeMutablePointer(mutating: sparse)
    return ecs_vec_first(&m.pointee.dense)?
        .bindMemory(to: UInt64.self, capacity: Int(ecs_vec_count(&m.pointee.dense)))
}

private func flecs_sparse_create_id(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>,
    _ dense: Int32) -> UInt64
{
    let id = flecs_sparse_inc_id(sparse)
    flecs_sparse_grow_dense(sparse)

    let page = flecs_sparse_get_or_create_page(sparse, FLECS_SPARSE_PAGE(id))
    let dense_array = sparse_dense_ptr(sparse)!
    flecs_sparse_assign_index(page, dense_array, id, dense)

    return id
}

private func flecs_sparse_new_index(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>) -> UInt64
{
    let dense_count = ecs_vec_count(&sparse.pointee.dense)
    let count = sparse.pointee.count
    sparse.pointee.count += 1

    if count < dense_count {
        let dense_array = sparse_dense_ptr(sparse)!
        return dense_array[Int(count)]
    } else {
        return flecs_sparse_create_id(sparse, count)
    }
}

private func flecs_sparse_get_sparse(
    _ sparse: UnsafePointer<ecs_sparse_t>,
    _ dense: Int32,
    _ id: UInt64) -> UnsafeMutableRawPointer?
{
    let index = UInt64(UInt32(truncatingIfNeeded: id))
    guard let page = flecs_sparse_get_page(sparse, FLECS_SPARSE_PAGE(index)) else {
        return nil
    }
    guard page.pointee.sparse != nil else {
        return nil
    }
    let offset = FLECS_SPARSE_OFFSET(index)
    return SPARSE_DATA(page.pointee.data, sparse.pointee.size, offset)
}

private func flecs_sparse_swap_dense(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>,
    _ page_a: UnsafeMutablePointer<ecs_sparse_page_t>,
    _ a: Int32,
    _ b: Int32)
{
    let dense_array = sparse_dense_ptr(sparse)!
    let id_a = dense_array[Int(a)]
    let id_b = dense_array[Int(b)]

    let page_b = flecs_sparse_get_or_create_page(sparse, FLECS_SPARSE_PAGE(id_b))
    flecs_sparse_assign_index(page_a, dense_array, id_a, b)
    flecs_sparse_assign_index(page_b, dense_array, id_b, a)
}

// MARK: - Public internal API (flecs_ prefix)

public func flecs_sparse_init(
    _ result: UnsafeMutablePointer<ecs_sparse_t>,
    _ allocator: UnsafeMutablePointer<ecs_allocator_t>?,
    _ page_allocator: UnsafeMutablePointer<ecs_block_allocator_t>?,
    _ size: ecs_size_t)
{
    result.pointee.size = size
    result.pointee.max_id = UInt64.max
    result.pointee.allocator = allocator
    result.pointee.page_allocator = page_allocator

    ecs_vec_init(allocator, &result.pointee.pages, sparsePageSize, 0)
    ecs_vec_init(allocator, &result.pointee.dense, uint64Size, 1)
    result.pointee.dense.count = 1

    // Consume first value in dense array as 0 is sentinel
    let first = ecs_vec_first(&result.pointee.dense)!
        .bindMemory(to: UInt64.self, capacity: 1)
    first[0] = 0

    result.pointee.count = 1
}

public func flecs_sparse_fini(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>)
{
    let count = ecs_vec_count(&sparse.pointee.pages)
    if count > 0 {
        let pages = ecs_vec_first(&sparse.pointee.pages)!
            .bindMemory(to: ecs_sparse_page_t.self, capacity: Int(count))
        for i in 0..<Int(count) {
            if pages[i].sparse != nil {
                flecs_sparse_page_free(sparse, &pages[i])
            }
        }
    }
    ecs_vec_fini(sparse.pointee.allocator, &sparse.pointee.pages, sparsePageSize)
    ecs_vec_fini(sparse.pointee.allocator, &sparse.pointee.dense, uint64Size)
}

public func flecs_sparse_clear(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>)
{
    let count = ecs_vec_count(&sparse.pointee.pages)
    if count > 0 {
        let pages = ecs_vec_first(&sparse.pointee.pages)!
            .bindMemory(to: ecs_sparse_page_t.self, capacity: Int(count))
        for i in 0..<Int(count) {
            if let indices = pages[i].sparse {
                memset(indices, 0, Int(FLECS_SPARSE_PAGE_SIZE) * MemoryLayout<Int32>.size)
            }
        }
    }

    ecs_vec_set_count(sparse.pointee.allocator, &sparse.pointee.dense, uint64Size, 1)
    sparse.pointee.count = 1
    sparse.pointee.max_id = 0
}

public func flecs_sparse_new_id(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>) -> UInt64
{
    return flecs_sparse_new_index(sparse)
}

public func flecs_sparse_add(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>,
    _ size: ecs_size_t) -> UnsafeMutableRawPointer?
{
    let id = flecs_sparse_new_index(sparse)
    let page = flecs_sparse_get_page(UnsafePointer(sparse), FLECS_SPARSE_PAGE(id))!
    return SPARSE_DATA(page.pointee.data, size, FLECS_SPARSE_OFFSET(id))
}

public func flecs_sparse_last_id(
    _ sparse: UnsafePointer<ecs_sparse_t>) -> UInt64
{
    guard let dense_array = sparse_dense_ptr_const(sparse) else { return 0 }
    return dense_array[Int(sparse.pointee.count - 1)]
}

public func flecs_sparse_insert(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>,
    _ size: ecs_size_t,
    _ id: UInt64) -> UnsafeMutableRawPointer?
{
    var is_new = true
    let result = flecs_sparse_ensure(sparse, size, id, &is_new)
    if !is_new {
        return nil
    }
    return result
}

public func flecs_sparse_ensure(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>,
    _ size: ecs_size_t,
    _ id: UInt64,
    _ is_new: UnsafeMutablePointer<Bool>?) -> UnsafeMutableRawPointer?
{
    let index = UInt64(UInt32(truncatingIfNeeded: id))
    let page = flecs_sparse_get_or_create_page(sparse, FLECS_SPARSE_PAGE(index))
    let offset = FLECS_SPARSE_OFFSET(index)
    let dense = page.pointee.sparse![Int(offset)]

    if dense != 0 {
        let count = sparse.pointee.count
        if dense >= count {
            flecs_sparse_swap_dense(sparse, page, dense, count)

            sparse.pointee.count += 1

            let dense_array = sparse_dense_ptr(sparse)!
            dense_array[Int(count)] = id
        } else {
            is_new?.pointee = false
        }
    } else {
        flecs_sparse_grow_dense(sparse)

        let dense_array = sparse_dense_ptr(sparse)!
        let dense_count = ecs_vec_count(&sparse.pointee.dense) - 1
        let count = sparse.pointee.count
        sparse.pointee.count += 1

        if index >= sparse.pointee.max_id {
            sparse.pointee.max_id = index
        }

        if count < dense_count {
            let unused = dense_array[Int(count)]
            let unused_page = flecs_sparse_get_or_create_page(sparse, FLECS_SPARSE_PAGE(unused))
            flecs_sparse_assign_index(unused_page, dense_array, unused, dense_count)
        }

        flecs_sparse_assign_index(page, dense_array, id, count)
    }

    return SPARSE_DATA(page.pointee.data, sparse.pointee.size, offset)
}

public func flecs_sparse_ensure_fast(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>,
    _ size: ecs_size_t,
    _ id: UInt64) -> UnsafeMutableRawPointer?
{
    let index = UInt32(truncatingIfNeeded: id)
    let page = flecs_sparse_get_or_create_page(sparse, FLECS_SPARSE_PAGE(UInt64(index)))
    let offset = FLECS_SPARSE_OFFSET(UInt64(index))
    let dense = page.pointee.sparse![Int(offset)]
    let count = sparse.pointee.count

    if dense == 0 {
        sparse.pointee.count = count + 1
        if count == ecs_vec_count(&sparse.pointee.dense) {
            flecs_sparse_grow_dense(sparse)
        }

        let dense_array = sparse_dense_ptr(sparse)!
        flecs_sparse_assign_index(page, dense_array, UInt64(index), count)
    }

    return SPARSE_DATA(page.pointee.data, sparse.pointee.size, offset)
}

@discardableResult
public func flecs_sparse_remove(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>,
    _ size: ecs_size_t,
    _ id: UInt64) -> Bool
{
    guard let page = flecs_sparse_get_page(UnsafePointer(sparse), FLECS_SPARSE_PAGE(id)) else {
        return false
    }
    guard page.pointee.sparse != nil else {
        return false
    }

    let index = UInt64(UInt32(truncatingIfNeeded: id))
    let offset = FLECS_SPARSE_OFFSET(index)
    let dense = page.pointee.sparse![Int(offset)]

    if dense != 0 {
        let count = sparse.pointee.count
        if dense == (count - 1) {
            sparse.pointee.count -= 1
        } else if dense < count {
            flecs_sparse_swap_dense(sparse, page, dense, count - 1)
            sparse.pointee.count -= 1
        }

        if sparse.pointee.size > 0 {
            if let ptr = SPARSE_DATA(page.pointee.data, sparse.pointee.size, offset) {
                memset(ptr, 0, Int(size))
            }
        }

        return true
    }

    return false
}

public func flecs_sparse_is_alive(
    _ sparse: UnsafePointer<ecs_sparse_t>,
    _ id: UInt64) -> Bool
{
    guard let page = flecs_sparse_get_page(sparse, FLECS_SPARSE_PAGE(id)) else {
        return false
    }
    guard page.pointee.sparse != nil else {
        return false
    }

    let offset = FLECS_SPARSE_OFFSET(id)
    let dense = page.pointee.sparse![Int(offset)]
    if dense == 0 || dense >= sparse.pointee.count {
        return false
    }
    return true
}

public func flecs_sparse_get_dense(
    _ sparse: UnsafePointer<ecs_sparse_t>,
    _ size: ecs_size_t,
    _ dense_index: Int32) -> UnsafeMutableRawPointer?
{
    let di = dense_index + 1
    guard let dense_array = sparse_dense_ptr_const(sparse) else { return nil }
    return flecs_sparse_get_sparse(sparse, di, dense_array[Int(di)])
}

public func flecs_sparse_count(
    _ sparse: UnsafePointer<ecs_sparse_t>?) -> Int32
{
    guard let sparse = sparse, sparse.pointee.count > 0 else {
        return 0
    }
    return sparse.pointee.count - 1
}

public func flecs_sparse_get(
    _ sparse: UnsafePointer<ecs_sparse_t>,
    _ size: ecs_size_t,
    _ id: UInt64) -> UnsafeMutableRawPointer?
{
    let index = UInt64(UInt32(truncatingIfNeeded: id))
    guard let page = flecs_sparse_get_page(sparse, FLECS_SPARSE_PAGE(index)) else {
        return nil
    }
    guard page.pointee.sparse != nil else {
        return nil
    }

    let offset = FLECS_SPARSE_OFFSET(index)
    let dense = page.pointee.sparse![Int(offset)]
    let in_use = dense != 0 && dense < sparse.pointee.count
    if !in_use {
        return nil
    }

    return SPARSE_DATA(page.pointee.data, sparse.pointee.size, offset)
}

public func flecs_sparse_ids(
    _ sparse: UnsafePointer<ecs_sparse_t>) -> UnsafePointer<UInt64>?
{
    let m = UnsafeMutablePointer(mutating: sparse)
    guard let arr = ecs_vec_first(&m.pointee.dense) else { return nil }
    let typed = arr.bindMemory(to: UInt64.self,
        capacity: Int(ecs_vec_count(&m.pointee.dense)))
    return UnsafePointer(typed.advanced(by: 1))
}

// MARK: - Public API (ecs_ prefix)

public func ecs_sparse_init(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>,
    _ elem_size: ecs_size_t)
{
    flecs_sparse_init(sparse, nil, nil, elem_size)
}

public func ecs_sparse_add(
    _ sparse: UnsafeMutablePointer<ecs_sparse_t>,
    _ elem_size: ecs_size_t) -> UnsafeMutableRawPointer?
{
    return flecs_sparse_add(sparse, elem_size)
}

public func ecs_sparse_last_id(
    _ sparse: UnsafePointer<ecs_sparse_t>) -> UInt64
{
    return flecs_sparse_last_id(sparse)
}

public func ecs_sparse_count(
    _ sparse: UnsafePointer<ecs_sparse_t>) -> Int32
{
    return flecs_sparse_count(sparse)
}

public func ecs_sparse_get_dense(
    _ sparse: UnsafePointer<ecs_sparse_t>,
    _ elem_size: ecs_size_t,
    _ index: Int32) -> UnsafeMutableRawPointer?
{
    return flecs_sparse_get_dense(sparse, elem_size, index)
}

public func ecs_sparse_get(
    _ sparse: UnsafePointer<ecs_sparse_t>,
    _ elem_size: ecs_size_t,
    _ id: UInt64) -> UnsafeMutableRawPointer?
{
    return flecs_sparse_get(sparse, elem_size, id)
}
