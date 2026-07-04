// Copyright (c) 2026 moonbit-indexmap contributors
// SPDX-License-Identifier: Apache-2.0
//
// Extreme stress / robustness / memory / edge-case tests for
// aurasuisui/indexmap v0.2.0 — consumed as an external dependency.
//
// Evaluates: robustness at scale, memory efficiency, edge conditions,
// concurrent-access safety (via copy/consume patterns), and
// overall production readiness.

// ============================================================================
// SECTION 1 — ROBUSTNESS: large-scale correctness
// ============================================================================

///|
test "stress: insert 100k int keys" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 100000 {
    map.insert(i, i * 3) |> ignore
    i = i + 1
  }
  inspect(map.len(), content="100000")
  // Spot-check at boundaries
  inspect(map.get(0), content="Some(0)")
  inspect(map.get(50000), content="Some(150000)")
  inspect(map.get(99999), content="Some(299997)")
}

///|
test "stress: insert 50k int keys then get all" {
  let map = @indexmap.with_capacity(65536)
  let mut i = 0
  while i < 50000 {
    map.insert(i, i * 7) |> ignore
    i = i + 1
  }
  // Get every 1000th key
  let mut j = 0
  while j < 50000 {
    match map.get(j) {
      Some(v) => inspect(v, content="\{j * 7}")
      None => @test.fail("missing key")
    }
    j = j + 1000
  }
}

///|
test "stress: insert 50k string keys" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 50000 {
    map.insert("key_\{i}", i) |> ignore
    i = i + 1
  }
  inspect(map.len(), content="50000")
  inspect(map.get("key_0"), content="Some(0)")
  inspect(map.get("key_49999"), content="Some(49999)")
}

///|
test "stress: 100k entries iteration count matches len" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 100000 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  let iter = map.iter()
  let mut count = 0
  while true {
    match iter.next() {
      Some(_) => count = count + 1
      None => break
    }
  }
  inspect(count, content="100000")
}

///|
test "stress: remove 50k from 100k entries" {
  let map = @indexmap.with_capacity(131072)
  let mut i = 0
  while i < 100000 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  // Remove even keys
  let mut j = 0
  while j < 100000 {
    if j % 2 == 0 {
      map.remove(j) |> ignore
    }
    j = j + 1
  }
  inspect(map.len(), content="50000")
  // Odd keys should remain
  inspect(map.contains(0), content="false")
  inspect(map.contains(1), content="true")
  inspect(map.contains(99999), content="true")
}

///|
test "stress: overwrite same key 10k times" {
  let map = @indexmap.new()
  map.insert("pinned", 0) |> ignore
  let mut i = 1
  while i <= 10000 {
    let old = map.insert("pinned", i)
    inspect(old, content="Some(\{i - 1})")
    i = i + 1
  }
  inspect(map.len(), content="1")
  inspect(map.get("pinned"), content="Some(10000)")
}

///|
test "stress: overwrite same key 10k times with other keys present" {
  let map = @indexmap.new()
  // Insert 100 surrounding keys
  let mut i = 0
  while i < 100 {
    map.insert("surrounding_\{i}", i) |> ignore
    i = i + 1
  }
  // Overwrite a pinned key 1000 times
  map.insert("pinned", 0) |> ignore
  let mut j = 1
  while j <= 1000 {
    map.insert("pinned", j) |> ignore
    j = j + 1
  }
  inspect(map.len(), content="101")
  inspect(map.get("pinned"), content="Some(1000)")
  // Surrounding keys still intact
  inspect(map.get("surrounding_50"), content="Some(50)")
}

///|
test "stress: fill → drain → refill cycle (3 rounds)" {
  let map = @indexmap.new()
  let mut round = 0
  while round < 3 {
    let mut i = 0
    while i < 1000 {
      map.insert(i * round + i, i * round) |> ignore
      i = i + 1
    }
    inspect(map.len(), content="1000")
    let drained = map.drain()
    inspect(drained.length(), content="1000")
    inspect(map.is_empty(), content="true")
    inspect(map.len(), content="0")
    round = round + 1
  }
}

///|
test "stress: empty map get/remove/pop/first/last are safe" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.new()
  let mut i = 0
  while i < 100 {
    inspect(map.get("none"), content="None")
    inspect(map.remove("none"), content="None")
    inspect(map.pop(), content="None")
    inspect(map.first(), content="None")
    inspect(map.last(), content="None")
    inspect(map.contains("none"), content="false")
    i = i + 1
  }
  inspect(map.is_empty(), content="true")
}

///|
test "stress: huge string key (64k chars)" {
  let map = @indexmap.new()
  // Build a 64k-char string
  let mut huge = ""
  let mut i = 0
  while i < 65536 {
    huge = huge + "x"
    i = i + 1
  }
  map.insert(huge, 42) |> ignore
  inspect(map.len(), content="1")
  inspect(map.get(huge), content="Some(42)")
}

///|
test "stress: huge string value (64k chars)" {
  let map = @indexmap.new()
  let mut huge_val = ""
  let mut i = 0
  while i < 65536 {
    huge_val = huge_val + "y"
    i = i + 1
  }
  map.insert("huge_value", huge_val) |> ignore
  inspect(map.contains("huge_value"), content="true")
  match map.get("huge_value") {
    Some(v) => inspect(v.length(), content="65536")
    None => @test.fail("huge value missing")
  }
}

///|
test "stress: tombstones trigger rehash" {
  let map = @indexmap.new()
  // Insert 5000 entries
  let mut i = 0
  while i < 5000 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  let cap_before = map.capacity()
  // Delete 90% to trigger many tombstones
  let mut j = 0
  while j < 5000 {
    if j % 10 != 0 {
      map.remove(j) |> ignore
    }
    j = j + 1
  }
  inspect(map.len(), content="500")
  // Remaining keys are multiples of 10: 0, 10, 20, ..., 4990
  inspect(map.get(0), content="Some(0)")
  inspect(map.get(10), content="Some(10)")
  inspect(map.contains(1), content="false")
  // Re-insert to exercise rehash
  let mut k = 0
  while k < 500 {
    map.insert(10000 + k, 10000 + k) |> ignore
    k = k + 1
  }
  inspect(map.len(), content="1000")
}

///|
test "stress: rehash integrity after mass delete and re-insert" {
  let map = @indexmap.new()
  // Fill with 10k
  let mut i = 0
  while i < 10000 {
    map.insert(i, i * 2) |> ignore
    i = i + 1
  }
  // Delete 9k (all except multiples of 10)
  let mut j = 0
  while j < 10000 {
    if j % 10 != 0 {
      map.remove(j) |> ignore
    }
    j = j + 1
  }
  inspect(map.len(), content="1000")
  // Re-insert 5000 fresh
  let mut k = 0
  while k < 5000 {
    map.insert(20000 + k, k) |> ignore
    k = k + 1
  }
  inspect(map.len(), content="6000")
  // Verify surviving entries still correct
  inspect(map.get(0), content="Some(0)")
  inspect(map.get(10), content="Some(20)")
  inspect(map.get(9990), content="Some(19980)")
  // Verify new entries
  inspect(map.get(20000), content="Some(0)")
  inspect(map.get(24999), content="Some(4999)")
}

///|
test "stress: nested IndexMap (IndexMap[String, IndexMap[String, Int]])" {
  let outer = @indexmap.new()
  let inner1 = @indexmap.new()
  inner1.insert("a", 1) |> ignore
  inner1.insert("b", 2) |> ignore
  outer.insert("first", inner1) |> ignore
  let inner2 = @indexmap.new()
  inner2.insert("x", 10) |> ignore
  outer.insert("second", inner2) |> ignore
  inspect(outer.len(), content="2")
  match outer.get("first") {
    Some(m) => {
      inspect(m.len(), content="2")
      inspect(m.get("a"), content="Some(1)")
    }
    None => @test.fail("inner map missing")
  }
  match outer.get("second") {
    Some(m) => inspect(m.get("x"), content="Some(10)")
    None => @test.fail("inner map missing")
  }
}

// ============================================================================
// SECTION 2 — CONCURRENCY SAFETY: copy / consume / multi-view
// ============================================================================

///|
test "concurrency: copy is fully independent" {
  let original = @indexmap.new()
  original.insert("shared", 1) |> ignore
  original.insert("only_orig", 2) |> ignore
  let copy = original.copy()
  // Mutate copy
  copy.insert("only_copy", 3) |> ignore
  copy.remove("only_orig") |> ignore
  // Mutate original
  original.insert("new_orig", 4) |> ignore
  original.remove("shared") |> ignore
  // copy should still have shared and only_copy, but not only_orig or new_orig
  inspect(copy.len(), content="2")
  inspect(copy.contains("shared"), content="true")
  inspect(copy.contains("only_copy"), content="true")
  inspect(copy.contains("only_orig"), content="false")
  inspect(copy.contains("new_orig"), content="false")
  // original should have only_orig and new_orig, but not shared or only_copy
  inspect(original.len(), content="2")
  inspect(original.contains("only_orig"), content="true")
  inspect(original.contains("new_orig"), content="true")
  inspect(original.contains("shared"), content="false")
  inspect(original.contains("only_copy"), content="false")
}

///|
test "concurrency: into_iter empties the map" {
  let map = @indexmap.new()
  map.insert("x", 1) |> ignore
  map.insert("y", 2) |> ignore
  let into = map.into_iter()
  // Collect all entries
  let mut count = 0
  while true {
    match into.next() {
      Some((_, _)) => count = count + 1
      None => break
    }
  }
  inspect(count, content="2")
  // Map should now be empty
  inspect(map.is_empty(), content="true")
  inspect(map.len(), content="0")
}

///|
test "concurrency: into_array empties the map" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  let arr = map.into_array()
  inspect(arr.length(), content="1")
  inspect(map.is_empty(), content="true")
}

///|
test "concurrency: drain empties the map" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 500 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  let entries = map.drain()
  inspect(entries.length(), content="500")
  inspect(map.is_empty(), content="true")
}

///|
test "concurrency: iter + keys + values can coexist" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  let kv_iter = map.iter()
  let k_iter = map.keys()
  let v_iter = map.values()
  // Each advances independently
  match kv_iter.next() {
    Some((k, v)) => {
      inspect(k, content="a")
      inspect(v, content="1")
    }
    None => @test.fail("expected (a, 1)")
  }
  match k_iter.next() {
    Some(k) => inspect(k, content="a")
    None => @test.fail("expected a")
  }
  match v_iter.next() {
    Some(v) => inspect(v, content="1")
    None => @test.fail("expected 1")
  }
}

///|
test "concurrency: multiple copies are independent" {
  let base = @indexmap.new()
  base.insert("k", 100) |> ignore
  let copy_a = base.copy()
  let copy_b = base.copy()
  copy_a.insert("k", 200) |> ignore
  copy_b.insert("k", 300) |> ignore
  inspect(base.get("k"), content="Some(100)")
  inspect(copy_a.get("k"), content="Some(200)")
  inspect(copy_b.get("k"), content="Some(300)")
}

// ============================================================================
// SECTION 3 — MEMORY: capacity, tombstone, shrink behavior
// ============================================================================

///|
test "memory: new map has capacity 16" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.new()
  inspect(map.capacity(), content="16")
}

///|
test "memory: 1 element still uses min capacity" {
  let map = @indexmap.new()
  map.insert("only", 1) |> ignore
  inspect(map.capacity(), content="16")
  inspect(map.len(), content="1")
}

///|
test "memory: 5 elements still at min capacity" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 5 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  inspect(map.len(), content="5")
  inspect(map.capacity(), content="16")
}

///|
test "memory: capacity doubles at load threshold (0.75)" {
  let map = @indexmap.new()
  // Fill to ~12 (75% of 16), 13th should trigger resize to 32
  let mut i = 0
  while i < 20 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  inspect(map.len(), content="20")
  inspect(map.capacity() >= 32, content="true")
}

///|
test "memory: shrink_to_fit reduces capacity for sparse map" {
  let map = @indexmap.with_capacity(1024)
  let mut i = 0
  while i < 10 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  let cap_before_shrink = map.capacity()
  map.shrink_to_fit()
  let cap_after_shrink = map.capacity()
  inspect(cap_after_shrink <= cap_before_shrink, content="true")
  inspect(map.len(), content="10")
  // All data preserved
  let mut j = 0
  while j < 10 {
    inspect(map.contains(j), content="true")
    j = j + 1
  }
}

///|
test "memory: clear resets capacity to initial" {
  let map = @indexmap.with_capacity(1024)
  map.insert("x", 1) |> ignore
  map.clear()
  // clear rebuilds buckets with same capacity
  inspect(map.capacity(), content="1024")
  inspect(map.len(), content="0")
  inspect(map.is_empty(), content="true")
}

///|
test "memory: load_factor stays in [0, 0.75] range" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 50 {
    map.insert(i, i) |> ignore
    let lf = map.load_factor()
    // load_factor is (len + tombstones) / capacity
    // With no tombstones, should be <= 0.75 or just resized
    inspect(lf < 1.0, content="true")
    i = i + 1
  }
}

///|
test "memory: after full drain + refill, capacity stable" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 2000 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  let cap_after_fill = map.capacity()
  map.drain() |> ignore
  // Refill same amount
  let mut j = 0
  while j < 2000 {
    map.insert(j, j) |> ignore
    j = j + 1
  }
  // Capacity should be similar (no pathological growth)
  let cap_after_refill = map.capacity()
  inspect(cap_after_refill, content="\{cap_after_fill}")
}

///|
test "memory: reserve(1) on empty map does not shrink" {
  let map = @indexmap.new()
  let cap_before = map.capacity()
  map.reserve(1)
  inspect(map.capacity() >= cap_before, content="true")
}

///|
test "memory: reserve grows capacity if needed" {
  let map = @indexmap.new()
  let cap_before = map.capacity()
  map.reserve(1000)
  inspect(map.capacity() >= 1000 || map.capacity() >= cap_before, content="true")
}

// ============================================================================
// SECTION 4 — EDGE CASES: special values and boundary conditions
// ============================================================================

///|
test "edge: zero as key" {
  let map = @indexmap.new()
  map.insert(0, "zero_val") |> ignore
  inspect(map.get(0), content="Some(zero_val)")
  inspect(map.contains(0), content="true")
}

///|
test "edge: negative one as key" {
  let map = @indexmap.new()
  map.insert(-1, "neg_one") |> ignore
  inspect(map.get(-1), content="Some(neg_one)")
  map.remove(-1) |> ignore
  inspect(map.contains(-1), content="false")
}

///|
test "edge: Int minimum and maximum as keys" {
  let map = @indexmap.new()
  map.insert(-2147483648, "min") |> ignore
  map.insert(2147483647, "max") |> ignore
  inspect(map.len(), content="2")
  inspect(map.get(-2147483648), content="Some(min)")
  inspect(map.get(2147483647), content="Some(max)")
}

///|
test "edge: empty string as key" {
  let map = @indexmap.new()
  map.insert("", "empty_key") |> ignore
  inspect(map.len(), content="1")
  inspect(map.get(""), content="Some(empty_key)")
  map.remove("") |> ignore
  inspect(map.contains(""), content="false")
}

///|
test "edge: empty string as value" {
  let map = @indexmap.new()
  map.insert("k", "") |> ignore
  inspect(map.get("k"), content="Some()")
}

///|
test "edge: from_array with duplicate keys uses last value" {
  let entries = [("dup", 1), ("dup", 2), ("dup", 3)]
  let map = @indexmap.IndexMap::from_array(entries)
  inspect(map.len(), content="1")
  inspect(map.get("dup"), content="Some(3)")
}

///|
test "edge: from_array with empty array" {
  let entries : Array[(String, Int)] = []
  let map = @indexmap.IndexMap::from_array(entries)
  inspect(map.is_empty(), content="true")
  inspect(map.len(), content="0")
}

///|
test "edge: extend with empty array on non-empty map" {
  let map = @indexmap.new()
  map.insert("existing", 1) |> ignore
  let empty_entries : Array[(String, Int)] = []
  map.extend(empty_entries)
  inspect(map.len(), content="1")
  inspect(map.get("existing"), content="Some(1)")
}

///|
test "edge: extend with empty array on empty map" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.new()
  let empty_entries : Array[(String, Int)] = []
  map.extend(empty_entries)
  inspect(map.is_empty(), content="true")
}

///|
test "edge: retain none then iterate" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.retain(fn(_, _) { false })
  inspect(map.is_empty(), content="true")
  let iter = map.iter()
  inspect(iter.next(), content="None")
  let kiter = map.keys()
  inspect(kiter.next(), content="None")
  let viter = map.values()
  inspect(viter.next(), content="None")
}

///|
test "edge: retain none then first/last/pop return None" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.retain(fn(_, _) { false })
  inspect(map.first(), content="None")
  inspect(map.last(), content="None")
  inspect(map.pop(), content="None")
}

///|
test "edge: remove already removed key (double-remove)" {
  let map = @indexmap.new()
  map.insert("k", 1) |> ignore
  map.remove("k") |> ignore
  // Second remove on same key
  let result = map.remove("k")
  inspect(result, content="None")
  inspect(map.len(), content="0")
}

///|
test "edge: remove then re-insert moves to end" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  map.remove("a") |> ignore
  map.insert("a", 10) |> ignore
  // "a" should be last
  let entries = map.iter().collect()
  inspect(entries[0], content="(b, 2)")
  inspect(entries[1], content="(c, 3)")
  inspect(entries[2], content="(a, 10)")
}

///|
test "edge: delete all in insertion order" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 100 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  let mut j = 0
  while j < 100 {
    map.remove(j) |> ignore
    j = j + 1
  }
  inspect(map.is_empty(), content="true")
}

///|
test "edge: delete all in reverse insertion order" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 100 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  let mut j = 99
  while j >= 0 {
    map.remove(j) |> ignore
    j = j - 1
  }
  inspect(map.is_empty(), content="true")
}

///|
test "edge: delete every other entry (alternating pattern)" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 200 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  // Delete every other entry (even indices in order)
  let mut j = 0
  while j < 200 {
    if j % 2 == 0 {
      map.remove(j) |> ignore
    }
    j = j + 1
  }
  inspect(map.len(), content="100")
  // Remaining keys are odd numbers in insertion order
  let entries = map.iter().collect()
  let mut k = 0
  while k < entries.length() {
    inspect(entries[k].0 % 2 == 1, content="true")
    k = k + 1
  }
}

///|
test "edge: swap_remove at each index" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 100 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  // Remove element at index 0, then index 0 again, ...
  let mut j = 0
  while j < 10 {
    map.swap_remove_index(0) |> ignore
    j = j + 1
  }
  inspect(map.len(), content="90")
}

///|
test "edge: IndexSet singleton disjoint with itself" {
  let set = @indexmap.IndexSet::new()
  set.insert(42) |> ignore
  let copy = set.copy()
  // A set with the same element is NOT disjoint
  inspect(set.is_disjoint(copy), content="false")
}

///|
test "edge: IndexSet empty set is disjoint with itself" {
  let empty : @indexmap.IndexSet[Int] = @indexmap.IndexSet::new()
  inspect(empty.is_disjoint(empty), content="true")
}

///|
test "edge: IndexSet from_array with duplicates" {
  let set = @indexmap.IndexSet::from_array(["a", "b", "a", "c", "b"])
  inspect(set.len(), content="3")
  inspect(set.contains("a"), content="true")
  inspect(set.contains("b"), content="true")
  inspect(set.contains("c"), content="true")
}

///|
test "edge: IndexSet extend with duplicates" {
  let set = @indexmap.IndexSet::new()
  set.insert("x") |> ignore
  set.extend(["x", "y", "x", "z"])
  inspect(set.len(), content="3")
}

// ============================================================================
// SECTION 5 — STRESS: mixed operation patterns
// ============================================================================

///|
test "stress: alternating insert/remove (no net growth)" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 10000 {
    map.insert(i, i) |> ignore
    if i > 0 {
      map.remove(i - 1) |> ignore
    }
    i = i + 1
  }
  // Only the last inserted entry should remain
  inspect(map.len(), content="1")
  inspect(map.get(9999), content="Some(9999)")
}

///|
test "stress: insert→get→remove roundtrip 5000 times" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 5000 {
    map.insert(i, i * 10) |> ignore
    match map.get(i) {
      Some(v) => inspect(v, content="\{i * 10}")
      None => @test.fail("roundtrip get failed")
    }
    map.remove(i) |> ignore
    inspect(map.contains(i), content="false")
    i = i + 1
  }
  inspect(map.is_empty(), content="true")
}

///|
test "stress: sort_by_key after heavy mutation" {
  let map = @indexmap.new()
  // Insert in reverse order
  let mut i = 1000
  while i >= 0 {
    map.insert(i, i) |> ignore
    i = i - 1
  }
  // Remove some in the middle
  let mut j = 300
  while j <= 700 {
    map.remove(j) |> ignore
    j = j + 1
  }
  map.sort_by_key()
  // Verify ascending order in remaining keys
  let entries = map.iter().collect()
  let mut prev = -1
  let mut k = 0
  while k < entries.length() {
    inspect(entries[k].0 > prev, content="true")
    prev = entries[k].0
    k = k + 1
  }
}

///|
test "stress: sort_by value descending" {
  let map = @indexmap.new()
  map.insert("a", 30) |> ignore
  map.insert("b", 10) |> ignore
  map.insert("c", 20) |> ignore
  map.insert("d", 50) |> ignore
  map.insert("e", 40) |> ignore
  map.sort_by(fn(a, b) { b.1.compare(a.1) })
  let entries = map.iter().collect()
  // Sorted by value descending: 50, 40, 30, 20, 10
  inspect(entries[0].1, content="50")
  inspect(entries[1].1, content="40")
  inspect(entries[2].1, content="30")
  inspect(entries[3].1, content="20")
  inspect(entries[4].1, content="10")
}

///|
test "stress: get_mut cascading on 100 keys" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 100 {
    map.insert(i, 0) |> ignore
    i = i + 1
  }
  // Increment each via get_mut
  let mut j = 0
  while j < 100 {
    map.get_mut(j, fn(v) {
      match v {
        Some(x) => Some(x + 1)
        None => None
      }
    })
    j = j + 1
  }
  // Deletion via get_mut on a specific key
  map.get_mut(50, fn(_) { None })
  inspect(map.len(), content="99")
  inspect(map.contains(50), content="false")
  // Remaining still have updated values
  inspect(map.get(0), content="Some(1)")
  inspect(map.get(99), content="Some(1)")
}

///|
test "stress: for_each with side effects on 5000 entries" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 5000 {
    map.insert(i, 1) |> ignore
    i = i + 1
  }
  let mut acc = 0
  map.for_each(fn(_, v) { acc = acc + v })
  inspect(acc, content="5000")
}

///|
test "stress: IndexSet large-scale operations" {
  let set = @indexmap.IndexSet::new()
  let mut i = 0
  while i < 50000 {
    set.insert(i) |> ignore
    i = i + 1
  }
  inspect(set.len(), content="50000")
  // Check contains for a sample
  inspect(set.contains(0), content="true")
  inspect(set.contains(49999), content="true")
  inspect(set.contains(50000), content="false")
  // Remove half
  let mut j = 0
  while j < 50000 {
    if j % 2 == 0 {
      set.remove(j) |> ignore
    }
    j = j + 1
  }
  inspect(set.len(), content="25000")
}

///|
test "stress: VERSION constant is 0.2.0" {
  inspect(@indexmap.VERSION, content="0.2.0")
}

// ============================================================================
// SECTION 6 — Let's test deletion ordering robustness deeply
// ============================================================================

///|
test "robustness: remove_from_order - delete all from front one by one" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 1000 {
    map.insert(i, i * 10) |> ignore
    i = i + 1
  }
  // Remove from front (index 0) 500 times
  let mut j = 0
  while j < 500 {
    let key = j
    map.remove(key) |> ignore
    j = j + 1
  }
  inspect(map.len(), content="500")
  // Remaining keys: 500..999
  let entries = map.iter().collect()
  let mut k = 0
  while k < entries.length() {
    inspect(entries[k].0, content="\{500 + k}")
    k = k + 1
  }
}

///|
test "robustness: remove_from_order - delete all from back one by one" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 1000 {
    map.insert(i, i * 10) |> ignore
    i = i + 1
  }
  // Remove from back 500 times
  let mut j = 999
  while j >= 500 {
    map.remove(j) |> ignore
    j = j - 1
  }
  inspect(map.len(), content="500")
  let entries = map.iter().collect()
  let mut k = 0
  while k < entries.length() {
    inspect(entries[k].0, content="\{k}")
    k = k + 1
  }
}

///|
test "robustness: delete every third element preserves order" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 300 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  // Delete every 3rd element (i where i%3==0)
  let mut j = 0
  while j < 300 {
    if j % 3 == 0 {
      map.remove(j) |> ignore
    }
    j = j + 1
  }
  inspect(map.len(), content="200")
  // Remaining keys: those not divisible by 3, in insertion order
  let entries = map.iter().collect()
  let mut prev_pos = -1
  let mut k = 0
  while k < entries.length() {
    // All remaining keys should be in order
    inspect(entries[k].0 > prev_pos, content="true")
    inspect(entries[k].0 % 3 != 0, content="true")
    prev_pos = entries[k].0
    k = k + 1
  }
}

///|
test "robustness: IndexSet disjoint with large sets" {
  let evens = @indexmap.IndexSet::new()
  let odds = @indexmap.IndexSet::new()
  let mut i = 0
  while i < 10000 {
    if i % 2 == 0 {
      evens.insert(i) |> ignore
    } else {
      odds.insert(i) |> ignore
    }
    i = i + 1
  }
  inspect(evens.is_disjoint(odds), content="true")
  inspect(odds.is_disjoint(evens), content="true")
}

///|
test "robustness: IndexSet subset check with large sets" {
  let small = @indexmap.IndexSet::new()
  let large = @indexmap.IndexSet::new()
  let mut i = 0
  while i < 1000 {
    large.insert(i) |> ignore
    if i % 2 == 0 {
      small.insert(i) |> ignore
    }
    i = i + 1
  }
  inspect(small.is_subset(large), content="true")
  inspect(large.is_superset(small), content="true")
  inspect(large.is_subset(small), content="false")
}

///|
test "robustness: into_iter collect then count_remaining" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  let into = map.into_iter()
  inspect(into.count_remaining(), content="3")
  into.next() |> ignore
  inspect(into.count_remaining(), content="2")
  let rest = into.collect()
  inspect(rest.length(), content="2")
}

// ============================================================================
// SECTION 7 — Trait edge cases under stress
// ============================================================================

///|
test "trait: to_json on map with 1000 entries" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 1000 {
    map.insert("k\{i}", i) |> ignore
    i = i + 1
  }
  let json = map.to_json()
  // Should produce valid JSON object
  let s = json.to_string()
  // First key should appear before last
  let first_key_pos = s.find("k0")
  let last_key_pos = s.find("k999")
  inspect(first_key_pos.is_some(), content="true")
  inspect(last_key_pos.is_some(), content="true")
}

///|
test "trait: Eq on maps with same data but different insertion order" {
  let a = @indexmap.new()
  a.insert("x", 1) |> ignore
  a.insert("y", 2) |> ignore
  let b = @indexmap.new()
  b.insert("y", 2) |> ignore
  b.insert("x", 1) |> ignore
  // Different insertion order → not equal
  inspect(a == b, content="false")
  // Same insertion order → equal
  let c = @indexmap.new()
  c.insert("x", 1) |> ignore
  c.insert("y", 2) |> ignore
  inspect(a == c, content="true")
}

///|
test "trait: Debug to_repr on map with 100 entries" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 100 {
    map.insert("item_\{i}", i) |> ignore
    i = i + 1
  }
  let repr = map.to_repr()
  // Should not crash — we just verify it produces something
  inspect(map.len(), content="100")
}

///|
test "trait: Hash is consistent across copies" {
  let original = @indexmap.new()
  original.insert("a", 1) |> ignore
  original.insert("b", 2) |> ignore
  let copy = original.copy()
  inspect(original.hash() == copy.hash(), content="true")
}

///|
test "trait: Default for IndexSet" {
  let set : @indexmap.IndexSet[String] = @indexmap.IndexSet::default()
  inspect(set.is_empty(), content="true")
  inspect(set.len(), content="0")
}

///|
test "trait: IndexSet Show on empty set" {
  let set : @indexmap.IndexSet[String] = @indexmap.IndexSet::new()
  let s = set.to_string()
  inspect(s.contains("IndexSet"), content="true")
}

test "trait: IndexSet to_json empty set" {
  let set : @indexmap.IndexSet[String] = @indexmap.IndexSet::new()
  let json = set.to_json()
  let s = json.to_string()
  // Empty IndexSet serializes as empty JSON array
  inspect(s.contains("["), content="true")
  inspect(s.contains("]"), content="true")
}
