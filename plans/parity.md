# Tree-Sitter Crystal ↔ Rust API Parity

Source of truth: `vendor/tree-sitter/lib/binding_rust/lib.rs` (submodule, v0.27.0)

Upstream repo: https://github.com/crystal-lang-tools/crystal-tree-sitter

Verification: focused query specs pass against vendored tree-sitter `0.27.0`; full-suite counts remain environment-dependent because parser discovery still relies on external grammar setup.

---

## Phase 1: v0.27.0 C API Parity

New in v0.27.0 that needs binding or is partially missing.

### 1A. New C API Functions (bind missing symbols)

| Function | Crystal Status | Action |
|---|---|---|
| `ts_language_is_parseable` | ✅ bound + `Language#parseable?` | Done: bind + method (spec/language_spec.cr) |
| `ts_language_name` | ✅ already bound | — |
| `ts_node_eq` | ✅ already bound | — |
| `ts_point_edit` | ✅ bound + `Point#edit` | Done: bind + `Point#edit(edit, byte) : {Point, UInt32}` (spec/point_edit_spec.cr) |
| `ts_range_edit` | ✅ bound + `Range#edit` | Done: bind + in-place `Range#edit(edit)` (spec/range_edit_spec.cr) |
| `ts_node_eq` | ✅ already bound | Used by `Node#==` |
| `ts_parser_parse_with_options` | ⚠️ partial (`parse_with_progress`) | Add direct bind for full `TSParseOptions` support |
| `ts_query_cursor_exec_with_options` | ❌ not bound | Bind for `QueryCursorOptions` |
| `ts_language_copy` | ✅ bound + `Language#copy` | Done: bind + refcounted copy (spec/language_spec.cr) |
| `ts_language_delete` | ✅ bound | Done: bound (native delete is a no-op; cached instance is process-lifetime) |

### 1B. TSInput `decode` Field

The v0.27.0 `TSInput` struct has a `decode` field (`TSDecodeFunction`) for custom encodings. The Crystal `TSInput` struct is missing this field.

| Item | Status | Action |
|---|---|---|
| `TSDecodeFunction` typedef | ✅ bound | `alias TSDecodeFunction` in `lib_tree_sitter.cr` |
| `TSInput.decode` field | ✅ added | `decode : TSDecodeFunction` on `TSInput` struct (v0.27.0 layout) |
| `TSInputEncodingCustom` enum | ✅ added | Enum now `UTF8 / UTF16LE / UTF16BE / Custom` matching C ABI (spec/input_spec.cr) |

### 1C. ParseOptions / QueryCursorOptions Structs

| Item | Status | Action |
|---|---|---|
| `TSParseState` struct | ⚠️ used by `parse_with_progress` | Ensure `TSInput.decode` is wired for full options |
| `TSParseOptions` struct | ⚠️ partial | Add full struct for `ts_parser_parse_with_options` |
| `TSQueryCursorState` struct | ❌ not bound | Bind for progress callbacks |
| `TSQueryCursorOptions` struct | ❌ not bound | Bind for query progress callbacks |

---

## Phase 2: Thread Safety

Source of truth: Rust binding `unsafe impl Send/Sync` + tree-sitter docs.

### Thread Safety Model (from upstream)

```
Thread-safe (immutable/reference-counted):
  - Language     — immutable after creation, safe to share
  - Tree (copy)  — ts_tree_copy is atomic refcount bump
  - Query        — immutable after creation, safe to share
  - Node         — value type, references tree

NOT thread-safe (mutable state):
  - Parser       — must not be shared across threads simultaneously
  - TreeCursor   — mutable walk state
  - QueryCursor  — mutable iteration state
  - LookaheadIterator — mutable iteration state
```

### 2A. Language: Immutable, Reference-Counted

Rust: `unsafe impl Send for Language {}` + `unsafe impl Sync for Language {}`

Crystal actions:
- [x] Add `Language#copy` using `ts_language_copy` (returns new reference)
- [x] Add `Language#finalize` using `ts_language_delete` (release reference)
- [x] Use `AtomicCounter` or Crystal's GC for reference counting
- [x] Document: "Language instances are immutable and thread-safe"

### 2B. Tree: Copy for Thread-Safe Sharing

Rust: `unsafe impl Send for Tree {}` + `unsafe impl Sync for Tree {}`

Crystal actions:
- [x] `Tree#copy` already exists (uses `ts_tree_copy`)
- [x] Add `Tree#finalize` (already exists)
- [x] Document: "Use `Tree#copy` before sharing across fibers/threads"
- [x] Document: "Individual Tree instances are NOT thread-safe"

### 2C. Parser: Not Thread-Safe

Rust: `unsafe impl Send for Parser {}` + `unsafe impl Sync for Parser {}`
BUT upstream docs say: "Individual Parser instances are not thread safe"

Crystal actions:
- [x] Document: "Parser instances must not be shared across fibers simultaneously"
- [ ] Add example: `Channel(Parser)` or spawn-per-thread pattern
- [ ] Consider adding `Parser#clone` that creates a new independent parser with same language

### 2D. Query: Immutable, Thread-Safe

Rust: `unsafe impl Send for Query {}` + `unsafe impl Sync for Query {}`

Crystal actions:
- [x] `Query#copy` already exists (uses `ts_query_copy`)
- [x] Add `Query#finalize` (already exists)
- [x] Document: "Query instances are immutable and thread-safe"

### 2E. QueryCursor / TreeCursor / LookaheadIterator: Not Thread-Safe

Rust: `unsafe impl Send for QueryCursor {}` + `unsafe impl Sync for QueryCursor {}`
But these carry mutable state; not safe to share.

Crystal actions:
- [x] Document: "QueryCursor/TreeCursor/LookaheadIterator must not be shared across fibers"
- [x] Note: Crystal fibers run on a single thread (event loop), so this is safe by default in typical usage

### 2F. Node: Value Type, Thread-Safe by Copy

Rust: `unsafe impl Send for Node<'_> {}` + `unsafe impl Sync for Node<'_> {}`

Crystal actions:
- [x] `Node` is already a `struct` (value type, copied on assignment)
- [x] Document: "Node is a value type; safe to pass between fibers"

### 2G. Thread Safety Summary Table

| Type | Send | Sync | Crystal | Action |
|---|---|---|---|---|
| `Language` | ✅ | ✅ | class (reference) | Add refcount via `ts_language_copy`/`ts_language_delete` |
| `Tree` | ✅ | ✅ | class (pointer) | `copy` exists; document usage |
| `Parser` | ✅ | ✅ | class (pointer) | Document: not safe to share |
| `Query` | ✅ | ✅ | class (pointer) | `copy` exists; document usage |
| `Node` | ✅ | ✅ | struct (value) | Already safe |
| `TreeCursor` | ✅ | ✅ | class (pointer) | Document: not safe to share |
| `QueryCursor` | ✅ | ✅ | class (pointer) | Document: not safe to share |
| `LookaheadIterator` | ✅ | ✅ | class (pointer) | Document: not safe to share |

### 2H. Recommended Usage Patterns

```crystal
# Pattern 1: Parser per fiber (recommended)
spawn(name: "parse-worker") do
  parser = Parser.new(language)
  tree = parser.parse(nil, source)
  tree_copy = tree.copy  # safe to send to another fiber
  channel.send(tree_copy)
end

# Pattern 2: Channel-based parser pool
parser_channel = Channel(Parser).new(capacity: 8)
8.times { parser_channel.send(Parser.new(language)) }

# Pattern 3: Share immutable Language and Query
language = Language.new("crystal")
query = Query.new(language, "(function_def name: (identifier) @name)")

# These are safe to share across fibers:
spawn { use_query(query) }
spawn { use_language(language) }
```

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
| `child_containing_descendant` | — | deprecated | ⚠️ skipped (deprecated) |
| `field_name_for_child` | `field_name_for_child` | `lib.rs:1812` | ✅ pre-existing |
| `field_name_for_named_child` | `field_name_for_named_child` | `lib.rs:1821` | ✅ pre-existing |
| `id` | `id` | `lib.rs:1580` | ✅ |
| `kind_id` (symbol) | `kind_id` | `lib.rs:1587` | ✅ |
| `grammar_id` (grammar_symbol) | `grammar_id` | `lib.rs:1595` | ✅ |
| `grammar_name` (grammar_type) | `grammar_name` | `lib.rs:1612` | ✅ |
| `language` | `language` | `lib.rs:1621` | ✅ |
| `byte_range` | `byte_range` | `lib.rs:1710` | ✅ |
| `range` (combined) | — | `lib.rs:1717` | ⬜ low priority |
| `to_sexp` (String) | `to_s` (String, auto-generated from IO) | `lib.rs:2036` | ✅ |
| `utf8_text` | `text` | `lib.rs:2046` | ✅ pre-existing |
| `utf16_text` | — | `lib.rs:2051` | ⬜ large scope |
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
| `delete` | — | `lib.rs:507` | ⬜ deferred (native delete is a no-op; cached instance is process-lifetime) |
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
| `logger` (getter) | — | `lib.rs:764` | ⬜ low priority |
| `print_dot_graphs` | `print_dot_graphs` | `lib.rs:822` | ✅ pre-existing |
| `stop_printing_dot_graphs` | `stop_printing_dot_graphs` | `lib.rs:849` | ✅ |
| `parse` (string) | `parse`/`parse?` | `lib.rs:864` | ✅ pre-existing |
| `parse_with` (callback) | `parse`/`parse?` (&block) | `lib.rs:891` | ✅ pre-existing |
| `parse_utf16_le` / `parse_utf16_be` | — | `lib.rs:984` | ⬜ large scope |
| `parse_custom_encoding` | — | `lib.rs:1246` | ⬜ large scope |
| `parse_with_options` (progress) | `parse_with_progress` | `lib.rs:891` | ✅ Crystal-idiomatic |
| `reset` | `reset` | `lib.rs:1354` | ✅ pre-existing |
| `set_included_ranges` | `set_included_ranges` | `lib.rs:1376` | ✅ |
| `included_ranges` | `included_ranges` | `lib.rs:1403` | ✅ |
| `set_timeout_micros` | `set_timeout_micros` | — | ✅ |
| `timeout_micros` | `timeout_micros` | — | ✅ |
| `set_cancellation_flag` | — | — | ⬜ symbol not in installed library v0.26.9 |
| `cancellation_flag` | — | — | ⬜ symbol not in installed library v0.26.9 |

---

## Query

| Method | Crystal | Rust (line) | Status |
|---|---|---|---|
| `new` | `new` | `lib.rs:2386` | ✅ pre-existing |
| `new_raw` | — | `lib.rs:2396` | ⬜ low priority |
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
| `property_predicates` | — | `lib.rs:2863` | ⬜ low priority |
| `property_settings` | — | `lib.rs:2871` | ⬜ low priority |
| `general_predicates` | — | `lib.rs:2883` | ⬜ low priority |
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
| `exec_with_options` (progress) | — | `lib.rs:3028` | ⬜ Phase 1 |
| `matches` (stream) | — | `lib.rs:3050` | ⬜ Crystal uses exec+each_match |
| `captures` (stream) | — | `lib.rs:3142` | ⬜ Crystal uses exec+each_capture |
| `matches_with_options` | — | `lib.rs:3077` | ⬜ large scope (TSParseOptions) |
| `captures_with_options` | — | `lib.rs:3168` | ⬜ large scope (TSParseOptions) |

---

## Match

| Method | Crystal | Rust (line) | Status |
|---|---|---|---|
| `pattern_index` | `pattern_index` | — | ✅ pre-existing |
| `captures` | `captures` | — | ✅ pre-existing |
| `id` | `id` | `lib.rs:3317` | ✅ |
| `remove` | `remove(cursor)` | `lib.rs:3322` | ✅ |
| `nodes_for_capture_index` | `nodes_for_capture_index` | `lib.rs:3326` | ✅ |
| `satisfies_text_predicates` | — | `lib.rs:3353` | ⬜ low priority |

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

## Optional: Crystal-Native Range Convenience (not C-API parity)

`TreeSitter::Range` is the 2D source span (`start_byte/end_byte/start_point/end_point`)
that mirrors the C `TSRange` and drives `included_ranges`, `changed_ranges`, and edit
ops. It is **not** a Crystal `Range(A, B)`. To let callers slice/iterate source or
intervals with native Crystal ergonomics, expose a derived byte `Range` without
conflating the two types.

| Addition | Why / sealed with | Status |
|---|---|---|
| `TreeSitter::Range#byte_range : Range(UInt32, UInt32)` → `start_byte..end_byte` | Slice `source[range.byte_range]`; additive, leaves `TSRange`/C-API coupling untouched | ⬜ optional |
| Change `Node#byte_range` to return `Range(UInt32, UInt32)` (currently `Tuple(UInt32, UInt32)` at `node.cr:357`) | Matches Crystal's native slice/iterate idiom; **breaking** change to consider before v1.0 | ⬜ optional |
| (deferred) `SourceBuffer`/reference-slice helper over a `Range` | Iterate/chunk a byte span | ⬜ optional |

Note: keep `TreeSitter::Range` separate from Crystal's `Range`; only *convert* via the
helpers above. Do not attempt to make `TreeSitter::Range` itself a Crystal `Range`.

---

## Remaining Gaps (intentionally deferred)

| Gap | Reason |
|---|---|
| UTF16 parse methods | Large scope, niche usage |
| `parse_custom_encoding`, `Decode` trait | Rust-specific abstraction |
| `TextProvider` trait | Rust-specific abstraction |
| `cancellation_flag` / `logger` getter | Symbol not in installed tree-sitter v0.26.9 |
| `ParseOptions` / `QueryCursorOptions` structs | Large scope; partial coverage via `parse_with_progress` |
| `property_predicates` / `property_settings` | Existing `predicates_for_pattern` covers most use cases |
| `Node#range` (combined) | Low priority convenience |
| `InputEdit::edit_point` / `edit_range` | Phase 1 ✓ done |
| Crystal-native `Range` conversions | Optional; see "Optional: Crystal-Native Range Convenience" above |
| Wasm support | Not applicable to Crystal |

---

## Upstream Tracking

- **Upstream repo:** https://github.com/crystal-lang-tools/crystal-tree-sitter
- **Fork:** https://github.com/dsisnero/crystal-tree-sitter
- **Source of truth submodule:** `vendor/tree-sitter` (tree-sitter/tree-sitter, tag `v0.27.0`, API v15)
- **Crystal verification:** `spec/query_predicate_spec.cr` and `spec/query_copy_spec.cr` pass against the vendored `tree-sitter` `0.27.0` build; broader suite status remains environment-dependent.
