require "./capture"

module TreeSitter
  # A match of a query to a particular set of nodes.
  class Match
    getter pattern_index : UInt16
    getter captures : Array(Capture)
    getter id : UInt32

    def initialize(@pattern_index, @captures, @id)
    end

    def nodes_for_capture_index(capture_ix : UInt32) : Array(Node)
      @captures.compact_map { |capture|
        capture.node if capture.index == capture_ix
      }
    end

    # Remove this match from the query cursor.
    #
    # Removes a match from the query cursor so that it will not be returned
    # again by future calls to `next_match`.
    def remove(cursor : QueryCursor) : Nil
      LibTreeSitter.ts_query_cursor_remove_match(cursor, @id)
    end
  end

  # A stateful object for executing a query on a syntax tree.
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

    # Set the byte range within which all matches must be fully contained.
    #
    # In contrast to `set_byte_range`, this will restrict the query cursor to
    # only return matches where _all_ nodes are _fully_ contained within the
    # given range. Both methods can be used together, e.g. to search for any
    # matches that intersect a given line, as long as they are fully contained
    # within a given range.
    def set_containing_byte_range(start_byte : UInt32, end_byte : UInt32) : Bool
      LibTreeSitter.ts_query_cursor_set_containing_byte_range(self, start_byte, end_byte)
    end

    # Set the point range within which all matches must be fully contained.
    #
    # In contrast to `set_point_range`, this will restrict the query cursor to
    # only return matches where _all_ nodes are _fully_ contained within the
    # given range. Both methods can be used together, e.g. to search for any
    # matches that intersect a given line, as long as they are fully contained
    # within a given range.
    def set_containing_point_range(start_point : Point, end_point : Point) : Bool
      LibTreeSitter.ts_query_cursor_set_containing_point_range(self, start_point, end_point)
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
      Capture.new(rule, Node.new_unsafe(capture.node), capture.index.to_u32)
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
        captures << Capture.new(rule, Node.new_unsafe(capture.node), capture.index.to_u32)
      end

      Match.new(match.pattern_index, captures, match.id.to_u32)
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

    # Return the maximum number of in-progress matches for this cursor.
    def match_limit : UInt32
      LibTreeSitter.ts_query_cursor_match_limit(self)
    end

    # Set the maximum number of in-progress matches for this cursor.
    #
    # The limit must be > 0 and <= 65536.
    def set_match_limit(limit : UInt32) : Nil
      LibTreeSitter.ts_query_cursor_set_match_limit(self, limit)
    end

    # Check if, on its last execution, this cursor exceeded its maximum number
    # of in-progress matches.
    def did_exceed_match_limit? : Bool
      LibTreeSitter.ts_query_cursor_did_exceed_match_limit(self)
    end

    # Set the maximum start depth for a query cursor.
    #
    # This prevents cursors from exploring children nodes at a certain depth.
    # Note if a pattern includes many children, then they will still be
    # checked.
    #
    # The zero max start depth value can be used as a special behavior and
    # it helps to destructure a subtree by staying on a node and using
    # captures for interested parts. Note that the zero max start depth
    # only limits a search depth for a pattern's root node but other nodes
    # that are parts of the pattern may be searched at any depth depending on
    # what is defined by the pattern structure.
    def set_max_start_depth(max_start_depth : UInt32) : Nil
      LibTreeSitter.ts_query_cursor_set_max_start_depth(self, max_start_depth)
    end

    # Set the maximum duration in microseconds that query execution should be
    # allowed to run before being halted.
    def set_timeout_micros(timeout_micros : UInt64) : Nil
      LibTreeSitter.ts_query_cursor_set_timeout_micros(self, timeout_micros)
    end

    # Get the maximum duration in microseconds that query execution is allowed
    # to run before being halted.
    def timeout_micros : UInt64
      LibTreeSitter.ts_query_cursor_timeout_micros(self)
    end

    def to_unsafe
      @cursor
    end
  end
end
