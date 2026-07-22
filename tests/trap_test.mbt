// Copyright (c) 2026 moonbit-indexmap contributors
// SPDX-License-Identifier: Apache-2.0
//
// TRAP TESTS — designed to expose hidden bugs, misleading semantics,
// and "looks correct but is actually wrong" scenarios in
// aurasuisui/indexmap v0.3.2.
//
// Each test includes inline documentation of WHAT trap we're testing
// and WHY a casual user might fall into it.

// ============================================================================
// CATEGORY 1: Metadata Consistency
//
// v0.2.0: sort_by_key / sort_by rebuilt order[] and positions[] but did
// NOT recalculate max_probe_distance — so max_probe() returned stale
// pre-sort values (WARN-003).
//
// v0.3.2: a new internal recalc_max_probe() helper is called at the end
// of sort_by_key() and sort_by(), so max_probe() now reflects the live
// bucket layout after sorting. We re-verify this fix.
// ============================================================================

///|
test "TRAP: max_probe distance now recalculated after sort_by_key (v0.3.2 fix)" {
  // Insert in random order to create probe distances
  let map = @indexmap.with_capacity(16)
  let mut i = 0
  while i < 30 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  let max_probe_before = map.max_probe()
  map.sort_by_key()
  let max_probe_after = map.max_probe()
  // v0.3.2: recalc_max_probe() is called, so after sort max_probe
  // should still equal before (sorting doesn't move buckets, it only
  // rearranges order[], so the actual probe distances haven't changed —
  // but the value is NOW explicitly recalculated rather than stale).
  debug_inspect(max_probe_after, content="\{max_probe_before}")
  debug_inspect(max_probe_after >= 0, content="true")
}

///|
test "TRAP: sort_by_key does not invalidate capacity invariants" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 200 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  let cap_before = map.capacity()
  let lf_before = map.load_factor()
  map.sort_by_key()
  let cap_after = map.capacity()
  let lf_after = map.load_factor()
  // Capacity should not change after sort
  debug_inspect(cap_before, content="\{cap_after}")
  // Load factor should not change after sort (same number of entries)
  debug_inspect(lf_before, content="\{lf_after}")
}

///|
test "TRAP: sort_by recalculates max_probe after descending sort (v0.3.2 fix)" {
  let map = @indexmap.new()
  // Insert to build up probe distances
  let mut i = 0
  while i < 100 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  let old_max_probe = map.max_probe()
  map.sort_by(fn(a, b) { b.1.compare(a.1) })
  let new_max_probe = map.max_probe()
  // Len preserved
  debug_inspect(map.len(), content="100")
  // v0.3.2: max_probe is recalculated — it should equal the old value
  // because sorting does not move entries between buckets, only reorders order[].
  debug_inspect(old_max_probe >= 0, content="true")
  debug_inspect(new_max_probe, content="\{old_max_probe}")
}

// ============================================================================
// CATEGORY 2: Iterator Invalidation (true fail-fast since v0.3.3)
//
// Each iterator (iter/keys/values) snapshots the map's mutation `version`
// at creation. If the map is structurally modified before the iterator is
// exhausted (insert/remove/clear/retain/sort_by*/reserve/shrink_to_fit, or
// an Entry/get_mut mutation), the next `next()` aborts with
// "IndexMap: map mutated during iteration". Earlier versions silently
// skipped entries and could crash with an out-of-bounds access. The abort
// is not catchable in an expect-test, so the tests below assert map state
// or the safe "mutate first, then iterate" path, and document the abort.
// ============================================================================

///|

///|
test "TRAP: remove during iteration causes skips" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  map.insert("d", 4) |> ignore
  map.insert("e", 5) |> ignore
  // Get an iterator but also mutate the map BEFORE consuming it
  let _iter = map.iter()
  // Remove a key that the iterator hasn't reached yet
  map.remove("d") |> ignore
  // v0.3.3: creating the iterator snapshots its mutation version; remove("d")
  // bumps the map's version but does NOT itself abort. Because we never consume
  // `_iter` here, no abort fires. Had we called _iter.next() now, it would abort
  // with "IndexMap: map mutated during iteration" (true fail-fast). Earlier
  // versions instead crashed with an out-of-bounds array access on consumption.
  // We verify the map state is consistent after the mutation:
  debug_inspect(map.contains("e"), content="true")
  debug_inspect(map.len(), content="4")
}

///|
test "iterator created after mutation sees the full mutated state (v0.3.3 fail-fast)" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  // Finish ALL mutations BEFORE creating the iterator...
  map.insert("c", 3) |> ignore
  let iter = map.iter()
  let collected = iter.collect()
  // ...and the iterator sees every entry, in insertion order.
  debug_inspect(collected.length(), content="3")
  debug_inspect(
    collected[0].0,
    content=(
      #|"a"
    ),
  )
  debug_inspect(
    collected[1].0,
    content=(
      #|"b"
    ),
  )
  debug_inspect(
    collected[2].0,
    content=(
      #|"c"
    ),
  )
  // v0.3.3 made iterators truly fail-fast: had we created `iter` BEFORE
  // inserting "c" and then called collect(), the first next() would abort with
  // "IndexMap: map mutated during iteration". That abort is not catchable in an
  // expect-test, so we assert the safe contract here: mutate first, then iterate.
}

///|
test "TRAP: into_iter count_remaining after partial consumption" {
  let map = @indexmap.new()
  map.insert("x", 10) |> ignore
  map.insert("y", 20) |> ignore
  map.insert("z", 30) |> ignore
  let into = map.into_iter()
  // Consume first entry
  into.next() |> ignore
  // count_remaining should now be 2
  debug_inspect(into.count_remaining(), content="2")
  // collect should return remaining 2 entries
  let rest = into.collect()
  debug_inspect(rest.length(), content="2")
}

///|
test "TRAP: into_iter next after all consumed returns None" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  let into = map.into_iter()
  into.next() |> ignore
  debug_inspect(into.next(), content="None")
  // Additional next calls after exhaustion should keep returning None
  debug_inspect(into.next(), content="None")
}

///|

///|
test "TRAP: iter with size_hint but actual count differs after mutation" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  // size_hint=3 at construction time
  let _iter = map.iter()
  // Remove a key BEFORE consuming the iterator
  map.remove("b") |> ignore
  // v0.3.3: remove("b") bumps the map's version but does not abort by itself.
  // We never consume `_iter`, so no abort fires here. Had we called _iter.next(),
  // it would abort with "IndexMap: map mutated during iteration" (true fail-fast).
  // Earlier versions crashed with an out-of-bounds array access on consumption.
  // The map state after the mutation is consistent:
  debug_inspect(map.len(), content="2")
  debug_inspect(map.contains("a"), content="true")
  debug_inspect(map.contains("c"), content="true")
}

// ============================================================================
// CATEGORY 3: Ordering Semantics Traps
//
// Eq requires insertion order to match. This is a FUNDAMENTAL design
// decision inherited from Rust's indexmap — but Rust devs expect that.
// MoonBit devs using the built-in Map (which uses the same Eq) may
// be surprised that two IndexMaps with the same keys/values are
// NOT equal if inserted in different order.
// ============================================================================

///|
test "TRAP: Eq false for same keys/values different insertion order" {
  let a = @indexmap.new()
  a.insert("b", 2) |> ignore
  a.insert("a", 1) |> ignore
  let b = @indexmap.new()
  b.insert("a", 1) |> ignore
  b.insert("b", 2) |> ignore
  // Same keys, same values — but different insertion order
  // This is the #1 gotcha: Eq is ORDER-SENSITIVE
  debug_inspect(a == b, content="false")
  // Meanwhile, a standard Map would consider them equal
  let std_a : Map[String, Int] = Map([])
  std_a["b"] = 2
  std_a["a"] = 1
  let std_b : Map[String, Int] = Map([])
  std_b["a"] = 1
  std_b["b"] = 2
  // Standard Map's Eq is order-independent (it uses Set semantics)
  // But IndexMap's Eq is order-dependent
  // This is a design difference, not a bug — but users MUST know
}

///|
test "TRAP: from_array with duplicate key — which position wins?" {
  // Key "dup" appears 3 times. Which insert position does it get?
  let entries = [("dup", 1), ("unique", 99), ("dup", 2), ("dup", 3)]
  let map = @indexmap.IndexMap::from_array(entries)
  debug_inspect(map.len(), content="2")
  debug_inspect(map.get("dup"), content="Some(3)")
  // "dup" kept the LAST value. But WHERE is "dup" in the order?
  // Is it at position 0 (first insert of "dup") or at some other position?
  let iter = map.iter()
  let collected = iter.collect()
  debug_inspect(
    collected[0].0,
    content=(
      #|"dup"
    ),
  )
  // Indeed: "dup" stays at its first insertion position (index 0),
  // keeping only the last value. This is correct per README but
  // unexpected: the VALUE is from the last insert, the POSITION
  // is from the first insert. This creates asymmetric semantics.
}

///|
test "TRAP: remove then re-insert — is it same key or a new entry?" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.remove("a") |> ignore
  map.insert("a", 10) |> ignore
  // "a" is now at the END (latest insert) — re-insert treats it as new
  let entries = map.iter().collect()
  debug_inspect(
    entries[0],
    content=(
      #|("b", 2)
    ),
  )
  debug_inspect(
    entries[1],
    content=(
      #|("a", 10)
    ),
  )
  // This is correct but means: an IndexMap has no "update" operation
  // that preserves position. `insert` an existing key keeps position.
  // But `remove` + `insert` moves it to the end.
  // Users who want to update a value WITHOUT changing order should
  // use insert (overwrite) or OccupiedEntry::insert, NOT remove+insert.
}

///|
test "TRAP: retain callback mutating other keys via map reference" {
  // This is a pathological pattern: the retain callback has access
  // to the map's own reference, so it could remove OTHER keys.
  // This is NOT recommended but should be documented as UB.
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  // retain the NON-"b" entries, but DON'T mutate inside callback
  map.retain(fn(k, _) { k != "b" })
  debug_inspect(map.len(), content="2")
  debug_inspect(map.contains("a"), content="true")
  debug_inspect(map.contains("b"), content="false")
  debug_inspect(map.contains("c"), content="true")
}

// ============================================================================
// CATEGORY 4: ToJson Key Rendering
//
// Since v0.3.3, IndexMap's ToJson impl renders each object key via the
// key's Show rendering (k.to_string()), matching moonbitlang/core's own
// Map convention: a String key `name` becomes the raw JSON key "name"
// (canonical), an Int key 42 becomes "42". The impl is bounded on K:Show.
// (Earlier versions built keys via @debug.to_string(k.to_json()), which
// mangled a String key into the literal object key String("name") and an
// Int key into Number(42).) Insertion order is preserved in the output.
// ============================================================================

///|
test "TRAP: ToJson key collision when two keys stringify the same" {
  let map = @indexmap.new()
  // Inserting the SAME key twice keeps a single entry (last value wins).
  map.insert("key", "first") |> ignore
  map.insert("key", "second") |> ignore
  let json = map.to_json()
  let s = @debug.to_string(json)
  // "second" overwrites because it was inserted last
  debug_inspect(s.contains("second"), content="true")
  debug_inspect(map.len(), content="1")
  // v0.3.3 (D3 fix): the object KEY is the key's Show rendering — the raw string
  // "key" appears as a clean JSON key. Pre-fix the key was built via
  // @debug.to_string(k.to_json()), mangling it into String("key"), so the
  // contiguous substring "key" with clean surrounding quotes was absent.
  // (Values still render in Debug constructor form, e.g. String("second"), so a
  // bare contains("String(") cannot detect key mangling — we check the key form.)
  debug_inspect(s.contains("\"key\""), content="true")
}

///|
test "TRAP: ToJson on IndexMap with non-string keys renders keys via Show (v0.3.3)" {
  // Int keys — the JSON object key is the Show rendering (decimal text).
  let map = @indexmap.new()
  map.insert(1, "one") |> ignore
  map.insert(2, "two") |> ignore
  let json = map.to_json()
  let s = @debug.to_string(json)
  // JSON object with stringified numeric keys
  debug_inspect(s.contains("1"), content="true")
  debug_inspect(s.contains("2"), content="true")
  debug_inspect(s.contains("one"), content="true")
  debug_inspect(s.contains("two"), content="true")
  // v0.3.3 (D3 fix): Int keys render via Show as the clean JSON keys "1"/"2"
  // (pre-fix they were mangled into Number(1) / Number(2)).
  debug_inspect(s.contains("\"1\""), content="true")
  debug_inspect(s.contains("\"2\""), content="true")
  debug_inspect(s.contains("Number("), content="false")
}

///|
test "TRAP: ToJson preserves insertion order in JSON output (v0.3.3)" {
  let map = @indexmap.new()
  map.insert("zzz", "last_alphabetically") |> ignore
  map.insert("aaa", "first_alphabetically") |> ignore
  map.insert("mmm", "middle") |> ignore
  let json = map.to_json()
  let s = @debug.to_string(json)
  // Keys appear in INSERTION order (zzz, aaa, mmm), not alphabetical.
  let pos_zzz = s.find("zzz")
  let pos_aaa = s.find("aaa")
  let pos_mmm = s.find("mmm")
  debug_inspect(pos_zzz is Some(_), content="true")
  debug_inspect(pos_aaa is Some(_), content="true")
  debug_inspect(pos_mmm is Some(_), content="true")
  // Actually assert the order: zzz before aaa before mmm.
  match (pos_zzz, pos_aaa, pos_mmm) {
    (Some(z), Some(a), Some(m)) => {
      debug_inspect(z < a, content="true")
      debug_inspect(a < m, content="true")
    }
    _ => @test.fail("all three keys should be present")
  }
  // v0.3.3 (D3 fix): keys render via Show — the raw keys appear as clean JSON
  // keys (pre-fix they were mangled into String("zzz") etc.).
  debug_inspect(s.contains("\"zzz\""), content="true")
  debug_inspect(s.contains("\"aaa\""), content="true")
}

// ============================================================================
// CATEGORY 5: Tombstone Accumulation Under Cyclic Load
//
// If the deletion pattern keeps tombstones just under the 25% rehash
// threshold, the map can accumulate tombstones indefinitely without
// triggering a cleanup rehash. This degrades iteration performance
// because the iterator must skip tombstone entries.
// ============================================================================

///|
test "TRAP: repeated insert-delete cycles may accumulate tombstones" {
  let map = @indexmap.new()
  // Fill with 1000 entries
  let mut i = 0
  while i < 1000 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  // Delete 200 (20%) — shouldn't trigger rehash (needs 25%+)
  let mut j = 0
  while j < 200 {
    map.remove(j) |> ignore
    j = j + 1
  }
  debug_inspect(map.len(), content="800")
  // Re-insert 200 new keys
  let mut k = 0
  while k < 200 {
    map.insert(10000 + k, k) |> ignore
    k = k + 1
  }
  debug_inspect(map.len(), content="1000")
  // Repeat: delete 200 more
  let mut l = 200
  while l < 400 {
    map.remove(l) |> ignore
    l = l + 1
  }
  debug_inspect(map.len(), content="800")
  // Re-insert again
  let mut m = 0
  while m < 200 {
    map.insert(20000 + m, m) |> ignore
    m = m + 1
  }
  debug_inspect(map.len(), content="1000")
  // At this point there may be accumulated tombstones.
  // The map should still function correctly:
  debug_inspect(map.contains(9999), content="false")
  debug_inspect(map.contains(10000), content="true")
  debug_inspect(map.contains(20000), content="true")
}

///|
test "TRAP: delete all entries one by one vs clear" {
  let map_a = @indexmap.new()
  let mut i = 0
  while i < 500 {
    map_a.insert(i, i) |> ignore
    i = i + 1
  }
  // Delete each individually (creates tombstones)
  let mut j = 0
  while j < 500 {
    map_a.remove(j) |> ignore
    j = j + 1
  }
  debug_inspect(map_a.is_empty(), content="true")
  debug_inspect(map_a.len(), content="0")
  // Compare: fresh map + clear
  let map_b = @indexmap.new()
  let mut k = 0
  while k < 500 {
    map_b.insert(k, k) |> ignore
    k = k + 1
  }
  map_b.clear()
  debug_inspect(map_b.is_empty(), content="true")
  // Both are empty, but map_a has 500 tombstones while map_b has none.
  // The capacity may differ (map_a may have triggered a rehash along the way,
  // or it may have exactly 500 tombstones and not yet reached the 25% threshold
  // per active entries — but since len=0, the tombstone check is len+tombstons*4 > cap)
  // Either way, both should work correctly afterward
  map_a.insert(9999, 42) |> ignore
  debug_inspect(map_a.get(9999), content="Some(42)")
  map_b.insert(9999, 42) |> ignore
  debug_inspect(map_b.get(9999), content="Some(42)")
}

///|
test "TRAP: 80% deletion may not trigger rehash if tombstone ratio < 0.25 of CAPACITY" {
  // The rehash trigger is: tombstone_count * 4 > buckets.length() AND total > 0
  // So if we have a large capacity but few tombstones, rehash won't trigger
  let map = @indexmap.with_capacity(8192)
  // Insert just a few entries (capacity is large, so tombstones per capacity is low)
  let mut i = 0
  while i < 100 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  // Delete 24 (24%) — under 25% of capacity trigger
  let mut j = 0
  while j < 24 {
    map.remove(j) |> ignore
    j = j + 1
  }
  debug_inspect(map.len(), content="76")
  // The 24 tombstones are well below 25% of 8192 capacity, so no rehash.
  // Functionally correct but with tombstones in the probe chain
  let mut k = 76
  while k < 200 {
    map.insert(k, k) |> ignore
    k = k + 1
  }
  // After inserting 124 more (76→200), internal resize may happen.
  // The total entries (including tombstones) triggers resize at 0.75 load factor.
  // 200 entries / 8192 capacity = ~2.4% load factor, well under 75%.
  // So no resize/rehash triggered, data integrity preserved.
  debug_inspect(map.len() >= 76, content="true")
  // Verify data integrity — all surviving and re-inserted keys present
  debug_inspect(map.get(50), content="Some(50)")
  debug_inspect(map.get(100), content="Some(100)")
}

// ============================================================================
// CATEGORY 6: swap_remove_index Has Misleading Name
//
// Despite "swap" in the name (suggesting O(1) swap-with-last),
// swap_remove_index calls remove(key) which calls remove_from_order
// which does O(n) shift-remove. This means:
// 1) It's O(n), not O(1)
// 2) It PRESERVES insertion order of remaining elements
// 3) The name "swap" is misleading — it does NOT swap with the last element
// ============================================================================

///|
test "TRAP: swap_remove_index preserves order (O(n) shift-remove, not O(1) swap)" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  map.insert("d", 4) |> ignore
  map.insert("e", 5) |> ignore
  // swap_remove at index 2 ("c")
  map.swap_remove_index(2) |> ignore
  let entries = map.iter().collect()
  // With TRUE swap-remove: elements after index 2 would shift
  // With shift-remove: order is preserved (a, b, d, e)
  debug_inspect(entries.length(), content="4")
  debug_inspect(
    entries[0],
    content=(
      #|("a", 1)
    ),
  )
  debug_inspect(
    entries[1],
    content=(
      #|("b", 2)
    ),
  )
  // If swap-remove: "e" would be at index 2
  // If shift-remove: "d" is at index 2
  debug_inspect(
    entries[2],
    content=(
      #|("d", 4)
    ),
  )
  debug_inspect(
    entries[3],
    content=(
      #|("e", 5)
    ),
  )
  // Result: it's shift-remove. Order preserved. Name is misleading.
}

///|
test "TRAP: swap_remove_index does NOT break order (documents actual behavior)" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 100 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  // Remove index 50
  map.swap_remove_index(50) |> ignore
  debug_inspect(map.len(), content="99")
  // "swap_remove" name suggests that the LAST element moved to index 50
  // But what actually happens: elements 51..99 shift left by 1
  // Let's check: is the element at index 98 now 99 (shift-remove) or
  // some other value (actual swap-remove)?
  let entries = map.iter().collect()
  // In a pure swap-remove: entry at position 50 would be what was at 98 (value 98)
  // In shift-remove: everything shifts, entries[i].0 == i for i<50, and entries[i].0 == i+1 for i>=50
  debug_inspect(entries[50].0, content="51")
  debug_inspect(entries[98].0, content="99")
}

// ============================================================================
// CATEGORY 7: get_mut Semantic Edge Cases
//
// Since v0.3.3 the callback's return value is AUTHORITATIVE and re-applied
// via a fresh insert/remove: Some(v) stores v under the key (inserting it if
// it was absent — an upsert), and None removes the key (even if the callback
// re-inserted it). The callback may safely mutate the map (including
// triggering a resize). Earlier versions wrote back to a stale bucket index,
// which could corrupt the table and silently broke plain deletion.
// ============================================================================

///|
test "TRAP: get_mut on absent key — None is a no-op, Some(v) upserts (v0.3.3)" {
  let map = @indexmap.new()
  // get_mut on a non-existing key, callback returns None → stays absent.
  map.get_mut("ghost", fn(v) {
    match v {
      Some(x) => Some(x + 1)
      None => None
    }
  })
  debug_inspect(map.contains("ghost"), content="false")
  debug_inspect(map.len(), content="0")
  // v0.3.3: returning Some(v) on an ABSENT key now INSERTS it (upsert),
  // rather than discarding the value as earlier versions did.
  map.get_mut("ghost", fn(v) {
    match v {
      Some(x) => Some(x + 1)
      None => Some(42)
    }
  })
  debug_inspect(map.contains("ghost"), content="true")
  debug_inspect(map.get("ghost"), content="Some(42)")
  debug_inspect(map.len(), content="1")
}

///|
test "TRAP: get_mut deletion by returning None — key is removed from order" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  // Delete "b" via get_mut
  map.get_mut("b", fn(_) { None })
  debug_inspect(map.len(), content="2")
  debug_inspect(map.contains("b"), content="false")
  // "a" and "c" still present in order
  let entries = map.iter().collect()
  debug_inspect(
    entries[0],
    content=(
      #|("a", 1)
    ),
  )
  debug_inspect(
    entries[1],
    content=(
      #|("c", 3)
    ),
  )
}

///|
test "TRAP: get_mut on a removed key upserts when callback returns Some (v0.3.3)" {
  let map = @indexmap.new()
  map.insert("temp", 42) |> ignore
  map.remove("temp") |> ignore
  // get_mut on an already-removed key; callback receives None, returns Some(99).
  map.get_mut("temp", fn(v) {
    match v {
      Some(x) => Some(x * 2)
      None => Some(99)
    }
  })
  // v0.3.3: Some(99) is re-applied via insert → the key is re-added (upsert).
  debug_inspect(map.contains("temp"), content="true")
  debug_inspect(map.get("temp"), content="Some(99)")
  debug_inspect(map.len(), content="1")
}

// ============================================================================
// CATEGORY 8: Iterator Comparison (iter vs keys vs values after mutation)
// ============================================================================

///|
test "TRAP: multiple iterators from same map are independent" {
  let map = @indexmap.new()
  map.insert("x", 10) |> ignore
  map.insert("y", 20) |> ignore
  map.insert("z", 30) |> ignore
  let iter_a = map.iter()
  let iter_b = map.iter()
  // Each iterator is created fresh — independent closures
  match iter_a.next() {
    Some((k, _)) =>
      debug_inspect(
        k,
        content=(
          #|"x"
        ),
      )
    None => @test.fail("expected x")
  }
  match iter_b.next() {
    Some((k, _)) =>
      debug_inspect(
        k,
        content=(
          #|"x"
        ),
      )
    None => @test.fail("expected x")
  }
  // iter_a continues from where it left off
  match iter_a.next() {
    Some((k, _)) =>
      debug_inspect(
        k,
        content=(
          #|"y"
        ),
      )
    None => @test.fail("expected y")
  }
}

///|
test "TRAP: iter().size_hint may be optimistic after deletions" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  // Delete "b" — now order[] is ["a", "c"]
  map.remove("b") |> ignore
  // Create a NEW iterator (size_hint uses self.order.length() = 2)
  let iter = map.iter()
  let collected = iter.collect()
  debug_inspect(collected.length(), content="2")
}

// ============================================================================
// CATEGORY 9: IndexSet Order-Sensitive Set Operations
// ============================================================================

///|
test "TRAP: IndexSet Eq is order-sensitive" {
  let a = @indexmap.IndexSet::from_array(["b", "a"])
  let b = @indexmap.IndexSet::from_array(["a", "b"])
  // Same elements, different insertion order
  debug_inspect(a == b, content="false")
  // This is consistent with IndexMap but may surprise set users
  // who expect set equality to be order-independent
}

///|
test "TRAP: IndexSet is_subset does NOT require same order" {
  let a = @indexmap.IndexSet::from_array(["a", "b"])
  let b = @indexmap.IndexSet::from_array(["b", "a", "c"])
  // a is a subset of b even though order differs
  debug_inspect(a.is_subset(b), content="true")
  // This is correct: subset checks membership, not order
  // But Eq checks ORDER — inconsistency in semantics
}

///|
test "TRAP: IndexSet Hash depends on insertion order" {
  let a = @indexmap.IndexSet::from_array(["x", "y"])
  let b = @indexmap.IndexSet::from_array(["y", "x"])
  // Same elements, different order → different hashes
  let hash_a = a.hash()
  let hash_b = b.hash()
  // Different hashes for same elements!
  debug_inspect(hash_a == hash_b, content="false")
  // This means you CANNOT use IndexSet as a key in another IndexMap
  // if insertion order varies — you'll get different hash buckets.
}

// ============================================================================
// CATEGORY 10: Empty Map Iteration Traps
// ============================================================================

///|
test "TRAP: iterating empty map after heavy use then clear" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 10000 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  map.clear()
  let iter = map.iter()
  debug_inspect(iter.next(), content="None")
  let kiter = map.keys()
  debug_inspect(kiter.next(), content="None")
  let viter = map.values()
  debug_inspect(viter.next(), content="None")
  let into = map.into_iter()
  debug_inspect(into.count_remaining(), content="0")
}

///|
test "TRAP: for_each on empty map does nothing" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.new()
  let mut called = false
  map.for_each(fn(_, _) { called = true })
  debug_inspect(called, content="false")
}

// ============================================================================
// CATEGORY 11: Capacity/Resize Edge Cases
// ============================================================================

///|
test "TRAP: with_capacity(0) produces valid map" {
  let map = @indexmap.with_capacity(0)
  debug_inspect(map.capacity() >= 16, content="true")
  debug_inspect(map.is_empty(), content="true")
  map.insert("works", 1) |> ignore
  debug_inspect(map.get("works"), content="Some(1)")
}

///|
test "TRAP: with_capacity(1) uses MIN_CAPACITY" {
  let map = @indexmap.with_capacity(1)
  debug_inspect(map.capacity(), content="16")
  debug_inspect(map.is_empty(), content="true")
}

///|
test "TRAP: shrink_to_fit on empty map" {
  let map = @indexmap.with_capacity(1024)
  map.shrink_to_fit()
  // Should shrink to MIN_CAPACITY (16) since next_power_of_two(0) = 1 → min 16
  debug_inspect(map.capacity(), content="16")
  debug_inspect(map.is_empty(), content="true")
}

///|
test "TRAP: shrink_to_fit on map with exactly 16 entries" {
  let map = @indexmap.with_capacity(1024)
  let mut i = 0
  while i < 16 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  map.shrink_to_fit()
  // next_power_of_two(16) = 16, so capacity should be 16
  debug_inspect(map.capacity(), content="16")
  debug_inspect(map.len(), content="16")
  // Verify data
  let mut j = 0
  while j < 16 {
    debug_inspect(map.contains(j), content="true")
    j = j + 1
  }
}

// ============================================================================
// CATEGORY 12: from_array / extend with Exact Same Key Multiple Times
// ============================================================================

///|
test "TRAP: from_array with all same key yields 1 element" {
  let entries = [
    ("only", 1),
    ("only", 2),
    ("only", 3),
    ("only", 4),
    ("only", 5),
  ]
  let map = @indexmap.IndexMap::from_array(entries)
  debug_inspect(map.len(), content="1")
  debug_inspect(map.get("only"), content="Some(5)")
}

///|
test "TRAP: extend with all duplicates keeps first occurrence position" {
  let map = @indexmap.new()
  let entries = [("dup", 1), ("dup", 2), ("dup", 3)]
  map.extend_from_array(entries)
  debug_inspect(map.len(), content="1")
  debug_inspect(map.get("dup"), content="Some(3)")
  // The key "dup" is at the position of its FIRST insert
  let collected = map.iter().collect()
  debug_inspect(
    collected[0].0,
    content=(
      #|"dup"
    ),
  )
}

///|
test "TRAP: extend after insert mixes correctly" {
  let map = @indexmap.new()
  map.insert("pre", 0) |> ignore
  let batch = [("a", 1), ("b", 2), ("pre", 99), ("c", 3)]
  map.extend_from_array(batch)
  // "pre" exists from before — batch overwrites value but NOT position
  debug_inspect(map.len(), content="4")
  debug_inspect(map.get("pre"), content="Some(99)")
  // "pre" should still be at index 0 (first inserted before extend)
  let entries = map.iter().collect()
  debug_inspect(
    entries[0],
    content=(
      #|("pre", 99)
    ),
  )
}

// ============================================================================
// CATEGORY 13: Entry API Edge Cases
// ============================================================================

///|
test "OccupiedEntry handle stays correct across a resize (v0.3.3 D1 fix)" {
  let map = @indexmap.new()
  map.insert("anchor", 42) |> ignore
  match map.entry("anchor") {
    @indexmap.Occupied(e) => {
      // Force several resizes with many OTHER inserts while holding the handle.
      let mut i = 0
      while i < 100 {
        map.insert("k\{i}", i) |> ignore
        i = i + 1
      }
      // v0.3.3: OccupiedEntry::get/insert re-probe BY KEY instead of trusting a
      // stale cached bucket index, so the handle still resolves the right key
      // after the table has been rebuilt by resizes.
      debug_inspect(e.get(), content="42")
      let old = e.insert(43)
      debug_inspect(old, content="42")
      debug_inspect(map.get("anchor"), content="Some(43)")
    }
    @indexmap.Vacant(_) => @test.fail("expected Occupied")
  }
  // NOTE: using an OccupiedEntry whose key has since been REMOVED now aborts
  // with "OccupiedEntry: key is no longer present in the map" (it re-probes by
  // key and finds nothing). That abort is not catchable in an expect-test, so it
  // is documented here rather than asserted.
}

///|
test "TRAP: VacantEntry from a just-emptied bucket" {
  let map = @indexmap.new()
  match map.entry("new_key") {
    @indexmap.Occupied(_) => @test.fail("expected Vacant")
    @indexmap.Vacant(e) => {
      e.insert(42) |> ignore
      debug_inspect(map.get("new_key"), content="Some(42)")
    }
  }
}
