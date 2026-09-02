require "./spec_helper"

describe LibTreeSitter::TSInputEncoding do
  it "matches the C ABI enum values (v0.27.0)" do
    LibTreeSitter::TSInputEncoding::UTF8.value.should eq(0)
    LibTreeSitter::TSInputEncoding::UTF16LE.value.should eq(1)
    LibTreeSitter::TSInputEncoding::UTF16BE.value.should eq(2)
    LibTreeSitter::TSInputEncoding::Custom.value.should eq(3)
  end
end

describe "TSDecodeFunction binding" do
  it "binds TSDecodeFunction as a callable that decodes a code point" do
    decoder = ->(_string : UInt8*, _length : UInt32, code_point : Int32*) : UInt32 {
      code_point.value = 65 # 'A'
      1_u32
    }
    cp = 0
    bytes = decoder.call(Pointer(UInt8).malloc(1), 1_u32, pointerof(cp))
    cp.should eq(65)
    bytes.should eq(1)
  end

  it "exposes a decode field on TSInput compatible with the decode proc" do
    input = LibTreeSitter::TSInput.new
    decoder = ->(string : UInt8*, _length : UInt32, code_point : Int32*) : UInt32 {
      code_point.value = string.null? ? 0 : string.value.to_i32
      1_u32
    }
    input.decode = decoder
    input.encoding = LibTreeSitter::TSInputEncoding::Custom
    input.decode.should eq(decoder)
  end
end

describe TreeSitter::Parser do
  it "parses source using a custom decoder" do
    parser = TreeSitter::Parser.new("json")
    decoder = ->(bytes : UInt8*, _length : UInt32, code_point : Int32*) : UInt32 {
      code_point.value = bytes[0].to_i32
      1_u32
    }

    tree = parser.parse_custom_encoding(nil, "[1]".to_slice, decoder)
    tree.not_nil!.root_node.type.should eq("document")
  end

  it "handles an invalid custom code point without crashing" do
    decoder = ->(_bytes : UInt8*, _length : UInt32, code_point : Int32*) : UInt32 {
      code_point.value = -1
      1_u32
    }

    tree = TreeSitter::Parser.new("json").parse_custom_encoding(nil, "[1]".to_slice, decoder)
    tree.should_not be_nil
    tree.not_nil!.root_node.has_error?.should be_true
  end
end
