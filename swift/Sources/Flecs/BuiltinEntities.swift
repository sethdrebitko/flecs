// BuiltinEntities.swift - 1:1 translation of flecs built-in entity IDs
// These are the well-known entity IDs assigned during bootstrap

import Foundation

// MARK: - Built-in Component IDs (1..8)

public var FLECS_IDEcsComponentID_: ecs_entity_t = 1
public var FLECS_IDEcsIdentifierID_: ecs_entity_t = 2
public var FLECS_IDEcsPolyID_: ecs_entity_t = 3
public var FLECS_IDEcsParentID_: ecs_entity_t = 4
public var FLECS_IDEcsTreeSpawnerID_: ecs_entity_t = 5
public var FLECS_IDEcsDefaultChildComponentID_: ecs_entity_t = 6

// MARK: - Built-in Entity IDs (> FLECS_HI_COMPONENT_ID)

// Hierarchy
public var EcsFlecs: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 1
public var EcsFlecsCore: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 2
public var EcsWorld: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 3

// Special entities
public var EcsWildcard: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 4
public var EcsAny: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 5
public var EcsThis: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 6
public var EcsVariable: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 7

// Relationship traits
public var EcsTransitive: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 8
public var EcsReflexive: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 9
public var EcsFinal: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 10
public var EcsInheritable: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 11
public var EcsOnInstantiate: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 12
public var EcsOverride: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 13
public var EcsInherit: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 14
public var EcsDontInherit: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 15
public var EcsSymmetric: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 16
public var EcsExclusive: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 17
public var EcsAcyclic: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 18
public var EcsTraversable: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 19
public var EcsWith: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 20
public var EcsOneOf: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 21
public var EcsCanToggle: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 22
public var EcsTrait: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 23
public var EcsRelationship: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 24
public var EcsTarget: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 25
public var EcsPairIsTagEntity: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 26

// Identifiers
public var EcsName: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 27
public var EcsSymbol: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 28
public var EcsAlias: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 29

// Relationships
public var EcsChildOf: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 30
public var EcsIsA: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 31
public var EcsDependsOn: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 32
public var EcsSlotOf: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 33
public var EcsOrderedChildren: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 34

// Tags
public var EcsModule: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 35
public var EcsPrefab: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 36
public var EcsDisabled: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 37
public var EcsNotQueryable: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 38

// Events
public var EcsOnAdd: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 39
public var EcsOnRemove: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 40
public var EcsOnSet: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 41
public var EcsMonitor: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 42
public var EcsOnTableCreate: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 43
public var EcsOnTableDelete: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 44

// Cleanup policies
public var EcsOnDelete: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 45
public var EcsOnDeleteTarget: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 46
public var EcsRemove: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 47
public var EcsDelete: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 48
public var EcsPanic: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 49

// Storage modifiers
public var EcsSingleton: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 50
public var EcsSparse: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 51
public var EcsDontFragment: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 52

// Query predicates
public var EcsPredEq: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 53
public var EcsPredMatch: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 54
public var EcsPredLookup: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 55
public var EcsScopeOpen: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 56
public var EcsScopeClose: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 57
public var EcsEmpty: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 58

// System-related
public var EcsQuery: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 59
public var EcsObserver: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 60
public var EcsSystem: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 61
public var EcsParentDepth: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 62

// Pipeline phases
public var EcsOnStart: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 70
public var EcsPreFrame: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 71
public var EcsOnLoad: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 72
public var EcsPostLoad: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 73
public var EcsPreUpdate: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 74
public var EcsOnUpdate: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 75
public var EcsOnValidate: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 76
public var EcsPostUpdate: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 77
public var EcsPreStore: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 78
public var EcsOnStore: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 79
public var EcsPostFrame: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 80
public var EcsPhase: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 81
