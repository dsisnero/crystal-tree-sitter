require "benchmark"
require "../src/tree_sitter"

private ITEMS = (1..200).map { |i| %({"id":#{i},"name":"item-#{i}","tags":["tag-#{i}","common"],"nested":{"key":"value","flag":#{i % 2 == 0},"count":#{i}}}) }
LARGE_JSON = "[#{ITEMS.join(",")}]"

private MEDIUM_ITEMS = (1..20).map { |i| %({"id":#{i},"name":"item-#{i}"}) }
MEDIUM_JSON = "[#{MEDIUM_ITEMS.join(",")}]"

QUERY_SOURCE = "(pair) @pair\n(string) @string\n(number) @number"

module Harness
  @@parser : TreeSitter::Parser?
  @@tree : TreeSitter::Tree?
  @@query : TreeSitter::Query?

  def self.parser : TreeSitter::Parser
    @@parser ||= TreeSitter::Parser.new("json")
    @@parser.not_nil!
  end

  def self.tree : TreeSitter::Tree
    @@tree ||= parser.parse(nil, LARGE_JSON).not_nil!
    @@tree.not_nil!
  end

  def self.query : TreeSitter::Query
    @@query ||= TreeSitter::Query.new(tree.language, QUERY_SOURCE)
    @@query.not_nil!
  end
end

puts "=== Benchmarks ==="
puts "Document: 200 JSON objects (~45KB)"
puts

Benchmark.bm do |x|
  x.report("parse") { Harness.parser.parse(nil, LARGE_JSON) }
  x.report("walk root→leaf") do
    t = Harness.tree
    cursor = TreeSitter::TreeCursor.new(t.root_node)
    cursor.goto_first_child
    cursor.goto_first_child
    n = cursor.current_node
  end
  x.report("children iter") do
    Harness.tree.root_node.children.each { |_| }
  end
  x.report("named_children") do
    cursor = TreeSitter::TreeCursor.new(Harness.tree.root_node)
    Harness.tree.root_node.named_children(cursor).each { |_| }
  end
  x.report("query exec") do
    cursor = TreeSitter::QueryCursor.new(Harness.query)
    cursor.exec(Harness.tree.root_node)
  end
  x.report("query next_match×100") do
    cursor = TreeSitter::QueryCursor.new(Harness.query)
    cursor.exec(Harness.tree.root_node)
    100.times { cursor.next_match }
  end
  x.report("query each_capture") do
    cursor = TreeSitter::QueryCursor.new(Harness.query)
    cursor.exec(Harness.tree.root_node)
    count = 0
    cursor.each_capture { count += 1 }
  end
  x.report("lookahead iter") do
    root = Harness.tree.root_node
    iter = TreeSitter::LookaheadIterator.new(root.language, root.parse_state)
    iter.each { |_| }
  end
end

puts
puts "=== IPS (iterations/sec, higher = better) ==="
puts

Benchmark.ips do |x|
  x.report("parse medium") { Harness.parser.parse(nil, MEDIUM_JSON) }

  x.report("children 200") do
    Harness.tree.root_node.children.each { |_| }
  end

  x.report("each_child 200") do
    Harness.tree.root_node.each_child { |_| }
  end

  x.report("each_named_child 200") do
    Harness.tree.root_node.each_named_child { |_| }
  end

  x.report("named_children 200") do
    root = Harness.tree.root_node
    cursor = TreeSitter::TreeCursor.new(root)
    root.named_children(cursor).each { |_| }
  end

  x.report("named_children (no arg)") do
    Harness.tree.root_node.named_children.each { |_| }
  end

  x.report("field_by_name 200") do
    root = Harness.tree.root_node
    arr = root.named_child(0).not_nil!
    first_obj = arr.named_child(0).not_nil!
    cursor = TreeSitter::TreeCursor.new(first_obj)
    first_obj.children_by_field_name("key", cursor).each { |_| }
  end

  x.report("query each_capture") do
    cursor = TreeSitter::QueryCursor.new(Harness.query)
    cursor.exec(Harness.tree.root_node)
    cursor.each_capture { |_| }
  end

  x.report("lookahead") do
    root = Harness.tree.root_node
    iter = TreeSitter::LookaheadIterator.new(root.language, root.parse_state)
    iter.each { |_| }
  end

  x.report("treecursor walk") do
    t = Harness.tree
    cursor = TreeSitter::TreeCursor.new(t.root_node)
    cursor.goto_first_child
    cursor.goto_first_child
    n = cursor.current_node
  end
end
