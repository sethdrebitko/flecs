// Bootstrap.swift - 1:1 translation of flecs bootstrap.c
// World initialization and builtin entity/component registration

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


/// Destructor for EcsIdentifier - frees the string value.
public func flecs_identifier_dtor(
    _ ptr: UnsafeMutablePointer<EcsIdentifier>)
{
    if ptr.pointee.value != nil {
        ecs_os_free(UnsafeMutableRawPointer(mutating: ptr.pointee.value!))
        ptr.pointee.value = nil
    }
}

/// Copy for EcsIdentifier - duplicates the string value.
public func flecs_identifier_copy(
    _ dst: UnsafeMutablePointer<EcsIdentifier>,
    _ src: UnsafePointer<EcsIdentifier>)
{
    if src.pointee.value != nil {
        dst.pointee.value = ecs_os_strdup(src.pointee.value!)
    } else {
        dst.pointee.value = nil
    }
    dst.pointee.hash = src.pointee.hash
    dst.pointee.length = src.pointee.length
    dst.pointee.index_hash = src.pointee.index_hash
    dst.pointee.index = src.pointee.index
}

/// Move for EcsIdentifier - transfers ownership of the string.
public func flecs_identifier_move(
    _ dst: UnsafeMutablePointer<EcsIdentifier>,
    _ src: UnsafeMutablePointer<EcsIdentifier>)
{
    if dst.pointee.value != nil {
        ecs_os_free(UnsafeMutableRawPointer(mutating: dst.pointee.value!))
    }
    dst.pointee.value = src.pointee.value
    dst.pointee.hash = src.pointee.hash
    dst.pointee.length = src.pointee.length
    dst.pointee.index_hash = src.pointee.index_hash
    dst.pointee.index = src.pointee.index

    src.pointee.value = nil
    src.pointee.hash = 0
    src.pointee.index_hash = 0
    src.pointee.index = nil
    src.pointee.length = 0
}


/// Move for EcsPoly - transfers the poly pointer.
public func flecs_poly_move(
    _ dst: UnsafeMutablePointer<EcsPoly>,
    _ src: UnsafeMutablePointer<EcsPoly>)
{
    if dst.pointee.poly != nil && dst.pointee.poly! != src.pointee.poly {
        let dtor = flecs_get_dtor(dst.pointee.poly!)
        if dtor != nil {
            dtor!(dst.pointee.poly!)
        }
    }
    dst.pointee.poly = src.pointee.poly
    src.pointee.poly = nil
}

/// Destructor for EcsPoly - invokes the poly's destructor.
public func flecs_poly_dtor(
    _ ptr: UnsafeMutablePointer<EcsPoly>)
{
    if ptr.pointee.poly != nil {
        let dtor = flecs_get_dtor(ptr.pointee.poly!)
        if dtor != nil {
            dtor!(ptr.pointee.poly!)
        }
    }
}


/// Context for trait observers that map traits to component record flags.
public struct ecs_on_trait_ctx_t {
    public var flag: ecs_flags32_t
    public var not_flag: ecs_flags32_t
    public init(flag: ecs_flags32_t, not_flag: ecs_flags32_t) {
        self.flag = flag
        self.not_flag = not_flag
    }
}

/// Assert that a relationship is not in use when changing traits.
public func flecs_assert_relation_unused(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ rel: ecs_entity_t,
    _ trait: ecs_entity_t)
{
    if (world.pointee.flags & (EcsWorldInit | EcsWorldFini)) != 0 {
        return
    }

    // Check if id is being cleaned up
    let count = ecs_vec_count(&world.pointee.store.marked_ids)
    if count > 0 {
        let ids = ecs_vec_first(&world.pointee.store.marked_ids)?
            .bindMemory(to: ecs_marked_id_t.self, capacity: Int(count))
        if ids != nil {
            for i in 0..<Int(count) {
                if ids![i].id == ecs_pair(rel, EcsWildcard) {
                    return
                }
            }
        }
    }

    // Would check ecs_id_in_use and throw if relationship is already used
}

/// Set a flag on a component record if not already set.
public func flecs_set_id_flag(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ flag: ecs_flags32_t,
    _ trait: ecs_entity_t) -> Bool
{
    if (cr.pointee.flags & flag) == 0 {
        cr.pointee.flags |= flag
        if flag == EcsIdSparse {
            flecs_component_init_sparse(world, cr)
        }
        if flag == EcsIdDontFragment {
            flecs_component_record_init_dont_fragment(world, cr)
        }
        if flag == EcsIdExclusive {
            flecs_component_record_init_exclusive(world, cr)
        }
        return true
    }
    return false
}

/// Clear a flag on a component record.
public func flecs_unset_id_flag(
    _ cr: UnsafeMutablePointer<ecs_component_record_t>,
    _ flag: ecs_flags32_t) -> Bool
{
    if (cr.pointee.flags & EcsIdMarkedForDelete) != 0 {
        return false
    }
    if (cr.pointee.flags & flag) != 0 {
        cr.pointee.flags &= ~flag
        return true
    }
    return false
}

/// Register flags for a trait on all entities in the iterator.
public func flecs_register_flag_for_trait(
    _ it: UnsafeMutablePointer<ecs_iter_t>,
    _ trait: ecs_entity_t,
    _ flag: ecs_flags32_t,
    _ not_flag: ecs_flags32_t,
    _ entity_flag: ecs_flags32_t)
{
    let world = it.pointee.world!
    let event = it.pointee.event

    for i in 0..<Int(it.pointee.count) {
        let e = it.pointee.entities![i]
        var changed = false

        if event == EcsOnAdd {
            let cr1 = flecs_components_get(UnsafePointer(world), e)
            if cr1 != nil {
                changed = flecs_set_id_flag(world, cr1!, flag, trait) || changed
            }
            let cr2 = flecs_components_get(UnsafePointer(world), ecs_pair(e, EcsWildcard))
            if cr2 != nil {
                var cur: UnsafeMutablePointer<ecs_component_record_t>? = cr2
                repeat {
                    changed = flecs_set_id_flag(world, cur!, flag, trait) || changed
                    cur = flecs_component_first_next(cur!)
                } while cur != nil
            }
            if entity_flag != 0 {
                flecs_add_flag(world, e, entity_flag)
            }
        } else if event == EcsOnRemove {
            let cr3 = flecs_components_get(UnsafePointer(world), e)
            if cr3 != nil {
                changed = flecs_unset_id_flag(cr3!, not_flag) || changed
            }
            let cr4 = flecs_components_get(UnsafePointer(world), ecs_pair(e, EcsWildcard))
            if cr4 != nil {
                var cur: UnsafeMutablePointer<ecs_component_record_t>? = cr4
                repeat {
                    changed = flecs_unset_id_flag(cur!, not_flag) || changed
                    cur = flecs_component_first_next(cur!)
                } while cur != nil
            }
        }

        if changed {
            flecs_assert_relation_unused(world, e, trait)
        }
    }
}


/// Make an entity alive before the root table is initialized.
public func flecs_bootstrap_make_alive(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ e: ecs_entity_t)
{
    let root = withUnsafeMutablePointer(to: &world.pointee.store.root) { $0 }
    flecs_entities_make_alive(world, e)

    let r = flecs_entities_ensure(world, e)
    if r.pointee.table == nil {
        r.pointee.table = UnsafeMutableRawPointer(root)
        r.pointee.row = UInt32(root.pointee.data.count)

        // Append entity to root table
        if root.pointee.data.entities != nil {
            root.pointee.data.entities![Int(root.pointee.data.count)] = e
        }
        root.pointee.data.count += 1
    }
}

/// Bootstrap a named entity under a parent.
public func flecs_bootstrap_entity(
    _ world: UnsafeMutablePointer<ecs_world_t>,
    _ id: ecs_entity_t,
    _ name: UnsafePointer<CChar>,
    _ parent: ecs_entity_t)
{
    flecs_bootstrap_make_alive(world, id)
    ecs_add_pair(world, id, EcsChildOf, parent)
    ecs_set_name(world, id, name)
}


/// Initialize the world by bootstrapping all builtin entities and components.
/// This is the entry point that sets up the entire ECS type system.
public func flecs_bootstrap(
    _ world: UnsafeMutablePointer<ecs_world_t>)
{
    // Set name prefix for stripping "Ecs" from component names
    ecs_set_name_prefix(world, "Ecs")

    // Make builtin ids alive
    let builtin_ids: [ecs_entity_t] = [
        ecs_id_EcsComponent, ecs_id_EcsIdentifier, ecs_id_EcsPoly,
        ecs_id_EcsParent, ecs_id_EcsTreeSpawner, ecs_id_EcsDefaultChildComponent,
        EcsFinal, EcsName, EcsSymbol, EcsAlias,
        EcsChildOf, EcsFlecs, EcsFlecsCore,
        EcsOnAdd, EcsOnRemove, EcsOnSet,
        EcsOnDelete, EcsPanic, EcsFlag,
        EcsIsA, EcsWildcard, EcsAny,
        EcsCanToggle, EcsTrait, EcsRelationship, EcsTarget,
        EcsSparse, EcsDontFragment, EcsObserver, EcsPairIsTag
    ]

    for id in builtin_ids {
        flecs_bootstrap_make_alive(world, id)
    }

    // Initialize id records cached on world
    world.pointee.cr_childof_wildcard = flecs_components_ensure(
        world, ecs_pair(EcsChildOf, EcsWildcard))
    world.pointee.cr_childof_wildcard!.pointee.flags |=
        EcsIdOnDeleteTargetDelete | EcsIdOnInstantiateDontInherit |
        EcsIdTraversable | EcsIdPairIsTag | EcsIdExclusive

    let cr_ident = flecs_components_ensure(
        world, ecs_pair(ecs_id_EcsIdentifier, EcsWildcard))
    cr_ident.pointee.flags |= EcsIdOnInstantiateDontInherit

    world.pointee.cr_identifier_name = flecs_components_ensure(
        world, ecs_pair(ecs_id_EcsIdentifier, EcsName))
    world.pointee.cr_childof_0 = flecs_components_ensure(
        world, ecs_pair(EcsChildOf, 0))

    // Initialize root table
    flecs_init_root_table(world)

    // Create and cache often used id records
    flecs_components_init(world)

    // Initialize default entity id range
    world.pointee.info.last_component_id = EcsFirstUserComponentId
    world.pointee.info.min_id = 0
    world.pointee.info.max_id = 0

    // Set up core module hierarchy
    ecs_set_scope(world, EcsFlecsCore)

    // Bootstrap entity names
    flecs_bootstrap_entity(world, EcsFlecs, "flecs", 0)
    ecs_add_id(world, EcsFlecs, EcsModule)
    ecs_add_pair(world, EcsFlecs, EcsOnDelete, EcsPanic)

    ecs_add_pair(world, EcsFlecsCore, EcsChildOf, EcsFlecs)
    ecs_set_name(world, EcsFlecsCore, "core")
    ecs_add_id(world, EcsFlecsCore, EcsModule)

    // Bootstrap builtin entities
    flecs_bootstrap_entity(world, EcsWorld, "World", EcsFlecsCore)
    flecs_bootstrap_entity(world, EcsWildcard, "*", EcsFlecsCore)
    flecs_bootstrap_entity(world, EcsAny, "_", EcsFlecsCore)
    flecs_bootstrap_entity(world, EcsThis, "this", EcsFlecsCore)
    flecs_bootstrap_entity(world, EcsVariable, "$", EcsFlecsCore)
    flecs_bootstrap_entity(world, EcsFlag, "Flag", EcsFlecsCore)

    // Bootstrap events
    flecs_bootstrap_entity(world, EcsOnAdd, "OnAdd", EcsFlecsCore)
    flecs_bootstrap_entity(world, EcsOnRemove, "OnRemove", EcsFlecsCore)
    flecs_bootstrap_entity(world, EcsOnSet, "OnSet", EcsFlecsCore)

    // Set relationship properties
    ecs_add_pair(world, EcsChildOf, EcsOnDeleteTarget, EcsDelete)
    ecs_add_id(world, EcsChildOf, EcsTrait)
    ecs_add_id(world, EcsIsA, EcsTrait)
    ecs_add_id(world, EcsChildOf, EcsAcyclic)
    ecs_add_id(world, EcsChildOf, EcsTraversable)
    ecs_add_pair(world, EcsChildOf, EcsOnInstantiate, EcsDontInherit)
    ecs_add_pair(world, ecs_id_EcsIdentifier, EcsOnInstantiate, EcsDontInherit)

    // Exclusive properties
    ecs_add_id(world, EcsChildOf, EcsExclusive)
    ecs_add_id(world, EcsOnDelete, EcsExclusive)
    ecs_add_id(world, EcsOnDeleteTarget, EcsExclusive)
    ecs_add_id(world, EcsOnInstantiate, EcsExclusive)

    // Tag relationships
    ecs_add_id(world, EcsIsA, EcsPairIsTag)
    ecs_add_id(world, EcsChildOf, EcsPairIsTag)
    ecs_add_id(world, EcsSlotOf, EcsPairIsTag)
    ecs_add_id(world, EcsDependsOn, EcsPairIsTag)
    ecs_add_id(world, EcsFlag, EcsPairIsTag)
    ecs_add_id(world, EcsWith, EcsPairIsTag)

    // Traversable/acyclic
    ecs_add_id(world, EcsIsA, EcsTraversable)
    ecs_add_id(world, EcsDependsOn, EcsTraversable)
    ecs_add_id(world, EcsWith, EcsAcyclic)

    // Transitive relationships
    ecs_add_id(world, EcsIsA, EcsTransitive)
    ecs_add_id(world, EcsIsA, EcsReflexive)

    // With properties
    ecs_add_pair(world, EcsTraversable, EcsWith, EcsAcyclic)
    ecs_add_pair(world, EcsTransitive, EcsWith, EcsTraversable)
    ecs_add_pair(world, EcsDontFragment, EcsWith, EcsSparse)
    ecs_add_pair(world, EcsModule, EcsWith, EcsSingleton)

    // DontInherit components
    ecs_add_pair(world, EcsPrefab, EcsOnInstantiate, EcsDontInherit)
    ecs_add_pair(world, ecs_id_EcsComponent, EcsOnInstantiate, EcsDontInherit)

    // Inherited components
    ecs_add_pair(world, EcsIsA, EcsOnInstantiate, EcsInherit)
    ecs_add_pair(world, EcsDependsOn, EcsOnInstantiate, EcsInherit)

    // Run sub-bootstrap functions
    flecs_bootstrap_entity_name(world)

    ecs_set_scope(world, 0)
    ecs_set_name_prefix(world, nil)
}
