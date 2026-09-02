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
end
