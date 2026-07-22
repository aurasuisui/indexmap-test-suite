# Test Report — aurasuisui/indexmap v0.3.3

**Date**: 2026-07-22
**Test Suite**: indexmap-test-suite (independent black-box)
**Toolchain**: moon 0.1.20260710
**Library Under Test**: [aurasuisui/indexmap](https://github.com/aurasuisui/moonbit-indexmap) v0.3.3

---

## Executive Summary

`aurasuisui/indexmap` v0.3.3 passed **513 total tests** with **0 failures**. v0.3.3 was a
post-acceptance quality pass that fixed four correctness defects (Entry-API expansion,
`get_mut` deletion, JSON keys, iterator invalidation) and made two deliberate behavior
changes. This suite was expanded from 232 to **236 black-box tests** to regression-test each
fix, and the tests asserting the old (now-reversed) `get_mut` semantics were rewritten.

| Metric | Value |
|--------|-------|
| Total tests run | 513 |
| Passed | 513 (100%) |
| Failed | 0 |
| Black-box suite tests | 236 (was 232) |
| Library self-tests | 277 (was 253) |
| Library defects fixed in v0.3.3 | 4 (D1–D4) |
| Deliberate behavior changes | 2 |
| Test categories | 6 |

---

## What Changed: v0.3.2 → v0.3.3

### Four defects fixed (regression-tested by this suite)

| # | Defect | Root cause → fix | Source |
|---|--------|------------------|--------|
| **D1** | **Entry API expansion could hang/corrupt** | `VacantEntry::insert` skipped the resize gate, so filling the table purely via the Entry API drove it to 100% and the next insert spun forever in `robin_hood_insert_at`. → `VacantEntry::insert` now delegates to the resize-aware `insert`; `OccupiedEntry::get`/`insert` re-probe by key instead of a stale cached `bucket_index` (field removed); `robin_hood_insert_at` gained a termination guard. | `src/map.mbt` 636-707 |
| **D2** | **`get_mut` deletion silently corrupted** | The old code wrote back to a stale bucket index. → The callback's return value is now authoritative and re-applied via a fresh `insert`/`remove`: `Some(v)` stores `v` (inserting if absent), `None` removes the key. Fixes plain deletion (the v0.3.2 `contains` guard had made it a no-op), double-`len`/double-tombstone, ghost entries, and stale-index mis-writes on callback resize. | `src/map.mbt` 461-494 |
| **D3** | **ToJson keys were mangled** | Keys were built via `@debug.to_string(k.to_json())`, rendering a String key `name` as the literal object key `String("name")`. → Keys now use `k.to_string()` (`Show`), matching core `Map`. **Breaking bound change:** `K:ToJson → K:Show`. | `src/map.mbt` 1150-1167 |
| **D4** | **Iterators were not fail-fast** | Mutating mid-iteration silently skipped entries, then could crash OOB (README claimed fail-fast but it was not). → `iter`/`keys`/`values` snapshot a private mutation `version` and `abort("IndexMap: map mutated during iteration")` on the next `next()` after a structural change. | `src/map.mbt` 814-884 |

### Two deliberate behavior changes (our tests updated to match)

| Change | Detail | Tests affected |
|--------|--------|----------------|
| **`get_mut` None-semantics reversed** | Returning `None` removes the key **even if the callback re-inserted it** (the v0.3.2 "preserve re-insert" behavior is gone — it is what broke plain deletion). `get_mut` on a missing key with `Some(v)` now **upserts**. | `comprehensive_test.mbt:300` inverted; `trap_test.mbt:549`/`:584` rewritten as upsert tests |
| **`ToJson` bound `K:ToJson → K:Show`** | Technically breaking, but the old output was unusable. A custom-struct key must derive `Show` to be serializable. | No compile break (no test serializes a non-`Show` key); `UserRecord` noted as a latent trap |

---

## 1. Test Suite Architecture

### 1.1 Test Files

| File | Count | Scope |
|------|:-----:|-------|
| `tests/api_test.mbt` | 90 | Every public API method; **Entry API fill-past-capacity regression (D1)** |
| `tests/stress_test.mbt` | 72 | Robustness, concurrency safety, memory efficiency, edge cases |
| `tests/trap_test.mbt` | 39 | Hidden traps: iterator fail-fast, `get_mut` upsert, ToJson key rendering, Eq/Hash order |
| `tests/comprehensive_test.mbt` | 35 | Custom key types, resize cascade, **`get_mut` authoritative-return regression (D2)** |
| Library self-tests (in `../moonbit-indexmap/src/`) | 277 | Unit, property, QuickCheck, benchmark tests |
| **Total** | **513** | |

### 1.2 Runnable Example

`cmd/lru_cache/` — a working LRU cache implementation built on IndexMap (uses none of the
v0.3.3-changed APIs; unaffected).

---

## 2. v0.3.3 Regression Coverage Added

| New / rewritten test | File | Defect |
|----------------------|------|:------:|
| `Entry API: filling past capacity via VacantEntry::insert does not hang` (200 keys, capacity grows past 16) | `api_test.mbt` | D1 |
| `OccupiedEntry handle stays correct across a resize` (hold handle across 100 inserts) | `trap_test.mbt` | D1 |
| `get_mut: returning None removes the key even if the callback re-inserted it` | `comprehensive_test.mbt` | D2 |
| `get_mut: callback removes the same key then returns None — no double deletion` | `comprehensive_test.mbt` | D2 |
| `get_mut: callback removes the same key then returns Some — no ghost entry` | `comprehensive_test.mbt` | D2 |
| `get_mut: callback triggers a resize mid-callback — value lands correctly` | `comprehensive_test.mbt` | D2 |
| `get_mut on absent key — None is a no-op, Some(v) upserts` | `trap_test.mbt` | D2 |
| `get_mut on a removed key upserts when callback returns Some` | `trap_test.mbt` | D2 |
| ToJson tests assert raw keys appear as clean JSON keys (`"name"`, `"1"`) — pre-fix they were `String("name")`/`Number(1)` | `api`/`trap`/`stress` | D3 |
| `iterator created after mutation sees the full mutated state` + CATEGORY 2 documents the `abort` message | `trap_test.mbt` | D4 |

**Note on D4 testing:** MoonBit's `abort` is not catchable in an expect-test, so the fail-fast
abort itself cannot be asserted. The suite asserts the *safe* contract (mutate first, then
iterate) and documents the exact abort message — mirroring the library, which also documents
rather than tests the abort.

---

## 3. Findings

### 3.1 Defects fixed in v0.3.3 (D1–D4)

All four are verified by the regression tests in §2. Each new test fails on the pre-fix code
and passes on v0.3.3.

### 3.2 Historical — BUG-001 (superseded)

**BUG-001** (v0.2.0): `get_mut` callback delete + re-insert of the same key lost data.
- v0.3.2 "fixed" it with a `contains(key)` guard that preserved the re-inserted value — but
  that guard **silently broke plain deletion** (returning `None` became a no-op).
- v0.3.3 **supersedes** it: `get_mut` was reworked so the callback's return value is
  authoritative. `None` now always removes the key (even after a re-insert); plain deletion
  works again. Our former BUG-001 regression test was **inverted** to assert the new semantics.
- **Status: ✅ Resolved by redesign.** The four plain-deletion tests
  (`api_test:187`, `comprehensive_test:287`, `stress_test:881`, `trap_test:563`) now pass
  correctly.

### 3.3 Design notes (unchanged)

**WARN-001: `Eq` and `Hash` are insertion-order-sensitive.** Two maps with identical
key-value pairs but different insertion orders are not equal and hash differently. IndexSet
equally affected. **Status: still present** — a design choice inherited from Rust indexmap,
documented in the library README.

**WARN-002: `swap_remove_index` is an O(n) shift-remove.** The name implies O(1)
swap-with-last, but the implementation preserves insertion order via shift-remove. Behavior
is correct; only the name is misleading. **Status: README clarified (v0.3.2); implementation
intentionally unchanged.** Our `trap_test.mbt` asserts the order-preserving (shift-remove)
semantics.

**WARN-004: Iterator mutation is fail-fast.** In v0.3.3 this was **improved**: instead of
silently skipping entries then crashing OOB, iterators now `abort` with the clear message
`IndexMap: map mutated during iteration`. **Status: ✅ improved in v0.3.3.**

### 3.4 Confirmed Correct

- All README-documented API methods work as specified
- Insertion-order iteration invariant holds at all tested scales (1 to 100,000 entries)
- **Entry API is resize-safe** — filling past capacity via `VacantEntry::insert` no longer hangs (D1)
- **`OccupiedEntry` handles stay valid across resizes** — re-probed by key (D1)
- **`get_mut` is corruption-free** under callback delete / re-insert / resize (D2)
- **`ToJson` emits canonical raw keys** for String and Int keys (D3)
- `sort_by_key` / `sort_by` reorder correctly and keep `max_probe()` consistent (fixed v0.3.2)
- All trait implementations (`Debug`, `Eq`, `Hash`, `Default`, `ToJson`) function correctly
- Custom struct keys with derived traits work across module boundaries

---

## 4. Robustness Results (unchanged from prior runs, re-verified)

| Scenario | Scale | Result |
|----------|-------|:------:|
| Int key insertion | 100,000 entries | ✅ Pass |
| Int key roundtrip | 50,000 entries | ✅ Pass |
| Mass deletion (50%) | 50,000 removed from 100,000 | ✅ Pass |
| Resize cascade (16→…→16384) | 20,000 entries | ✅ Pass |
| Entry API fill past capacity | 200 entries (multiple resizes) | ✅ Pass (new, D1) |
| `get_mut` callback-triggered resize | 32 entries | ✅ Pass (new, D2) |
| Huge key / value (64KB) | 65,536 chars | ✅ Pass |

---

## 5. Production Readiness Assessment

| Dimension | Rating | Notes |
|-----------|:------:|-------|
| **API Completeness** | ⭐⭐⭐⭐⭐ | All documented methods verified |
| **Data Correctness** | ⭐⭐⭐⭐⭐ | 0 correctness failures; D1/D2 corruption bugs fixed |
| **Robustness (100k+)** | ⭐⭐⭐⭐⭐ | Stable resize/rehash under load |
| **Memory Efficiency** | ⭐⭐⭐⭐ | Auto resize/shrink works |
| **Edge Case Handling** | ⭐⭐⭐⭐⭐ | All boundary values handled safely |
| **Concurrency Safety** | ⭐⭐⭐⭐ | Copy isolation works; iterator mutation aborts cleanly |
| **API Design Clarity** | ⭐⭐⭐⭐ | `get_mut` semantics now documented; `swap_remove_index` name still slightly misleading |
| **Documentation** | ⭐⭐⭐⭐ | README gotchas accurate; fail-fast documented |
| **Test Coverage** | ⭐⭐⭐⭐⭐ | 513 tests, 100% API coverage + regression tests for all four v0.3.3 fixes |

**Overall: Production-ready for single-threaded use.** v0.3.3 closes the last correctness
defects (Entry-API hang, `get_mut` corruption). Suitable for configuration parsing, LRU
caches, ordered JSON serialization, deterministic testing, and message deduplication. Users
should be aware of the order-sensitive `Eq`/`Hash` semantics, the authoritative `get_mut`
return value, and the fail-fast iterator contract.

---

## 6. Test Execution

```bash
cd indexmap-test-suite
moon check    # 0 errors (warnings are in the library source, not this suite)
moon test     # 236 tests from indexmap-test-suite
              # + 277 tests from library self-tests
              # = 513 total, 0 failed

# Runnable example
moon run cmd/lru_cache
# Output: correct LRU eviction behavior verified
```

---

## 7. Recommendations

### For Library Maintainers (v0.3.3 status)

1. ~~**Fix BUG-001**~~ — **✅ Superseded in v0.3.3**: `get_mut` reworked to authoritative-return;
   plain deletion and the re-insert edge case are both correct now.
2. ~~**Fix WARN-003** (`max_probe` stale after sort)~~ — **✅ Done in v0.3.2**.
3. ~~**Fix the Entry-API expansion hang (D1)**~~ — **✅ Done in v0.3.3**.
4. ~~**Make iterators fail-fast with a clear message (WARN-004 / D4)**~~ — **✅ Done in v0.3.3**.
5. **WARN-001 (Eq/Hash order-sensitive)**: Keep as a documented design choice (inherited from
   Rust indexmap). Changing it would break the API contract.
6. **WARN-002 (`swap_remove_index` name)**: Consider renaming to `shift_remove_index` in a
   future breaking release, or keep the README clarification.
7. **Minor**: the library emits `type_param_method` deprecation warnings (dot-syntax on
   multi-bound type params, e.g. `k.to_string()` → `Show::to_string`). Cosmetic only.

### For Users

1. `get_mut(key, f)`: the callback's return is authoritative — `Some(v)` stores/upserts `v`,
   `None` removes the key (even if the callback re-inserted it).
2. Use `OccupiedEntry::insert()` to update values without changing position (handle is
   resize-safe in v0.3.3).
3. Finish all mutations before creating an iterator; a live iterator aborts if the map changes.
4. To serialize custom-struct keys with `to_json`, the key type must derive `Show`.
5. Do not rely on IndexMap/IndexSet `Eq`/`Hash` for order-independent comparisons.
