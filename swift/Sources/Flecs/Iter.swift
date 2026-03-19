// Iter.swift - 1:1 translation of flecs iterator utilities
// Iterator initialization, field access, and lifecycle

import Foundation

// MARK: - Iterator Init

public func flecs_iter_init(
    _ world: UnsafeRawPointer?,
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ alloc_resources: Bool
) {
    it.pointee.world = UnsafeMutableRawPointer(mutating: world)
    it.pointee.real_world = UnsafeMutableRawPointer(mutating: world)

    if alloc_resources {
        let field_count = Int(it.pointee.field_count)
        if field_count > 0 {
            // Allocate field arrays
            let idSize = MemoryLayout<ecs_id_t>.stride * field_count
            it.pointee.ids = UnsafeMutablePointer<ecs_id_t>.allocate(capacity: field_count)
            it.pointee.ids!.initialize(repeating: 0, count: field_count)

            let srcSize = MemoryLayout<ecs_entity_t>.stride * field_count
            it.pointee.sources = UnsafeMutablePointer<ecs_entity_t>.allocate(capacity: field_count)
            it.pointee.sources!.initialize(repeating: 0, count: field_count)

            it.pointee.ptrs = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: field_count)
            it.pointee.ptrs!.initialize(repeating: nil, count: field_count)

            it.pointee.sizes = UnsafeMutablePointer<ecs_size_t>.allocate(capacity: field_count)
            UnsafeMutablePointer(mutating: it.pointee.sizes)!.initialize(repeating: 0, count: field_count)
        }
    }

    it.pointee.flags |= EcsIterIsValid
}

public func flecs_iter_fini_fields(
    _ it: UnsafeMutablePointer<ecs_iter_t>
) {
    let field_count = Int(it.pointee.field_count)
    if field_count > 0 {
        if let ids = it.pointee.ids {
            ids.deinitialize(count: field_count)
            ids.deallocate()
            it.pointee.ids = nil
        }
        if let sources = it.pointee.sources {
            sources.deinitialize(count: field_count)
            sources.deallocate()
            it.pointee.sources = nil
        }
        if let ptrs = it.pointee.ptrs {
            ptrs.deinitialize(count: field_count)
            ptrs.deallocate()
            it.pointee.ptrs = nil
        }
        if let sizes = it.pointee.sizes {
            let mutable = UnsafeMutablePointer(mutating: sizes)
            mutable.deinitialize(count: field_count)
            mutable.deallocate()
            it.pointee.sizes = nil
        }
    }
}

public func flecs_iter_free(
    _ ptr: UnsafeMutableRawPointer?,
    _ size: ecs_size_t
) {
    if let ptr = ptr {
        ptr.deallocate()
    }
}

public func flecs_iter_calloc(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ size: ecs_size_t,
    _ align: ecs_size_t
) -> UnsafeMutableRawPointer? {
    let ptr = ecs_os_calloc(Int32(size))
    return ptr
}

// MARK: - Public Iterator API

/// Check if iterator is valid
public func ecs_iter_is_true(
    _ it: UnsafeMutablePointer<ecs_iter_t>
) -> Bool {
    // Evaluate the query to check if it has any results
    if let next = it.pointee.next {
        let hasResults = next(it)
        if hasResults {
            // Fini
            if let fini = it.pointee.fini {
                fini(it)
            }
            return true
        }
    }
    return false
}

/// Get field data for current iterator result
public func ecs_field(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int32
) -> UnsafeMutableRawPointer? {
    guard index >= 0 && index < Int32(it.pointee.field_count) else { return nil }
    guard let ptrs = it.pointee.ptrs else { return nil }
    return ptrs[Int(index)]
}

/// Get field size
public func ecs_field_size(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int32
) -> ecs_size_t {
    guard index >= 0 && index < Int32(it.pointee.field_count) else { return 0 }
    guard let sizes = it.pointee.sizes else { return 0 }
    return sizes[Int(index)]
}

/// Check if field is set
public func ecs_field_is_set(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int32
) -> Bool {
    guard index >= 0 && index < Int32(it.pointee.field_count) else { return false }
    return (it.pointee.set_fields & (1 << UInt32(index))) != 0
}

/// Check if field is self (not inherited)
public func ecs_field_is_self(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int32
) -> Bool {
    guard index >= 0 && index < Int32(it.pointee.field_count) else { return false }
    guard let sources = it.pointee.sources else { return true }
    return sources[Int(index)] == 0
}

/// Get field id
public func ecs_field_id(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int32
) -> ecs_id_t {
    guard index >= 0 && index < Int32(it.pointee.field_count) else { return 0 }
    guard let ids = it.pointee.ids else { return 0 }
    return ids[Int(index)]
}

/// Get field source
public func ecs_field_src(
    _ it: UnsafePointer<ecs_iter_t>,
    _ index: Int32
) -> ecs_entity_t {
    guard index >= 0 && index < Int32(it.pointee.field_count) else { return 0 }
    guard let sources = it.pointee.sources else { return 0 }
    return sources[Int(index)]
}

/// Finalize iterator
public func ecs_iter_fini(
    _ it: UnsafeMutablePointer<ecs_iter_t>
) {
    it.pointee.flags &= ~EcsIterIsValid

    if let fini = it.pointee.fini {
        fini(it)
    }

    flecs_iter_fini_fields(it)
}

/// Get entity for current row
public func ecs_iter_entity(
    _ it: UnsafePointer<ecs_iter_t>,
    _ row: Int32
) -> ecs_entity_t {
    guard let entities = it.pointee.entities else { return 0 }
    return entities[Int(it.pointee.offset + row)]
}

// MARK: - Each Iterator

public func ecs_each_id(
    _ world: UnsafeMutableRawPointer?,
    _ id: ecs_id_t
) -> ecs_iter_t {
    var it = ecs_iter_t()
    it.world = world
    it.real_world = world
    it.next = { _ in return false }  // Stub
    return it
}

public func ecs_each_next(
    _ it: UnsafeMutablePointer<ecs_iter_t>?
) -> Bool {
    guard let it = it, let next = it.pointee.next else { return false }
    return next(it)
}

// MARK: - Utility

/// Get the count of entities matched in the current result
public func ecs_iter_count(
    _ it: UnsafePointer<ecs_iter_t>
) -> Int32 {
    return it.pointee.count
}

/// Get the table for the current result
public func ecs_iter_table(
    _ it: UnsafePointer<ecs_iter_t>
) -> UnsafeMutableRawPointer? {
    return it.pointee.table
}

/// Skip the current result during iteration
public func ecs_iter_skip(
    _ it: UnsafeMutablePointer<ecs_iter_t>
) {
    it.pointee.flags |= EcsIterSkip
}
