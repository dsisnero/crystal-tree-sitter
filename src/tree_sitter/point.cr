module TreeSitter
  # A point is a line/column tuple.
  struct Point
    @point : LibTreeSitter::TSPoint

    def initialize(@point)
    end

    def initialize(row : Int32, column : Int32)
      @point = LibTreeSitter::TSPoint.new(row: row, column: column)
    end

    delegate row, to: @point
    delegate :row=, to: @point
    delegate column, to: @point
    delegate :column=, to: @point

    def ==(other : Tuple(Int32, Int32))
      @point.row == other[0] && @point.column == other[1]
    end

    # Returns the point as a tuple of {row, column}.
    def to_tuple : Tuple(Int32, Int32)
      {row, column}
    end

    # Edit the point to keep it in-sync with source code that has been edited,
    # returning the edited byte offset alongside the edited point.
    #
    # The `byte` argument is the byte offset associated with this point.
    def edit(edit : LibTreeSitter::TSInputEdit, byte : UInt32) : {Point, UInt32}
      edited_byte = byte
      LibTreeSitter.ts_point_edit(pointerof(@point), pointerof(edited_byte), pointerof(edit))
      {Point.new(@point), edited_byte}
    end

    def inspect(io : IO)
      io << '{' << row << ", " << column << '}'
    end

    def to_unsafe
      @point
    end
  end
end
