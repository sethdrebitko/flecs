# Flecs Swift Translation

A 1:1 mechanical translation of the [flecs](https://github.com/SanderMertens/flecs) C ECS framework into Swift.

## Overview

This is **not** a Swift wrapper or idiomatic Swift API. It is a direct, line-by-line port of the C source code into Swift, preserving:

- C function names (`ecs_*`, `flecs_*`)
- C control flow and branching logic
- C memory management patterns via `ecs_os_malloc`/`ecs_os_free`
- C-style error handling (nil returns, -1 for failures)

The goal is a Swift codebase that reads like the C original, making it easy to cross-reference and maintain parity.

## Current Status

- **~21,000 lines** of Swift across **57 files**
- **~23%** of the ~90,800-line C codebase translated
- Core runtime, query subsystem (partial), and 6 addons translated

### What's Translated

| Subsystem | Files | Coverage |
|-----------|-------|----------|
| Core runtime (`src/`) | 36 files | ~25-100% per file |
| Query engine (`src/query/`) | 6 files | ~29-79% per file |
| Addons (`src/addons/`) | 6 files | ~44-79% per file |
| Support files (types, structs) | 5 files | Swift-only |

See [CLAUDE.md](CLAUDE.md) for the full file-by-file translation status table.

## Building

```bash
cd swift
swift build
```

Requires Swift 5.9+ on macOS (Darwin) or Linux (Glibc).

## Translation Conventions

- One Swift file per C source file (e.g., `entity.c` -> `Entity.swift`)
- C structs redefined in Swift (not imported via bridging header)
- `T*` -> `UnsafeMutablePointer<T>?`, `void*` -> `UnsafeMutableRawPointer?`
- All allocations through `ecs_os_malloc`/`ecs_os_calloc`/`ecs_os_free`
- No Swift idioms: no `guard let`, no enums for C integer types, no Foundation

## Project Documentation

- [CLAUDE.md](CLAUDE.md) - Detailed project plan, translation conventions, file status, and known issues
