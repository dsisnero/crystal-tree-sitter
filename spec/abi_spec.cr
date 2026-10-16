require "./spec_helper"

describe "Tree-sitter C ABI" do
  it "uses unsigned fixed-width integers in ABI fields" do
    sizeof(LibTreeSitter::TSStateId).should eq(sizeof(UInt16))
    sizeof(LibTreeSitter::TSSymbol).should eq(sizeof(UInt16))
    sizeof(LibTreeSitter::TSFieldId).should eq(sizeof(UInt16))
    sizeof(LibTreeSitter::TSQueryMatch).should eq(sizeof(Pointer(Void)) + 8)
  end
end
