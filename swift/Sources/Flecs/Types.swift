// Types.swift - 1:1 translation of flecs core types
// All fundamental types, constants, enums, and flags

import Foundation

// MARK: - Version

public let FLECS_VERSION_MAJOR: Int32 = 4
public let FLECS_VERSION_MINOR: Int32 = 1
public let FLECS_VERSION_PATCH: Int32 = 5

// MARK: - Configuration Constants

public let FLECS_HI_COMPONENT_ID: Int32 = 256
public let FLECS_HI_ID_RECORD_ID: Int32 = 1024
public let FLECS_SPARSE_PAGE_BITS: Int32 = 6
public let FLECS_ENTITY_PAGE_BITS: Int32 = 10
public let FLECS_ID_DESC_MAX: Int32 = 32
public let FLECS_EVENT_DESC_MAX: Int32 = 8
public let FLECS_VARIABLE_COUNT_MAX: Int32 = 64
public let FLECS_TERM_COUNT_MAX: Int32 = 32
public let FLECS_TERM_ARG_COUNT_MAX: Int32 = 16
public let FLECS_QUERY_VARIABLE_COUNT_MAX: Int32 = 64
public let FLECS_QUERY_SCOPE_NESTING_MAX: Int32 = 8
public let FLECS_DAG_DEPTH_MAX: Int32 = 128
public let FLECS_TREE_SPAWNER_DEPTH_CACHE_SIZE: Int32 = 6
public let EcsFirstUserComponentId: ecs_entity_t = 8
public let EcsFirstUserEntityId: ecs_entity_t = UInt64(FLECS_HI_COMPONENT_ID) + 128
public let ECS_MAX_RECURSION: Int32 = 512
public let ECS_MAX_TOKEN_SIZE: Int32 = 256

// MARK: - Fundamental Type Aliases

public typealias ecs_id_t = UInt64
public typealias ecs_entity_t = UInt64
// ecs_size_t is defined in Allocator.swift
public typealias ecs_flags8_t = UInt8
public typealias ecs_flags16_t = UInt16
public typealias ecs_flags32_t = UInt32
public typealias ecs_flags64_t = UInt64
public typealias ecs_termset_t = UInt32
public typealias ecs_float_t = Float
public typealias ecs_ftime_t = Float
public typealias ecs_map_data_t = UInt64
public typealias ecs_map_key_t = UInt64
public typealias ecs_map_val_t = UInt64

// MARK: - Magic Numbers

public let ecs_world_t_magic: Int32 = 0x65637377
public let ecs_stage_t_magic: Int32 = 0x65637373
public let ecs_query_t_magic: Int32 = 0x65637375
public let ecs_observer_t_magic: Int32 = 0x65637362

// MARK: - Entity ID Masks and Helpers

public let ECS_ROW_MASK: UInt32 = 0x0FFFFFFF
public let ECS_ROW_FLAGS_MASK: UInt32 = ~UInt32(0x0FFFFFFF)
public let ECS_ID_FLAGS_MASK: UInt64 = 0xFF << 60
public let ECS_ENTITY_MASK: UInt64 = 0xFFFFFFFF
public let ECS_GENERATION_MASK: UInt64 = 0xFFFF << 32
public let ECS_COMPONENT_MASK: UInt64 = ~(UInt64(0xFF) << 60)

// ID flags
public let ECS_PAIR: UInt64 = 1 << 63
public let ECS_AUTO_OVERRIDE: UInt64 = 1 << 62
public let ECS_TOGGLE: UInt64 = 1 << 61
public let ECS_VALUE_PAIR: UInt64 = 1 << 60

public let ECS_MAX_COMPONENT_ID: UInt32 = ~UInt32(ECS_ID_FLAGS_MASK >> 32)

@inline(__always)
public func ECS_GENERATION(_ e: UInt64) -> UInt64 {
    return (e & ECS_GENERATION_MASK) >> 32
}

@inline(__always)
public func ECS_GENERATION_INC(_ e: UInt64) -> UInt64 {
    return (e & ~ECS_GENERATION_MASK) | ((0xFFFF & (ECS_GENERATION(e) + 1)) << 32)
}

@inline(__always)
public func ECS_RECORD_TO_ROW(_ v: UInt32) -> Int32 {
    return Int32(v & ECS_ROW_MASK)
}

@inline(__always)
public func ECS_RECORD_TO_ROW_FLAGS(_ v: UInt32) -> UInt32 {
    return v & ECS_ROW_FLAGS_MASK
}

@inline(__always)
public func ECS_ROW_TO_RECORD(_ row: Int32, _ flags: UInt32) -> UInt32 {
    return UInt32(bitPattern: row) | flags
}

@inline(__always)
public func ECS_HAS_ID_FLAG(_ e: UInt64, _ flag: UInt64) -> Bool {
    return (e & flag) != 0
}

@inline(__always)
public func ECS_IS_PAIR(_ id: UInt64) -> Bool {
    return ((id & ECS_ID_FLAGS_MASK) == ECS_PAIR) || ECS_IS_VALUE_PAIR(id)
}

@inline(__always)
public func ECS_IS_VALUE_PAIR(_ id: UInt64) -> Bool {
    return (id & ECS_ID_FLAGS_MASK) == ECS_VALUE_PAIR
}

@inline(__always)
public func ECS_PAIR_FIRST(_ e: UInt64) -> UInt64 {
    return UInt64(ecs_entity_t_hi(e & ECS_COMPONENT_MASK))
}

@inline(__always)
public func ECS_PAIR_SECOND(_ e: UInt64) -> UInt64 {
    return UInt64(ecs_entity_t_lo(e))
}

@inline(__always)
public func ecs_entity_t_lo(_ value: UInt64) -> UInt32 {
    return UInt32(truncatingIfNeeded: value)
}

@inline(__always)
public func ecs_entity_t_hi(_ value: UInt64) -> UInt32 {
    return UInt32(truncatingIfNeeded: value >> 32)
}

@inline(__always)
public func ecs_entity_t_comb(_ lo: UInt32, _ hi: UInt32) -> UInt64 {
    return (UInt64(hi) << 32) + UInt64(lo)
}

@inline(__always)
public func ecs_pair(_ rel: ecs_entity_t, _ tgt: ecs_entity_t) -> ecs_id_t {
    return ECS_PAIR | ecs_entity_t_comb(ecs_entity_t_lo(tgt), ecs_entity_t_lo(rel))
}

@inline(__always)
public func ecs_value_pair(_ rel: ecs_entity_t, _ val: ecs_entity_t) -> ecs_id_t {
    return ECS_VALUE_PAIR | ecs_entity_t_comb(ecs_entity_t_lo(val), ecs_entity_t_lo(rel))
}

// MARK: - Term Reference Flags

public let EcsSelf: UInt64 = 1 << 63
public let EcsUp: UInt64 = 1 << 62
public let EcsTrav: UInt64 = 1 << 61
public let EcsCascade: UInt64 = 1 << 60
public let EcsDesc: UInt64 = 1 << 59
public let EcsIsVariable: UInt64 = 1 << 58
public let EcsIsEntity: UInt64 = 1 << 57
public let EcsIsName: UInt64 = 1 << 56
public let EcsTraverseFlags: UInt64 = EcsSelf | EcsUp | EcsTrav | EcsCascade | EcsDesc
public let EcsTermRefFlags: UInt64 = EcsTraverseFlags | EcsIsVariable | EcsIsEntity | EcsIsName

// MARK: - World Flags

public let EcsWorldQuitWorkers: UInt32 = 1 << 0
public let EcsWorldReadonly: UInt32 = 1 << 1
public let EcsWorldInit: UInt32 = 1 << 2
public let EcsWorldQuit: UInt32 = 1 << 3
public let EcsWorldFini: UInt32 = 1 << 4
public let EcsWorldMeasureFrameTime: UInt32 = 1 << 5
public let EcsWorldMeasureSystemTime: UInt32 = 1 << 6
public let EcsWorldMultiThreaded: UInt32 = 1 << 7
public let EcsWorldFrameInProgress: UInt32 = 1 << 8

// MARK: - Entity Flags (upper bits of ecs_record_t::row)

public let EcsEntityIsId: UInt32 = 1 << 31
public let EcsEntityIsTarget: UInt32 = 1 << 30
public let EcsEntityIsTraversable: UInt32 = 1 << 29
public let EcsEntityHasDontFragment: UInt32 = 1 << 28

// MARK: - ID Flags (ecs_component_record_t::flags)

public let EcsIdOnDeleteRemove: UInt32 = 1 << 0
public let EcsIdOnDeleteDelete: UInt32 = 1 << 1
public let EcsIdOnDeletePanic: UInt32 = 1 << 2
public let EcsIdOnDeleteMask: UInt32 = 0x7 // bits 0-2
public let EcsIdOnDeleteTargetRemove: UInt32 = 1 << 3
public let EcsIdOnDeleteTargetDelete: UInt32 = 1 << 4
public let EcsIdOnDeleteTargetPanic: UInt32 = 1 << 5
public let EcsIdOnDeleteTargetMask: UInt32 = 0x38 // bits 3-5
public let EcsIdOnInstantiateOverride: UInt32 = 1 << 6
public let EcsIdOnInstantiateInherit: UInt32 = 1 << 7
public let EcsIdOnInstantiateDontInherit: UInt32 = 1 << 8
public let EcsIdOnInstantiateMask: UInt32 = 0x1C0 // bits 6-8
public let EcsIdExclusive: UInt32 = 1 << 9
public let EcsIdTraversable: UInt32 = 1 << 10
public let EcsIdPairIsTag: UInt32 = 1 << 11
public let EcsIdWith: UInt32 = 1 << 12
public let EcsIdCanToggle: UInt32 = 1 << 13
public let EcsIdIsTransitive: UInt32 = 1 << 14
public let EcsIdInheritable: UInt32 = 1 << 15
public let EcsIdHasOnAdd: UInt32 = 1 << 16
public let EcsIdHasOnRemove: UInt32 = 1 << 17
public let EcsIdHasOnSet: UInt32 = 1 << 18
public let EcsIdHasOnTableCreate: UInt32 = 1 << 19
public let EcsIdHasOnTableDelete: UInt32 = 1 << 20
public let EcsIdSparse: UInt32 = 1 << 21
public let EcsIdDontFragment: UInt32 = 1 << 22
public let EcsIdMatchDontFragment: UInt32 = 1 << 23
public let EcsIdOrderedChildren: UInt32 = 1 << 24
public let EcsIdSingleton: UInt32 = 1 << 25
public let EcsIdPrefabChildren: UInt32 = 1 << 26
public let EcsIdMarkedForDelete: UInt32 = 1 << 30
public let EcsIdEventMask: UInt32 = (1 << 16) | (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 21) | (1 << 24)

// MARK: - Non-Trivial Flags

public let EcsNonTrivialIdSparse: UInt8 = 1 << 0
public let EcsNonTrivialIdNonFragmenting: UInt8 = 1 << 1
public let EcsNonTrivialIdInherit: UInt8 = 1 << 2

// MARK: - Iterator Flags

public let EcsIterIsValid: UInt32 = 1 << 0
public let EcsIterNoData: UInt32 = 1 << 1
public let EcsIterNoResults: UInt32 = 1 << 2
public let EcsIterMatchEmptyTables: UInt32 = 1 << 3
public let EcsIterIgnoreThis: UInt32 = 1 << 4
public let EcsIterTrivialChangeDetection: UInt32 = 1 << 5
public let EcsIterHasCondSet: UInt32 = 1 << 6
public let EcsIterProfile: UInt32 = 1 << 7
public let EcsIterTrivialSearch: UInt32 = 1 << 8
public let EcsIterTrivialTest: UInt32 = 1 << 11
public let EcsIterTrivialCached: UInt32 = 1 << 14
public let EcsIterCached: UInt32 = 1 << 15
public let EcsIterFixedInChangeComputed: UInt32 = 1 << 16
public let EcsIterFixedInChanged: UInt32 = 1 << 17
public let EcsIterSkip: UInt32 = 1 << 18
public let EcsIterCppEach: UInt32 = 1 << 19
public let EcsIterTableOnly: UInt32 = 1 << 20
public let EcsIterImmutableCacheData: UInt32 = 1 << 21

// MARK: - Event Flags

public let EcsEventTableOnly: UInt32 = 1 << 20
public let EcsEventNoOnSet: UInt32 = 1 << 16

// MARK: - Query Flags (internal, set by query implementation)

public let EcsQueryMatchThis: UInt32 = 1 << 11
public let EcsQueryMatchOnlyThis: UInt32 = 1 << 12
public let EcsQueryMatchOnlySelf: UInt32 = 1 << 13
public let EcsQueryMatchWildcards: UInt32 = 1 << 14
public let EcsQueryMatchNothing: UInt32 = 1 << 15
public let EcsQueryHasCondSet: UInt32 = 1 << 16
public let EcsQueryHasPred: UInt32 = 1 << 17
public let EcsQueryHasScopes: UInt32 = 1 << 18
public let EcsQueryHasRefs: UInt32 = 1 << 19
public let EcsQueryHasOutTerms: UInt32 = 1 << 20
public let EcsQueryHasNonThisOutTerms: UInt32 = 1 << 21
public let EcsQueryHasChangeDetection: UInt32 = 1 << 22
public let EcsQueryIsTrivial: UInt32 = 1 << 23
public let EcsQueryHasCacheable: UInt32 = 1 << 24
public let EcsQueryIsCacheable: UInt32 = 1 << 25
public let EcsQueryHasTableThisVar: UInt32 = 1 << 26
public let EcsQueryCacheYieldEmptyTables: UInt32 = 1 << 27
public let EcsQueryTrivialCache: UInt32 = 1 << 28
public let EcsQueryNested: UInt32 = 1 << 29
public let EcsQueryCacheWithFilter: UInt32 = 1 << 30
public let EcsQueryValid: UInt32 = 1 << 31

// MARK: - Query Descriptor Flags

public let EcsQueryMatchPrefab: UInt32 = 1 << 1
public let EcsQueryMatchDisabled: UInt32 = 1 << 2
public let EcsQueryMatchEmptyTablesFlag: UInt32 = 1 << 3
public let EcsQueryAllowUnresolvedByName: UInt32 = 1 << 6
public let EcsQueryTableOnlyFlag: UInt32 = 1 << 7
public let EcsQueryDetectChanges: UInt32 = 1 << 8

// MARK: - Term Flags

public let EcsTermMatchAny: UInt16 = 1 << 0
public let EcsTermMatchAnySrc: UInt16 = 1 << 1
public let EcsTermTransitive: UInt16 = 1 << 2
public let EcsTermReflexive: UInt16 = 1 << 3
public let EcsTermIdInherited: UInt16 = 1 << 4
public let EcsTermIsTrivial: UInt16 = 1 << 5
public let EcsTermIsCacheable: UInt16 = 1 << 6
public let EcsTermIsScope: UInt16 = 1 << 7
public let EcsTermIsMember: UInt16 = 1 << 8
public let EcsTermIsToggle: UInt16 = 1 << 9
public let EcsTermIsSparse: UInt16 = 1 << 10
public let EcsTermIsOr: UInt16 = 1 << 11
public let EcsTermDontFragment: UInt16 = 1 << 12
public let EcsTermNonFragmentingChildOf: UInt16 = 1 << 13

// MARK: - Observer Flags

public let EcsObserverMatchPrefab: UInt32 = 1 << 1
public let EcsObserverMatchDisabled: UInt32 = 1 << 2
public let EcsObserverIsMulti: UInt32 = 1 << 3
public let EcsObserverIsMonitor: UInt32 = 1 << 4
public let EcsObserverIsDisabled: UInt32 = 1 << 5
public let EcsObserverIsParentDisabled: UInt32 = 1 << 6
public let EcsObserverBypassQuery: UInt32 = 1 << 7
public let EcsObserverYieldOnCreate: UInt32 = 1 << 8
public let EcsObserverYieldOnDelete: UInt32 = 1 << 9
public let EcsObserverKeepAlive: UInt32 = 1 << 11

// MARK: - Table Flags

public let EcsTableHasBuiltins: UInt32 = 1 << 0
public let EcsTableIsPrefab: UInt32 = 1 << 1
public let EcsTableHasIsA: UInt32 = 1 << 2
public let EcsTableHasMultiIsA: UInt32 = 1 << 3
public let EcsTableHasChildOf: UInt32 = 1 << 4
public let EcsTableHasParent: UInt32 = 1 << 5
public let EcsTableHasName: UInt32 = 1 << 6
public let EcsTableHasPairs: UInt32 = 1 << 7
public let EcsTableHasModule: UInt32 = 1 << 8
public let EcsTableIsDisabled: UInt32 = 1 << 9
public let EcsTableNotQueryable: UInt32 = 1 << 10
public let EcsTableHasCtors: UInt32 = 1 << 11
public let EcsTableHasDtors: UInt32 = 1 << 12
public let EcsTableHasCopy: UInt32 = 1 << 13
public let EcsTableHasMove: UInt32 = 1 << 14
public let EcsTableHasToggle: UInt32 = 1 << 15
public let EcsTableHasOnAdd: UInt32 = 1 << 16
public let EcsTableHasOnRemove: UInt32 = 1 << 17
public let EcsTableHasOnSet: UInt32 = 1 << 18
public let EcsTableHasOnTableCreate: UInt32 = 1 << 19
public let EcsTableHasOnTableDelete: UInt32 = 1 << 20
public let EcsTableHasSparse: UInt32 = 1 << 21
public let EcsTableHasDontFragment: UInt32 = 1 << 22
public let EcsTableOverrideDontFragment: UInt32 = 1 << 23
public let EcsTableHasOrderedChildren: UInt32 = 1 << 24
public let EcsTableHasOverrides: UInt32 = 1 << 25
public let EcsTableHasTraversable: UInt32 = 1 << 27
public let EcsTableEdgeReparent: UInt32 = 1 << 28
public let EcsTableMarkedForDelete: UInt32 = 1 << 29

// Composite table flags
public let EcsTableHasLifecycle: UInt32 = (1 << 11) | (1 << 12)
public let EcsTableIsComplex: UInt32 = (1 << 11) | (1 << 12) | (1 << 15) | (1 << 21)
public let EcsTableHasAddActions: UInt32 = (1 << 2) | (1 << 11) | (1 << 16) | (1 << 18)
public let EcsTableHasRemoveActions: UInt32 = (1 << 2) | (1 << 12) | (1 << 17)
public let EcsTableEdgeFlags: UInt32 = (1 << 16) | (1 << 17) | (1 << 21)
public let EcsTableAddEdgeFlags: UInt32 = (1 << 16) | (1 << 21)
public let EcsTableRemoveEdgeFlags: UInt32 = (1 << 17) | (1 << 21) | (1 << 24)

// MARK: - Aperiodic Action Flags

public let EcsAperiodicComponentMonitors: UInt32 = 1 << 2
public let EcsAperiodicEmptyQueries: UInt32 = 1 << 4

// MARK: - Type Hook Flags

public let ECS_TYPE_HOOK_CTOR: ecs_flags32_t = 1 << 0
public let ECS_TYPE_HOOK_DTOR: ecs_flags32_t = 1 << 1
public let ECS_TYPE_HOOK_COPY: ecs_flags32_t = 1 << 2
public let ECS_TYPE_HOOK_MOVE: ecs_flags32_t = 1 << 3
public let ECS_TYPE_HOOK_COPY_CTOR: ecs_flags32_t = 1 << 4
public let ECS_TYPE_HOOK_MOVE_CTOR: ecs_flags32_t = 1 << 5
public let ECS_TYPE_HOOK_CTOR_MOVE_DTOR: ecs_flags32_t = 1 << 6
public let ECS_TYPE_HOOK_MOVE_DTOR: ecs_flags32_t = 1 << 7
public let ECS_TYPE_HOOK_CMP: ecs_flags32_t = 1 << 8
public let ECS_TYPE_HOOK_EQUALS: ecs_flags32_t = 1 << 9

public let ECS_TYPE_HOOK_CTOR_ILLEGAL: ecs_flags32_t = 1 << 10
public let ECS_TYPE_HOOK_DTOR_ILLEGAL: ecs_flags32_t = 1 << 12
public let ECS_TYPE_HOOK_COPY_ILLEGAL: ecs_flags32_t = 1 << 13
public let ECS_TYPE_HOOK_MOVE_ILLEGAL: ecs_flags32_t = 1 << 14
public let ECS_TYPE_HOOK_COPY_CTOR_ILLEGAL: ecs_flags32_t = 1 << 15
public let ECS_TYPE_HOOK_MOVE_CTOR_ILLEGAL: ecs_flags32_t = 1 << 16
public let ECS_TYPE_HOOK_CTOR_MOVE_DTOR_ILLEGAL: ecs_flags32_t = 1 << 17
public let ECS_TYPE_HOOK_MOVE_DTOR_ILLEGAL: ecs_flags32_t = 1 << 18
public let ECS_TYPE_HOOK_CMP_ILLEGAL: ecs_flags32_t = 1 << 19
public let ECS_TYPE_HOOK_EQUALS_ILLEGAL: ecs_flags32_t = 1 << 20
public let ECS_TYPE_HOOK_IN_USE: ecs_flags32_t = 1 << 21

// MARK: - Enums

public enum EcsInoutKind: Int16 {
    case inOutDefault = 0
    case inOutNone = 1
    case inOutFilter = 2
    case inOut = 3
    case `in` = 4
    case out = 5
}

public enum EcsOperKind: Int16 {
    case and = 0
    case or = 1
    case not = 2
    case optional = 3
    case andFrom = 4
    case orFrom = 5
    case notFrom = 6
}

public enum EcsQueryCacheKind: Int32 {
    case `default` = 0
    case auto = 1
    case all = 2
    case none = 3
}

// MARK: - Utility Functions

@inline(__always)
public func ECS_ALIGN(_ size: Int32, _ alignment: Int32) -> ecs_size_t {
    return ecs_size_t((((Int(size) - 1) / Int(alignment)) + 1) * Int(alignment))
}

@inline(__always)
public func ECS_OFFSET(_ ptr: UnsafeMutableRawPointer?, _ offset: Int) -> UnsafeMutableRawPointer? {
    guard let ptr = ptr else { return nil }
    return ptr.advanced(by: offset)
}

@inline(__always)
public func ECS_ELEM(_ ptr: UnsafeMutableRawPointer?, _ size: Int32, _ index: Int32) -> UnsafeMutableRawPointer? {
    return ECS_OFFSET(ptr, Int(size) * Int(index))
}

@inline(__always)
public func ECS_BIT_SET(_ flags: inout UInt32, _ bit: UInt32) {
    flags |= bit
}

@inline(__always)
public func ECS_BIT_CLEAR(_ flags: inout UInt32, _ bit: UInt32) {
    flags &= ~bit
}

@inline(__always)
public func ECS_BIT_IS_SET(_ flags: UInt32, _ bit: UInt32) -> Bool {
    return (flags & bit) != 0
}

// MARK: - ECS_TERM_REF helpers

@inline(__always)
public func ECS_TERM_REF_FLAGS(_ ref: ecs_term_ref_t) -> UInt64 {
    return ref.id & EcsTermRefFlags
}

@inline(__always)
public func ECS_TERM_REF_ID(_ ref: ecs_term_ref_t) -> UInt64 {
    return ref.id & ~EcsTermRefFlags
}
