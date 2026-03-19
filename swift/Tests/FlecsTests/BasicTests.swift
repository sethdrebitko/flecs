import XCTest
@testable import Flecs

final class BasicTests: XCTestCase {
    func testVersionConstants() {
        XCTAssertEqual(FLECS_VERSION_MAJOR, 4)
        XCTAssertEqual(FLECS_VERSION_MINOR, 1)
        XCTAssertEqual(FLECS_VERSION_PATCH, 5)
    }

    func testEntityIdHelpers() {
        let lo = ecs_entity_t_lo(0x00000002_00000001)
        XCTAssertEqual(lo, 1)

        let hi = ecs_entity_t_hi(0x00000002_00000001)
        XCTAssertEqual(hi, 2)

        let combined = ecs_entity_t_comb(1, 2)
        XCTAssertEqual(combined, 0x00000002_00000001)

        let pair = ecs_pair(10, 20)
        XCTAssertTrue(ECS_IS_PAIR(pair))
        XCTAssertEqual(ECS_PAIR_FIRST(pair), 10)
        XCTAssertEqual(ECS_PAIR_SECOND(pair), 20)
    }

    func testOsApi() {
        ecs_os_set_api_defaults()
        let ptr = ecs_os_malloc(64)
        XCTAssertNotNil(ptr)
        ecs_os_free(ptr)
    }

    func testVec() {
        var vec = ecs_vec_t()
        let elemSize = ecs_size_t(MemoryLayout<Int32>.stride)
        ecs_vec_init(nil, &vec, elemSize, 4)

        XCTAssertEqual(ecs_vec_count(&vec), 0)

        // Append elements
        for i: Int32 in 0..<10 {
            let ptr = ecs_vec_append(nil, &vec, elemSize)!
                .assumingMemoryBound(to: Int32.self)
            ptr.pointee = i
        }

        XCTAssertEqual(ecs_vec_count(&vec), 10)

        // Check values
        let first = ecs_vec_get(&vec, elemSize, 0)!
            .assumingMemoryBound(to: Int32.self)
        XCTAssertEqual(first.pointee, 0)

        let fifth = ecs_vec_get(&vec, elemSize, 4)!
            .assumingMemoryBound(to: Int32.self)
        XCTAssertEqual(fifth.pointee, 4)

        ecs_vec_fini(nil, &vec, elemSize)
    }

    func testMap() {
        var map = ecs_map_t()
        ecs_map_init(&map, nil)

        ecs_map_insert(&map, 42, 100)
        ecs_map_insert(&map, 43, 200)

        let val = ecs_map_get(&map, 42)
        XCTAssertNotNil(val)
        XCTAssertEqual(val?.pointee, 100)

        let val2 = ecs_map_get(&map, 43)
        XCTAssertEqual(val2?.pointee, 200)

        let missing = ecs_map_get(&map, 999)
        XCTAssertNil(missing)

        XCTAssertEqual(ecs_map_count(&map), 2)

        ecs_map_fini(&map)
    }

    func testEntityIndex() {
        var index = ecs_entity_index_t()
        flecs_entity_index_init(nil, &index)

        // Create some entities
        let e1 = flecs_entity_index_new_id(&index)
        let e2 = flecs_entity_index_new_id(&index)
        let e3 = flecs_entity_index_new_id(&index)

        XCTAssertTrue(e1 > 0)
        XCTAssertTrue(e2 > 0)
        XCTAssertTrue(e3 > 0)
        XCTAssertNotEqual(e1, e2)
        XCTAssertNotEqual(e2, e3)

        XCTAssertTrue(flecs_entity_index_is_alive(&index, e1))
        XCTAssertTrue(flecs_entity_index_is_alive(&index, e2))

        XCTAssertEqual(flecs_entity_index_count(&index), 3)

        // Remove an entity
        flecs_entity_index_remove(&index, e2)
        XCTAssertFalse(flecs_entity_index_is_alive(&index, e2))
        XCTAssertEqual(flecs_entity_index_count(&index), 2)

        flecs_entity_index_fini(&index)
    }

    func testBuiltinEntityIds() {
        XCTAssertTrue(EcsChildOf > 0)
        XCTAssertTrue(EcsIsA > 0)
        XCTAssertTrue(EcsWildcard > 0)
        XCTAssertTrue(EcsOnAdd > 0)
    }
}
