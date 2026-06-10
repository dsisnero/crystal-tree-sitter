require "./spec_helper"

describe TreeSitter::Node do
  it "can get node start/end points" do
    root_node = parse_json("[1,\n null]").root_node
    array_node = root_node.named_child(0).not_nil!
    null_node = array_node.named_child(1).not_nil!
    null_node.start_point.should eq({1, 1})
    null_node.end_point.should eq({1, 5})
  end

  it "can get node start/end byte" do
    root_node = parse_json("[1,\n null]").root_node
    array_node = root_node.named_child(0).not_nil!
    null_node = array_node.named_child(1).not_nil!
    null_node.start_byte.should eq(5)
    null_node.end_byte.should eq(9)
  end

  it "#descendant_for_byte_range" do
    root_node = parse_json("[1, null]").root_node
    root_node.descendant(6, 7).to_s.should eq("(null)")
  end

  it "#descendant_for_byte_range" do
    root_node = parse_json("[1,\nnull]").root_node
    root_node.descendant(TreeSitter::Point.new(1, 0), TreeSitter::Point.new(1, 2)).to_s.should eq("(null)")
  end

  describe "#named_children" do
    it "iterates only named children" do
      root_node = parse_json("[1, null]").root_node
      array_node = root_node.named_child(0).not_nil!
      cursor = TreeSitter::TreeCursor.new(array_node)
      named = array_node.named_children(cursor).to_a
      named.size.should eq(2)
      named[0].type.should eq("number")
      named[1].type.should eq("null")
    end
  end

  describe "#children_by_field_name" do
    it "iterates children with given field name" do
      source = "{\"key\": \"value\"}"
      root_node = parse_json(source).root_node
      object_node = root_node.named_child(0).not_nil!
      pair_node = object_node.named_child(0).not_nil!
      cursor = TreeSitter::TreeCursor.new(pair_node)
      children = pair_node.children_by_field_name("key", cursor).to_a
      children.size.should eq(1)
      children[0].type.should eq("string")
    end
  end

  describe "#children_by_field_id" do
    it "iterates children with given field id" do
      source = "{\"key\": \"value\"}"
      root_node = parse_json(source).root_node
      object_node = root_node.named_child(0).not_nil!
      pair_node = object_node.named_child(0).not_nil!
      lang = pair_node.language
      field_id = lang.field_id_for_name("key")
      cursor = TreeSitter::TreeCursor.new(pair_node)
      children = pair_node.children_by_field_id(field_id, cursor).to_a
      children.size.should eq(1)
      children[0].type.should eq("string")
    end
  end

  describe "LookaheadIterator" do
    it "iterates symbol IDs for a parse state" do
      root_node = parse_json("[1, null]").root_node
      array_node = root_node.named_child(0).not_nil!
      lang = array_node.language
      state = array_node.parse_state
      iter = TreeSitter::LookaheadIterator.new(lang, state)
      first = iter.next
      first.should be_a(UInt16)
    end

    it "iterates symbol names" do
      root_node = parse_json("[1, null]").root_node
      array_node = root_node.named_child(0).not_nil!
      lang = array_node.language
      state = array_node.parse_state
      iter = TreeSitter::LookaheadIterator.new(lang, state)
      names = iter.iter_names.to_a
      names.size.should be > 0
      names.all? { |n| n.is_a?(String) }.should be_true
    end
  end

  describe "Match" do
    it "#nodes_for_capture_index filters captures by index" do
      lang = TreeSitter::Language.new("json")
      query = TreeSitter::Query.new(lang, "(pair) @capture")
      tree = parse_json("{\"key\": \"value\"}").not_nil!
      cursor = TreeSitter::QueryCursor.new(query)
      cursor.exec(tree.root_node)
      match = cursor.next_match.not_nil!
      nodes = match.nodes_for_capture_index(0)
      nodes.size.should eq(1)
      nodes[0].type.should eq("pair")
    end

    it "#remove removes match from cursor" do
      lang = TreeSitter::Language.new("json")
      query = TreeSitter::Query.new(lang, "(pair) @capture")
      tree = parse_json("{\"key\": \"value\"}").not_nil!
      cursor = TreeSitter::QueryCursor.new(query)
      cursor.exec(tree.root_node)
      match = cursor.next_match.not_nil!
      match.remove(cursor)
      cursor.next_match.should be_nil
    end
  end

  describe "#is_error?" do
    it "returns false for valid nodes" do
      root_node = parse_json("[1, null]").root_node
      root_node.is_error?.should be_false
    end
  end

  describe "#child_by_field_id" do
    it "returns child with given field id" do
      source = "{\"key\": \"value\"}"
      root_node = parse_json(source).root_node
      object_node = root_node.named_child(0).not_nil!
      pair_node = object_node.named_child(0).not_nil!
      lang = pair_node.language
      field_id = lang.field_id_for_name("key")
      child = pair_node.child_by_field_id(field_id)
      child.should_not be_nil
      child.not_nil!.type.should eq("string")
    end
  end

  describe "#next_named_sibling" do
    it "finds the next named sibling" do
      root_node = parse_json("[1, null]").root_node
      array_node = root_node.named_child(0).not_nil!
      number_node = array_node.named_child(0).not_nil!
      sibling = number_node.next_named_sibling
      sibling.should_not be_nil
      sibling.not_nil!.type.should eq("null")
    end
  end

  describe "#prev_named_sibling" do
    it "finds the previous named sibling" do
      root_node = parse_json("[1, null]").root_node
      array_node = root_node.named_child(0).not_nil!
      null_node = array_node.named_child(1).not_nil!
      sibling = null_node.prev_named_sibling
      sibling.should_not be_nil
      sibling.not_nil!.type.should eq("number")
    end
  end

  describe "#next_parse_state" do
    it "returns the parse state after this node" do
      root_node = parse_json("[1, null]").root_node
      root_node.next_parse_state.should be_a(UInt16)
    end
  end

  describe "#first_child_for_byte" do
    it "returns first child extending beyond a byte offset" do
      root_node = parse_json("[1, null]").root_node
      array_node = root_node.named_child(0).not_nil!
      child = array_node.first_child_for_byte(1)
      child.should_not be_nil
    end
  end

  describe "#first_named_child_for_byte" do
    it "returns first named child beyond a byte offset" do
      root_node = parse_json("[1, null]").root_node
      array_node = root_node.named_child(0).not_nil!
      child = array_node.first_named_child_for_byte(1)
      child.should_not be_nil
      child.not_nil!.type.should eq("number")
    end
  end

  describe "#descendant_count" do
    it "counts descendants including self" do
      root_node = parse_json("[1, null]").root_node
      root_node.descendant_count.should be >= 1
    end
  end

  describe "#named_descendant_for_byte_range" do
    it "finds smallest named node for byte range" do
      root_node = parse_json("[1, null]").root_node
      result = root_node.named_descendant_for_byte_range(1, 2)
      result.should_not be_nil
      result.not_nil!.type.should eq("number")
    end
  end

  describe "#named_descendant_for_point_range" do
    it "finds smallest named node for point range" do
      root_node = parse_json("[1, null]").root_node
      result = root_node.named_descendant_for_point_range(
        TreeSitter::Point.new(0, 1), TreeSitter::Point.new(0, 2))
      result.should_not be_nil
      result.not_nil!.type.should eq("number")
    end
  end

  describe "#byte_range" do
    it "returns a range of byte offsets" do
      source = "{\"key\": \"value\"}"
      root_node = parse_json(source).root_node
      object_node = root_node.named_child(0).not_nil!
      pair_node = object_node.named_child(0).not_nil!
      key_node = pair_node.named_child(0).not_nil!
      rng = key_node.byte_range
      rng[0].should eq(1)
      rng[1].should eq(6)
    end
  end

  describe "#id" do
    it "returns a unique id" do
      root_node = parse_json("[1, null]").root_node
      root_node.id.should be > 0
    end
  end

  describe "#kind_id" do
    it "returns the numeric type id" do
      root_node = parse_json("[1, null]").root_node
      root_node.kind_id.should be_a(UInt16)
    end
  end

  describe "#grammar_id" do
    it "returns the numeric grammar type id" do
      root_node = parse_json("[1, null]").root_node
      root_node.grammar_id.should be_a(UInt16)
    end
  end

  describe "#grammar_name" do
    it "returns the grammar type name" do
      root_node = parse_json("[1, null]").root_node
      root_node.grammar_name.should be_a(String)
    end
  end

  describe TreeSitter::TreeCursor do
    it "#descendant_index" do
      root_node = parse_json("[1, null]").root_node
      cursor = TreeSitter::TreeCursor.new(root_node)
      cursor.descendant_index.should eq(0)
    end

    it "#goto_descendant" do
      root_node = parse_json("[1, null]").root_node
      cursor = TreeSitter::TreeCursor.new(root_node)
      cursor.goto_first_child
      cursor.goto_first_child
      cursor.goto_descendant(0)
      depth = cursor.current_depth
      depth.should eq(0)
    end

    it "#goto_first_child_for_byte finds child by byte range" do
      root_node = parse_json("[1, null]").root_node
      cursor = TreeSitter::TreeCursor.new(root_node)
      idx = cursor.goto_first_child_for_byte(1, 2)
      idx.should be_a(UInt64)
    end

    it "#goto_first_child_for_point finds child by point range" do
      root_node = parse_json("[1, null]").root_node
      cursor = TreeSitter::TreeCursor.new(root_node)
      idx = cursor.goto_first_child_for_point(
        TreeSitter::Point.new(0, 1), TreeSitter::Point.new(0, 2))
      idx.should be_a(UInt64)
    end
  end

  describe "CaptureQuantifier" do
    it "has expected enum values" do
      TreeSitter::CaptureQuantifier::Zero.value.should eq(0)
      TreeSitter::CaptureQuantifier::One.value.should eq(3)
    end
  end

  describe TreeSitter::Parser do
    it "#parse_with_progress reports byte offsets" do
      parser = TreeSitter::Parser.new("json")
      offsets = [] of UInt32
      tree = parser.parse_with_progress(nil, "[1, null]") { |offset|
        offsets << offset
      }
      tree.should_not be_nil
      offsets.size.should be > 0
      offsets[0].should be_a(UInt32)
    end
  end

  describe "#to_s" do
    it "returns S-expression as String" do
      root_node = parse_json("[1, null]").root_node
      sexp = root_node.to_s
      sexp.should eq("(document (array (number) (null)))")
    end
  end

  describe TreeSitter::QueryCursor do
    it "#set_containing_byte_range restricts matches to containing range" do
      lang = TreeSitter::Language.new("json")
      query = TreeSitter::Query.new(lang, "(pair) @capture")
      tree = parse_json("{\"key\": \"value\"}").not_nil!
      cursor = TreeSitter::QueryCursor.new(query)
      cursor.set_containing_byte_range(0, 20)
      cursor.exec(tree.root_node)
      cursor.next_match.should_not be_nil
    end

    it "#set_containing_point_range restricts matches to containing range" do
      lang = TreeSitter::Language.new("json")
      query = TreeSitter::Query.new(lang, "(pair) @capture")
      tree = parse_json("{\"key\": \"value\"}").not_nil!
      cursor = TreeSitter::QueryCursor.new(query)
      cursor.set_containing_point_range(
        TreeSitter::Point.new(0, 0), TreeSitter::Point.new(0, 20))
      cursor.exec(tree.root_node)
      cursor.next_match.should_not be_nil
    end
  end

  describe "TreeSitter.format_sexp" do
    it "pretty-prints an S-expression" do
      result = TreeSitter.format_sexp("(a (b) (c))")
      result.should contain("\n")
      result.should contain("(a")
      result.should contain("(b")
      result.should contain("(c")
    end
  end

  describe TreeSitter::QueryError do
    it "raises on invalid query with kind and offset" do
      lang = TreeSitter::Language.new("json")
      expect_raises(TreeSitter::QueryError) do
        TreeSitter::Query.new(lang, "(invalid")
      end
    end

    it "exposes error kind, offset, and message" do
      lang = TreeSitter::Language.new("json")
      begin
        TreeSitter::Query.new(lang, "(invalid")
      rescue ex : TreeSitter::QueryError
        ex.offset.should be > 0
        ex.message.should_not be_nil
        ex.message.not_nil!.size.should be > 0
        ex.kind.should_not be_nil
      end
    end
  end
end
