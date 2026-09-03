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
      @captures.compact_map do |capture|
        capture.node if capture.index == capture_ix
      end
    end

    # Remove this match from the query cursor.
    #
    # Removes a match from the query cursor so that it will not be returned
    # again by future calls to `next_match`.
    def remove(cursor : QueryCursor) : Nil
      LibTreeSitter.ts_query_cursor_remove_match(cursor, @id)
    end

    # Evaluate this match's text-based query predicates against the given
    # source text.
    #
    # Mirrors Rust's `QueryMatch::satisfies_text_predicates`. The C ABI no
    # longer exposes a native `ts_query_cursor_satisfies_text_predicates`, so
    # this binding evaluates the predicates itself using the pattern's parsed
    # predicates and the capture text read from `source`.
    #
    # Only the text predicates are evaluated — `#eq?`, `#not-eq?`,
    # `#any-eq?`, `#any-not-eq?`, `#match?`, `#not-match?`, `#any-match?`,
    # `#any-not-match?`, `#any-of?`, and `#not-any-of?`. Property predicates
    # (`#set!`, `#is?`, `#is-not?`) and general predicates are ignored.
    #
    # This is the primitive used by the `QueryCursor` streaming iterators that
    # take a `source` (`Iterator(Capture)` via `#captures(source)`,
    # `Iterator(Match)` via `#matches(source)`, and the matching `#next_*` pull
    # methods), mirroring Rust's `QueryMatches` / `QueryCaptures` streams.
    def satisfies_text_predicates?(query : Query, source : String) : Bool
      query.predicates_for_pattern(pattern_index).each do |predicate|
        case predicate.name
        when "eq?", "not-eq?", "any-eq?", "any-not-eq?"
          return false unless equal_text_predicate?(query, predicate, source)
        when "match?", "not-match?", "any-match?", "any-not-match?"
          return false unless match_text_predicate?(query, predicate, source)
        when "any-of?", "not-any-of?"
          return false unless any_of_text_predicate?(query, predicate, source)
        end
      end
      true
    end

    # Resolve a predicate capture argument to a numeric capture index through
    # the query's capture-name table.
    private def arg_capture_index(query : Query, predicate : Predicate, arg : Predicate::Arg) : UInt32
      query.capture_index_for_name(arg.value) ||
        raise("cannot resolve capture '#{arg.value}' for predicate '#{predicate.name}'")
    end

    # eq? family: compare captured node text against a string or another capture.
    private def equal_text_predicate?(query : Query, predicate : Predicate, source : String) : Bool
      capture_arg = predicate.args.find(&.capture?)
      return true if capture_arg.nil?
      capture_ix = arg_capture_index(query, predicate, capture_arg)
      nodes = nodes_for_capture_index(capture_ix)

      value_arg = predicate.args.find(&.string?)
      if value_arg
        value = value_arg.value
        results = nodes.map { |node| node.text(source) == value }
      else
        comparison = predicate.args.find { |a| a.capture? && a != capture_arg }
        return true if comparison.nil?
        other_ix = arg_capture_index(query, predicate, comparison)
        other_texts = nodes_for_capture_index(other_ix).map(&.text(source))
        # Compare each captured node against every other captured node.
        results = nodes.map do |node|
          other_texts.any? { |other| node.text(source) == other }
        end
      end

      aggregate(results, predicate.name)
    end

    # match? family: test captured node text against a regex string literal.
    private def match_text_predicate?(query : Query, predicate : Predicate, source : String) : Bool
      capture_arg = predicate.args.find(&.capture?)
      regex_arg = predicate.args.find(&.string?)
      return true if capture_arg.nil? || regex_arg.nil?
      capture_ix = arg_capture_index(query, predicate, capture_arg)
      nodes = nodes_for_capture_index(capture_ix)
      regex = Regex.new(regex_arg.value)
      results = nodes.map { |node| regex.matches?(node.text(source)) }
      aggregate(results, predicate.name)
    end

    # any-of? family: check captured node text against a list of string literals.
    private def any_of_text_predicate?(query : Query, predicate : Predicate, source : String) : Bool
      capture_arg = predicate.args.find(&.capture?)
      return true if capture_arg.nil?
      capture_ix = arg_capture_index(query, predicate, capture_arg)
      nodes = nodes_for_capture_index(capture_ix)
      values = predicate.args.select(&.string?).map(&.value)
      results = nodes.map { |node| values.includes?(node.text(source)) }
      aggregate(results, predicate.name)
    end

    # Aggregate per-node results using Enumerable semantics that mirror the
    # Rust binding's intended `all`/`any` plus positive/negative flags:
    #
    #   eq?/match?            all nodes must pass    -> results.all?
    #   not-eq?/not-match?    all nodes must fail    -> results.none?
    #   any-eq?/any-match?    some node must pass    -> results.any?
    #   any-not-*             some node must fail    -> results.any? { |r| !r }
    #
    # Note: the upstream Rust `satisfies_text_predicates` falls through to
    # `true` for the `any-*` cases even when nothing matches, which makes them
    # vacuously pass. This Crystal port keeps the intended (non-vacuous)
    # semantics instead.
    private def aggregate(results : Array(Bool), name : String) : Bool
      match_all = !name.starts_with?("any-")
      positive = !name.starts_with?("not-") && !name.starts_with?("any-not-")

      if match_all
        positive ? results.all? : results.none?
      elsif positive
        # ameba:disable Performance/AnyInsteadOfPresent -- Array(Bool)#present? means non-empty, not "any true".
        results.any?
      else
        results.any? { |r| !r }
      end
    end
  end

  # A stateful object for executing a query on a syntax tree.
  #
  # A `QueryCursor` carries mutable iteration state and must not be shared across
  # fibers/threads simultaneously.
  class QueryCursor
    @cursor : LibTreeSitter::TSQueryCursor*
    @query_options : LibTreeSitter::TSQueryCursorOptions*
    @progress_callback : ProgressCallback?
    property query : Query

    # State reported to an `#exec_with_options` progress callback.
    struct ProgressState
      getter current_byte_offset : UInt32

      def initialize(state : LibTreeSitter::TSQueryCursorState)
        @current_byte_offset = state.current_byte_offset.to_u32
      end
    end

    alias ProgressCallback = Proc(ProgressState, Bool)

    # Create a new cursor for executing a given query.
    #
    # The cursor stores the state that is needed to iteratively search
    # for matches. To use the query cursor, call `QueryCursor#exec`
    # to start running the given query on a given syntax node.
    def initialize(@query)
      @cursor = LibTreeSitter.ts_query_cursor_new
      @query_options = Pointer(LibTreeSitter::TSQueryCursorOptions).null
      @progress_callback = nil
    end

    def finalize
      LibTreeSitter.ts_query_cursor_delete(self)
    end

    # Start running a given query on a given node.
    #
    # Use `#next_capture` to fetch the captures.
    def exec(node : Node)
      @progress_callback = nil
      @query_options = Pointer(LibTreeSitter::TSQueryCursorOptions).null
      LibTreeSitter.ts_query_cursor_exec(self, @query, node)
    end

    # Start running a query with a progress callback. Returning `true` from the
    # callback stops query execution; subsequent iteration returns no more results.
    def exec_with_options(node : Node, &progress : ProgressCallback) : Nil
      @progress_callback = progress
      @query_options = Pointer(LibTreeSitter::TSQueryCursorOptions).malloc(1)
      @query_options.value.payload = Box.box(progress)
      @query_options.value.progress_callback = ->(state : LibTreeSitter::TSQueryCursorState*) do
        callback = Box(ProgressCallback).unbox(state.value.payload)
        callback.call(ProgressState.new(state.value))
      end
      LibTreeSitter.ts_query_cursor_exec_with_options(self, @query, node, @query_options)
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
      return if LibTreeSitter.ts_node_is_null(capture.node)

      rule = capture_name_for(capture)
      Capture.new(rule, Node.new_unsafe(capture.node), capture.index.to_u32)
    end

    # Returns the next capture whose match satisfies its text predicates, or
    # *nil*.
    #
    # Mirrors Rust's `QueryCaptures` streaming iterator: when a candidate
    # capture's match fails its text predicates, the match is removed from the
    # cursor (so it is not yielded or revisited) and the next capture is pulled.
    def next_capture(source : String) : Capture?
      loop do
        ok = LibTreeSitter.ts_query_cursor_next_capture(self, out match, out capture_index)
        return unless ok

        capture = match.captures[capture_index]
        next if LibTreeSitter.ts_node_is_null(capture.node)

        full = build_match(match)
        if full.satisfies_text_predicates?(@query, source)
          rule = capture_name_for(capture)
          return Capture.new(rule, Node.new_unsafe(capture.node), capture.index.to_u32)
        else
          full.remove(self)
        end
      end
    end

    def each_capture(& : Capture -> Nil)
      while capture = next_capture
        yield capture
      end
    end

    # Returns the next match or *nil*.
    # A match contains all captures for a pattern.
    def next_match : Match?
      match = LibTreeSitter::TSQueryMatch.new
      ok = LibTreeSitter.ts_query_cursor_next_match(self, pointerof(match))
      return unless ok
      build_match(match)
    end

    # Returns the next match that satisfies its text predicates, or *nil*.
    #
    # Mirrors Rust's `QueryMatches` streaming iterator: candidate matches that
    # fail their text predicates are skipped on the fly and never yielded.
    def next_match(source : String) : Match?
      loop do
        match = next_match
        return if match.nil?
        return match if match.satisfies_text_predicates?(@query, source)
      end
    end

    def each_match(& : Match -> Nil)
      while match = next_match
        yield match
      end
    end

    # Return a lazy, streaming `Iterator(Match)` over the cursor's matches,
    # filtering each match by its text predicates against `source`.
    #
    # This is the Crystal analogue of Rust's `QueryMatches::StreamingIterator`:
    # elements are pulled one at a time via `Iterator(Match)#next`, and
    # `Iterator`'s `select`/`reject`/`map`/`take` chain lazily without
    # materializing the full result set. Matches that fail their text
    # predicates are skipped on the fly.
    def matches(source : String) : MatchIterator
      MatchIterator.new(self, source)
    end

    # Return a lazy, streaming `Iterator(Capture)` over the cursor's captures,
    # filtering each capture's match by its text predicates against `source`.
    #
    # This is the Crystal analogue of Rust's `QueryCaptures::StreamingIterator`.
    # Captures whose match fails its text predicates are removed from the cursor
    # (via `Match#remove`) so they are never re-emitted.
    def captures(source : String) : CaptureIterator
      CaptureIterator.new(self, source)
    end

    # Build a `Match` wrapper from the raw C match struct.
    private def build_match(match : LibTreeSitter::TSQueryMatch) : Match
      captures = Array(Capture).new(match.capture_count)
      match.capture_count.times do |i|
        capture = match.captures[i]
        # Skip null nodes in captures
        next if LibTreeSitter.ts_node_is_null(capture.node)

        captures << Capture.new(capture_name_for(capture), Node.new_unsafe(capture.node), capture.index.to_u32)
      end

      Match.new(match.pattern_index, captures, match.id.to_u32)
    end

    # Return the maximum number of in-progress matches for this cursor.
    def match_limit : UInt32
      LibTreeSitter.ts_query_cursor_match_limit(self)
    end

    # Set the maximum number of in-progress matches for this cursor.
    #
    # The limit must be > 0 and <= 65536.
    # ameba:disable Naming/AccessorMethodName -- fluent alias, use `match_limit=`
    def set_match_limit(limit : UInt32) : Nil
      LibTreeSitter.ts_query_cursor_set_match_limit(self, limit)
    end

    # Set the maximum number of in-progress matches for this cursor
    # (Crystal-style alias of `set_match_limit`).
    def match_limit=(limit : UInt32) : Nil
      set_match_limit(limit)
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
    # ameba:disable Naming/AccessorMethodName -- fluent alias, use `max_start_depth=`
    def set_max_start_depth(max_start_depth : UInt32) : Nil
      LibTreeSitter.ts_query_cursor_set_max_start_depth(self, max_start_depth)
    end

    # Set the maximum start depth for a query cursor (Crystal-style alias of
    # `set_max_start_depth`).
    def max_start_depth=(max_start_depth : UInt32) : Nil
      set_max_start_depth(max_start_depth)
    end

    # Set the maximum duration in microseconds that query execution should be
    # allowed to run before being halted.
    # ameba:disable Naming/AccessorMethodName -- fluent alias, use `timeout_micros=`
    def set_timeout_micros(timeout_micros : UInt64) : Nil
      LibTreeSitter.ts_query_cursor_set_timeout_micros(self, timeout_micros)
    end

    # Set the maximum duration in microseconds that query execution should be
    # allowed to run before being halted (Crystal-style alias of `set_timeout_micros`).
    def timeout_micros=(timeout_micros : UInt64) : Nil
      set_timeout_micros(timeout_micros)
    end

    # Get the maximum duration in microseconds that query execution is allowed
    # to run before being halted.
    def timeout_micros : UInt64
      LibTreeSitter.ts_query_cursor_timeout_micros(self)
    end

    # Resolve the capture name for a match capture, raising if it cannot be found.
    private def capture_name_for(capture) : String
      @query.capture_name_for_id(capture.index) || raise("failed to resolve capture name for id #{capture.index}")
    end

    def to_unsafe
      @cursor
    end

    # A lazy, streaming iterator over a cursor's matches, evaluating each
    # match's text predicates against a fixed `source`.
    #
    # Mirrors Rust's `QueryMatches`. Each `next` pulls the next qualifying
    # match from the underlying cursor, skipping those that fail their text
    # predicates.
    class MatchIterator
      include Iterator(Match)

      def initialize(@cursor : QueryCursor, @source : String)
      end

      def next : Match | Iterator::Stop
        @cursor.next_match(@source) || stop
      end
    end

    # A lazy, streaming iterator over a cursor's captures, evaluating each
    # capture's match text predicates against a fixed `source`.
    #
    # Mirrors Rust's `QueryCaptures`: a candidate whose match fails its text
    # predicates is removed from the cursor (via `Match#remove`) so it is not
    # re-emitted, then iteration continues with the next capture.
    class CaptureIterator
      include Iterator(Capture)

      def initialize(@cursor : QueryCursor, @source : String)
      end

      def next : Capture | Iterator::Stop
        @cursor.next_capture(@source) || stop
      end
    end
  end
end
