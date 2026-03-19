# Flecs Swift Translation - Project Plan

## Goal

Exact 1:1 mechanical translation of the flecs C ECS framework into Swift. Every C
function becomes a Swift function with identical logic, control flow, and memory
layout. No Swiftification, no wrappers, no abstractions beyond what C has.

## Guiding Principles

1. **Exact replication** - Translate every line of C logic faithfully. Do not
   simplify, optimize, or "improve" the code. If the C code has a branch, the
   Swift code has the same branch.
2. **Preserve C naming** - Keep `ecs_*` and `flecs_*` function names as-is.
   Do not rename to Swift conventions.
3. **Preserve C signatures** - Match parameter types, return types, and
   nullability. Use `UnsafeMutablePointer<T>` for `T*`, `UnsafeRawPointer?`
   for `void*`, etc.
4. **No stubs or TODOs** - Every function must contain the complete translated
   logic. Remove existing TODOs by implementing the actual C logic.
5. **No wrappers** - Do not add convenience APIs, computed properties, or
   protocol conformances. The Swift layer is a direct port, not a new API.

## Translation Conventions

### Naming
- C function `ecs_foo_bar()` → Swift function `ecs_foo_bar()`
- C internal `flecs_foo_bar()` → Swift function `flecs_foo_bar()`
- C macro `ECS_FOO(x)` → `@inline(__always) public func ECS_FOO(_ x: ...) -> ...`
- C constant `EcsFoo` → `public let EcsFoo: UInt64 = ...`
- Swift reserved words: use trailing underscore (`init_`, `fini_`, `priv_`)

### Structs
- Redefine all C structs in Swift (do not import from C bridging header)
- All fields explicitly initialized with defaults in `init()`
- C unions → store all variant fields (Swift has no unions)
- Fixed-size C arrays → tuples for small, `UnsafeMutablePointer` for large

### Memory
- `T*` → `UnsafeMutablePointer<T>?`
- `const T*` → `UnsafePointer<T>?`
- `void*` → `UnsafeMutableRawPointer?`
- Use `ecs_os_malloc` / `ecs_os_free` (not `.allocate()` / `.deallocate()`)
- Use `ecs_os_memcpy` (not bare `memcpy`)
- Use `ecs_os_strdup` (not bare `strdup`)
- Match C's alloc/free pairing exactly

### Error Handling
- Return `nil` for allocation failures and missing lookups
- Return `-1` for search/query failures
- Return `false` for validation failures
- No Swift exceptions, no `guard` early-return patterns that differ from C

### File Organization
- One Swift file per C source file (1:1 mapping)
- File named after C source: `entity.c` → `Entity.swift`
- Query subsystem files map to their C counterparts directly
- Addon files map 1:1 to addon C sources

## Current Translation Status

### Core Runtime (src/)

| C Source File | Lines | Swift File | Swift Lines | Status |
|---|---|---|---|---|
| entity.c | 3396 | Entity.swift | 455 | ~13% - 15 TODOs, most functions stubbed |
| table.c | 2958 | Table.swift | 724 | ~25% |
| world.c | 2019 | World.swift | 466 | ~23% - 3 TODOs |
| observable.c | 1628 | Observable.swift | 398 | ~24% |
| table_graph.c | 1568 | TableGraph.swift | 627 | ~40% |
| observer.c | 1484 | Observer.swift | 552 | ~37% |
| commands.c | 1433 | Commands.swift | 981 | ~68% - 6 TODOs |
| bootstrap.c | 1348 | Bootstrap.swift | 372 | ~28% |
| component_index.c | 1247 | ComponentIndex.swift | 465 | ~37% |
| entity_name.c | 1099 | EntityName.swift | 253 | ~23% |
| iter.c | 996 | Iter.swift | 716 | ~72% |
| type_info.c | 873 | TypeInfo.swift | 303 | ~35% |
| on_delete.c | 764 | OnDelete.swift | 300 | ~39% |
| sparse.c | 718 | Sparse.swift | 576 | ~80% |
| os_api.c | 653 | OsApi.swift | 446 | ~68% |
| component_actions.c | 630 | ComponentActions.swift | 212 | ~34% |
| strbuf.c | 595 | Strbuf.swift | 452 | ~76% |
| instantiate.c | 534 | Instantiate.swift | 420 | ~79% |
| sparse_storage.c | 544 | SparseStorage.swift | 516 | ~95% |
| misc.c | 528 | Misc.swift | 459 | ~87% |
| vec.c | 510 | Vec.swift | 345 | ~68% |
| stage.c | 486 | Stage.swift | 221 | ~45% |
| map.c | 462 | Map.swift | 540 | ~100% |
| non_fragmenting_childof.c | 451 | NonFragmentingChildOf.swift | 381 | ~85% |
| entity_index.c | 415 | EntityIndex.swift | 395 | ~95% |
| search.c | 445 | Search.swift | 278 | ~63% |
| id.c | 360 | Id.swift | 211 | ~59% |
| block_allocator.c | 350 | BlockAllocator.swift | 233 | ~67% |
| tree_spawner.c | 345 | TreeSpawner.swift | 306 | ~89% |
| hashmap.c | 284 | Hashmap.swift | 384 | ~100% |
| poly.c | 241 | Poly.swift | 234 | ~97% |
| name_index.c | 239 | NameIndex.swift | 254 | ~100% |
| table_cache.c | 229 | TableCache.swift | 243 | ~100% |
| ordered_children.c | 222 | — | — | not started |
| value.c | 213 | Value.swift | 244 | ~100% |
| stack_allocator.c | 211 | StackAllocator.swift | 222 | ~100% |
| each.c | 189 | Each.swift | 195 | ~100% |
| allocator.c | 176 | Allocator.swift | 177 | ~100% |
| hash.c | 152 | Hash.swift | 97 | ~64% |
| bitset.c | 126 | Bitset.swift | 121 | ~96% |
| ref.c | 119 | Ref.swift | 105 | ~88% |

### Query Subsystem (src/query/)

| C Source File | Lines | Swift File | Swift Lines | Status |
|---|---|---|---|---|
| validator.c | 2009 | QueryValidator.swift | 587 | ~29% |
| eval.c | 1571 | QueryEngine.swift | 626 | ~40% |
| compiler_term.c | 1552 | — | — | not started (part in QueryCompiler) |
| compiler.c | 1175 | QueryCompiler.swift | 433 | ~37% |
| eval_tree.c | 827 | — | — | not started |
| util.c | 754 | QueryUtil.swift | 344 | ~46% |
| api.c | 694 | Query.swift | 548 | ~79% |
| cache.c | 769 | QueryCache.swift | 349 | ~45% |
| eval_sparse.c | 643 | — | — | not started |
| change_detection.c | 670 | — | — | not started |
| eval_iter.c | 566 | — | — | not started |
| eval_up.c | 470 | — | — | not started |
| group.c | 448 | — | — | not started |
| eval_utils.c | 414 | — | — | not started |
| cache_iter.c | 387 | — | — | not started |
| trav_down_cache.c | 365 | — | — | not started |
| match.c | 355 | — | — | not started |
| eval_toggle.c | 344 | — | — | not started |
| order_by.c | 316 | — | — | not started |
| eval_pred.c | 309 | — | — | not started |
| eval_trav.c | 289 | — | — | not started |
| trav_up_cache.c | 270 | — | — | not started |
| trivial_iter.c | 231 | — | — | not started |
| trav_cache.c | 148 | — | — | not started |
| eval_member.c | 139 | — | — | not started |

### Addons (src/addons/) - Partially Started

| C Source File | Lines | Swift File | Swift Lines | Status |
|---|---|---|---|---|
| pipeline.c | 946 | Pipeline.swift | 417 | ~44% |
| system.c | 484 | System.swift | 296 | ~61% |
| timer.c | 376 | Timer.swift | 230 | ~61% |
| app.c | 210 | App.swift | 108 | ~51% |
| doc.c | 243 | Doc.swift | 167 | ~69% |
| module.c | 131 | Module.swift | 103 | ~79% |
| units.c | 987 | — | — | not started |
| metrics.c | 952 | — | — | not started |
| alerts.c | 790 | — | — | not started |
| rest.c | 2270 | — | — | not started |
| http.c | 1614 | — | — | not started |
| journal.c | 65 | — | — | not started |
| log.c | 349 | — | — | not started |
| meta/ (7 files) | ~5524 | — | — | not started |
| script/ (20+ files) | ~8000+ | — | — | not started |
| json/ (9 files) | ~3500+ | — | — | not started |
| stats/ (6 files) | ~3300+ | — | — | not started |
| query_dsl/ | 831 | — | — | not started |

### Support Files (Swift-only)

| Swift File | Lines | Purpose |
|---|---|---|
| Types.swift | 451 | Constants, macros-as-functions, type aliases |
| Structs.swift | 622 | Public API struct definitions |
| InternalTypes.swift | 385 | Internal struct definitions |
| BuiltinEntities.swift | 113 | Entity ID constants |
| QueryTypes.swift | 362 | Query-specific struct/enum types |

## Translation Priority Order

### Phase 1: Complete Core Runtime (highest priority)
Complete all partially-translated core files to 100%. Fix all TODOs.

1. **entity.c** → Entity.swift (3396 lines, currently ~13%)
2. **world.c** → World.swift (2019 lines, currently ~23%)
3. **table.c** → Table.swift (2958 lines, currently ~25%)
4. **observable.c** → Observable.swift (1628 lines, currently ~24%)
5. **observer.c** → Observer.swift (1484 lines, currently ~37%)
6. **commands.c** → Commands.swift (1433 lines, currently ~68%)
7. **bootstrap.c** → Bootstrap.swift (1348 lines, currently ~28%)
8. **component_index.c** → ComponentIndex.swift (1247 lines, currently ~37%)
9. **entity_name.c** → EntityName.swift (1099 lines, currently ~23%)
10. **iter.c** → Iter.swift (996 lines, currently ~72%)
11. **type_info.c** → TypeInfo.swift (873 lines, currently ~35%)
12. **on_delete.c** → OnDelete.swift (764 lines, currently ~39%)
13. **os_api.c** → OsApi.swift (653 lines, currently ~68%)
14. **component_actions.c** → ComponentActions.swift (630 lines, currently ~34%)
15. **strbuf.c** → Strbuf.swift (595 lines, currently ~76%)
16. **stage.c** → Stage.swift (486 lines, currently ~45%)
17. **search.c** → Search.swift (445 lines, currently ~63%)
18. **id.c** → Id.swift (360 lines, currently ~59%)
19. **block_allocator.c** → BlockAllocator.swift (350 lines, currently ~67%)
20. **vec.c** → Vec.swift (510 lines, currently ~68%)
21. **hash.c** → Hash.swift (152 lines, currently ~64%)
22. **ordered_children.c** → new file (222 lines, not started)

### Phase 2: Complete Query Subsystem
All query engine files to 100%.

1. **validator.c** → QueryValidator.swift (2009 lines)
2. **eval.c** → QueryEngine.swift (1571 lines)
3. **compiler_term.c** → QueryCompilerTerm.swift (1552 lines, new file)
4. **compiler.c** → QueryCompiler.swift (1175 lines)
5. **eval_tree.c** → QueryEvalTree.swift (827 lines, new file)
6. **util.c** → QueryUtil.swift (754 lines)
7. **cache.c** → QueryCache.swift (769 lines)
8. **api.c** → Query.swift (694 lines)
9. **change_detection.c** → QueryChangeDetection.swift (670 lines, new file)
10. **eval_sparse.c** → QueryEvalSparse.swift (643 lines, new file)
11. **eval_iter.c** → QueryEvalIter.swift (566 lines, new file)
12. **eval_up.c** → QueryEvalUp.swift (470 lines, new file)
13. **group.c** → QueryGroup.swift (448 lines, new file)
14. **eval_utils.c** → QueryEvalUtils.swift (414 lines, new file)
15. **cache_iter.c** → QueryCacheIter.swift (387 lines, new file)
16. **trav_down_cache.c** → QueryTravDownCache.swift (365 lines, new file)
17. **match.c** → QueryMatch.swift (355 lines, new file)
18. **eval_toggle.c** → QueryEvalToggle.swift (344 lines, new file)
19. **order_by.c** → QueryOrderBy.swift (316 lines, new file)
20. **eval_pred.c** → QueryEvalPred.swift (309 lines, new file)
21. **eval_trav.c** → QueryEvalTrav.swift (289 lines, new file)
22. **trav_up_cache.c** → QueryTravUpCache.swift (270 lines, new file)
23. **trivial_iter.c** → QueryTrivialIter.swift (231 lines, new file)
24. **trav_cache.c** → QueryTravCache.swift (148 lines, new file)
25. **eval_member.c** → QueryEvalMember.swift (139 lines, new file)

### Phase 3: Complete Addons
Finish partially-started addons, then translate remaining.

1. Complete: pipeline.c, system.c, timer.c, app.c, doc.c, module.c
2. New: units.c, metrics.c, alerts.c, log.c, journal.c
3. New: meta/ (7 files), json/ (9 files), stats/ (6 files)
4. New: script/ (20+ files), rest.c, http.c, query_dsl/

### Phase 4: Verification
- Every C function has a Swift counterpart
- Tests compile and pass
- No remaining TODOs, stubs, or placeholders

## Known Issues to Fix

1. **31+ TODO comments** - Must be replaced with actual implementations
2. **Memory function inconsistency** - Standardize on `ecs_os_*` functions
3. **47 bare `memcpy` calls** - Replace with `ecs_os_memcpy`
4. **5 bare `strdup` calls** - Replace with `ecs_os_strdup`
5. **Mixed `.allocate()/.deallocate()` with `ecs_os_malloc/ecs_os_free`** - Pick one per context

## Line Count Summary

- **C core (non-addon)**: ~42,500 lines across 50 files
- **C query subsystem**: ~15,300 lines across 25 files
- **C addons**: ~33,000 lines across 60+ files
- **Total C**: ~90,800 lines
- **Swift translated**: ~21,000 lines across 57 files
- **Estimated completion**: ~23% of total C codebase
