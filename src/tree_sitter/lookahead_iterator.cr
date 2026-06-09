require "./language"

module TreeSitter
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

    def current_symbol : UInt16
      LibTreeSitter.ts_lookahead_iterator_current_symbol(@iterator).to_u16
    end

    def current_symbol_name : String
      ptr = LibTreeSitter.ts_lookahead_iterator_current_symbol_name(@iterator)
      raise Error.new("No current symbol name") if ptr.null?
      String.new(ptr)
    end

    def language : Language
      ptr = LibTreeSitter.ts_lookahead_iterator_language(@iterator)
      raise Error.new("No language") if ptr.null?
      Language.new(ptr)
    end

    def reset(state : UInt16) : Bool
      LibTreeSitter.ts_lookahead_iterator_reset_state(@iterator, state)
    end

    def reset(language : Language, state : UInt16) : Bool
      LibTreeSitter.ts_lookahead_iterator_reset(@iterator, language, state)
    end

    def next : UInt16 | Iterator::Stop
      return stop unless LibTreeSitter.ts_lookahead_iterator_next(@iterator)
      current_symbol
    end

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
      String.new(ptr)
    end
  end
end
