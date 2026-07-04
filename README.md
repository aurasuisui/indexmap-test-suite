# indexmap-test-suite

Independent black-box test suite for [`aurasuisui/indexmap`](https://github.com/aurasuisui/moonbit-indexmap) v0.2.0 — a MoonBit port of Rust's `indexmap` crate that provides a hash map preserving insertion order.

## Overview

This repository is a **standalone test project** that consumes `aurasuisui/indexmap` as an external dependency (via `moon.work` workspace). It does not contain any library code — only tests and one runnable example.

**Test count**: 232 black-box tests (plus the library's own 253 unit/property/bench tests = 485 total verified).

## Project Structure

```
indexmap-test-suite/
├── moon.mod                  # Module config — declares dependency on aurasuisui/indexmap@0.2.0
├── moon.pkg                  # Package config — imports @indexmap alias
├── moon.work                 # Workspace config — links local ../0.2.0 as dependency
├── .gitignore
├── LICENSE
├── README.md                 # This file
├── TEST_REPORT.md            # Detailed test findings and analysis
│
├── tests/                    # All black-box test files
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

- MoonBit toolchain (`moon` CLI) — tested with `moon 0.1.20260629`
- This repo and `aurasuisui/indexmap` source side-by-side:
  ```
  moon-dev/
  ├── 0.2.0/                 # aurasuisui/indexmap source
  └── indexmap-test-suite/   # this repo
  ```

### Run All Tests

```bash
cd indexmap-test-suite
moon check      # Type-check (0 errors)
moon test       # Run all 232 tests
```

### Run Specific Test Category

```bash
moon test --test-filter "stress:"   # Only stress tests
moon test --test-filter "TRAP:"     # Only trap tests
moon test --test-filter "get_mut"   # Tests mentioning get_mut
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
- Custom `struct` keys with `derive(Hash, Eq, Compare, Show, Debug)` work across module boundaries
- `Bool`/`Char` key types (high collision potential) behave correctly

## Dependency Setup

This project uses MoonBit's `moon.work` workspace mechanism to reference the local `aurasuisui/indexmap` source:

```toml
# moon.work
members = [
  ".",
  "../0.2.0",
]
```

```toml
# moon.mod
import {
  "aurasuisui/indexmap@0.2.0",
}
```

All test files access the library via the `@indexmap` alias declared in `moon.pkg`.

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

## License

Apache 2.0 — see [LICENSE](LICENSE).

## Related

- [aurasuisui/moonbit-indexmap](https://github.com/aurasuisui/moonbit-indexmap) — the library under test
- [indexmap-rs/indexmap](https://github.com/indexmap-rs/indexmap) — the original Rust crate
