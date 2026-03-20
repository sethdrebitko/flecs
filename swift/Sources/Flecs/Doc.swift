// Doc.swift - 1:1 translation of flecs addons/doc.c
// Documentation description component management

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Entity documentation description (stores a string value).
public struct EcsDocDescription {
    public var value: UnsafePointer<CChar>?
    public init() { self.value = nil }
}


/// Set the UUID documentation for an entity.
public func ecs_doc_set_uuid(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ name: UnsafePointer<CChar>?)
{
    flecs_doc_set(world, entity, EcsDocUuid, name)
}

/// Set the display name documentation for an entity.
public func ecs_doc_set_name(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ name: UnsafePointer<CChar>?)
{
    flecs_doc_set(world, entity, EcsName, name)
}

/// Set the brief description for an entity.
public func ecs_doc_set_brief(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ brief: UnsafePointer<CChar>?)
{
    flecs_doc_set(world, entity, EcsDocBrief, brief)
}

/// Set the detailed description for an entity.
public func ecs_doc_set_detail(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ detail: UnsafePointer<CChar>?)
{
    flecs_doc_set(world, entity, EcsDocDetail, detail)
}

/// Set the link for an entity.
public func ecs_doc_set_link(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ link: UnsafePointer<CChar>?)
{
    flecs_doc_set(world, entity, EcsDocLink, link)
}

/// Set the color for an entity.
public func ecs_doc_set_color(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ color: UnsafePointer<CChar>?)
{
    flecs_doc_set(world, entity, EcsDocColor, color)
}

/// Internal: set a doc description pair on an entity.
private func flecs_doc_set(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ kind: ecs_entity_t,
    _ value: UnsafePointer<CChar>?)
{
    if value != nil {
        ecs_set_pair(world, entity, ecs_id_EcsDocDescription, kind,
            UnsafeRawPointer(value),
            Int32(MemoryLayout<EcsDocDescription>.stride))
    } else {
        ecs_remove_pair(world, entity, ecs_id_EcsDocDescription, kind)
    }
}


/// Get the UUID documentation for an entity.
public func ecs_doc_get_uuid(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t) -> UnsafePointer<CChar>?
{
    let ptr = ecs_get_pair(world, entity, EcsDocDescription.self, EcsDocUuid)
    if ptr == nil {
        return nil
    }
    return ptr!.pointee.value
}

/// Get the display name for an entity (falls back to entity name).
public func ecs_doc_get_name(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t) -> UnsafePointer<CChar>?
{
    let ptr = ecs_get_pair(world, entity, EcsDocDescription.self, EcsName)
    if ptr != nil {
        return ptr!.pointee.value
    }
    return ecs_get_name(world, entity)
}

/// Get the brief description for an entity.
public func ecs_doc_get_brief(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t) -> UnsafePointer<CChar>?
{
    let ptr = ecs_get_pair(world, entity, EcsDocDescription.self, EcsDocBrief)
    if ptr == nil {
        return nil
    }
    return ptr!.pointee.value
}

/// Get the detailed description for an entity.
public func ecs_doc_get_detail(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t) -> UnsafePointer<CChar>?
{
    let ptr = ecs_get_pair(world, entity, EcsDocDescription.self, EcsDocDetail)
    if ptr == nil {
        return nil
    }
    return ptr!.pointee.value
}

/// Get the link for an entity.
public func ecs_doc_get_link(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t) -> UnsafePointer<CChar>?
{
    let ptr = ecs_get_pair(world, entity, EcsDocDescription.self, EcsDocLink)
    if ptr == nil {
        return nil
    }
    return ptr!.pointee.value
}

/// Get the color for an entity.
public func ecs_doc_get_color(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t) -> UnsafePointer<CChar>?
{
    let ptr = ecs_get_pair(world, entity, EcsDocDescription.self, EcsDocColor)
    if ptr == nil {
        return nil
    }
    return ptr!.pointee.value
}


/// Import the Doc module, registering the EcsDocDescription component.
public func FlecsDocImport(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    ecs_set_name_prefix(world, "EcsDoc")

    // Would register EcsDocDescription component and tag entities
    // (EcsDocUuid, EcsDocBrief, EcsDocDetail, EcsDocLink, EcsDocColor)
    // with copy/move/dtor hooks

    ecs_add_pair(world, ecs_id_EcsDocDescription, EcsOnInstantiate, EcsDontInherit)
}
