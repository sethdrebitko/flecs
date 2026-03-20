// Ref.swift - 1:1 translation of flecs ref.c
// Refs provide faster access to components than get

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Initialize a ref for fast repeated access to an entity's component.
/// The ref caches the table and column, only updating when the table changes.
public func ecs_ref_init_id(
    _ world: UnsafePointer<ecs_world_t>,
    _ entity: ecs_entity_t,
    _ id: ecs_id_t) -> ecs_ref_t
{
    guard ecs_is_alive(world, entity) else { return ecs_ref_t() }
    guard ecs_id_is_valid(UnsafeRawPointer(world), id) else { return ecs_ref_t() }

    let w = ecs_get_world(UnsafeRawPointer(world))!

    let record = flecs_entities_get(w, entity)
    if record == nil {
        return ecs_ref_t()
    }

    var result = ecs_ref_t()
    result.entity = entity
    result.id = id
    result.record = UnsafeMutablePointer(mutating: record!)

    if record!.pointee.table == nil {
        return ecs_ref_t()
    }
    let table = record!.pointee.table!

    result.table_id = table.pointee.id
    result.table_version = table.pointee.version

    // Get cached component pointer
    let cr = flecs_components_get(w, id)
    if cr != nil {
        result.ptr = flecs_get_component(
            w, table, ECS_RECORD_TO_ROW(record!.pointee.row), cr!)
    }

    return result
}


/// Update a ref after potential table changes.
/// Uses fast version check to skip work when nothing changed.
public func ecs_ref_update(
    _ world: UnsafePointer<ecs_world_t>,
    _ ref: UnsafeMutablePointer<ecs_ref_t>)
{
    guard ref.pointee.entity != 0 else { return }
    guard ref.pointee.id != 0 else { return }
    if ref.pointee.record == nil { return }
    let record = ref.pointee.record!

    if record.pointee.table == nil {
        // Entity was deleted
        ref.pointee.table_id = 0
        ref.pointee.table_version = 0
        ref.pointee.ptr = nil
        return
    }
    let table = record.pointee.table!

    if !ecs_is_alive(world, ref.pointee.entity) {
        ref.pointee.table_id = 0
        ref.pointee.table_version = 0
        ref.pointee.ptr = nil
        return
    }

    // Check if table and version still match
    if ref.pointee.table_id == table.pointee.id &&
       ref.pointee.table_version == table.pointee.version
    {
        return
    }

    // Table changed, update cached pointer
    ref.pointee.table_id = table.pointee.id
    ref.pointee.table_version = table.pointee.version

    let cr = flecs_components_get(world, ref.pointee.id)
    if cr != nil {
        ref.pointee.ptr = flecs_get_component(
            world, table, ECS_RECORD_TO_ROW(record.pointee.row), cr!)
    } else {
        ref.pointee.ptr = nil
    }
}


/// Get a component pointer from a ref, updating if necessary.
public func ecs_ref_get_id(
    _ world: UnsafePointer<ecs_world_t>,
    _ ref: UnsafeMutablePointer<ecs_ref_t>,
    _ id: ecs_id_t) -> UnsafeMutableRawPointer?
{
    guard ref.pointee.entity != 0 else { return nil }
    guard ref.pointee.id != 0 else { return nil }
    guard ref.pointee.record != nil else { return nil }

    ecs_ref_update(world, ref)
    return ref.pointee.ptr
}
