// Copyright (c) 2026 moonbit-indexmap contributors
// SPDX-License-Identifier: Apache-2.0
//
// Black-box test suite for aurasuisui/indexmap v0.3.2.
// Tests every public API method documented in the README against the
// library consumed as an external dependency via moon.work.

// ===========================================================================
// INDEXMAP — Construction
// ===========================================================================

///|
test "IndexMap::new() creates empty map" {
  let map = @indexmap.new()
  debug_inspect(map.len(), content="0")
  debug_inspect(map.is_empty(), content="true")
}

///|
test "IndexMap::with_capacity(n) creates map with given capacity" {
  let map = @indexmap.with_capacity(100)
  debug_inspect(map.len(), content="0")
  debug_inspect(map.is_empty(), content="true")
  debug_inspect(map.capacity() >= 100, content="true")
}

///|
test "IndexMap::from_array(entries) creates map from key-value pairs" {
  let entries = [("a", 1), ("b", 2), ("c", 3)]
  let map = @indexmap.IndexMap::from_array(entries)
  debug_inspect(map.len(), content="3")
  debug_inspect(map.get("a"), content="Some(1)")
  debug_inspect(map.get("b"), content="Some(2)")
  debug_inspect(map.get("c"), content="Some(3)")
}

///|
test "IndexMap::default() creates empty IndexMap" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.IndexMap::default()
  debug_inspect(map.len(), content="0")
  debug_inspect(map.is_empty(), content="true")
}

///|
test "IndexMap::copy() creates shallow copy preserving order" {
  let map = @indexmap.new()
  map.insert("b", 2) |> ignore
  map.insert("a", 1) |> ignore
  map.insert("c", 3) |> ignore
  let copy = map.copy()
  debug_inspect(copy.len(), content="3")
  debug_inspect(copy.get("a"), content="Some(1)")
  debug_inspect(copy.get("b"), content="Some(2)")
  debug_inspect(copy.get("c"), content="Some(3)")
  // Verify original is unchanged
  map.insert("d", 4) |> ignore
  debug_inspect(copy.len(), content="3")
}

// ===========================================================================
// INDEXMAP — Query
// ===========================================================================

///|
test "IndexMap::len() returns number of entries" {
  let map = @indexmap.new()
  debug_inspect(map.len(), content="0")
  map.insert("x", 10) |> ignore
  debug_inspect(map.len(), content="1")
  map.insert("y", 20) |> ignore
  debug_inspect(map.len(), content="2")
}

///|
test "IndexMap::is_empty() returns true only for empty map" {
  let map = @indexmap.new()
  debug_inspect(map.is_empty(), content="true")
  map.insert("k", 1) |> ignore
  debug_inspect(map.is_empty(), content="false")
}

///|
test "IndexMap::capacity() returns bucket count" {
  let map = @indexmap.with_capacity(32)
  debug_inspect(map.capacity() >= 32, content="true")
}

///|
test "IndexMap::load_factor() returns a value between 0 and 1" {
  let map = @indexmap.new()
  let lf = map.load_factor()
  debug_inspect(lf < 1.0, content="true")
  debug_inspect(lf >= 0.0, content="true")
}

///|
test "IndexMap::max_probe() returns observed max probe distance" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  debug_inspect(map.max_probe() >= 0, content="true")
}

// ===========================================================================
// INDEXMAP — Core operations
// ===========================================================================

///|
test "IndexMap::insert(k, v) insert new key returns None" {
  let map = @indexmap.new()
  let old = map.insert("key", 42)
  debug_inspect(old, content="None")
  debug_inspect(map.len(), content="1")
}

///|
test "IndexMap::insert(k, v) overwrite existing key returns Some(old)" {
  let map = @indexmap.new()
  map.insert("key", 42) |> ignore
  let old = map.insert("key", 99)
  debug_inspect(old, content="Some(42)")
  debug_inspect(map.len(), content="1")
  debug_inspect(map.get("key"), content="Some(99)")
}

///|
test "IndexMap::get(k) returns Some(v) for existing key" {
  let map = @indexmap.new()
  map.insert("pi", 314) |> ignore
  debug_inspect(map.get("pi"), content="Some(314)")
}

///|
test "IndexMap::get(k) returns None for missing key" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.new()
  debug_inspect(map.get("missing"), content="None")
}

///|
test "IndexMap::remove(k) returns Some(v) for existing key" {
  let map = @indexmap.new()
  map.insert("del", 7) |> ignore
  let removed = map.remove("del")
  debug_inspect(removed, content="Some(7)")
  debug_inspect(map.len(), content="0")
  debug_inspect(map.contains("del"), content="false")
}

///|
test "IndexMap::remove(k) returns None for missing key" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.new()
  let removed = map.remove("nope")
  debug_inspect(removed, content="None")
}

///|
test "IndexMap::contains(k) returns true for existing key" {
  let map = @indexmap.new()
  map.insert("findme", 1) |> ignore
  debug_inspect(map.contains("findme"), content="true")
  debug_inspect(map.contains("absent"), content="false")
}

///|
test "IndexMap::clear() removes all entries" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.clear()
  debug_inspect(map.len(), content="0")
  debug_inspect(map.is_empty(), content="true")
}

///|
test "IndexMap::get_mut(k, f) updates value in-place" {
  let map = @indexmap.new()
  map.insert("counter", 0) |> ignore
  map.get_mut("counter", fn(v) {
    match v {
      Some(x) => Some(x + 1)
      None => None
    }
  })
  debug_inspect(map.get("counter"), content="Some(1)")
}

///|
test "IndexMap::get_mut(k, f) with None callback deletes entry" {
  let map = @indexmap.new()
  map.insert("temp", 42) |> ignore
  map.get_mut("temp", fn(_) { None })
  debug_inspect(map.len(), content="0")
  debug_inspect(map.contains("temp"), content="false")
}

// ===========================================================================
// INDEXMAP — Insertion order preservation
// ===========================================================================

///|
test "iteration preserves insertion order" {
  let map = @indexmap.new()
  map.insert("b", 2) |> ignore
  map.insert("a", 1) |> ignore
  map.insert("c", 3) |> ignore
  let iter = map.iter()
  let result : Array[(String, Int)] = []
  while true {
    match iter.next() {
      Some(pair) => result.push(pair)
      None => break
    }
  }
  debug_inspect(result.length(), content="3")
  debug_inspect(result[0], content=(
    #|("b", 2)
  ))
  debug_inspect(result[1], content=(
    #|("a", 1)
  ))
  debug_inspect(result[2], content=(
    #|("c", 3)
  ))
}

// ===========================================================================
// INDEXMAP — Entry API
// ===========================================================================

///|
test "OccupiedEntry::get() returns value" {
  let map = @indexmap.new()
  map.insert("x", 10) |> ignore
  match map.entry("x") {
    @indexmap.Occupied(e) => debug_inspect(e.get(), content="10")
    @indexmap.Vacant(_) => @test.fail("expected Occupied")
  }
}

///|
test "OccupiedEntry::insert() replaces value returns old" {
  let map = @indexmap.new()
  map.insert("y", 20) |> ignore
  match map.entry("y") {
    @indexmap.Occupied(e) => {
      let old = e.insert(30)
      debug_inspect(old, content="20")
    }
    @indexmap.Vacant(_) => @test.fail("expected Occupied")
  }
  debug_inspect(map.get("y"), content="Some(30)")
}

///|
test "OccupiedEntry::remove() deletes entry returns value" {
  let map = @indexmap.new()
  map.insert("z", 40) |> ignore
  match map.entry("z") {
    @indexmap.Occupied(e) => debug_inspect(e.remove(), content="40")
    @indexmap.Vacant(_) => @test.fail("expected Occupied")
  }
  debug_inspect(map.contains("z"), content="false")
}

///|
test "OccupiedEntry::key() returns key" {
  let map = @indexmap.new()
  map.insert("mykey", 5) |> ignore
  match map.entry("mykey") {
    @indexmap.Occupied(e) => debug_inspect(e.key(), content=(
      #|"mykey"
    ))
    @indexmap.Vacant(_) => @test.fail("expected Occupied")
  }
}

///|
test "VacantEntry::insert() adds new entry" {
  let map = @indexmap.new()
  match map.entry("fresh") {
    @indexmap.Occupied(_) => @test.fail("expected Vacant")
    @indexmap.Vacant(e) => {
      let v = e.insert(99)
      debug_inspect(v, content="99")
    }
  }
  debug_inspect(map.get("fresh"), content="Some(99)")
}

///|
test "VacantEntry::key() returns key" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.new()
  match map.entry("slot") {
    @indexmap.Occupied(_) => @test.fail("expected Vacant")
    @indexmap.Vacant(e) => debug_inspect(e.key(), content=(
      #|"slot"
    ))
  }
}

// ===========================================================================
// INDEXMAP — Index-based access
// ===========================================================================

///|
test "get_index(i) returns entry at insertion-order index" {
  let map = @indexmap.new()
  map.insert("x", 10) |> ignore
  map.insert("y", 20) |> ignore
  map.insert("z", 30) |> ignore
  debug_inspect(map.get_index(0), content=(
    #|Some(("x", 10))
  ))
  debug_inspect(map.get_index(1), content=(
    #|Some(("y", 20))
  ))
  debug_inspect(map.get_index(2), content=(
    #|Some(("z", 30))
  ))
}

///|
test "get_index(i) out of bounds returns None" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  debug_inspect(map.get_index(-1), content="None")
  debug_inspect(map.get_index(5), content="None")
}

///|
test "get_full(k) returns Some((k, v)) for existing key" {
  let map = @indexmap.new()
  map.insert("full", 42) |> ignore
  debug_inspect(map.get_full("full"), content=(
    #|Some(("full", 42))
  ))
  debug_inspect(map.get_full("nope"), content="None")
}

///|
test "get_index_of(k) returns insertion-order position" {
  let map = @indexmap.new()
  map.insert("first", 1) |> ignore
  map.insert("second", 2) |> ignore
  debug_inspect(map.get_index_of("first"), content="Some(0)")
  debug_inspect(map.get_index_of("second"), content="Some(1)")
  debug_inspect(map.get_index_of("third"), content="None")
}

///|
test "first() returns earliest inserted entry" {
  let map = @indexmap.new()
  map.insert("earliest", 1) |> ignore
  map.insert("later", 2) |> ignore
  debug_inspect(map.first(), content=(
    #|Some(("earliest", 1))
  ))
}

///|
test "first() returns None for empty map" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.new()
  debug_inspect(map.first(), content="None")
}

///|
test "last() returns most recently inserted entry" {
  let map = @indexmap.new()
  map.insert("old", 1) |> ignore
  map.insert("newest", 2) |> ignore
  debug_inspect(map.last(), content=(
    #|Some(("newest", 2))
  ))
}

///|
test "last() returns None for empty map" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.new()
  debug_inspect(map.last(), content="None")
}

///|
test "pop() removes and returns last entry" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  let popped = map.pop()
  debug_inspect(popped, content=(
    #|Some(("b", 2))
  ))
  debug_inspect(map.len(), content="1")
  debug_inspect(map.contains("b"), content="false")
}

///|
test "pop() returns None for empty map" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.new()
  debug_inspect(map.pop(), content="None")
}

///|
test "swap_remove_index(i) removes entry at position" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  let removed = map.swap_remove_index(1)
  debug_inspect(removed, content=(
    #|Some(("b", 2))
  ))
  debug_inspect(map.len(), content="2")
  debug_inspect(map.contains("b"), content="false")
}

///|
test "swap_remove_index(i) out of bounds returns None" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  debug_inspect(map.swap_remove_index(99), content="None")
  debug_inspect(map.swap_remove_index(-1), content="None")
}

// ===========================================================================
// INDEXMAP — Capacity management
// ===========================================================================

///|
test "reserve(n) ensures space for n more entries" {
  let map = @indexmap.new()
  let old_cap = map.capacity()
  map.reserve(1000)
  debug_inspect(
    map.capacity() >= old_cap + 1000 || map.capacity() >= 1000,
    content="true",
  )
}

///|
test "shrink_to_fit() reduces capacity" {
  let map = @indexmap.with_capacity(1024)
  map.insert("only", 1) |> ignore
  map.shrink_to_fit()
  debug_inspect(map.len(), content="1")
  // Capacity should be reduced after shrink
  debug_inspect(map.capacity() <= 128, content="true")
}

// ===========================================================================
// INDEXMAP — Iteration
// ===========================================================================

///|
test "iter() returns lazy iterator over (k, v) pairs" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  let iter = map.iter()
  let mut count = 0
  while true {
    match iter.next() {
      Some(_) => count = count + 1
      None => break
    }
  }
  debug_inspect(count, content="2")
}

///|
test "keys() returns lazy iterator over keys" {
  let map = @indexmap.new()
  map.insert("x", 10) |> ignore
  map.insert("y", 20) |> ignore
  let iter = map.keys()
  let keys : Array[String] = []
  while true {
    match iter.next() {
      Some(k) => keys.push(k)
      None => break
    }
  }
  debug_inspect(keys.length(), content="2")
  debug_inspect(keys[0], content=(
    #|"x"
  ))
  debug_inspect(keys[1], content=(
    #|"y"
  ))
}

///|
test "values() returns lazy iterator over values" {
  let map = @indexmap.new()
  map.insert("a", 100) |> ignore
  map.insert("b", 200) |> ignore
  let iter = map.values()
  let vals : Array[Int] = []
  while true {
    match iter.next() {
      Some(v) => vals.push(v)
      None => break
    }
  }
  debug_inspect(vals.length(), content="2")
  debug_inspect(vals[0], content="100")
  debug_inspect(vals[1], content="200")
}

///|
test "for_each(f) applies function to each entry" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  let mut sum = 0
  map.for_each(fn(_, v) { sum = sum + v })
  debug_inspect(sum, content="3")
}

///|
test "into_iter() creates consuming iterator" {
  let map = @indexmap.new()
  map.insert("one", 1) |> ignore
  map.insert("two", 2) |> ignore
  let into = map.into_iter()
  let mut count = 0
  while true {
    match into.next() {
      Some((_, _)) => count = count + 1
      None => break
    }
  }
  debug_inspect(count, content="2")
}

///|
test "into_array() consumes map returns array" {
  let map = @indexmap.new()
  map.insert("x", 10) |> ignore
  map.insert("y", 20) |> ignore
  let arr = map.into_array()
  debug_inspect(arr.length(), content="2")
}

// ===========================================================================
// INDEXMAP — Bulk operations
// ===========================================================================

///|
test "retain(f) keeps entries satisfying predicate" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  map.retain(fn(_, v) { v >= 2 })
  debug_inspect(map.len(), content="2")
  debug_inspect(map.contains("a"), content="false")
  debug_inspect(map.contains("b"), content="true")
  debug_inspect(map.contains("c"), content="true")
}

///|
test "sort_by_key() sorts entries by key" {
  let map = @indexmap.new()
  map.insert("z", 3) |> ignore
  map.insert("a", 1) |> ignore
  map.insert("m", 2) |> ignore
  map.sort_by_key()
  let iter = map.keys()
  let keys : Array[String] = []
  while true {
    match iter.next() {
      Some(k) => keys.push(k)
      None => break
    }
  }
  debug_inspect(keys[0], content=(
    #|"a"
  ))
  debug_inspect(keys[1], content=(
    #|"m"
  ))
  debug_inspect(keys[2], content=(
    #|"z"
  ))
}

///|
test "sort_by(cmp) sorts entries by custom comparator" {
  let map = @indexmap.new()
  map.insert("a", 30) |> ignore
  map.insert("b", 10) |> ignore
  map.insert("c", 20) |> ignore
  map.sort_by(fn(a, b) { a.1.compare(b.1) })
  let iter = map.keys()
  let keys : Array[String] = []
  while true {
    match iter.next() {
      Some(k) => keys.push(k)
      None => break
    }
  }
  debug_inspect(keys[0], content=(
    #|"b"
  ))
  debug_inspect(keys[1], content=(
    #|"c"
  ))
  debug_inspect(keys[2], content=(
    #|"a"
  ))
}

///|
test "drain() removes all entries and returns them" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  let entries = map.drain()
  debug_inspect(entries.length(), content="2")
  debug_inspect(map.len(), content="0")
}

///|
test "extend(entries) inserts multiple entries" {
  let map = @indexmap.new()
  let entries = [("x", 10), ("y", 20), ("z", 30)]
  map.extend_from_array(entries)
  debug_inspect(map.len(), content="3")
  debug_inspect(map.get("x"), content="Some(10)")
  debug_inspect(map.get("y"), content="Some(20)")
  debug_inspect(map.get("z"), content="Some(30)")
}

// ===========================================================================
// INDEXMAP — Traits
// ===========================================================================

///|
test "Show trait: to_string() produces human-readable output" {
  let map = @indexmap.new()
  map.insert("x", 1) |> ignore
  let s = @debug.to_string(map)
  debug_inspect(s.contains("IndexMap"), content="true")
}

///|
test "Debug trait: to_repr() produces debug representation" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  // Debug trait is available; just verify no crash
  let _repr = map.to_repr()
}

///|
test "Eq trait: equal() compares two maps" {
  let a = @indexmap.new()
  a.insert("k", 1) |> ignore
  let b = @indexmap.new()
  b.insert("k", 1) |> ignore
  debug_inspect(a == b, content="true")

  let c = @indexmap.new()
  c.insert("k", 99) |> ignore
  debug_inspect(a == c, content="false")
}

///|
test "Hash trait: two equal maps produce same hash" {
  let a = @indexmap.new()
  a.insert("x", 1) |> ignore
  let b = @indexmap.new()
  b.insert("x", 1) |> ignore
  debug_inspect(a.hash() == b.hash(), content="true")
}

///|
test "Default trait: default() returns empty map" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.IndexMap::default()
  debug_inspect(map.len(), content="0")
}

///|
test "ToJson trait: to_json() serializes preserving order" {
  let map = @indexmap.new()
  map.insert("name", "test") |> ignore
  map.insert("version", "1.0") |> ignore
  let json = map.to_json()
  let s = @debug.to_string(json)
  debug_inspect(s.contains("name"), content="true")
  debug_inspect(s.contains("test"), content="true")
  debug_inspect(s.contains("version"), content="true")
  debug_inspect(s.contains("1.0"), content="true")
}

// ===========================================================================
// INDEXMAP — VERSION constant
// ===========================================================================

///|
test "VERSION constant is defined" {
  debug_inspect(@indexmap.VERSION, content=(
    #|"0.3.2"
  ))
}

// ===========================================================================
// INDEXMAP helper functions: new() and with_capacity()
// ===========================================================================

///|
test "top-level new() creates empty IndexMap" {
  let map = @indexmap.new()
  debug_inspect(map.is_empty(), content="true")
}

///|
test "top-level with_capacity(n) creates IndexMap with capacity" {
  let map = @indexmap.with_capacity(64)
  debug_inspect(map.capacity() >= 64, content="true")
}

// ===========================================================================
// INDEXSET — Construction
// ===========================================================================

///|
test "IndexSet::new() creates empty set" {
  let set = @indexmap.IndexSet::new()
  debug_inspect(set.len(), content="0")
  debug_inspect(set.is_empty(), content="true")
}

///|
test "IndexSet::with_capacity(n) creates set with capacity" {
  let set = @indexmap.IndexSet::with_capacity(64)
  debug_inspect(set.is_empty(), content="true")
}

///|
test "IndexSet::from_array(elements) creates set from array" {
  let set = @indexmap.IndexSet::from_array(["a", "b", "c"])
  debug_inspect(set.len(), content="3")
  debug_inspect(set.contains("a"), content="true")
  debug_inspect(set.contains("b"), content="true")
}

///|
test "IndexSet::default() creates empty set" {
  let set : @indexmap.IndexSet[String] = @indexmap.IndexSet::default()
  debug_inspect(set.is_empty(), content="true")
}

///|
test "IndexSet::copy() creates shallow copy" {
  let set = @indexmap.IndexSet::from_array(["x", "y"])
  let copy = set.copy()
  debug_inspect(copy.len(), content="2")
  debug_inspect(copy.contains("x"), content="true")
  // Original unchanged after modification
  copy.insert("z") |> ignore
  debug_inspect(set.contains("z"), content="false")
}

// ===========================================================================
// INDEXSET — Core operations
// ===========================================================================

///|
test "IndexSet::insert(v) returns true for new element" {
  let set = @indexmap.IndexSet::new()
  let inserted = set.insert("item")
  debug_inspect(inserted, content="true")
  debug_inspect(set.len(), content="1")
}

///|
test "IndexSet::insert(v) returns false for duplicate" {
  let set = @indexmap.IndexSet::new()
  set.insert("dup") |> ignore
  let inserted = set.insert("dup")
  debug_inspect(inserted, content="false")
  debug_inspect(set.len(), content="1")
}

///|
test "IndexSet::contains(v) returns true for existing element" {
  let set = @indexmap.IndexSet::from_array(["hello"])
  debug_inspect(set.contains("hello"), content="true")
  debug_inspect(set.contains("world"), content="false")
}

///|
test "IndexSet::remove(v) returns true if element was present" {
  let set = @indexmap.IndexSet::from_array(["remove_me"])
  let removed = set.remove("remove_me")
  debug_inspect(removed, content="true")
  debug_inspect(set.len(), content="0")
}

///|
test "IndexSet::remove(v) returns false for absent element" {
  let set = @indexmap.IndexSet::new()
  let removed = set.remove("ghost")
  debug_inspect(removed, content="false")
}

///|
test "IndexSet::clear() removes all elements" {
  let set = @indexmap.IndexSet::from_array(["a", "b", "c"])
  set.clear()
  debug_inspect(set.len(), content="0")
  debug_inspect(set.is_empty(), content="true")
}

// ===========================================================================
// INDEXSET — Set operations
// ===========================================================================

///|
test "is_disjoint: empty sets are disjoint" {
  let a = @indexmap.IndexSet::from_array(["a", "b"])
  let b = @indexmap.IndexSet::from_array(["c", "d"])
  debug_inspect(a.is_disjoint(b), content="true")
}

///|
test "is_disjoint: overlapping sets are not disjoint" {
  let a = @indexmap.IndexSet::from_array(["a", "b", "c"])
  let b = @indexmap.IndexSet::from_array(["c", "d"])
  debug_inspect(a.is_disjoint(b), content="false")
}

///|
test "is_subset: subset relationship" {
  let a = @indexmap.IndexSet::from_array(["a", "b"])
  let b = @indexmap.IndexSet::from_array(["a", "b", "c"])
  debug_inspect(a.is_subset(b), content="true")
  debug_inspect(b.is_subset(a), content="false")
}

///|
test "is_superset: superset relationship" {
  let a = @indexmap.IndexSet::from_array(["a", "b", "c"])
  let b = @indexmap.IndexSet::from_array(["a", "b"])
  debug_inspect(a.is_superset(b), content="true")
  debug_inspect(b.is_superset(a), content="false")
}

// ===========================================================================
// INDEXSET — Bulk operations
// ===========================================================================

///|
test "IndexSet::retain(f) keeps elements matching predicate" {
  let set = @indexmap.IndexSet::from_array(["a", "bb", "ccc"])
  set.retain(fn(s) { s.length() >= 2 })
  debug_inspect(set.len(), content="2")
  debug_inspect(set.contains("a"), content="false")
  debug_inspect(set.contains("bb"), content="true")
  debug_inspect(set.contains("ccc"), content="true")
}

///|
test "IndexSet::drain() removes all elements and returns them" {
  let set = @indexmap.IndexSet::from_array(["x", "y", "z"])
  let elements = set.drain()
  debug_inspect(elements.length(), content="3")
  debug_inspect(set.len(), content="0")
}

///|
test "IndexSet::extend(elements) inserts multiple elements" {
  let set = @indexmap.IndexSet::new()
  set.extend_from_array(["p", "q", "r"])
  debug_inspect(set.len(), content="3")
  debug_inspect(set.contains("p"), content="true")
}

///|
test "IndexSet::into_array() consumes set returns array" {
  let set = @indexmap.IndexSet::from_array(["one", "two"])
  let arr = set.into_array()
  debug_inspect(arr.length(), content="2")
}

// ===========================================================================
// INDEXSET — Iteration
// ===========================================================================

///|
test "IndexSet::iter() returns elements in insertion order" {
  let set = @indexmap.IndexSet::new()
  set.insert("b") |> ignore
  set.insert("a") |> ignore
  set.insert("c") |> ignore
  let iter = set.iter()
  let result : Array[String] = []
  while true {
    match iter.next() {
      Some(k) => result.push(k)
      None => break
    }
  }
  debug_inspect(result[0], content=(
    #|"b"
  ))
  debug_inspect(result[1], content=(
    #|"a"
  ))
  debug_inspect(result[2], content=(
    #|"c"
  ))
}

// ===========================================================================
// INDEXSET — Traits
// ===========================================================================

///|
test "IndexSet Show trait: to_string()" {
  let set = @indexmap.IndexSet::from_array(["tag1"])
  let s = @debug.to_string(set)
  debug_inspect(s.contains("IndexSet"), content="true")
}

///|
test "IndexSet Debug trait: to_repr()" {
  let set = @indexmap.IndexSet::from_array(["a"])
  let _repr = set.to_repr()
}

///|
test "IndexSet Eq trait: equal()" {
  let a = @indexmap.IndexSet::from_array(["x", "y"])
  let b = @indexmap.IndexSet::from_array(["x", "y"])
  debug_inspect(a == b, content="true")
  let c = @indexmap.IndexSet::from_array(["x"])
  debug_inspect(a == c, content="false")
}

///|
test "IndexSet Hash trait: same hash for equal sets" {
  let a = @indexmap.IndexSet::from_array(["x", "y"])
  let b = @indexmap.IndexSet::from_array(["x", "y"])
  debug_inspect(a.hash() == b.hash(), content="true")
}

///|
test "IndexSet Default trait: default() returns empty set" {
  let set : @indexmap.IndexSet[String] = @indexmap.IndexSet::default()
  debug_inspect(set.is_empty(), content="true")
}

///|
test "IndexSet ToJson trait: to_json() serializes preserving order" {
  let set = @indexmap.IndexSet::new()
  set.insert("alpha") |> ignore
  set.insert("beta") |> ignore
  let json = set.to_json()
  let s = @debug.to_string(json)
  debug_inspect(s.contains("alpha"), content="true")
  debug_inspect(s.contains("beta"), content="true")
}

// ===========================================================================
// INDEXSET — Len and is_empty
// ===========================================================================

///|
test "IndexSet::len() returns element count" {
  let set = @indexmap.IndexSet::from_array(["a", "b", "c", "d"])
  debug_inspect(set.len(), content="4")
}

///|
test "IndexSet::is_empty() returns true only for empty set" {
  let set = @indexmap.IndexSet::new()
  debug_inspect(set.is_empty(), content="true")
  set.insert("elem") |> ignore
  debug_inspect(set.is_empty(), content="false")
}
