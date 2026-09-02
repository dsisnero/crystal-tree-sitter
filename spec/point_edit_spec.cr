require "./spec_helper"

describe TreeSitter::Point do
  # Insert two bytes at byte offset 1 (row 0, column 1).
  edit = LibTreeSitter::TSInputEdit.new(
    start_byte: 1_u32,
    old_end_byte: 1_u32,
    new_end_byte: 3_u32,
    start_point: LibTreeSitter::TSPoint.new(row: 0, column: 1),
    old_end_point: LibTreeSitter::TSPoint.new(row: 0, column: 1),
    new_end_point: LibTreeSitter::TSPoint.new(row: 0, column: 3),
  )

  it "shifts a point after the edit by the insert delta" do
    point, byte = TreeSitter::Point.new(0, 5).edit(edit, 5_u32)
    byte.should eq(7)
    point.should eq({0, 7})
  end

  it "leaves a point before the edit unchanged" do
    point, byte = TreeSitter::Point.new(0, 0).edit(edit, 0_u32)
    byte.should eq(0)
    point.should eq({0, 0})
  end

  it "collapses a point inside the edited region to the new end" do
    point, byte = TreeSitter::Point.new(0, 1).edit(edit, 1_u32)
    byte.should eq(3)
    point.should eq({0, 3})
  end
end
