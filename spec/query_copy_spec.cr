require "./spec_helper"

describe TreeSitter::Query do
  it "copies independently so disabling a pattern does not affect the original" do
    parser = TreeSitter::Parser.new("go")
    tree = parser.parse(nil, "package main\nfunc hello() {}").not_nil!
    language = parser.language

    original = TreeSitter::Query.new(language, "(function_declaration) @func")
    copy = original.copy
    copy.disable_pattern(0)

    original_cursor = TreeSitter::QueryCursor.new(original)
    original_cursor.exec(tree.root_node)
    original_cursor.next_match.should_not be_nil

    copy_cursor = TreeSitter::QueryCursor.new(copy)
    copy_cursor.exec(tree.root_node)
    copy_cursor.next_match.should be_nil
  end
end
