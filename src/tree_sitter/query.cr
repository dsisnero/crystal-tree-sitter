require "./predicate"

module TreeSitter
  # A query consists of one or more patterns, where each pattern is an S-expression
  # that matches a certain set of nodes in a syntax tree. The expression to match a
  # given node consists of a pair of parentheses containing two things: the node's type,
  # and optionally, a series of other S-expressions that match the node's children.
  #
  # `Query` instances are immutable after creation and safe to share across fibers/threads.
  class Query
    @query : LibTreeSitter::TSQuery*
    @capture_names : Array(String)
    @string_values : Array(String)
    @pattern_count : UInt32
    @capture_count : UInt32
    @string_count : UInt32

    def initialize(language : Language, source : String)
      query = LibTreeSitter.ts_query_new(language, source, source.bytesize, out error_offset, out error_type)
      if error_type.none?
        @query = query
      else
        raise QueryError.from_c(error_offset, error_type)
      end
      @pattern_count = LibTreeSitter.ts_query_pattern_count(to_unsafe)
      @capture_count = LibTreeSitter.ts_query_capture_count(to_unsafe)
      @string_count = LibTreeSitter.ts_query_string_count(to_unsafe)
      @capture_names = Array(String).new(@capture_count) do |i|
        ptr = LibTreeSitter.ts_query_capture_name_for_id(to_unsafe, i.to_u32, out strlen)
        TreeSitter.string_pool.get(ptr, strlen)
      end
      @string_values = Array(String).new(@string_count) do |i|
        ptr = LibTreeSitter.ts_query_string_value_for_id(to_unsafe, i.to_u32, out strlen)
        TreeSitter.string_pool.get(ptr, strlen)
      end
    end

    # Construct a query without Rust-specific predicate validation.
    def self.new_raw(language : Language, source : String) : Query
      new(language, source)
    end

    protected def initialize(@query : LibTreeSitter::TSQuery*)
      @pattern_count = LibTreeSitter.ts_query_pattern_count(to_unsafe)
      @capture_count = LibTreeSitter.ts_query_capture_count(to_unsafe)
      @string_count = LibTreeSitter.ts_query_string_count(to_unsafe)
      @capture_names = Array(String).new(@capture_count) do |i|
        ptr = LibTreeSitter.ts_query_capture_name_for_id(to_unsafe, i.to_u32, out strlen)
        TreeSitter.string_pool.get(ptr, strlen)
      end
      @string_values = Array(String).new(@string_count) do |i|
        ptr = LibTreeSitter.ts_query_string_value_for_id(to_unsafe, i.to_u32, out strlen)
        TreeSitter.string_pool.get(ptr, strlen)
      end
    end

    # :nodoc:
    def finalize
      LibTreeSitter.ts_query_delete(to_unsafe)
    end

    def pattern_count : UInt32
      @pattern_count
    end

    def capture_count : UInt32
      @capture_count
    end

    def string_count : UInt32
      @string_count
    end

    # Get the name of a capture by its numeric id.
    def capture_name_for_id(index : UInt32) : String?
      @capture_names[index.to_i]?
    end

    # Get the string value of a query string literal by its numeric id.
    def string_value_for_id(index : UInt32) : String?
      @string_values[index.to_i]?
    end

    # Get the byte offset where the given pattern starts in the query's source.
    #
    # This can be useful when combining queries by concatenating their source
    # code strings.
    def start_byte_for_pattern(pattern_index : UInt32) : UInt32
      LibTreeSitter.ts_query_start_byte_for_pattern(to_unsafe, pattern_index)
    end

    # Get the byte offset where the given pattern ends in the query's source.
    #
    # This can be useful when combining queries by concatenating their source
    # code strings.
    def end_byte_for_pattern(pattern_index : UInt32) : UInt32
      LibTreeSitter.ts_query_end_byte_for_pattern(to_unsafe, pattern_index)
    end

    # Get the names of all captures used in the query.
    def capture_names : Array(String)
      Array(String).new(capture_count) do |i|
        name = capture_name_for_id(i.to_u32)
        raise "failed to load capture name for id #{i}" if name.nil?
        name
      end
    end

    # Get the index for a given capture name.
    def capture_index_for_name(name : String) : UInt32?
      capture_count.times do |i|
        n = capture_name_for_id(i.to_u32)
        return i.to_u32 if n == name
      end
      nil
    end

    # Disable a certain capture within a query.
    #
    # This prevents the capture from being returned in matches, and also avoids
    # any resource usage associated with recording the capture.
    def disable_capture(name : String) : Nil
      LibTreeSitter.ts_query_disable_capture(to_unsafe, name, name.bytesize.to_u32)
    end

    # Disable a certain pattern within a query.
    #
    # This prevents the pattern from matching and removes most of the overhead
    # associated with the pattern.
    def disable_pattern(pattern_index : UInt32) : Nil
      LibTreeSitter.ts_query_disable_pattern(to_unsafe, pattern_index)
    end

    # Create a deep copy of the query so it can be mutated independently.
    def copy : Query
      Query.new(LibTreeSitter.ts_query_copy(to_unsafe))
    end

    # Check if the given pattern in the query has a single root node.
    def pattern_rooted?(pattern_index : UInt32) : Bool
      LibTreeSitter.ts_query_is_pattern_rooted(to_unsafe, pattern_index)
    end

    # Check if the given pattern in the query is 'non local'.
    #
    # A non-local pattern has multiple root nodes and can match within a
    # repeating sequence of nodes, as specified by the grammar. Non-local
    # patterns disable certain optimizations that would otherwise be possible
    # when executing a query on a specific range of a syntax tree.
    def pattern_non_local?(pattern_index : UInt32) : Bool
      LibTreeSitter.ts_query_is_pattern_non_local(to_unsafe, pattern_index)
    end

    # Check if a given pattern is guaranteed to match once a given step is reached.
    # The step is specified by its byte offset in the query's source code.
    def pattern_guaranteed_at_step?(byte_offset : UInt32) : Bool
      LibTreeSitter.ts_query_is_pattern_guaranteed_at_step(to_unsafe, byte_offset)
    end

    # Get the quantifier of a capture for the given pattern and capture index.
    # Each capture is associated with a numeric id based on the order that it
    # appeared in the query's source.
    def capture_quantifier_for_id(pattern_index : UInt32, capture_index : UInt32) : CaptureQuantifier
      CaptureQuantifier.from_value(
        LibTreeSitter.ts_query_capture_quantifier_for_id(to_unsafe, pattern_index, capture_index).value
      )
    end

    # Get the capture quantifiers for all captures of a given pattern.
    def capture_quantifiers_for_pattern(pattern_index : UInt32) : Array(CaptureQuantifier)
      Array(CaptureQuantifier).new(capture_count) do |i|
        capture_quantifier_for_id(pattern_index, i.to_u32)
      end
    end

    # Parse and return all predicates for a given pattern index.
    #
    # Predicates are S-expressions in query patterns like:
    # `(#eq? @name "value")` or `(#set! @capture is_export)`
    #
    # Each predicate is returned as a `Predicate` object with a name and
    # list of arguments. Arguments are either captures (`@name`) or
    # string literals.
    def predicates_for_pattern(pattern_index : UInt32) : Array(Predicate)
      predicates = [] of Predicate
      return predicates if pattern_index >= pattern_count

      steps = LibTreeSitter.ts_query_predicates_for_pattern(to_unsafe, pattern_index, out step_count)
      return predicates if step_count == 0 || steps.null?

      predicate_name = ""
      current_args = [] of Predicate::Arg

      step_count.times do |i|
        step = steps[i]
        next if step.type.done?

        if arg = predicate_arg_for_step(step)
          if predicate_name.empty?
            predicate_name = arg.value
          else
            current_args << arg
          end
        end

        if boundary?(steps, i, step_count)
          unless predicate_name.empty?
            predicates << Predicate.new(predicate_name, current_args)
          end
          predicate_name = ""
          current_args = [] of Predicate::Arg
        end
      end

      predicates
    end

    # Get properties assigned by `#set!` predicates for a pattern.
    def property_settings(pattern_index : UInt32) : Array(QueryProperty)
      predicates_for_pattern(pattern_index).compact_map do |predicate|
        property_for(predicate) if predicate.name == "set!"
      end
    end

    # Get properties checked by `#is?` and `#is-not?` predicates. The boolean
    # is true for `#is?` and false for `#is-not?`.
    def property_predicates(pattern_index : UInt32) : Array(Tuple(QueryProperty, Bool))
      predicates_for_pattern(pattern_index).compact_map do |predicate|
        case predicate.name
        when "is?"
          property_for(predicate).try { |property| {property, true} }
        when "is-not?"
          property_for(predicate).try { |property| {property, false} }
        end
      end
    end

    # Get user-defined predicates excluding Tree-sitter's text and property predicates.
    def general_predicates(pattern_index : UInt32) : Array(Predicate)
      predicates_for_pattern(pattern_index).reject do |predicate|
        {"eq?", "not-eq?", "any-eq?", "any-not-eq?", "match?", "not-match?", "any-match?", "any-not-match?", "any-of?", "not-any-of?", "set!", "is?", "is-not?"}.includes?(predicate.name)
      end
    end

    # Return a `Predicate::Arg` for a given predicate step, or `nil` if the step
    # holds no value (e.g. `done`/`call` steps or an unresolved capture).
    private def predicate_arg_for_step(step) : Predicate::Arg?
      case step.type
      when .capture?
        capture_name_for_id(step.value_id).try { |name| Predicate::Arg.capture(name) }
      when .string?
        string_value_for_id(step.value_id).try { |value| Predicate::Arg.string(value) }
      end
    end

    private def property_for(predicate : Predicate) : QueryProperty?
      return if predicate.args.empty?
      capture_id = predicate.args.find(&.capture?).try { |arg| capture_index_for_name(arg.value) }
      strings = predicate.args.select(&.string?)
      key = strings[0]?.try(&.value)
      return if key.nil?
      QueryProperty.new(key, strings[1]?.try(&.value), capture_id)
    end

    # Whether the given step is the last step of a predicate.
    private def boundary?(steps, i, step_count) : Bool
      return true if i + 1 == step_count
      steps[i + 1].type.done?
    end

    # :nodoc:
    def to_unsafe
      @query
    end
  end
end
