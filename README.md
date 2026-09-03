# crystal-tree-sitter

Crystal bindings for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) API.

It works by reading the tree-sitter CLI configuration file to locate where the parsers can be found, then it loads the
parsers shared objects at runtime when needed. So any parser available on tree-sitter-cli must be available on Crystal.

This is not to be confused with [crystal-lang-tools/tree-sitter-crystal](https://github.com/crystal-lang-tools/tree-sitter-crystal),
which is a tree sitter parser for parsing Crystal lang.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     tree_sitter:
       github: crystal-lang-tools/crystal-tree-sitter
   ```

2. Run `shards install`

## Usage

API still not stable at all and subject to change. Meanwhile look at the spec tests to guess hwo to use it 😁️.

The code used in the [Using Parsers](https://tree-sitter.github.io/tree-sitter/using-parsers) tree-sitter tutorial
was ported as a spec test at [spec/tree_sitter_spec.cr](spec/tree_sitter_spec.cr), the API documentation is being
ported as well, not yet on github-pages, but run `crystal doc` and have fun.

### Basic Parsing

```crystal
require "tree_sitter"

parser = TreeSitter::Parser.new("json")
tree = parser.parse("[1, null]")
root_node = tree.root_node

root_node.type.should eq("document")
```

### Iterators

Cursor-based iterators for efficient tree walking (reuse cursor across iterations):

```crystal
root_node = parser.parse(source).root_node
cursor = TreeSitter::TreeCursor.new(root_node)

# Iterate only named children (skip anonymous tokens like brackets)
root_node.named_children(cursor).each do |node|
  puts "#{node.type}: #{node.text(source)}"
end

# Filter children by field name
pair_node = root_node.named_child(0).not_nil!
pair_node.children_by_field_name("key", cursor).each do |node|
  puts "key: #{node.text(source)}"
end
```

### Tree Cursor Walking

```crystal
cursor = TreeSitter::TreeCursor.new(root_node)
if cursor.goto_first_child
  loop do
    node = cursor.current_node
    break unless node
    puts "#{node.type} (depth #{cursor.current_depth})"
    break unless cursor.goto_next_sibling
  end
end
```

### Query with Match Controls

```crystal
query = TreeSitter::Query.new(language, "(pair) @capture")
cursor = TreeSitter::QueryCursor.new(query)
cursor.set_match_limit(10)  # Limit in-progress matches
cursor.exec(tree.root_node)

cursor.each_match do |match|
  puts "Pattern #{match.pattern_index}"
  nodes = match.nodes_for_capture_index(0)
  nodes.each { |n| puts "  #{n.type}" }
end
```

### Query with Text Predicates

Text predicates (`#eq?`, `#match?`, any-of variants) are evaluated lazily during
iteration, mirroring tree-sitter's Rust bindings. Pass the `source` string to
`#matches(source)` or `#captures(source)` to get a streaming `Iterator`; matches
that fail their predicates are skipped on the fly (and rejected capture matches
are removed from the cursor so they are never revisited):

```crystal
source = "package main\nfunc foo() {}\nfunc Bar() {}\n"
query = TreeSitter::Query.new(parser.language,
  "(function_declaration name: (identifier) @name (#match? @name \"^[a-z]\"))")
cursor = TreeSitter::QueryCursor.new(query)
cursor.exec(parser.parse(source).root_node)

# Lazy, streaming matches — only func foo passes the #match? predicate.
cursor.matches(source).each do |match|
  name = match.captures.find! { |c| c.rule == "name" }.text(source)
  puts name # => "foo"
end

# Chain Iterator operations without materializing the full result set.
names = cursor.matches(source)
  .map { |m| m.captures.find! { |c| c.rule == "name" }.text(source) }
  .to_a
  .sort

# Or iterate captures directly (rejected matches are removed from the cursor).
cursor.captures(source).each do |capture|
  puts capture.text(source)
end
```

### Editing

Once you have a syntax tree, you can edit it when source code changes.
Passing the previous edited tree makes `parse` run much more quickly:

```crystal
# Convert between byte offsets and row/column points
point_to_offset = ->(line : Int32, col : Int32) { col.to_u32 }
offset_to_point = ->(offset : UInt32) { TreeSitter::Point.new(0, offset.to_i) }

editor = TreeSitter::TreeEditor.new(old_tree, point_to_offset, offset_to_point)
editor.insert(line: 0, column: 8, n_bytes: 6)
new_tree = parser.parse(new_source, old_tree)
```

### Changed Ranges

Compare two trees to find what changed:

```crystal
new_tree = parser.parse(new_source, old_tree)
new_tree.changed_ranges(old_tree).each do |range|
  puts "changed: bytes #{range.start_byte}..#{range.end_byte}"
end
```

### Progress Callback

```crystal
tree = parser.parse_with_options(source) do |state|
  puts "parsing at byte #{state.current_byte_offset}"
  false # return true to cancel parsing
end
```

### UTF-16 and Custom Encodings

```crystal
utf16 = Slice(UInt16).new(3) { |i| [91u16, 49u16, 93u16][i] } # "[1]"
tree = parser.parse_utf16_le(utf16).not_nil!
puts tree.root_node.named_child(0).not_nil!.utf16_text(utf16).to_a

decoder = ->(bytes : UInt8*, _length : UInt32, code_point : Int32*) : UInt32 {
  code_point.value = bytes[0].to_i32
  1_u32
}
tree = parser.parse_custom_encoding("[1]".to_slice, decoder)
```

### Query Properties and Ranges

```crystal
source = "[1]"
tree = parser.parse(source)
query = TreeSitter::Query.new(parser.language, "((number) @value (#set! @value \"scope\" \"constant\"))")
property = query.property_settings(0).first
puts property.key # scope

node = tree.root_node
puts source[node.range.byte_range] # Tree-sitter byte spans are end-exclusive
```

### Safe Parser Concurrency

Create one parser per fiber, or keep parsers in a channel so a parser is used by
only one fiber at a time. `Language`, `Query`, and copied trees can be shared.

```crystal
pool = Channel(TreeSitter::Parser).new(1)
pool.send(TreeSitter::Parser.new("json"))

spawn do
  worker = pool.receive
  tree = worker.parse("[1]")
  pool.send(worker)
end
```

### Lookahead Iterator

Get valid symbols for a parse state (useful for autocomplete):

```crystal
node = tree.root_node
iter = TreeSitter::LookaheadIterator.new(node.language, node.parse_state)
iter.each do |symbol_id|
  puts iter.current_symbol_name
end
```

### Advanced Usage

```crystal
require "tree_sitter"

parser = TreeSitter::Parser.new("crystal")

source = <<-CRYSTAL
class Name
end
CRYSTAL

tree = parser.parse nil, source

query = TreeSitter::Query.new(parser.language, <<-SCM)
(class_def) @class

(constant) @constant
SCM

cursor = TreeSitter::QueryCursor.new(query)
cursor.exec(tree.root_node)

cursor.each_capture do |capture|
  p capture
end
```

## Building and Testing

Tests load grammar drivers (e.g. `tree-sitter-json`, `tree-sitter-go`) at runtime,
so they must be present. The Makefile will download and build the required grammars
for you and run the specs against a repo-local tree-sitter config, so the build does
not depend on your global `tree-sitter` CLI config:

```sh
make test      # build whatever grammars are needed (if missing), then run specs
make grammars  # just build/download the grammar fixtures
make clean     # remove the downloaded grammar fixtures and the local config
```

Requires a [Crystal](https://crystal-lang.org) toolchain and the
[`tree-sitter`](https://github.com/tree-sitter/tree-sitter) CLI (`tree-sitter build`).

## Contributing

1. Fork it (<https://github.com/crystal-lang-tools/crystal-tree-sitter/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Hugo Parente Lima](https://github.com/hugopl) - creator
- [Margret Riegert](https://github.com/nobodywasishere) - maintainer
