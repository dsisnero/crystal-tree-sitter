# Tree-Sitter Crystal ↔ Rust API Parity

Source of truth: `vendor/tree-sitter/lib/binding_rust/lib.rs` (submodule, v0.27.0)

Upstream repo: https://github.com/crystal-lang-tools/crystal-tree-sitter

Verification: focused query specs pass against vendored tree-sitter `0.27.0`; full-suite counts remain environment-dependent because parser discovery still relies on external grammar setup.

---

## How to Read This Plan

Each phase is **feature-sized**: one cohesive, shippable feature (mirroring one Rust
API surface) that leaves the suite green. Phases are ordered by **dependency + value**
so you don't need to decide what's next — just do the next unchecked phase.

Legend for the method tables: **✅** done, **🔶#** remaining work lands in phase `#`,
**❌** cannot be done (see "Cannot Be Done in Crystal" below).

### Done so far
- PHASE 1 — v0.27.0 single-symbol parity: `Language#parseable?`, `Language#copy`,
  `Point#edit`, `Range#edit`, `Language#finalize`, `TSInput.decode` field +
  `TSDecodeFunction` + full `TSInputEncoding` enum.
- PHASE 2 — Thread-safety contract: `#copy`/`#finalize` on collectable types, the
  thread-safety model documented on every class.

## Phase Order

> **tldr:** Options structs → text encodings → query predicate API → parser UX → node
> range ergonomics → concurrency examples → docs.

### PHASE 3 — Parser & Cursor Options (progress callbacks)
Binds the four options structs and the two `*_with_options` entry points; generalizes the
existing `parse_with_progress` to a full `parse_with_options`.
- `TSParseState`, `TSParseOptions`, `TSQueryCursorState`, `TSQueryCursorOptions` structs.
- `ts_parser_parse_with_options`, `ts_query_cursor_exec_with_options`.
- Expose `Parser#parse_with_options(...)` and `QueryCursor#exec_with_options(...)` progress callbacks.
- Why first: it is the largest named gap and unblocks the custom-encoding phase.

### PHASE 4 — UTF-16 text support
- `Parser#parse_utf16_le` / `#parse_utf16_be` via `ts_parser_parse_string_encoding`.
- `Node#utf16_text` (reinterpret node byte range as `UInt16` slice).
- Why here: no dependency on Phase 3, but small and round-trips with Phase 3's encoding work.

### PHASE 5 — Custom encoding parse
- `Parser#parse_custom_encoding` using the `TSInput.decode`/`TSDecodeFunction` binding from Phase 1.
- Why here: builds directly on the decode plumbing already landed.

### PHASE 6 — Query predicate/public-accessor API
- `Query#property_predicates`, `Query#property_settings`, `Query#general_predicates`,
  `Query#new_raw`.
- Refactor the monolithic `predicates_for_pattern` around the granular accessors.
- Why here: completes the Rust `Query` surface that `predicates_for_pattern` now covers only partially.

### PHASE 7 — Parser UX + thread-safety examples
- `Parser#clone` (independent parser sharing language), `Parser#logger` getter.
- `Channel(Parser)` parser-pool example + spawn-per-fiber example as executable specs
  (resolves the two remaining Phase-2C checkboxes).
- Why here: independently useful; pairs the concurrency docs with runnable proof.

### PHASE 8 — Node & range ergonomics (Crystal-native)
- `Node#range` (combined start/end point+byte tuple) — trivial C convenience.
- `TreeSitter::Range#byte_range : Range(UInt32, UInt32)` (additive).
- `Node#byte_range` change to `Range(UInt32, UInt32)` — **breaking**; staged last and
  called out for review before v1.0.
- Why here: nice-to-have ergonomics, purely additive except the flagged single rename.

### PHASE 9 — Docs & release-prep wrapper
- Sweep the parity tables to ✅/❌, remove stale "deferred/low-priority" language, add
  CHANGELOG entries per completed feature, verify gates, tag boundary.

---

## Thread Safety Model (from upstream, PHASE 2)

```
Thread-safe (immutable/reference-counted):
  - Language     — immutable after creation, safe to share
  - Tree (copy)  — ts_tree_copy is atomic refcount bump
  - Query        — immutable after creation, safe to share
  - Node         — value type, references tree

NOT thread-safe (mutable state):
  - Parser             — must not be shared across threads simultaneously
  - TreeCursor         — mutable walk state
  - QueryCursor        — mutable iteration state
  - LookaheadIterator  — mutable iteration state
```

Recommended usage (see PHASE 7 for executable versions):

```crystal
# Parser per fiber (recommended)
spawn(name: "parse-worker") do
  parser = Parser.new(language)
  tree = parser.parse(nil, source)
  channel.send(tree.copy) # copy is safe to share across fibers
end

# Channel-based parser pool (PHASE 7 turns this into a spec)
parser_channel = Channel(Parser).new(capacity: 8)
8.times { parser_channel.send(Parser.new(language)) }

# Language and Query are immutable: safe to share across fibers
spawn { use_query(query) }
spawn { use_language(language) }
```

---

## Cannot Be Done In Crystal (verified against the v0.27.0 C ABI)

These are **not deferred for convenience**; they were checked against the vendored
`v0.27.0` symbols and cannot be implemented through the C binding. Flagging them here so
they are never silently dropped. **Ask the user for a decision on each before closing out
the plan.**

| Gap | Why it cannot be done | Decision needed |
|---|---|---|
| `Parser#set_cancellation_flag` / `#cancellation_flag` | Symbol **removed** from tree-sitter; present in no v0.27.0 header or dylib (only existed ≤ v0.26). No binding target exists. | Drop entirely, or track a legacy shim? (recommend: drop) |
| `Match#satisfies_text_predicates` | The v0.27.0 C ABI **removed** `ts_query_cursor_satisfies_text_predicates`; text predicates are evaluated internally during iteration. Rust's method (lib.rs:3487) is pure-Rust over private query internals — no C symbol to bind. | Implement emulation over public API, or drop? (recommend: drop) |
| WebAssembly / `wasm` grammars | Parsing WASM needs a WASM engine (wasmtime &c.); Crystal has no built-in runtime, so this would need a C/FFI shim that fundamentally changes the library. | Full shim, optional native-only support, or drop? (recommend: drop; WASM is niche) |
| `TextProvider` / `Decode` **traits** | Rust **traits** on the Rust (*not* C) surface; a C-ABI binding has no trait concept. Not a missing feature — a Rust-only abstraction. | Document as N/A (recommend: N/A) |

---

## Iterators

| Feature | Crystal | Rust (line) | Status |
|---|---|---|---|
| `Node#children` (index-based) | `ChildrenIterator` | — | ✅ pre-existing |
| `Node#named_children(cursor)` | `NamedChildrenIterator` | `lib.rs:1853` | ✅ |
| `Node#children_by_field_name(name, cursor)` | `ChildrenByFieldNameIterator` | `lib.rs:1874` | ✅ |
| `Node#children_by_field_id(id, cursor)` | `ChildrenByFieldIdIterator` | `lib.rs:1905` | ✅ |
| `Tree#changed_ranges` (CBufferIter) | `Range::Iterator` | `util.rs` | ✅ pre-existing |
| `LookaheadIterator` (Iterator\<UInt16\>) | `LookaheadIterator` | `lib.rs:2362` | ✅ |
| `LookaheadIterator#iter_names` | `LookaheadNamesIterator` | `lib.rs:2352` | ✅ |
| `Match#nodes_for_capture_index` | `Array(Node)` | `lib.rs:3326` | ✅ |
| `QueryMatches` (StreamingIterator) | `QueryCursor#each_match` block | `lib.rs:3476` | ✅ Crystal-idiomatic |
| `QueryCaptures` (StreamingIterator) | `QueryCursor#each_capture` block | `lib.rs:3513` | ✅ Crystal-idiomatic |

---

## Node

| Method | Crystal | Rust (line) | Status |
|---|---|---|---|
| `kind` (type) | `type` | `lib.rs:1602` | ✅ pre-existing |
| `is_named` | `named?` | `lib.rs:1631` | ✅ pre-existing |
| `is_missing` | `missing?` | `lib.rs:1690` | ✅ pre-existing |
| `is_extra` | `extra?` | `lib.rs:1641` | ✅ pre-existing |
| `has_changes` | `has_changes?` | `lib.rs:1648` | ✅ pre-existing |
| `has_error` | `has_error?` | `lib.rs:1656` | ✅ pre-existing |
| `is_error` | `error?` | `lib.rs:1666` | ✅ |
| `parse_state` | `parse_state` | `lib.rs:1673` | ✅ |
| `next_parse_state` | `next_parse_state` | `lib.rs:1680` | ✅ |
| `start_byte` / `end_byte` | `start_byte` / `end_byte` | `lib.rs:1697` | ✅ pre-existing |
| `start_position` / `end_position` | `start_point` / `end_point` | `lib.rs:1729` | ✅ pre-existing |
| `parent` | `parent` | `lib.rs:1935` | ✅ pre-existing |
| `child(n)` | `child(n)` | `lib.rs:1750` | ✅ pre-existing |
| `named_child(n)` | `named_child(n)` | `lib.rs:1769` | ✅ pre-existing |
| `child_by_field_name` | `child_by_field_name` | `lib.rs:1788` | ✅ pre-existing |
| `child_by_field_id` | `child_by_field_id` | `lib.rs:1805` | ✅ |
| `next_sibling` / `prev_sibling` | `next_sibling` / `prev_sibling` | `lib.rs:1951` | ✅ pre-existing |
| `next_named_sibling` / `prev_named_sibling` | `next_named_sibling` / `prev_named_sibling` | `lib.rs:1965` | ✅ |
| `first_child_for_byte` | `first_child_for_byte` | `lib.rs:1979` | ✅ |
| `first_named_child_for_byte` | `first_named_child_for_byte` | `lib.rs:1986` | ✅ |
| `descendant_for_byte_range` | `descendant_for_byte_range` | `lib.rs:2000` | ✅ pre-existing |
| `descendant_for_point_range` | `descendant_for_point_range` | `lib.rs:2018` | ✅ pre-existing |
| `named_descendant_for_byte_range` | `named_descendant_for_byte_range` | `lib.rs:2009` | ✅ |
| `named_descendant_for_point_range` | `named_descendant_for_point_range` | `lib.rs:2027` | ✅ |
| `descendant_count` | `descendant_count` | `lib.rs:1993` | ✅ |
| `child_with_descendant` | `child_with_descendant` | `lib.rs:1944` | ✅ |
| `child_containing_descendant` | — | deprecated | ❌ removed in v0.27.0 (deprecated upstream) |
| `field_name_for_child` | `field_name_for_child` | `lib.rs:1812` | ✅ pre-existing |
| `field_name_for_named_child` | `field_name_for_named_child` | `lib.rs:1821` | ✅ pre-existing |
| `id` | `id` | `lib.rs:1580` | ✅ |
| `kind_id` (symbol) | `kind_id` | `lib.rs:1587` | ✅ |
| `grammar_id` (grammar_symbol) | `grammar_id` | `lib.rs:1595` | ✅ |
| `grammar_name` (grammar_type) | `grammar_name` | `lib.rs:1612` | ✅ |
| `language` | `language` | `lib.rs:1621` | ✅ |
| `byte_range` | `byte_range` | `lib.rs:1710` | ✅ |
| `range` (combined) | — | `lib.rs:1717` | 🔶 Phase 8 |
| `to_sexp` (String) | `to_s` (String, auto-generated from IO) | `lib.rs:2036` | ✅ |
| `utf8_text` | `text` | `lib.rs:2046` | ✅ pre-existing |
| `utf16_text` | — | `lib.rs:2130` | 🔶 Phase 4 |
| `walk` | `walk` | `lib.rs:2061` | ✅ pre-existing |
| `edit` | `NodeEditor` (separate class) | `lib.rs:2073` | ✅ pre-existing |
| `==` (ts_node_eq) | `==` | `lib.rs:1745` | ✅ |

---

## TreeCursor

| Method | Crystal | Rust (line) | Status |
|---|---|---|---|
| `node` | `current_node` | `lib.rs:2126` | ✅ pre-existing |
| `field_id` | `current_field_id` | `lib.rs:2138` | ✅ pre-existing |
| `field_name` | `current_field_name` | `lib.rs:2146` | ✅ pre-existing |
| `depth` | `current_depth` | `lib.rs:2157` | ✅ pre-existing |
| `descendant_index` | `descendant_index` | `lib.rs:2165` | ✅ |
| `goto_first_child` | `goto_first_child` | `lib.rs:2174` | ✅ pre-existing |
| `goto_last_child` | `goto_last_child` | `lib.rs:2187` | ✅ pre-existing |
| `goto_parent` | `goto_parent` | `lib.rs:2200` | ✅ pre-existing |
| `goto_next_sibling` | `goto_next_sibling` | `lib.rs:2212` | ✅ pre-existing |
| `goto_previous_sibling` | `goto_previous_sibling` | `lib.rs:2236` | ✅ pre-existing |
| `goto_descendant` | `goto_descendant` | `lib.rs:2220` | ✅ |
| `goto_first_child_for_byte` | `goto_first_child_for_byte` | `lib.rs:2246` | ✅ |
| `goto_first_child_for_point` | `goto_first_child_for_point` | `lib.rs:2258` | ✅ |
| `reset` / `reset_to` | `reset` / `reset_to` | `lib.rs:2268` | ✅ pre-existing |
| `copy` | `copy` | `lib.rs:605` (C) | ✅ |

---

## Tree

| Method | Crystal | Rust (line) | Status |
|---|---|---|---|
| `root_node` | `root_node` | `lib.rs:1435` | ✅ pre-existing |
| `root_node_with_offset` | `root_node_with_offset` | `lib.rs:1443` | ✅ |
| `language` | `language` | `lib.rs:1457` | ✅ |
| `edit` | `TreeEditor` (separate) | `lib.rs:1470` | ✅ pre-existing |
| `walk` | `walk` | `lib.rs:1477` | ✅ |
| `changed_ranges` | `changed_ranges` | `lib.rs:1492` | ✅ pre-existing |
| `included_ranges` | `included_ranges` | `lib.rs:1507` | ✅ |
| `print_dot_graph` | `save_dot` / `save_png` | `lib.rs:1526` | ✅ pre-existing |
| `copy` | `copy` | `lib.rs:1559` | ✅ pre-existing |

---

## Language

| Method | Crystal | Rust (line) | Status |
|---|---|---|---|
| `name` | `name` (set at construction) | `lib.rs:505` | ✅ pre-existing |
| `abi_version` | `abi_version` | `lib.rs:514` | ✅ pre-existing |
| `metadata` | `metadata` | `lib.rs:525` | ✅ |
| `node_kind_count` (symbol_count) | `symbol_count` | `lib.rs:535` | ✅ pre-existing |
| `parse_state_count` (state_count) | `state_count` | `lib.rs:542` | ✅ |
| `node_kind_for_id` (symbol_name) | `symbol_name` | `lib.rs:579` | ✅ |
| `id_for_node_kind` | `id_for_node_kind` | `lib.rs:587` | ✅ |
| `node_kind_is_named` | `node_kind_is_named?` | `lib.rs:601` | ✅ |
| `node_kind_is_visible` | `node_kind_is_visible?` | `lib.rs:608` | ✅ |
| `node_kind_is_supertype` | `node_kind_is_supertype?` | `lib.rs:614` | ✅ |
| `supertypes` | `supertypes` | `lib.rs:549` | ✅ |
| `subtypes_for_supertype` | `subtypes_for_supertype` | `lib.rs:564` | ✅ |
| `field_count` | `field_count` | `lib.rs:621` | ✅ pre-existing |
| `field_name_for_id` | `field_name_for_id` | `lib.rs:628` | ✅ |
| `field_id_for_name` | `field_id_for_name` | `lib.rs:637` | ✅ |
| `next_state` | `next_state` | `lib.rs:658` | ✅ |
| `lookahead_iterator` | `lookahead_iterator` | `lib.rs:677` | ✅ |
| `copy` | `copy` | `lib.rs:500` | ✅ (`ts_language_copy` bound + `Language#copy`, spec/language_spec.cr) |
| `delete` | `finalize` | `lib.rs:507` | ✅ (`ts_language_delete`; native is a no-op for non-WASM; cached instance is process-lifetime) |
| `is_parseable` | `parseable?` | — | ✅ (`ts_language_is_parseable` bound + `Language#parseable?`, spec/language_spec.cr) |
| `name` (dynamic) | `name` (static) | — | ✅ (Crystal caches at construction) |

---

## Parser

| Method | Crystal | Rust (line) | Status |
|---|---|---|---|
| `new` | `new` | `lib.rs:719` | ✅ pre-existing |
| `set_language` | `language=` | `lib.rs:735` | ✅ pre-existing |
| `language` | `language` | `lib.rs:756` | ✅ pre-existing |
| `set_logger` | `set_logger` | `lib.rs:771` | ✅ |
| `logger` (getter) | — | `lib.rs:764` | 🔶 Phase 7 |
| `print_dot_graphs` | `print_dot_graphs` | `lib.rs:822` | ✅ pre-existing |
| `stop_printing_dot_graphs` | `stop_printing_dot_graphs` | `lib.rs:849` | ✅ |
| `parse` (string) | `parse`/`parse?` | `lib.rs:864` | ✅ pre-existing |
| `parse_with` (callback) | `parse`/`parse?` (&block) | `lib.rs:891` | ✅ pre-existing |
| `parse_utf16_le` / `parse_utf16_be` | — | `lib.rs:984` | 🔶 Phase 4 |
| `parse_custom_encoding` | — | `lib.rs:1246` | 🔶 Phase 5 |
| `parse_with_options` (progress) | `parse_with_options` | `lib.rs:891` | 🔶 Phase 3 |
| `reset` | `reset` | `lib.rs:1354` | ✅ pre-existing |
| `set_included_ranges` | `set_included_ranges` | `lib.rs:1376` | ✅ |
| `included_ranges` | `included_ranges` | `lib.rs:1403` | ✅ |
| `set_timeout_micros` | `set_timeout_micros` | — | ✅ |
| `timeout_micros` | `timeout_micros` | — | ✅ |
| `set_cancellation_flag` | — | — | ❌ symbol removed in v0.27.0 |
| `cancellation_flag` | — | — | ❌ symbol removed in v0.27.0 |

---

## Query

| Method | Crystal | Rust (line) | Status |
|---|---|---|---|
| `new` | `new` | `lib.rs:2386` | ✅ pre-existing |
| `new_raw` | — | `lib.rs:2396` | 🔶 Phase 6 |
| `pattern_count` | `pattern_count` | `lib.rs:2834` | ✅ pre-existing |
| `capture_count` | `capture_count` | `lib.rs:2840` | ✅ pre-existing |
| `string_count` | `string_count` | `lib.rs:2841` | ✅ pre-existing |
| `start_byte_for_pattern` | `start_byte_for_pattern` | `lib.rs:2805` | ✅ |
| `end_byte_for_pattern` | `end_byte_for_pattern` | `lib.rs:2820` | ✅ |
| `capture_names` | `capture_names` | `lib.rs:2840` | ✅ |
| `capture_index_for_name` | `capture_index_for_name` | `lib.rs:2852` | ✅ |
| `capture_quantifier_for_id` | `capture_quantifier_for_id` | `lib.rs:2850` | ✅ |
| `capture_quantifiers` | `capture_quantifiers_for_pattern` | `lib.rs:2846` | ✅ |
| `predicates_for_pattern` | `predicates_for_pattern` | `lib.rs:2883` | ✅ pre-existing |
| `property_predicates` | — | `lib.rs:2863` | 🔶 Phase 6 |
| `property_settings` | — | `lib.rs:2871` | 🔶 Phase 6 |
| `general_predicates` | — | `lib.rs:2883` | 🔶 Phase 6 |
| `disable_capture` | `disable_capture` | `lib.rs:2892` | ✅ |
| `disable_pattern` | `disable_pattern` | `lib.rs:2907` | ✅ |
| `deep_clone` (`ts_query_copy`) | `copy` | `lib.rs:2919` | ✅ |
| `is_pattern_rooted` | `pattern_rooted?` | `lib.rs:2914` | ✅ |
| `is_pattern_non_local` | `pattern_non_local?` | `lib.rs:2921` | ✅ |
| `is_pattern_guaranteed_at_step` | `pattern_guaranteed_at_step?` | `lib.rs:2931` | ✅ |

---

## QueryCursor

| Method | Crystal | Rust (line) | Status |
|---|---|---|---|
| `new` | `new` | `lib.rs:3009` | ✅ pre-existing |
| `exec` | `exec` | — | ✅ pre-existing |
| `next_match` / `next_capture` | `next_match` / `next_capture` | — | ✅ pre-existing |
| `each_match` / `each_capture` | `each_match` / `each_capture` | — | ✅ pre-existing |
| `match_limit` | `match_limit` | `lib.rs:3018` | ✅ |
| `set_match_limit` | `set_match_limit` | `lib.rs:3025` | ✅ |
| `did_exceed_match_limit` | `did_exceed_match_limit?` | `lib.rs:3035` | ✅ |
| `set_max_start_depth` | `set_max_start_depth` | `lib.rs:3304` | ✅ |
| `set_byte_range` | `set_byte_range` | `lib.rs:3226` | ✅ pre-existing |
| `set_point_range` | `set_point_range` | `lib.rs:3240` | ✅ pre-existing |
| `set_containing_byte_range` | `set_containing_byte_range` | `lib.rs:3259` | ✅ |
| `set_containing_point_range` | `set_containing_point_range` | `lib.rs:3278` | ✅ |
| `set_timeout_micros` | `set_timeout_micros` | — | ✅ |
| `timeout_micros` | `timeout_micros` | — | ✅ |
| `exec_with_options` (progress) | — | `lib.rs:3028` | 🔶 Phase 3 |
| `matches` (stream) | — | `lib.rs:3050` | ✅ Crystal-idiomatic `exec` + `each_match` |
| `captures` (stream) | — | `lib.rs:3142` | ✅ Crystal-idiomatic `exec` + `each_capture` |
| `matches_with_options` | — | `lib.rs:3077` | 🔶 Phase 3 |
| `captures_with_options` | — | `lib.rs:3168` | 🔶 Phase 3 |

---

## Match

| Method | Crystal | Rust (line) | Status |
|---|---|---|---|
| `pattern_index` | `pattern_index` | — | ✅ pre-existing |
| `captures` | `captures` | — | ✅ pre-existing |
| `id` | `id` | `lib.rs:3317` | ✅ |
| `remove` | `remove(cursor)` | `lib.rs:3322` | ✅ |
| `nodes_for_capture_index` | `nodes_for_capture_index` | `lib.rs:3326` | ✅ |
| `satisfies_text_predicates` | — | `lib.rs:3353` | ❌ no C symbol in v0.27.0 (see "Cannot Be Done In Crystal") |

---

## New Types

| Type | Crystal | Rust (line) | Status |
|---|---|---|---|
| `Capture` (record) | `Capture` (rule, node, index) | `lib.rs:98` | ✅ index added |
| `CaptureQuantifier` enum | `CaptureQuantifier` | `lib.rs:341` | ✅ |
| `QueryError` | `QueryError` + `QueryError::Kind` | `lib.rs:457` | ✅ |
| `Language::Metadata` | `Language::Metadata` | `lib.rs:73` | ✅ |
| `LookaheadIterator` | `LookaheadIterator` | `lib.rs:2297` | ✅ |

---

## Optional: Crystal-Native Range Convenience (not C-API parity, PHASE 8)

`TreeSitter::Range` is the 2D source span (`start_byte/end_byte/start_point/end_point`)
that mirrors the C `TSRange` and drives `included_ranges`, `changed_ranges`, and edit
ops. It is **not** a Crystal `Range(A, B)`. To let callers slice/iterate source or
intervals with native Crystal ergonomics, expose a derived byte `Range` without
conflating the two types.

| Addition | Why / sealed with | Status |
|---|---|---|
| `TreeSitter::Range#byte_range : Range(UInt32, UInt32)` → `start_byte..end_byte` | Slice `source[range.byte_range]`; additive, leaves `TSRange`/C-API coupling untouched | 🔶 Phase 8 |
| Change `Node#byte_range` to return `Range(UInt32, UInt32)` (currently `Tuple(UInt32, UInt32)` at `node.cr:357`) | Matches Crystal's native slice/iterate idiom; **breaking** change to consider before v1.0 | 🔶 Phase 8 (flagged for review) |
| `SourceBuffer`/reference-slice helper over a `Range` | Iterate/chunk a byte span | 🔶 Phase 8 |

Note: keep `TreeSitter::Range` separate from Crystal's `Range`; only *convert* via the
helpers above. Do not attempt to make `TreeSitter::Range` itself a Crystal `Range`.

---

## Phase Status Tracker

Check off each phase as its feature lands (RED-GREEN TDD: failing spec → minimal
implementation → gates: `make test` + `make lint` + `crystal tool format --check`).

- [x] **PHASE 1** — v0.27.0 single-symbol parity (parseable?, copy, point/range edit, Language#finalize, TSInput decode field + TSDecodeFunction + full TSInputEncoding)
- [x] **PHASE 2** — thread-safety docs + copy/finalize contract
- [ ] **PHASE 3** — parser & cursor options (progress callbacks)
- [ ] **PHASE 4** — UTF-16 text support (`parse_utf16_le/be`, `Node#utf16_text`)
- [ ] **PHASE 5** — custom encoding parse (`ts_parser_parse_custom_encoding` + decode)
- [ ] **PHASE 6** — query predicate/public accessor API (`property_predicates`, `property_settings`, `general_predicates`, `new_raw`)
- [ ] **PHASE 7** — parser UX + concurrency examples (`Parser#clone`, `logger` getter, `Channel(Parser)` pool spec)
- [ ] **PHASE 8** — node & range ergonomics (`Node#range`, `Range#byte_range`, `Node#byte_range` rename)
- [ ] **PHASE 9** — docs & release-prep sweep; resolve the Cannot-Be-Done items with the user

> **Any item not already assigned to a phase and not in "Cannot Be Done In Crystal" has no
> remaining work (✅) or is assigned above (🔶). Nothing is silently deferred.**

---

## Upstream Tracking

- **Upstream repo:** https://github.com/crystal-lang-tools/crystal-tree-sitter
- **Fork:** https://github.com/dsisnero/crystal-tree-sitter
- **Source of truth submodule:** `vendor/tree-sitter` (tree-sitter/tree-sitter, tag `v0.27.0`, API v15)
- **Crystal verification:** `spec/query_predicate_spec.cr` and `spec/query_copy_spec.cr` pass against the vendored `tree-sitter` `0.27.0` build; broader suite status remains environment-dependent.
