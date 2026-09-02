require "./spec_helper"

describe TreeSitter::Range do
  it "shifts a range after the edit by the insert delta" do
    range = TreeSitter::Range.new(5_u32, 8_u32, 0, 5, 0, 8)
    edit = LibTreeSitter::TSInputEdit.new(
      start_byte: 1_u32,
      old_end_byte: 1_u32,
      new_end_byte: 3_u32,
      start_point: LibTreeSitter::TSPoint.new(row: 0, column: 1),
      old_end_point: LibTreeSitter::TSPoint.new(row: 0, column: 1),
      new_end_point: LibTreeSitter::TSPoint.new(row: 0, column: 3),
    )
    range.edit(edit)
    range.start_byte.should eq(7)
    range.end_byte.should eq(10)
    range.start_point.should eq(TreeSitter::Point.new(0, 7))
    range.end_point.should eq(TreeSitter::Point.new(0, 10))
  end

  it "leaves a range before the edit unchanged" do
    range = TreeSitter::Range.new(0_u32, 0_u32, 0, 0, 0, 0)
    edit = LibTreeSitter::TSInputEdit.new(
      start_byte: 1_u32,
      old_end_byte: 1_u32,
      new_end_byte: 3_u32,
      start_point: LibTreeSitter::TSPoint.new(row: 0, column: 1),
      old_end_point: LibTreeSitter::TSPoint.new(row: 0, column: 1),
      new_end_point: LibTreeSitter::TSPoint.new(row: 0, column: 3),
    )
    range.edit(edit)
    range.start_byte.should eq(0)
    range.end_byte.should eq(0)
    range.start_point.should eq(TreeSitter::Point.new(0, 0))
    range.end_point.should eq(TreeSitter::Point.new(0, 0))
  end
end
