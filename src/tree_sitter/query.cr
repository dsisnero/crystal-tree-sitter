require "./predicate"

module TreeSitter
  # A query consists of one or more patterns, where each pattern is an S-expression
  # that matches a certain set of nodes in a syntax tree. The expression to match a
  # given node consists of a pair of parentheses containing two things: the node's type,
  # and optionally, a series of other S-expressions that match the node's children.
  class Query
    @query : LibTreeSitter::TSQuery*

    # Create a new query from a string containing one or more S-expression
    # patterns. The query is associated with a particular language, and can
    # only be run on syntax nodes parsed with that language.
    #
    # If all of the given patterns are valid, this returns a `Query`.
    # If a pattern is invalid, this raises an `Error` exception that provides two pieces
    # of information about the problem:
    # 1. The byte offset of the error.
    # 2. The type of error.
    def initialize(language : Language, source : String)
      query = LibTreeSitter.ts_query_new(language, source, source.bytesize, out error_offset, out error_type)
      if error_type.none?
        @query = query
      else
        # FIXME: This is horrible, transform this into a set of exceptions with a nice error message.
        raise Error.new("#{error_type} at #{error_offset}")
      end
    end

    # :nodoc:
    def finalize
      LibTreeSitter.ts_query_delete(to_unsafe)
    end

    def pattern_count : UInt32
      LibTreeSitter.ts_query_pattern_count(to_unsafe)
    end

    def capture_count : UInt32
      LibTreeSitter.ts_query_capture_count(to_unsafe)
    end

    def string_count : UInt32
      LibTreeSitter.ts_query_string_count(to_unsafe)
    end

    # Get the name of a capture by its numeric id.
    def capture_name_for_id(index : UInt32) : String?
      ptr = LibTreeSitter.ts_query_capture_name_for_id(to_unsafe, index, out strlen)
      return nil if ptr.null?
      TreeSitter.string_pool.get(ptr, strlen)
    end

    # Get the string value of a query string literal by its numeric id.
    def string_value_for_id(index : UInt32) : String?
      ptr = LibTreeSitter.ts_query_string_value_for_id(to_unsafe, index, out strlen)
      return nil if ptr.null?
      TreeSitter.string_pool.get(ptr, strlen)
    end

    def start_byte_for_pattern(pattern_index : UInt32) : UInt32
      LibTreeSitter.ts_query_start_byte_for_pattern(to_unsafe, pattern_index)
    end

    def end_byte_for_pattern(pattern_index : UInt32) : UInt32
      LibTreeSitter.ts_query_end_byte_for_pattern(to_unsafe, pattern_index)
    end

    def capture_names : Array(String)
      Array(String).new(capture_count) do |i|
        capture_name_for_id(i.to_u32).not_nil!
      end
    end

    def capture_index_for_name(name : String) : UInt32?
      capture_count.times do |i|
        n = capture_name_for_id(i.to_u32)
        return i.to_u32 if n == name
      end
      nil
    end

    def disable_capture(name : String) : Nil
      LibTreeSitter.ts_query_disable_capture(to_unsafe, name, name.bytesize.to_u32)
    end

    def disable_pattern(pattern_index : UInt32) : Nil
      LibTreeSitter.ts_query_disable_pattern(to_unsafe, pattern_index)
    end

    def is_pattern_rooted?(pattern_index : UInt32) : Bool
      LibTreeSitter.ts_query_is_pattern_rooted(to_unsafe, pattern_index)
    end

    def is_pattern_non_local?(pattern_index : UInt32) : Bool
      LibTreeSitter.ts_query_is_pattern_non_local(to_unsafe, pattern_index)
    end

    def is_pattern_guaranteed_at_step?(byte_offset : UInt32) : Bool
      LibTreeSitter.ts_query_is_pattern_guaranteed_at_step(to_unsafe, byte_offset)
    end

    def capture_quantifier_for_id(pattern_index : UInt32, capture_index : UInt32) : CaptureQuantifier
      CaptureQuantifier.from_value(
        LibTreeSitter.ts_query_capture_quantifier_for_id(to_unsafe, pattern_index, capture_index).value
      )
    end

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

      current_args = [] of Predicate::Arg
      predicate_name = ""

      step_count.times do |i|
        step = steps[i]
        next if step.type.done?

        case step.type
        when .capture?
          cap_name = capture_name_for_id(step.value_id)
          next unless cap_name

          # First capture in a predicate is the predicate name
          if predicate_name.empty?
            predicate_name = cap_name
          else
            current_args << Predicate::Arg.capture(cap_name)
          end
        when .string?
          str_val = string_value_for_id(step.value_id)
          next unless str_val

          # First string in a predicate is the predicate name
          if predicate_name.empty?
            predicate_name = str_val
          else
            current_args << Predicate::Arg.string(str_val)
          end
        end

        # Check if the next step or our current position signals done
        next_step = (i + 1 < step_count) ? steps[i + 1] : nil
        if next_step.nil? || next_step.type.done?
          unless predicate_name.empty?
            predicates << Predicate.new(predicate_name, current_args)
          end
          predicate_name = ""
          current_args = [] of Predicate::Arg
        end
      end

      predicates
    end

    # :nodoc:
    def to_unsafe
      @query
    end
  end
end
