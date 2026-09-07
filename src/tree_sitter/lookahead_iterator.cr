require "./language"

module TreeSitter
  # A stateful object that is used to look up symbols valid in a specific parse
  # state.
  #
  # Lookahead iterators can be useful to generate suggestions and improve
  # syntax error diagnostics. To get symbols valid in an ERROR node, use the
  # lookahead iterator on its first leaf node state. For MISSING nodes, a
  # lookahead iterator created on the previous non-extra leaf node may be
  # appropriate.
  class LookaheadIterator
    include Iterator(UInt16)

    @iterator : LibTreeSitter::TSLookaheadIterator*

    def initialize(language : Language, state : UInt16)
      @iterator = LibTreeSitter.ts_lookahead_iterator_new(language, state)
      raise Error.new("Failed to create lookahead iterator") if @iterator.null?
    end

    def finalize
      LibTreeSitter.ts_lookahead_iterator_delete(@iterator) unless @iterator.null?
    end

    # Get the current symbol of the lookahead iterator.
    def current_symbol : UInt16
      LibTreeSitter.ts_lookahead_iterator_current_symbol(@iterator).to_u16
    end

    # Get the current symbol name of the lookahead iterator.
    def current_symbol_name : String
      ptr = LibTreeSitter.ts_lookahead_iterator_current_symbol_name(@iterator)
      raise Error.new("No current symbol name") if ptr.null?
      String.new(ptr)
    end

    # Get the current language of the lookahead iterator.
    def language : Language
      ptr = LibTreeSitter.ts_lookahead_iterator_language(@iterator)
      raise Error.new("No language") if ptr.null?
      Language.new(ptr)
    end

    # Reset the lookahead iterator to another state.
    #
    # Returns `true` if the iterator was reset to the given state and `false`
    # otherwise.
    def reset(state : UInt16) : Bool
      LibTreeSitter.ts_lookahead_iterator_reset_state(@iterator, state)
    end

    # Reset the lookahead iterator.
    #
    # Returns `true` if the language was set successfully and `false`
    # otherwise.
    def reset(language : Language, state : UInt16) : Bool
      LibTreeSitter.ts_lookahead_iterator_reset(@iterator, language, state)
    end

    def next : UInt16 | Iterator::Stop
      return stop unless LibTreeSitter.ts_lookahead_iterator_next(@iterator)
      current_symbol
    end

    # Iterate over the symbol names.
    #
    # Returns an iterator that yields the string name of each symbol in the
    # lookahead.
    def iter_names : Iterator(String)
      LookaheadNamesIterator.new(@iterator)
    end

    def to_unsafe
      @iterator
    end
  end

  private class LookaheadNamesIterator
    include Iterator(String)

    def initialize(@iterator : LibTreeSitter::TSLookaheadIterator*)
    end

    def next : String | Iterator::Stop
      return stop unless LibTreeSitter.ts_lookahead_iterator_next(@iterator)
      ptr = LibTreeSitter.ts_lookahead_iterator_current_symbol_name(@iterator)
      return stop if ptr.null?
      TreeSitter.intern(ptr, LibC.strlen(ptr))
    end
  end
end
