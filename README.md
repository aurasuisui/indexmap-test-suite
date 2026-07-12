# indexmap-test-suite

Independent black-box test suite for [`aurasuisui/indexmap`](https://github.com/aurasuisui/moonbit-indexmap) v0.3.1 — a MoonBit port of Rust's `indexmap` crate that provides a hash map preserving insertion order.

## Overview

This repository is a **standalone test project** that consumes `aurasuisui/indexmap` as an external dependency (via `moon.work` workspace). It does not contain any library code — only tests and one runnable example.

**Test count**: 485 total tests (232 black-box + 253 library self-tests), all passing.

## Project Structure

```
indexmap-test-suite/
├── moon.mod                  # Module config — declares dependency on aurasuisui/indexmap@0.3.1
├── moon.pkg                  # Package config
├── moon.work                 # Workspace config — links local ../moonbit-indexmap as dependency
├── .gitignore
├── LICENSE
├── README.md                 # This file
├── TEST_REPORT.md            # Detailed test findings and analysis
│
├── tests/                    # All black-box test files
│   ├── moon.pkg              # Test package — imports @indexmap alias
│   ├── api_test.mbt          # (89 tests) README API coverage — every documented method
│   ├── stress_test.mbt       # (72 tests) Robustness, concurrency, memory, edge cases
│   ├── trap_test.mbt         # (39 tests) Hidden traps, misleading semantics, gotcha discovery
│   └── comprehensive_test.mbt# (32 tests) Custom key types, resize cascade, get_mut nesting
│
└── cmd/
    └── lru_cache/            # Runnable example: LRU cache built on IndexMap
        ├── moon.pkg
        └── main.mbt
```

## Test Matrix

| File | Tests | Focus | Severity of findings |
|------|:-----:|-------|:---------------------:|
| `tests/api_test.mbt` | 89 | Every public API method from README | 🟢 All pass |
| `tests/stress_test.mbt` | 72 | 100k+ scale, concurrency (copy/consume), memory efficiency, edge values | 🟢 All pass |
| `tests/trap_test.mbt` | 39 | Iterator mutation safety, Eq/Hash order-sensitivity, metadata staleness, tombstone accumulation | 🟡 4 design warnings |
| `tests/comprehensive_test.mbt` | 32 | Custom struct keys, resize cascade, get_mut nested side effects, Bool/Char keys, temp objects | 🔴 1 bug found |

## Quick Start

### Prerequisites

- MoonBit toolchain (`moon` CLI) — tested with `moon 0.1.20260710`
- This repo and `aurasuisui/indexmap` source side-by-side:
  ```
  moon-dev/
  ├── moonbit-indexmap/          # aurasuisui/indexmap source (v0.3.1)
  └── indexmap-test-suite/   # this repo
  ```

### Run All Tests

```bash
cd indexmap-test-suite
moon check      # Type-check (0 errors)
moon test       # Run all 485 tests (232 from this suite + 253 library self-tests)
```

### Run Specific Test Category

Use the MoonBit test filter syntax:
```bash
moon test tests/api_test      # Only API tests
moon test tests/stress_test   # Only stress tests
moon test tests/trap_test     # Only trap tests
```

### Run the LRU Cache Example

```bash
moon run cmd/lru_cache
```

Expected output:
```
Cache size: 3
Contains a: true
Contains b: false
Contains c: true
Contains d: true
=== Cache contents (LRU order) ===
c => gamma
a => alpha
d => delta
```

## Key Findings

### 🔴 Bug Found

**get_mut callback: simultaneous delete + re-insert of same key causes data loss**
- When a `get_mut` callback returns `None` (triggering tombstone deletion) AND calls `insert(same_key, ...)` on the map in the same callback, the tombstone overwrites the just-inserted value.
- See `tests/comprehensive_test.mbt` line ~296 for the reproduction test.
- See `TEST_REPORT.md` BUG-001 for detailed analysis.

**v0.3.1 status**: Still present. Listed as Gotcha #1 in the library's README.

### 🟡 Design Warnings

| # | Issue | Detail |
|---|-------|--------|
| WARN-001 | `Eq` / `Hash` depend on insertion order | `{a:1, b:2} != {b:2, a:1}` — unlike standard `Map`. IndexSet equally affected. |
| WARN-002 | `swap_remove_index` is O(n) shift-remove | Name implies O(1) swap-with-last, but implementation does order-preserving shift-remove. |
| WARN-003 | `max_probe_distance` stale after `sort_by_key` / `sort_by` | Sorting only rebuilds `order[]`/`positions[]`, not `buckets[]`. |
| WARN-004 | Iterator mutation is fail-fast (crash) | Removing keys during iteration causes OOB array access — crashes rather than silently corrupting. |

### 🟢 Strengths Verified

- All README-documented APIs work correctly as a black-box dependency
- Handles 100,000+ entries with stable resize/rehash
- Copy semantics are fully independent (concurrency-safe via isolation)
- All edge values (0, -1, MIN/MAX, empty string, huge strings) handled safely
- Custom `struct` keys with `derive(Hash, Eq, Compare, Debug)` work across module boundaries
- `Bool`/`Char` key types (high collision potential) behave correctly

## Dependency Setup

This project uses MoonBit's `moon.work` workspace mechanism to reference the local `aurasuisui/indexmap` source:

```toml
# moon.work
members = [
  ".",
  "../moonbit-indexmap",
]
```

```toml
# moon.mod
import {
  "aurasuisui/indexmap@0.3.1",
}
```

All test files access the library via the `@indexmap` alias declared in `tests/moon.pkg`.

## Production Readiness

| Dimension | Rating |
|-----------|:------:|
| API Completeness | ⭐⭐⭐⭐⭐ |
| Data Correctness | ⭐⭐⭐⭐⭐ |
| Robustness (100k+) | ⭐⭐⭐⭐⭐ |
| Memory Efficiency | ⭐⭐⭐⭐ |
| Edge Case Handling | ⭐⭐⭐⭐⭐ |
| Concurrency Safety | ⭐⭐⭐⭐ |
| API Design Clarity | ⭐⭐⭐ |
| Documentation | ⭐⭐⭐⭐ |
| Test Coverage | ⭐⭐⭐⭐⭐ |

**Overall: Production-ready for single-threaded use.** For detailed analysis, see [TEST_REPORT.md](TEST_REPORT.md).

## v0.2.0 → v0.3.1 Changes

Our test suite was upgraded from targeting v0.2.0 to v0.3.1. Key changes:

| Change | Impact on tests |
|--------|----------------|
| `extend` → `extend_from_array` (breaking) | 6 call sites renamed; `extend` is now a reserved keyword |
| `inspect` → `debug_inspect` migration | ~523 assert sites migrated; snapshots updated via `moon test -u` |
| `Show::to_string` → `@debug.to_string` (ToJson impl) | JSON serialization tests updated; output format unchanged |
| `VERSION` constant: "0.2.0" → "0.3.1" | Version assertions updated |
| Examples in `cmd/` packages | LRU cache example kept; library's other examples not duplicated |
| 5 gotchas documented in library README | All 1 bug + 4 warnings confirmed still present in v0.3.1 |

## License

Apache 2.0 — see [LICENSE](LICENSE).

## Related

- [aurasuisui/moonbit-indexmap](https://github.com/aurasuisui/moonbit-indexmap) — the library under test
- [indexmap-rs/indexmap](https://github.com/indexmap-rs/indexmap) — the original Rust crate
