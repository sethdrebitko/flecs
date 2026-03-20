// Module.swift - 1:1 translation of flecs addons/module.c
// Module import and initialization

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Convert a C module name (e.g. "FlecsSystem") to a flecs path ("flecs.system").
public func flecs_module_path_from_c(
    _ c_name: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
{
    var buf = ecs_strbuf_t()
    var ptr = c_name

    while ptr.pointee != 0 {
        var ch = ptr.pointee
        if ch >= 65 && ch <= 90 {  // isupper
            ch = ch + 32  // tolower
            if ptr != c_name {
                ecs_strbuf_appendstrn(&buf, ".", 1)
            }
        }
        withUnsafePointer(to: &ch) {
            ecs_strbuf_appendstrn(&buf, $0, 1)
        }
        ptr += 1
    }

    return ecs_strbuf_get(&buf)
}


/// Import a module into the world. If already imported, returns existing entity.
public func ecs_import(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ module: @convention(c) (UnsafeMutablePointer<ecs_world_t>) -> Void,
    _ module_name: UnsafePointer<CChar>) -> ecs_entity_t
{
    let old_scope = ecs_set_scope(world, 0)
    let old_name_prefix = world.pointee.info.name_prefix

    let path = flecs_module_path_from_c(module_name); if path == nil { return 0 }
    var e = ecs_lookup(world, path!)
    ecs_os_free(UnsafeMutableRawPointer(path!))

    if e == 0 {
        // Load module
        module(world)

        // Lookup module entity (must be registered by module)
        e = ecs_lookup(world, module_name)
        if e == 0 { return 0 }
    }

    ecs_set_scope(world, old_scope)
    world.pointee.info.name_prefix = old_name_prefix

    return e
}

/// Import a module using a C-style name (auto-converts to path).
public func ecs_import_c(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ module: @convention(c) (UnsafeMutablePointer<ecs_world_t>) -> Void,
    _ c_name: UnsafePointer<CChar>) -> ecs_entity_t
{
    let name = flecs_module_path_from_c(c_name); if name == nil { return 0 }
    let e = ecs_import(world, module, name!)
    ecs_os_free(UnsafeMutableRawPointer(name!))
    return e
}


/// Initialize a module entity with optional component data.
public func ecs_module_init(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ c_name: UnsafePointer<CChar>,
    _ desc: UnsafePointer<ecs_component_desc_t>) -> ecs_entity_t
{
    let old_scope = ecs_set_scope(world, 0)

    var e = desc.pointee.entity
    if e == 0 {
        let module_path = flecs_module_path_from_c(c_name); if module_path == nil { return 0 }
        e = ecs_new_entity(world, module_path!)
        ecs_set_symbol(world, e, module_path!)
        ecs_os_free(UnsafeMutableRawPointer(module_path!))
    }

    ecs_add_id(world, e, EcsModule)

    if desc.pointee.type.size != 0 {
        var private_desc = desc.pointee
        private_desc.entity = e
        let result = ecs_component_init(world, &private_desc)
        _ = result
    }

    ecs_set_scope(world, old_scope)
    return e
}
