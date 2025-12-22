# Repository Guidelines

## Project Structure & Module Organization
- Core build logic is in `build.zig`; pick the backend with `-Dbackend=native` (default) or `-Dbackend=zisk`.
- Source lives under `src/backends`: `native.zig` for host execution and `zisk.zig` for ZisK zkVM. The linker script is `src/zisk.ld`.
- Backend selection flows through the generated `build_options` module; keep backend-specific helpers near their peer file to limit drift.

## Build, Test, and Development Commands
- `zig build -Dbackend=native` — local dev build with host target and standard optimizations.
- `zig build -Dbackend=zisk -Doptimize=ReleaseSmall` — zkVM output using the provided linker script.
- `zig build test` — runs tests against the native backend; use before every PR.
- Quick iteration: `zig test src/backends/native.zig -Doptimize=Debug` while developing helpers.

## Coding Style & Naming Conventions
- Format with `zig fmt` before committing; 4-space indentation, no trailing whitespace.
- Zig conventions: types and comptime structs in `TitleCase`, functions/variables in `camelCase`, constants in lowerCamel.
- Prefer explicit `@import` paths and local helpers; keep panic and entry-point wiring centralized via the `zkvm` module.

## Testing Guidelines
- Place tests alongside implementation with `test "description"` blocks; name after behavior (e.g., `test "readInput returns provided bytes"`).
- Default to native backend for assertions; gate zkVM-only behavior with compile-time checks on `backend`.
- Cover input/output helpers, panic handling, and allocator use; add regressions for every bug.

## Commit & Pull Request Guidelines
- Use short, imperative commits (e.g., “Add zisk output helper”); add a body when behavior changes.
- PRs should state the backend(s) touched, testing performed (`zig build test`, manual zkVM run), and any follow-up tasks.
- Link issues when available and include reproduction steps or validating commands.

## Backend & Security Notes
- ZisK builds disable red zone/stack protector and assume single-threaded freestanding RISC-V; avoid OS services and large or unbounded allocation.
- Keep entry-point exports (`zkvm.exportEntryPoint`) and panic handling consistent to keep zkVM proofs verifiable.
