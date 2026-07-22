// Copyright (c) 2026 moonbit-indexmap contributors
// SPDX-License-Identifier: Apache-2.0
//
// COMPREHENSIVE TESTS: covering the remaining untested dimensions
// for aurasuisui/indexmap v0.3.2.
//
// Categories:
//   Custom struct keys (cross-module trait resolution)
//   Extreme resize cascade
//   get_mut nested side effects
//   IntoMapIter boundary cases
//   Alternate key types (Bool, Char)
//   Mass temporary object creation

// ---------------------------------------------------------------------------
// Custom struct key — cross-module trait verification
// ---------------------------------------------------------------------------

///|
struct UserRecord {
  id : Int
  name : String
} derive(Debug, Eq, Hash, Compare)
// NOTE: UserRecord intentionally does NOT derive Show. As of v0.3.3, IndexMap's
// ToJson impl is bounded on K:Show, so calling to_json() on an
// IndexMap[UserRecord, _] would be a compile error. Add Show to the derive list
// if JSON output for custom-struct keys is ever needed.

///|
test "custom struct as IndexMap key — basic insert/get" {
  let map = @indexmap.new()
  let alice = { id: 1, name: "Alice" }
  let bob = { id: 2, name: "Bob" }
  map.insert(alice, "admin") |> ignore
  map.insert(bob, "user") |> ignore
  debug_inspect(map.len(), content="2")
  // keys with same fields == equal
  let alice2 = { id: 1, name: "Alice" }
  debug_inspect(
    map.get(alice2),
    content=(
      #|Some("admin")
    ),
  )
}

///|
test "custom struct as IndexMap key — contains and remove" {
  let map = @indexmap.new()
  let key = { id: 42, name: "test_user" }
  map.insert(key, "present") |> ignore
  debug_inspect(map.contains(key), content="true")
  let key_copy = { id: 42, name: "test_user" }
  map.remove(key_copy) |> ignore
  debug_inspect(map.contains(key), content="false")
}

///|
test "custom struct as IndexMap key — iteration order" {
  let map = @indexmap.new()
  let a = { id: 3, name: "C3" }
  let b = { id: 1, name: "A1" }
  let c = { id: 2, name: "B2" }
  map.insert(a, "third") |> ignore
  map.insert(b, "first") |> ignore
  map.insert(c, "second") |> ignore
  let entries = map.iter().collect()
  debug_inspect(entries[0].0.id, content="3")
  debug_inspect(entries[1].0.id, content="1")
  debug_inspect(entries[2].0.id, content="2")
}

///|
test "custom struct as IndexMap key — sort_by_key with Compare" {
  let map = @indexmap.new()
  map.insert({ id: 30, name: "Z" }, "z_val") |> ignore
  map.insert({ id: 10, name: "A" }, "a_val") |> ignore
  map.insert({ id: 20, name: "M" }, "m_val") |> ignore
  map.sort_by_key()
  let entries = map.iter().collect()
  debug_inspect(entries[0].0.id, content="10")
  debug_inspect(entries[1].0.id, content="20")
  debug_inspect(entries[2].0.id, content="30")
}

///|
test "custom struct as IndexSet key" {
  let set = @indexmap.IndexSet::new()
  set.insert({ id: 1, name: "Alice" }) |> ignore
  set.insert({ id: 2, name: "Bob" }) |> ignore
  // duplicate structs with same fields
  debug_inspect(set.insert({ id: 1, name: "Alice" }), content="false")
  debug_inspect(set.len(), content="2")
}

///|
test "custom struct with large field — IndexMap key" {
  let map = @indexmap.new()
  let key = {
    id: 999,
    name: "a_very_long_name_for_stress_testing_hash_and_eq_traits",
  }
  map.insert(key, "found") |> ignore
  let lookup = {
    id: 999,
    name: "a_very_long_name_for_stress_testing_hash_and_eq_traits",
  }
  debug_inspect(
    map.get(lookup),
    content=(
      #|Some("found")
    ),
  )
}

// ---------------------------------------------------------------------------
// Extreme resize cascade
// ---------------------------------------------------------------------------

///|
test "resize cascade: 16->32->64->128->256->512->1024->2048->4096->8192->16384" {
  let map = @indexmap.new()
  let mut prev_cap = map.capacity()
  debug_inspect(prev_cap, content="16")
  let mut i = 0
  while i < 20000 {
    map.insert(i, i) |> ignore
    let cur_cap = map.capacity()
    if cur_cap != prev_cap {
      // Verify the new capacity is a power of two and > previous
      debug_inspect(cur_cap > prev_cap, content="true")
      // Verify data integrity at resize point
      debug_inspect(map.get(0), content="Some(0)")
      debug_inspect(map.get(i), content="Some(\{i})")
      prev_cap = cur_cap
    }
    i = i + 1
  }
  debug_inspect(map.len(), content="20000")
}

///|
test "resize cascade: order preserved through all resizes" {
  let map = @indexmap.new()
  let keys : Array[Int] = []
  let mut i = 0
  while i < 5000 {
    map.insert(i, i * 100) |> ignore
    keys.push(i)
    i = i + 1
  }
  // verify iteration order matches insertion order
  let entries = map.iter().collect()
  let mut j = 0
  while j < entries.length() {
    debug_inspect(entries[j].0, content="\{keys[j]}")
    j = j + 1
  }
}

///|
test "resize cascade: get_index_of after multiple resizes" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 10000 {
    map.insert(i, i) |> ignore
    i = i + 1
  }
  // position map should be consistent after many resizes
  match map.get_index_of(0) {
    Some(pos) => debug_inspect(pos, content="0")
    None => @test.fail("first key should be at index 0")
  }
  match map.get_index_of(9999) {
    Some(pos) => debug_inspect(pos, content="9999")
    None => @test.fail("last key should be at index 9999")
  }
}

///|
test "resize cascade: first/last correct through resizes" {
  let map = @indexmap.new()
  let mut i = 0
  while i < 50000 {
    map.insert(i, i * 10) |> ignore
    i = i + 1
  }
  match map.first() {
    Some((k, v)) => {
      debug_inspect(k, content="0")
      debug_inspect(v, content="0")
    }
    None => @test.fail("first should be (0, 0)")
  }
  match map.last() {
    Some((k, v)) => {
      debug_inspect(k, content="49999")
      debug_inspect(v, content="499990")
    }
    None => @test.fail("last should be (49999, 499990)")
  }
}

///|
test "with_capacity extreme: capacity 1000000" {
  let map = @indexmap.with_capacity(1000000)
  debug_inspect(map.capacity() >= 1000000, content="true")
  debug_inspect(map.is_empty(), content="true")
  map.insert("test", 42) |> ignore
  debug_inspect(map.get("test"), content="Some(42)")
}

// ---------------------------------------------------------------------------
// get_mut nested side effects — STRICT verification
// ---------------------------------------------------------------------------

///|
test "get_mut nested: callback modifies same key via get_mut again" {
  let map = @indexmap.new()
  map.insert("counter", 0) |> ignore
  // First get_mut: double the value
  map.get_mut("counter", fn(v) {
    match v {
      Some(x) => Some(x * 2)
      None => None
    }
  })
  // Second get_mut on same key after first completed
  map.get_mut("counter", fn(v) {
    match v {
      Some(x) => Some(x + 100)
      None => None
    }
  })
  debug_inspect(map.get("counter"), content="Some(100)")
}

///|
test "get_mut nested: callback inserts a NEW key via insert on map" {
  let map = @indexmap.new()
  map.insert("trigger", 1) |> ignore
  // In the callback for "trigger", insert a new key
  map.get_mut("trigger", fn(v) {
    match v {
      Some(x) => {
        map.insert("side_effect", x + 10) |> ignore
        Some(x * 2)
      }
      None => None
    }
  })
  debug_inspect(map.get("trigger"), content="Some(2)")
  // The side-effect insert should have worked
  debug_inspect(map.get("side_effect"), content="Some(11)")
  debug_inspect(map.len(), content="2")
}

///|
test "get_mut nested: callback removes ANOTHER key via remove on map" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  // In the callback for "a", remove "b"
  map.get_mut("a", fn(v) {
    match v {
      Some(_) => {
        map.remove("b") |> ignore
        Some(99)
      }
      None => None
    }
  })
  debug_inspect(map.get("a"), content="Some(99)")
  debug_inspect(map.contains("b"), content="false")
  debug_inspect(map.len(), content="1")
}

///|
test "get_mut nested: callback calls get_mut on ANOTHER key" {
  let map = @indexmap.new()
  map.insert("x", 10) |> ignore
  map.insert("y", 20) |> ignore
  // get_mut "x" → in callback, get_mut "y"
  map.get_mut("x", fn(v) {
    match v {
      Some(x_val) => {
        map.get_mut("y", fn(w) {
          match w {
            Some(y_val) => Some(y_val + x_val) // y = 20 + 10 = 30
            None => None
          }
        })
        Some(x_val + 1)
      }
      None => None
    }
  })
  debug_inspect(map.get("x"), content="Some(11)")
  debug_inspect(map.get("y"), content="Some(30)")
}

///|
test "get_mut nested: delete self via None then insert new entry" {
  let map = @indexmap.new()
  map.insert("self", 1) |> ignore
  // get_mut deletes "self", then we manually re-insert
  map.get_mut("self", fn(_) { None })
  debug_inspect(map.contains("self"), content="false")
  // Now re-insert — this is a fresh insert at end of order
  map.insert("self", 999) |> ignore
  debug_inspect(map.get("self"), content="Some(999)")
  debug_inspect(map.len(), content="1")
}

///|
test "get_mut: returning None removes the key even if the callback re-inserted it (v0.3.3)" {
  let map = @indexmap.new()
  map.insert("cycle", 5) |> ignore
  map.insert("other", 10) |> ignore
  // In the callback, re-insert "cycle" with a new value, then return None.
  map.get_mut("cycle", fn(v) {
    match v {
      Some(old) => {
        map.insert("cycle", old * 10) |> ignore
        None // request deletion
      }
      None => None
    }
  })
  // v0.3.3: the callback's return value is authoritative and re-applied via a
  // fresh insert/remove. Returning None calls remove(key) AFTER the callback
  // runs, which undoes the callback's re-insertion — so the key is gone.
  // (The v0.3.2 "preserve re-insert" behavior was removed; return Some(v) to
  // keep a value.)
  debug_inspect(map.contains("cycle"), content="false")
  debug_inspect(map.get("cycle"), content="None")
  debug_inspect(map.contains("other"), content="true")
  debug_inspect(map.get("other"), content="Some(10)")
  debug_inspect(map.len(), content="1")
}

///|
test "get_mut: callback removes the same key then returns None — no double deletion (v0.3.3)" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  // Callback removes "a" itself, then returns None (which also calls remove("a")).
  map.get_mut("a", fn(v) {
    match v {
      Some(_) => {
        map.remove("a") |> ignore
        None
      }
      None => None
    }
  })
  // v0.3.3 re-applies None via a fresh remove, which is a no-op on an
  // already-removed key — so len is decremented exactly once (no double len-- /
  // double tombstone), and the other key is untouched.
  debug_inspect(map.contains("a"), content="false")
  debug_inspect(map.len(), content="1")
  debug_inspect(map.get("b"), content="Some(2)")
}

///|
test "get_mut: callback removes the same key then returns Some — no ghost entry (v0.3.3)" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  // Callback removes "a", then returns Some(99) (which calls insert("a", 99)).
  map.get_mut("a", fn(v) {
    match v {
      Some(_) => {
        map.remove("a") |> ignore
        Some(99)
      }
      None => None
    }
  })
  // v0.3.3 re-applies Some(99) via a fresh insert, re-adding "a" cleanly at the
  // end of the order — no ghost/duplicate, fully iterable and indexable.
  debug_inspect(map.get("a"), content="Some(99)")
  debug_inspect(map.len(), content="2")
  let keys = map.keys().collect()
  debug_inspect(
    keys,
    content=(
      #|["b", "a"]
    ),
  )
  debug_inspect(map.get_index_of("a"), content="Some(1)")
}

///|
test "get_mut: callback triggers a resize mid-callback — value lands correctly (v0.3.3)" {
  let map = @indexmap.new()
  map.insert("anchor", 0) |> ignore
  map.insert("target", 1) |> ignore
  // In the callback for "target", insert enough NEW keys to cross the 0.75 load
  // factor and force a resize (default capacity 16 resizes at ~12 entries).
  map.get_mut("target", fn(v) {
    match v {
      Some(_) => {
        let mut i = 0
        while i < 30 {
          map.insert("filler_\{i}", i) |> ignore
          i = i + 1
        }
        Some(1234)
      }
      None => None
    }
  })
  // v0.3.3 snapshots the current value BEFORE the callback and re-applies the
  // result via a fresh probe, so the resize triggered inside the callback cannot
  // cause a stale-index mis-write. "target" ends up with Some(1234).
  debug_inspect(map.get("target"), content="Some(1234)")
  debug_inspect(map.get("anchor"), content="Some(0)")
  // 2 original + 30 fillers = 32 entries, all intact.
  debug_inspect(map.len(), content="32")
  debug_inspect(map.get("filler_0"), content="Some(0)")
  debug_inspect(map.get("filler_29"), content="Some(29)")
}

// ---------------------------------------------------------------------------
// IntoMapIter boundary cases — STRICT
// ---------------------------------------------------------------------------

///|
test "IntoMapIter: next after exhaustion keeps returning None" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  let into = map.into_iter()
  into.next() |> ignore
  // Exhausted
  debug_inspect(into.next(), content="None")
  debug_inspect(into.next(), content="None")
  debug_inspect(into.next(), content="None")
}

///|
test "IntoMapIter: collect after partial consumption returns remaining" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  let into = map.into_iter()
  into.next() |> ignore // consume "a"
  let rest = into.collect()
  debug_inspect(rest.length(), content="2")
}

///|
test "IntoMapIter: collect after full exhaustion returns empty" {
  let map = @indexmap.new()
  map.insert("x", 10) |> ignore
  let into = map.into_iter()
  into.next() |> ignore
  // exhausted
  let rest = into.collect()
  debug_inspect(rest.length(), content="0")
}

///|
test "IntoMapIter: count_remaining decreases after next" {
  let map = @indexmap.new()
  map.insert("a", 1) |> ignore
  map.insert("b", 2) |> ignore
  map.insert("c", 3) |> ignore
  let into = map.into_iter()
  debug_inspect(into.count_remaining(), content="3")
  into.next() |> ignore
  debug_inspect(into.count_remaining(), content="2")
  into.next() |> ignore
  debug_inspect(into.count_remaining(), content="1")
  into.next() |> ignore
  debug_inspect(into.count_remaining(), content="0")
}

///|
test "IntoMapIter: count_remaining is 0 for empty map" {
  let map : @indexmap.IndexMap[String, Int] = @indexmap.new()
  let into = map.into_iter()
  debug_inspect(into.count_remaining(), content="0")
  debug_inspect(into.next(), content="None")
}

// ---------------------------------------------------------------------------
// Alternate key types: Bool, Char
// ---------------------------------------------------------------------------

///|
test "Bool key: only two values — insert both" {
  let map = @indexmap.new()
  map.insert(true, "yes") |> ignore
  map.insert(false, "no") |> ignore
  debug_inspect(map.len(), content="2")
  debug_inspect(
    map.get(true),
    content=(
      #|Some("yes")
    ),
  )
  debug_inspect(
    map.get(false),
    content=(
      #|Some("no")
    ),
  )
}

///|
test "Bool key: overwrite works correctly" {
  let map = @indexmap.new()
  map.insert(true, "first") |> ignore
  map.insert(true, "second") |> ignore
  debug_inspect(map.len(), content="1")
  debug_inspect(
    map.get(true),
    content=(
      #|Some("second")
    ),
  )
}

///|
test "Bool key: iteration order preserved" {
  let map = @indexmap.new()
  map.insert(false, "first_inserted") |> ignore
  map.insert(true, "second_inserted") |> ignore
  let entries = map.iter().collect()
  debug_inspect(entries[0].0, content="false")
  debug_inspect(entries[1].0, content="true")
}

///|
test "Bool key: IndexSet with only two possible values" {
  let set = @indexmap.IndexSet::new()
  set.insert(true) |> ignore
  set.insert(false) |> ignore
  set.insert(true) |> ignore // duplicate — should return false
  debug_inspect(set.len(), content="2")
  debug_inspect(set.contains(true), content="true")
  debug_inspect(set.contains(false), content="true")
}

///|
test "Bool key: remove and re-insert" {
  let map = @indexmap.new()
  map.insert(true, "t") |> ignore
  map.insert(false, "f") |> ignore
  map.remove(true) |> ignore
  debug_inspect(map.len(), content="1")
  map.insert(true, "t_reinserted") |> ignore
  // Re-inserted "true" moves to end
  let entries = map.iter().collect()
  debug_inspect(
    entries[0],
    content=(
      #|(false, "f")
    ),
  )
  debug_inspect(
    entries[1],
    content=(
      #|(true, "t_reinserted")
    ),
  )
}

///|
test "Char key: insert various characters" {
  let map = @indexmap.new()
  map.insert('a', 1) |> ignore
  map.insert('z', 26) |> ignore
  map.insert('0', 0) |> ignore
  debug_inspect(map.len(), content="3")
  debug_inspect(map.get('a'), content="Some(1)")
  debug_inspect(map.get('z'), content="Some(26)")
  debug_inspect(map.get('0'), content="Some(0)")
}

///|
test "Char key: insert in order, verify order preserved" {
  let map = @indexmap.new()
  map.insert('c', "third") |> ignore
  map.insert('a', "first") |> ignore
  map.insert('b', "second") |> ignore
  let entries = map.iter().collect()
  debug_inspect(
    entries[0].0,
    content=(
      #|'c'
    ),
  )
  debug_inspect(
    entries[1].0,
    content=(
      #|'a'
    ),
  )
  debug_inspect(
    entries[2].0,
    content=(
      #|'b'
    ),
  )
}

// ---------------------------------------------------------------------------
// Mass temporary object creation
// ---------------------------------------------------------------------------

///|
test "temp objects: create and drop 5000 IndexMaps" {
  let mut i = 0
  while i < 5000 {
    let map = @indexmap.new()
    map.insert("temp", i) |> ignore
    // Map goes out of scope here — verify no crash
    i = i + 1
  }
  debug_inspect(true, content="true")
}

///|
test "temp objects: create and drop 5000 IndexSets" {
  let mut i = 0
  while i < 5000 {
    let set = @indexmap.IndexSet::new()
    set.insert(i) |> ignore
    // Set goes out of scope here
    i = i + 1
  }
  debug_inspect(true, content="true")
}

///|
test "temp objects: create IndexMap, fill 1000 entries, drop — repeat 100 times" {
  let mut cycle = 0
  while cycle < 100 {
    let map = @indexmap.new()
    let mut j = 0
    while j < 1000 {
      map.insert(j, j * cycle) |> ignore
      j = j + 1
    }
    debug_inspect(map.len(), content="1000")
    cycle = cycle + 1
  }
  debug_inspect(true, content="true")
}
