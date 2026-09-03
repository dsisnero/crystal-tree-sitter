# Changelog

## Unreleased

### Tree-sitter v0.27 API parity

- **Breaking:** parsing methods now take source first, with an optional previous
  `Tree?` second (`parser.parse(source, old_tree = nil)`), matching the Rust API.
  The former C-ABI-shaped `parse(old_tree, source)` order was removed.
- Added progress-aware parsing and query execution with cancellable callbacks.
- Added UTF-16 little-/big-endian parsing, UTF-16 node text, and custom decoding.
- Added granular query property/predicate accessors and `Query.new_raw`.
- Added `Parser#clone`, `Parser#logger`, and executable safe parser-pool/per-fiber examples.
- Added `Node#range` and end-exclusive `Range#byte_range`; `Node#byte_range` remains a
  compatible `{start_byte, end_byte}` tuple.
- Added streaming text-predicate iteration: `QueryCursor#matches(source)` /
  `#captures(source)` return lazy `Iterator(Match)` / `Iterator(Capture)` that evaluate
  `#eq?`/`#match?`/any-of text predicates on the fly (mirroring Rust's `QueryMatches` /
  `QueryCaptures`), with rejected capture matches removed from the cursor via
  `Match#remove`. Also added filtered `QueryCursor#next_match(source)` /
  `#next_capture(source)` and `Match#satisfies_text_predicates?(query, source)`.

## v0.3.0 (2026-06-10)

### Performance — FFI call minimization

Iterator hot paths inlined to reduce redundant C function calls:

- **`each_child`/`each_named_child`** — eliminated redundant `child_count` bounds-check FFI call per iteration, inlined raw `LibTreeSitter` calls directly. ~17% faster on 200-child nodes, 0B allocation unchanged.
- **`ChildrenIterator`** — inlined raw FFI calls, eliminating redundant bounds check. ~4% faster, 64B alloc unchanged.
- **`NamedChildrenIterator`** — inlined `ts_tree_cursor_current_node` and `ts_tree_cursor_goto_next_sibling` calls, skipping redundant null check and method dispatch per step. ~7–21% faster on cursor-based iteration.
- **`ChildrenByFieldNameIterator`** / **`ChildrenByFieldIdIterator`** — same inlining treatment. ~2–7% faster.
- **`LookaheadNamesIterator`** — switched from `String.new(ptr)` to `TreeSitter.string_pool.get(ptr, ...)` to deduplicate C strings. ~7% faster, 64% fewer allocations (528B → 192B/op).
- Added `TreeCursor#unsafe_cursor_ptr` for internal iterator access.

### Benchmark harness

- Added array-node benchmarks (`each_child array200`, `each_named_child array200`, `children_iter array200`) for measuring real multi-child iteration perf (previously only measured root node with 1 child).
- Added node metadata benchmarks (`node.type`, `node.kind_id`, `node.language`, `node.text`).
- Added `field_by_id` benchmark to compare with `field_by_name`.
- Added `query cursor reuse`, `range iter`, and `lookahead names` benchmarks.

## v0.2.0 (2026-06-09)

### Iterators

- Added `Node#named_children`, `Node#children_by_field_name`, `Node#children_by_field_id` — cursor-based iterators for named children, field-filtered iteration.
- Added convenience overload `Node#named_children` without cursor argument.
- Added `Node#each_child` / `Node#each_named_child` — zero-allocation block-based alternatives (2.1× faster than Iterator pattern).
- Added `LookaheadIterator#iter_names` — yields String symbol names.
- Added `Match#nodes_for_capture_index` — returns Array of Nodes for a given capture index.

### Query

- Added `Query#capture_name_for_id`, `Query#string_value_for_id`, `Query#capture_names`, `Query#capture_index_for_name`.
- Added `Query#capture_quantifier_for_id`, `Query#capture_quantifiers_for_pattern`.
- Added `Query#disable_capture`, `Query#disable_pattern`.
- Added `Query#is_pattern_rooted?`, `Query#is_pattern_non_local?`, `Query#is_pattern_guaranteed_at_step?`.
- Added `Query#start_byte_for_pattern`, `Query#end_byte_for_pattern`.
- Pre-computed capture names, string values, and counts in `Query.new`.

### QueryCursor

- Added `QueryCursor#match_limit`, `#set_match_limit`, `#did_exceed_match_limit?`.
- Added `QueryCursor#set_max_start_depth`.
- Added `QueryCursor#set_containing_byte_range`, `#set_containing_point_range`.
- Added `QueryCursor#set_timeout_micros`, `#timeout_micros`.
- Added `Match#remove(cursor)`.

### API Parity

- Added `Node#id`, `Node#kind_id`, `Node#grammar_id`, `Node#grammar_name`.
- Added `Node#is_error?`, `Node#parse_state`, `Node#next_parse_state`.
- Added `Node#descendant_count`.
- Added `Node#first_child_for_byte`, `Node#first_named_child_for_byte`.
- Added `Node#named_descendant_for_byte_range`, `Node#named_descendant_for_point_range`.
- Added `Node#child_with_descendant`.
- Added `Node#byte_range`.
- Added `Tree#root_node_with_offset`, `Tree#included_ranges`.
- Added `TreeCursor#descendant_index`, `TreeCursor#goto_descendant`.
- Added `TreeCursor#goto_first_child_for_byte`, `TreeCursor#goto_first_child_for_point`.
- Added `TreeCursor#copy`.
- Added `Parser#print_dot_graphs`, `Parser#stop_printing_dot_graphs`.
- Added `Parser#set_included_ranges`, `Parser#included_ranges`.
- Added `Parser#set_timeout_micros`, `Parser#timeout_micros`.
- Added `Parser#set_logger`, `Parser#stop_logging`.
- Added `Language#symbol_name`, `Language#next_state`, `Language#state_count`.
- Added `Language#id_for_node_kind`, `Language#node_kind_is_named?`, `#node_kind_is_visible?`, `#node_kind_is_supertype?`.
- Added `Language#supertypes`, `Language#subtypes_for_supertype`.
- Added `Language::Metadata` and `Language#metadata`.
- Added `CaptureQuantifier` enum.
- Added `Point` struct.

### Documentation

- Added comprehensive API parity manifest (`plans/parity.md`) tracking Crystal ↔ Rust API coverage.
- Added README examples for iterators, tree walking, editing, changed ranges, progress callbacks, lookahead.
- Added Crystal doc comments to all new methods.

### Specs

- 73 examples, 0 failures, 11 errors (pre-existing Go parser dependency), 1 pending.

## v0.1.0 (initial)

- Basic tree-sitter bindings for Crystal.
- Parser, Tree, Node, TreeCursor, Query, QueryCursor.
- Language repository with runtime loading.
- Tree/Node editors for incremental parsing.
