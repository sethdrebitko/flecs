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

        for i: Int32 in 0..<10 {
            let ptr = ecs_vec_append(nil, &vec, elemSize)!
                .assumingMemoryBound(to: Int32.self)
            ptr.pointee = i
        }

        XCTAssertEqual(ecs_vec_count(&vec), 10)

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

    func testHash() {
        let str1 = "hello"
        let hash1 = str1.withCString { ptr in
            flecs_hash(UnsafeRawPointer(ptr), ecs_size_t(str1.count))
        }
        XCTAssertNotEqual(hash1, 0)

        // Same string should produce same hash
        let hash2 = str1.withCString { ptr in
            flecs_hash(UnsafeRawPointer(ptr), ecs_size_t(str1.count))
        }
        XCTAssertEqual(hash1, hash2)

        // Different string should produce different hash
        let str2 = "world"
        let hash3 = str2.withCString { ptr in
            flecs_hash(UnsafeRawPointer(ptr), ecs_size_t(str2.count))
        }
        XCTAssertNotEqual(hash1, hash3)
    }

    func testNextPowOf2() {
        XCTAssertEqual(flecs_next_pow_of_2(1), 1)
        XCTAssertEqual(flecs_next_pow_of_2(3), 4)
        XCTAssertEqual(flecs_next_pow_of_2(5), 8)
        XCTAssertEqual(flecs_next_pow_of_2(16), 16)
        XCTAssertEqual(flecs_next_pow_of_2(17), 32)
    }

    func testIdHelpers() {
        let simple_id: ecs_id_t = 42
        XCTAssertFalse(ecs_id_is_pair(simple_id))
        XCTAssertFalse(ecs_id_is_wildcard(simple_id))

        let pair_id = ecs_pair(10, 20)
        XCTAssertTrue(ecs_id_is_pair(pair_id))
        XCTAssertFalse(ecs_id_is_wildcard(pair_id))

        let wildcard_pair = ecs_pair(EcsWildcard, 20)
        XCTAssertTrue(ecs_id_is_wildcard(wildcard_pair))
    }

    func testWorldCreateDestroy() {
        let world = ecs_init()
        XCTAssertEqual(world.pointee.hdr.type, ecs_world_t_magic)
        XCTAssertFalse(ecs_is_fini(UnsafePointer(world)))
        ecs_fini(world)
    }

    func testWorldScope() {
        let world = ecs_init()

        let oldScope = ecs_get_scope(UnsafeRawPointer(world))
        XCTAssertEqual(oldScope, 0)

        let prev = ecs_set_scope(UnsafeMutableRawPointer(world), 42)
        XCTAssertEqual(prev, 0)

        let newScope = ecs_get_scope(UnsafeRawPointer(world))
        XCTAssertEqual(newScope, 42)

        ecs_fini(world)
    }

    func testWorldFrameBeginEnd() {
        let world = ecs_init()

        let dt = ecs_frame_begin(world, 1.0 / 60.0)
        XCTAssertTrue(dt > 0)
        XCTAssertTrue((world.pointee.flags & EcsWorldFrameInProgress) != 0)

        ecs_frame_end(world)
        XCTAssertTrue((world.pointee.flags & EcsWorldFrameInProgress) == 0)

        ecs_fini(world)
    }

    func testStrbuf() {
        var buf = ecs_strbuf_t()
        ecs_strbuf_appendstr(&buf, "Hello")
        ecs_strbuf_appendstr(&buf, ", ")
        ecs_strbuf_appendstr(&buf, "World!")

        let result = ecs_strbuf_get(&buf)
        XCTAssertNotNil(result)
        if let result = result {
            XCTAssertEqual(String(cString: result), "Hello, World!")
            ecs_os_free(UnsafeMutableRawPointer(result))
        }
    }

    func testTableSearch() {
        // Create a simple type array
        var ids: [ecs_id_t] = [10, 20, 30, 40, 50]
        var table = ecs_table_t()
        table.type.count = 5
        ids.withUnsafeMutableBufferPointer { buf in
            table.type.array = buf.baseAddress
        }

        var found_id: ecs_id_t = 0

        // Search for existing id
        let result = ecs_search(nil, &table, 30, &found_id)
        XCTAssertEqual(result, 2)
        XCTAssertEqual(found_id, 30)

        // Search for missing id
        let missing = ecs_search(nil, &table, 99, &found_id)
        XCTAssertEqual(missing, -1)
    }

    func testBlockAllocator() {
        var ba = ecs_block_allocator_t()
        flecs_ballocator_init(&ba, 64)

        let p1 = flecs_balloc(&ba)
        XCTAssertNotNil(p1)

        let p2 = flecs_balloc(&ba)
        XCTAssertNotNil(p2)
        XCTAssertNotEqual(p1, p2)

        flecs_bfree(&ba, p1)
        flecs_bfree(&ba, p2)

        flecs_ballocator_fini(&ba)
    }

    func testObservable() {
        var obs = ecs_observable_t()
        flecs_observable_init(&obs)

        // Check that we can get event records for built-in events
        let er = flecs_event_record_get(&obs, EcsOnAdd)
        XCTAssertNotNil(er)

        flecs_observable_fini(&obs)
    }
}
