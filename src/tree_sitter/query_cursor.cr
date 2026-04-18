require "./capture"

module TreeSitter
  # A match of a query to a particular set of nodes
  class Match
    getter pattern_index : UInt16
    getter captures : Array(Capture)

    def initialize(@pattern_index, @captures)
    end
  end

  class QueryCursor
    @cursor : LibTreeSitter::TSQueryCursor*
    property query : Query

    # Create a new cursor for executing a given query.
    #
    # The cursor stores the state that is needed to iteratively search
    # for matches. To use the query cursor, call `QueryCursor#exec`
    # to start running the given query on a given syntax node.
    def initialize(@query)
      @cursor = LibTreeSitter.ts_query_cursor_new
    end

    def finalize
      LibTreeSitter.ts_query_cursor_delete(self)
    end

    # Start running a given query on a given node.
    #
    # Use `#next_capture` to fetch the captures.
    def exec(node : Node)
      LibTreeSitter.ts_query_cursor_exec(self, @query, node)
    end

    # Start running a given query on a given node.
    #
    # Yield the capture name and the node
    def exec(node : Node, &)
      exec(node)
      loop do
        capture = next_capture
        return if capture.nil?

        yield(capture)
      end
    end

    # Set the range of row, column positions in which the query will be executed.
    def set_point_range(start_row : Int32, start_column : Int32, end_row : Int32, end_column : Int32)
      start_point = LibTreeSitter::TSPoint.new(row: start_row, column: start_column)
      end_point = LibTreeSitter::TSPoint.new(row: end_row, column: end_column)
      LibTreeSitter.ts_query_cursor_set_point_range(self, start_point, end_point)
    end

    # Set the range of row, column positions in which the query will be executed.
    def set_point_range(start_point : Point, end_point : Point)
      LibTreeSitter.ts_query_cursor_set_point_range(self, start_point, end_point)
    end

    # Set the range of bytes in which the query will be executed.
    def set_byte_range(start_byte : UInt32, end_byte : UInt32)
      LibTreeSitter.ts_query_cursor_set_byte_range(self, start_byte, end_byte)
    end

    # Returns the next capture or *nil*.
    def next_capture : Capture?
      ok = LibTreeSitter.ts_query_cursor_next_capture(self, out match, out capture_index)
      return unless ok

      capture = match.captures[capture_index]
      return nil if LibTreeSitter.ts_node_is_null(capture.node)

      ptr = LibTreeSitter.ts_query_capture_name_for_id(@query, capture.index, out strlen)
      rule = TreeSitter.string_pool.get(ptr, strlen)
      Capture.new(rule, Node.new_unsafe(capture.node))
    end

    # Returns the next match or *nil*.
    # A match contains all captures for a pattern.
    def next_match : Match?
      match = LibTreeSitter::TSQueryMatch.new
      ok = LibTreeSitter.ts_query_cursor_next_match(self, pointerof(match))
      return unless ok

      # Collect all captures for this match
      captures = Array(Capture).new(match.capture_count)
      match.capture_count.times do |i|
        capture = match.captures[i]
        # Skip null nodes in captures
        next if LibTreeSitter.ts_node_is_null(capture.node)

        ptr = LibTreeSitter.ts_query_capture_name_for_id(@query, capture.index, out strlen)
        rule = TreeSitter.string_pool.get(ptr, strlen)
        captures << Capture.new(rule, Node.new_unsafe(capture.node))
      end

      Match.new(match.pattern_index, captures)
    end

    def each_capture(& : Capture -> Nil)
      while capture = next_capture
        yield capture
      end
    end

    def each_match(& : Match -> Nil)
      while match = next_match
        yield match
      end
    end

    def to_unsafe
      @cursor
    end
  end
end
