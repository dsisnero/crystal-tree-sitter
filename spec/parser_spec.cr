require "./spec_helper"

describe TreeSitter::Parser do
  it "can parse from an IO object" do
    parser = TreeSitter::Parser.new("json")

    io = IO::Memory.new("[1, null]")
    tree = parser.parse(nil, io).not_nil!
    tree.root_node.to_s.should eq("(document (array (number) (null)))")
  end

  describe "#parse_with_options" do
    it "reports parse progress and returns a tree" do
      parser = TreeSitter::Parser.new("json")
      offsets = [] of UInt32

      source = "[#{(["1"] * 1_000).join(",")}]"
      tree = parser.parse_with_options(nil, source) do |state|
        offsets << state.current_byte_offset
        false
      end

      tree.not_nil!.root_node.type.should eq("document")
      offsets.should_not be_empty
    end

    it "cancels parsing when the progress callback returns true" do
      parser = TreeSitter::Parser.new("json")

      source = "[#{(["1"] * 1_000).join(",")}]"
      parser.parse_with_options(nil, source) { true }.should be_nil
    end
  end

  it "parses UTF-16 little- and big-endian code units" do
    source = Slice(UInt16).new(3) { |i| [91u16, 49u16, 93u16][i] }

    TreeSitter::Parser.new("json").parse_utf16_le(nil, source).not_nil!.root_node.type.should eq("document")
    TreeSitter::Parser.new("json").parse_utf16_be(nil, source).not_nil!.root_node.type.should eq("document")
  end

  it "preserves UTF-16 surrogate pairs in node text" do
    source = Slice(UInt16).new(7) { |i| [91u16, 34u16, 0xd83du16, 0xde00u16, 34u16, 93u16, 10u16][i] }
    tree = TreeSitter::Parser.new("json").parse_utf16_le(nil, source).not_nil!

    tree.root_node.named_child(0).not_nil!.utf16_text(source).to_a.should eq(source[0, 6].to_a)
  end

  it "clones into an independent parser with the same language" do
    parser = TreeSitter::Parser.new("json")
    clone = parser.clone

    clone.should_not be(parser)
    clone.language.name.should eq("json")
    clone.parse(nil, "[1]").not_nil!.root_node.type.should eq("document")
  end

  it "reports whether a logger has been configured" do
    parser = TreeSitter::Parser.new("json")
    parser.logger.should be_nil

    parser.set_logger { |_type, _message| }
    parser.logger.should_not be_nil
    parser.stop_logging
    parser.logger.should be_nil
  end

  it "supports a channel-based parser pool" do
    parsers = Channel(TreeSitter::Parser).new(1)
    results = Channel(String).new(1)
    parsers.send(TreeSitter::Parser.new("json"))

    spawn do
      parser = parsers.receive
      results.send(parser.parse(nil, "[1]").not_nil!.root_node.type)
      parsers.send(parser)
    end

    results.receive.should eq("document")
    parsers.receive.language.name.should eq("json")
  end

  it "supports an independent parser per fiber" do
    results = Channel(String).new(1)

    spawn do
      parser = TreeSitter::Parser.new("json")
      results.send(parser.parse(nil, "[null]").not_nil!.root_node.type)
    end

    results.receive.should eq("document")
  end
end
