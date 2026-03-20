// Id.swift - 1:1 translation of flecs id.c
// Id utilities: matching, validation, pair operations, string conversion

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif


public func ecs_id_match(
    _ id: ecs_id_t,
    _ pattern: ecs_id_t) -> Bool
{
    if id == pattern {
        return true
    }

    if ECS_HAS_ID_FLAG(pattern, ECS_PAIR) {
        if !ECS_HAS_ID_FLAG(id, ECS_PAIR) {
            return false
        }

        let id_first = ECS_PAIR_FIRST(id)
        let id_second = ECS_PAIR_SECOND(id)
        let pattern_first = ECS_PAIR_FIRST(pattern)
        let pattern_second = ECS_PAIR_SECOND(pattern)

        if id_first == 0 || id_second == 0 { return false }
        if pattern_first == 0 || pattern_second == 0 { return false }

        var pattern_first_wildcard = pattern_first == EcsWildcard
        var pattern_second_wc = pattern_second == EcsWildcard

        if ECS_IS_VALUE_PAIR(pattern) {
            if !ECS_IS_VALUE_PAIR(id) {
                return false
            }
            pattern_first_wildcard = false
            pattern_second_wc = false
        }

        if pattern_first_wildcard {
            if pattern_second_wc || pattern_second == id_second {
                return true
            }
        } else if pattern_first == EcsFlag {
            if ECS_HAS_ID_FLAG(id, ECS_PAIR) && !ECS_IS_PAIR(id) {
                if ECS_PAIR_FIRST(id) == pattern_second {
                    return true
                }
                if ECS_PAIR_SECOND(id) == pattern_second {
                    return true
                }
            }
        } else if pattern_second == EcsWildcard {
            if pattern_first == id_first {
                return true
            }
        }
    } else {
        if (id & ECS_ID_FLAGS_MASK) != (pattern & ECS_ID_FLAGS_MASK) {
            return false
        }
        if (ECS_COMPONENT_MASK & pattern) == EcsWildcard {
            return true
        }
    }

    return false
}


public func ecs_id_is_pair(
    _ id: ecs_id_t) -> Bool
{
    return ECS_HAS_ID_FLAG(id, ECS_PAIR)
}

public func ecs_id_is_wildcard(
    _ id: ecs_id_t) -> Bool
{
    if id == EcsWildcard || id == EcsAny {
        return true
    }

    let is_pair = ECS_IS_PAIR(id)
    if !is_pair {
        return false
    }

    let first = ECS_PAIR_FIRST(id)
    if ECS_IS_VALUE_PAIR(id) {
        return first == EcsWildcard || first == EcsAny
    }

    let second = ECS_PAIR_SECOND(id)
    return first == EcsWildcard || second == EcsWildcard ||
           first == EcsAny || second == EcsAny
}

public func ecs_id_is_any(
    _ id: ecs_id_t) -> Bool
{
    if id == EcsAny {
        return true
    }

    if !ECS_IS_PAIR(id) {
        return false
    }

    let first = ECS_PAIR_FIRST(id)
    let second = ECS_PAIR_SECOND(id)
    return first == EcsAny || second == EcsAny
}


public func flecs_id_invalid_reason(
    _ world: UnsafePointer<ecs_world_t>,
    _ id: ecs_id_t) -> UnsafePointer<CChar>?
{
    if id == 0 {
        return _str_component_zero
    }
    if ecs_id_is_wildcard(id) {
        return _str_cannot_add_wildcards
    }

    if ECS_HAS_ID_FLAG(id, ECS_PAIR) {
        if ECS_PAIR_FIRST(id) == 0 && ECS_PAIR_SECOND(id) == 0 {
            return _str_both_zero
        }
        if ECS_PAIR_FIRST(id) == 0 {
            return _str_first_zero
        }
        if ECS_PAIR_SECOND(id) == 0 {
            return _str_second_zero
        }
    } else if ECS_HAS_ID_FLAG(id, ECS_VALUE_PAIR) {
        if ECS_PAIR_FIRST(id) == 0 {
            return _str_value_first_zero
        }
    }

    return nil
}

// Static error strings
private let _str_component_zero = UnsafePointer<CChar>(
    ("components cannot be 0 (is the component registered?)" as StaticString).utf8Start
        .assumingMemoryBound(to: CChar.self))
private let _str_cannot_add_wildcards = UnsafePointer<CChar>(
    ("cannot add wildcards" as StaticString).utf8Start
        .assumingMemoryBound(to: CChar.self))
private let _str_both_zero = UnsafePointer<CChar>(
    ("invalid pair: both elements are 0" as StaticString).utf8Start
        .assumingMemoryBound(to: CChar.self))
private let _str_first_zero = UnsafePointer<CChar>(
    ("invalid pair: first element is 0" as StaticString).utf8Start
        .assumingMemoryBound(to: CChar.self))
private let _str_second_zero = UnsafePointer<CChar>(
    ("invalid pair: second element is 0" as StaticString).utf8Start
        .assumingMemoryBound(to: CChar.self))
private let _str_value_first_zero = UnsafePointer<CChar>(
    ("invalid value pair: first element is 0" as StaticString).utf8Start
        .assumingMemoryBound(to: CChar.self))

public func ecs_id_is_valid(
    _ world: UnsafePointer<ecs_world_t>,
    _ id: ecs_id_t) -> Bool
{
    return flecs_id_invalid_reason(world, id) == nil
}


public func ecs_make_pair(
    _ relationship: ecs_entity_t,
    _ target: ecs_entity_t) -> ecs_id_t
{
    return ecs_pair(relationship, target)
}


public func ecs_id_flag_str(
    _ entity: UInt64) -> UnsafePointer<CChar>
{
    if ECS_IS_VALUE_PAIR(entity) {
        return _flag_value_pair
    } else if ECS_HAS_ID_FLAG(entity, ECS_PAIR) {
        return _flag_pair
    } else if ECS_HAS_ID_FLAG(entity, ECS_TOGGLE) {
        return _flag_toggle
    } else if ECS_HAS_ID_FLAG(entity, ECS_AUTO_OVERRIDE) {
        return _flag_auto_override
    } else {
        return _flag_unknown
    }
}

private let _flag_value_pair = UnsafePointer<CChar>(
    ("VALUE_PAIR" as StaticString).utf8Start.assumingMemoryBound(to: CChar.self))
private let _flag_pair = UnsafePointer<CChar>(
    ("PAIR" as StaticString).utf8Start.assumingMemoryBound(to: CChar.self))
private let _flag_toggle = UnsafePointer<CChar>(
    ("TOGGLE" as StaticString).utf8Start.assumingMemoryBound(to: CChar.self))
private let _flag_auto_override = UnsafePointer<CChar>(
    ("AUTO_OVERRIDE" as StaticString).utf8Start.assumingMemoryBound(to: CChar.self))
private let _flag_unknown = UnsafePointer<CChar>(
    ("UNKNOWN" as StaticString).utf8Start.assumingMemoryBound(to: CChar.self))
