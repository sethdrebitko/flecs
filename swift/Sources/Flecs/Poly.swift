// Poly.swift - 1:1 translation of flecs poly.c
// Functions for managing polymorphic flecs objects (world, query, observer)

import Foundation

// MARK: - Mixin Types

public enum ecs_mixin_kind_t: Int32 {
    case world = 0       // EcsMixinWorld
    case entity = 1      // EcsMixinEntity
    case observable = 2  // EcsMixinObservable
    case dtor = 3        // EcsMixinDtor
    case max = 4         // EcsMixinMax
}

public let EcsMixinWorld = ecs_mixin_kind_t.world
public let EcsMixinEntity = ecs_mixin_kind_t.entity
public let EcsMixinObservable = ecs_mixin_kind_t.observable
public let EcsMixinDtor = ecs_mixin_kind_t.dtor
public let EcsMixinMax = ecs_mixin_kind_t.max

public struct ecs_mixins_t {
    public var type_name: UnsafePointer<CChar>?
    public var elems: (ecs_size_t, ecs_size_t, ecs_size_t, ecs_size_t) // [EcsMixinMax]

    public init() {
        self.type_name = nil
        self.elems = (0, 0, 0, 0)
    }

    public subscript(kind: ecs_mixin_kind_t) -> ecs_size_t {
        get {
            switch kind {
            case .world: return elems.0
            case .entity: return elems.1
            case .observable: return elems.2
            case .dtor: return elems.3
            case .max: return 0
            }
        }
        set {
            switch kind {
            case .world: elems.0 = newValue
            case .entity: elems.1 = newValue
            case .observable: elems.2 = newValue
            case .dtor: elems.3 = newValue
            case .max: break
            }
        }
    }
}

// MARK: - Mixin Tables

public var ecs_world_t_mixins = ecs_mixins_t()
public var ecs_stage_t_mixins = ecs_mixins_t()
public var ecs_observer_t_mixins = ecs_mixins_t()

// MARK: - Internal

private func assert_mixin(
    _ poly: UnsafeRawPointer?,
    _ kind: ecs_mixin_kind_t) -> UnsafeMutableRawPointer?
{
    guard let poly = poly else { return nil }

    let hdr = poly.assumingMemoryBound(to: ecs_header_t.self)
    guard hdr.pointee.type != 0 else { return nil }
    guard let mixins = hdr.pointee.mixins else { return nil }

    let m = mixins.assumingMemoryBound(to: ecs_mixins_t.self)
    let offset = m.pointee[kind]
    guard offset != 0 else { return nil }

    return UnsafeMutableRawPointer(mutating: poly).advanced(by: Int(offset))
}

// MARK: - Public API

/// Initialize a poly object.
public func flecs_poly_init_(
    _ poly: UnsafeMutableRawPointer?,
    _ type: Int32,
    _ size: ecs_size_t,
    _ mixins: UnsafeMutablePointer<ecs_mixins_t>?) -> UnsafeMutableRawPointer?
{
    guard let poly = poly else { return nil }
    memset(poly, 0, Int(size))

    let hdr = poly.assumingMemoryBound(to: ecs_header_t.self)
    hdr.pointee.type = type
    hdr.pointee.refcount = 1
    hdr.pointee.mixins = UnsafeMutableRawPointer(mixins)

    return poly
}

/// Finalize a poly object.
public func flecs_poly_fini_(
    _ poly: UnsafeMutableRawPointer?,
    _ type: Int32)
{
    guard let poly = poly else { return }
    let hdr = poly.assumingMemoryBound(to: ecs_header_t.self)
    hdr.pointee.type = 0
}

/// Increment refcount on poly object.
@discardableResult
public func flecs_poly_claim_(
    _ poly: UnsafeMutableRawPointer?) -> Int32
{
    guard let poly = poly else { return 0 }
    let hdr = poly.assumingMemoryBound(to: ecs_header_t.self)
    hdr.pointee.refcount += 1
    return hdr.pointee.refcount
}

/// Decrement refcount on poly object.
@discardableResult
public func flecs_poly_release_(
    _ poly: UnsafeMutableRawPointer?) -> Int32
{
    guard let poly = poly else { return 0 }
    let hdr = poly.assumingMemoryBound(to: ecs_header_t.self)
    hdr.pointee.refcount -= 1
    return hdr.pointee.refcount
}

/// Get refcount of poly object.
public func flecs_poly_refcount(
    _ poly: UnsafeMutableRawPointer?) -> Int32
{
    guard let poly = poly else { return 0 }
    let hdr = poly.assumingMemoryBound(to: ecs_header_t.self)
    return hdr.pointee.refcount
}

/// Check if a poly object is of a given type.
public func flecs_poly_is_(
    _ poly: UnsafeRawPointer?,
    _ type: Int32) -> Bool
{
    guard let poly = poly else { return false }
    let hdr = poly.assumingMemoryBound(to: ecs_header_t.self)
    return hdr.pointee.type == type
}

/// Get observable mixin from poly object.
public func flecs_get_observable(
    _ poly: UnsafeRawPointer?) -> UnsafeMutablePointer<ecs_observable_t>?
{
    guard let ptr = assert_mixin(poly, .observable) else { return nil }
    return ptr.bindMemory(to: ecs_observable_t.self, capacity: 1)
}

/// Get the world from a poly object (world or stage).
public func ecs_get_world(
    _ poly: UnsafeRawPointer?) -> UnsafePointer<ecs_world_t>?
{
    guard let poly = poly else { return nil }
    let hdr = poly.assumingMemoryBound(to: ecs_header_t.self)
    if hdr.pointee.type == ecs_world_t_magic {
        return poly.assumingMemoryBound(to: ecs_world_t.self)
    }
    guard let ptr = assert_mixin(poly, .world) else { return nil }
    return ptr.assumingMemoryBound(to: UnsafeMutablePointer<ecs_world_t>.self)
        .pointee.withMemoryRebound(to: ecs_world_t.self, capacity: 1) { UnsafePointer($0) }
}

/// Get entity from poly object.
public func ecs_get_entity(
    _ poly: UnsafeRawPointer?) -> ecs_entity_t
{
    guard let ptr = assert_mixin(poly, .entity) else { return 0 }
    return ptr.assumingMemoryBound(to: ecs_entity_t.self).pointee
}

/// Get destructor mixin from poly object.
public func flecs_get_dtor(
    _ poly: UnsafeRawPointer?) -> UnsafeMutablePointer<flecs_poly_dtor_t>?
{
    guard let ptr = assert_mixin(poly, .dtor) else { return nil }
    return ptr.bindMemory(to: flecs_poly_dtor_t.self, capacity: 1)
}
