# indexmap-test-suite

Independent black-box test suite for [`aurasuisui/indexmap`](https://github.com/aurasuisui/moonbit-indexmap) v0.3.3 — a MoonBit port of Rust's `indexmap` crate that provides a hash map preserving insertion order.

## Overview

This repository is a **standalone test project** that consumes `aurasuisui/indexmap` as an external dependency (via `moon.work` workspace). It does not contain any library code — only tests and one runnable example.

**Test count**: 513 total tests (236 black-box + 277 library self-tests), all passing.

## Project Structure

```
indexmap-test-suite/
├── moon.mod                  # Module config — declares dependency on aurasuisui/indexmap@0.3.3
├── moon.pkg                  # Package config
├── moon.work                 # Workspace config — links local ../moonbit-indexmap as dependency
├── .gitignore
├── LICENSE
├── README.md                 # This file
├── TEST_REPORT.md            # Detailed test findings and analysis
│
├── tests/                    # All black-box test files
│   ├── moon.pkg              # Test package — imports @indexmap alias
│   ├── api_test.mbt          # (90 tests) README API coverage — every documented method
│   ├── stress_test.mbt       # (72 tests) Robustness, concurrency, memory, edge cases
│   ├── trap_test.mbt         # (39 tests) Hidden traps, misleading semantics, gotcha discovery
│   └── comprehensive_test.mbt# (35 tests) Custom key types, resize cascade, get_mut semantics
│
└── cmd/
    └── lru_cache/            # Runnable example: LRU cache built on IndexMap
        ├── moon.pkg
        └── main.mbt
```

## Test Matrix

| File | Tests | Focus | Severity of findings |
|------|:-----:|-------|:---------------------:|
| `tests/api_test.mbt` | 90 | Every public API method from README; **Entry API fill-past-capacity regression (v0.3.3)** | 🟢 All pass |
| `tests/stress_test.mbt` | 72 | 100k+ scale, concurrency (copy/consume), memory efficiency, edge values | 🟢 All pass |
| `tests/trap_test.mbt` | 39 | Iterator fail-fast, Eq/Hash order-sensitivity, `get_mut` upsert semantics, ToJson key rendering | 🟡 Design notes |
| `tests/comprehensive_test.mbt` | 35 | Custom struct keys, resize cascade, `get_mut` authoritative-return regression tests | 🟢 All pass |

## Quick Start

### Prerequisites

- MoonBit toolchain (`moon` CLI) — tested with `moon 0.1.20260710`
- This repo and `aurasuisui/indexmap` source side-by-side:
  ```
  moon-dev/
  ├── moonbit-indexmap/          # aurasuisui/indexmap source (v0.3.3)
  └── indexmap-test-suite/   # this repo
  ```

### Run All Tests

```bash
cd indexmap-test-suite
moon check      # Type-check (0 errors)
moon test       # Run all 513 tests (236 from this suite + 277 library self-tests)
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

### v0.3.3 — four library defects fixed, verified by this suite

v0.3.3 was a post-acceptance quality pass on the library. This suite was expanded to
regression-test each fix (each new test fails on the pre-fix code and passes after):

| # | Defect fixed in v0.3.3 | Our regression coverage |
|---|------------------------|--------------------------|
| D1 | **Entry API expansion hang** — `VacantEntry::insert` skipped the resize gate, so filling the table purely via the Entry API spun forever. Now delegates to the resize-aware `insert`; `OccupiedEntry::get/insert` re-probe by key. | `api_test.mbt` "filling past capacity via VacantEntry::insert does not hang" (200 keys); `trap_test.mbt` "OccupiedEntry handle stays correct across a resize" |
| D2 | **`get_mut` silent corruption** — the callback's return value is now authoritative, re-applied via fresh `insert`/`remove`. Fixes plain deletion, double-`len` decrement, ghost entries, stale-index mis-writes on callback resize. | `comprehensive_test.mbt` — 4 `get_mut` regression tests (None-removes-even-after-reinsert, remove+None, remove+Some, callback-triggered resize); `trap_test.mbt` upsert tests |
| D3 | **ToJson key mangling** — object keys now use the key's `Show` rendering (`k.to_string()`): a String key `name` is `name`, not `String("name")`. Bound changed `K:ToJson → K:Show`. | `trap_test.mbt` / `api_test.mbt` / `stress_test.mbt` ToJson tests assert raw keys appear as clean JSON keys |
| D4 | **Iterators are now truly fail-fast** — `iter`/`keys`/`values` snapshot a mutation version and `abort("IndexMap: map mutated during iteration")` if the map changes mid-iteration (previously silent skips then an OOB crash). | `trap_test.mbt` CATEGORY 2 — safe-path assertions + documented abort (the abort is not catchable in an expect-test) |

### ⚠️ Two deliberate behavior changes in v0.3.3 (tests updated to match)

1. **`get_mut` None-semantics reversed.** Returning `None` now **removes** the key *even if the
   callback re-inserted it* — the v0.3.2 "preserve re-insert" behavior (our former BUG-001
   regression test) is gone; it is what had silently broken plain deletion. Return `Some(v)` to
   keep a value. `get_mut` on a **missing** key with `Some(v)` now **upserts** (inserts).
2. **`ToJson` key bound** changed `K:ToJson → K:Show`. Technically breaking, but the old output
   was unusable (mangled keys), so nothing working depended on it. Note: a custom-struct key must
   derive `Show` to be used with `to_json` (our `UserRecord` does not, and is never serialized).

### 🟡 Design notes (unchanged, documented)

| # | Behavior | Detail | Status |
|---|----------|--------|--------|
| WARN-001 | `Eq` / `Hash` depend on insertion order | `{a:1, b:2} != {b:2, a:1}`. IndexSet equally affected. | Design choice (from Rust indexmap) |
| WARN-002 | `swap_remove_index` is O(n) shift-remove | Name implies O(1) swap-with-last, but implementation does order-preserving shift-remove. | README clarified (v0.3.2) |
| WARN-004 | Iterator mutation aborts (fail-fast) | Mutating mid-iteration aborts with a clear message (v0.3.3) — no longer an OOB crash. | ✅ Improved in v0.3.3 |

### 🟢 Strengths Verified

- All README-documented APIs work correctly as a black-box dependency
- Handles 100,000+ entries with stable resize/rehash
- **Entry API is resize-safe** — filling past capacity no longer hangs (v0.3.3)
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
  "aurasuisui/indexmap@0.3.3",
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
| API Design Clarity | ⭐⭐⭐⭐ |
| Documentation | ⭐⭐⭐⭐ |
| Test Coverage | ⭐⭐⭐⭐⭐ |

**Overall: Production-ready for single-threaded use.** For detailed analysis, see [TEST_REPORT.md](TEST_REPORT.md).

## Version History (as tracked by this suite)

Our test suite tracks each upgrade of the library. Key changes:

| Version | Change | Impact on tests |
|---------|--------|----------------|
| v0.3.0 | `extend` → `extend_from_array` (breaking) | 6 call sites renamed; `extend` became a reserved keyword |
| v0.3.1 | `inspect` → `debug_inspect` migration | ~523 assert sites migrated; snapshots updated via `moon test -u` |
| v0.3.1 | `Show::to_string` → `@debug.to_string` | JSON serialization tests updated |
| v0.3.2 | BUG-001 `contains(key)` guard in `get_mut`; `recalc_max_probe()` after sort | Tests rewritten to verify fixes |
| v0.3.3 | **D1 Entry API resize hang fixed** | New regression test: fill past capacity via Entry API |
| v0.3.3 | **D2 `get_mut` authoritative return** (None removes even after re-insert; Some upserts on missing key) | BUG-001 test inverted; 3 new `get_mut` regression tests; 2 upsert tests rewritten |
| v0.3.3 | **D3 ToJson raw keys via `K:Show`** | ToJson tests assert raw clean keys; stale comments updated |
| v0.3.3 | **D4 true fail-fast iterators** | Iterator tests assert safe path + document the abort message |
| v0.3.3 | `VERSION` "0.3.2" → "0.3.3" | Version assertions updated |

**Final tally**: 236 black-box tests + 277 library self-tests = 513 total, 0 failures.

## License

Apache 2.0 — see [LICENSE](LICENSE).

## Related

- [aurasuisui/moonbit-indexmap](https://github.com/aurasuisui/moonbit-indexmap) — the library under test
- [indexmap-rs/indexmap](https://github.com/indexmap-rs/indexmap) — the original Rust crate
