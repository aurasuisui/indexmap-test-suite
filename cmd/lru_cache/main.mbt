// Example: Simple LRU (Least Recently Used) cache built on IndexMap.
//
// Adapted from aurasuisui/indexmap v0.3.2 cmd/lru_cache/main.mbt
// Verified as a black-box consumer of the @indexmap dependency.

///|
/// A fixed-size LRU cache backed by IndexMap.
/// When capacity is exceeded, the least recently used entry is evicted.
struct LRUCache[V] {
  map : @indexmap.IndexMap[String, V]
  capacity : Int
}

///|
/// Create a new LRU cache with the given capacity.
fn[V] LRUCache::new(capacity? : Int = 100) -> LRUCache[V] {
  { map: @indexmap.with_capacity(capacity), capacity }
}

///|
/// Get a value from the cache. Returns `None` if not present.
/// On a cache hit, the entry is moved to the end (most recently used).
fn[V] LRUCache::get(self : LRUCache[V], key : String) -> V? {
  match self.map.get(key) {
    Some(v) => {
      self.map.remove(key) |> ignore
      self.map.insert(key, v) |> ignore
      Some(v)
    }
    None => None
  }
}

///|
/// Insert a value into the cache.
/// If the cache is full, evicts the least recently used entry (first in order).
fn[V] LRUCache::put(self : LRUCache[V], key : String, value : V) -> Unit {
  if self.map.contains(key) {
    self.map.remove(key) |> ignore
  } else if self.map.len() >= self.capacity {
    match self.map.first() {
      Some((oldest_key, _)) => self.map.remove(oldest_key) |> ignore
      None => ()
    }
  }
  self.map.insert(key, value) |> ignore
}

///|
/// Return the current number of entries in the cache.
fn[V] LRUCache::len(self : LRUCache[V]) -> Int {
  self.map.len()
}

///|
/// Return true if the cache contains the key.
fn[V] LRUCache::contains(self : LRUCache[V], key : String) -> Bool {
  self.map.contains(key)
}

///|
fn main {
  let cache : LRUCache[String] = LRUCache::new(capacity=3)
  cache.put("a", "alpha")
  cache.put("b", "beta")
  cache.put("c", "gamma")
  println("Cache size: \{cache.len()}")

  cache.get("a") |> ignore
  cache.put("d", "delta")

  println("Contains a: \{cache.contains("a")}")
  println("Contains b: \{cache.contains("b")}")
  println("Contains c: \{cache.contains("c")}")
  println("Contains d: \{cache.contains("d")}")

  println("=== Cache contents (LRU order) ===")
  let iter = cache.map.iter()
  while true {
    match iter.next() {
      Some((k, v)) => println("\{k} => \{v}")
      None => break
    }
  }
}
