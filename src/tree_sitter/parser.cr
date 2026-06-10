require "./language"
require "./tree"

module TreeSitter
  # A `Parser` is a stateful object that can be assigned a `Language` and used to produce a `Tree`
  # based on some source code.
  class Parser
    @parser : LibTreeSitter::TSParser*

    # Used on `Parser#parse` method, the 2 parameters are
    # - byte index
    # - position
    # Return value must be a Bytes object with the data or nil if there's no more data.
    alias ReadProc = Proc(UInt32, Point, Bytes?)

    def initialize(language_name : String)
      initialize(language: Language.new(language_name))
    end

    # Create a new parser.
    def initialize(*, language : Language? = nil)
      @parser = LibTreeSitter.ts_parser_new
      self.language = language if language
    end

    # :nodoc:
    def finalize
      LibTreeSitter.ts_parser_delete(to_unsafe)
    end

    # Set the language that the parser should use for parsing.
    #
    # Raises `Error` if the language version is incompatible with treesitter library.
    def language=(language : Language) : Language
      ok = LibTreeSitter.ts_parser_set_language(to_unsafe, language)
      raise Error.new("Incompatible language") unless ok

      language
    end

    # Get the parser's current language.
    def language : Language
      ptr = LibTreeSitter.ts_parser_language(to_unsafe)
      raise Error.new("Parser without language!") if ptr.null?

      Language.new(ptr)
    end

    def parse?(old_tree : Tree?, io : IO) : Tree?
      parse?(old_tree) do |index, _pos|
        io.seek(index)
        io.getb_to_end
      end
    end

    def parse(old_tree : Tree?, io : IO) : Tree?
      parse?(old_tree, io) || raise Error.new("Parser error")
    end

    def parse?(old_tree : Tree?, string : String) : Tree?
      ptr = LibTreeSitter.ts_parser_parse_string(to_unsafe, old_tree, string, string.bytesize)

      Tree.new(ptr) if ptr
    end

    def parse(old_tree : Tree?, string : String) : Tree
      parse?(old_tree, string) || raise Error.new("Parser error")
    end

    # Parse a string and provide a progress callback that receives the current byte index.
    def parse_with_progress(old_tree : Tree?, string : String, &progress : UInt32 ->) : Tree?
      data = {string, progress}
      input = LibTreeSitter::TSInput.new
      input.payload = Box.box(data)
      input.encoding = LibTreeSitter::TSInputEncoding::UTF8
      input.read = ->(payload : Pointer(Void), index : UInt32, pos : LibTreeSitter::TSPoint, read : Pointer(UInt32)) do
        tuple = Box({String, Proc(UInt32, Nil)}).unbox(payload)
        src = tuple[0]
        cb = tuple[1]
        if index < src.bytesize
          slice = src.to_slice[index..]
          cb.call(index)
          read.value = slice.size.to_u32
          slice.to_unsafe
        else
          read.value = 0
          Pointer(LibC::Char).null
        end
      end
      ptr = LibTreeSitter.ts_parser_parse(to_unsafe, old_tree, input)
      Tree.new(ptr) if ptr
    end

    def parse?(old_tree : Tree?, &block : ReadProc) : Tree?
      input = LibTreeSitter::TSInput.new
      input.payload = Box.box(block)
      input.encoding = LibTreeSitter::TSInputEncoding::UTF8
      input.read = ->(payload : Pointer(Void), index : UInt32, pos : LibTreeSitter::TSPoint, read : Pointer(UInt32)) do
        callback = Box(ReadProc).unbox(payload)
        bytes = callback.call(index, Point.new(pos))
        if bytes.nil?
          read.value = 0
          Pointer(LibC::Char).null
        else
          read.value = bytes.size.to_u32
          bytes.to_unsafe
        end
      end

      ptr = LibTreeSitter.ts_parser_parse(to_unsafe, old_tree, input)
      Tree.new(ptr) if ptr
    end

    def parse(old_tree : Tree?, &block : ReadProc) : Tree
      parse?(old_tree, block) || raise Error.new("Parser error")
    end

    # Instruct the parser to start the next parse from the beginning.
    #
    # If the parser previously failed because of a timeout or a cancellation, then
    # by default, it will resume where it left off on the next call to
    # `#parse` or other parsing methods. If you don't want to resume,
    # and instead intend to use this parser to parse some other document, you must
    # call `#reset` first.
    def reset
      LibTreeSitter.ts_parser_reset(to_unsafe)
    end

    # Set the file descriptor to which the parser should write debugging graphs
    # during parsing. The graphs are formatted in the DOT language. You may want
    # to pipe these graphs directly to a `dot(1)` process in order to generate
    # SVG output. You can turn off this logging by passing nil.
    def print_dot_graphs(io : IO::FileDescriptor?) : Nil
      fd = io.nil? ? -1 : io.fd
      LibTreeSitter.ts_parser_print_dot_graphs(to_unsafe, fd)
    end

    # Stop the parser from printing debugging graphs while parsing.
    def stop_printing_dot_graphs : Nil
      LibTreeSitter.ts_parser_print_dot_graphs(to_unsafe, -1)
    end

    # Get the ranges of text that the parser will include when parsing.
    def included_ranges : Range::Iterator
      ranges = LibTreeSitter.ts_parser_included_ranges(to_unsafe, out length)
      Range::Iterator.new(ranges, length)
    end

    # Set the ranges of text that the parser should include when parsing.
    #
    # By default, the parser will always include entire documents. This
    # function allows you to parse only a *portion* of a document but
    # still return a syntax tree whose ranges match up with the document
    # as a whole. You can also pass multiple disjoint ranges.
    #
    # If `ranges` is empty, then the entire document will be parsed.
    # Otherwise, the given ranges must be ordered from earliest to latest
    # in the document, and they must not overlap. Returns true on success.
    def set_included_ranges(ranges : Array(Range)) : Bool
      LibTreeSitter.ts_parser_set_included_ranges(to_unsafe, ranges.to_unsafe, ranges.size.to_u32)
    end

    # Set the maximum duration in microseconds that parsing should be allowed to
    # take before halting.
    #
    # If parsing takes longer than this, it will halt early, returning nil.
    # See `#parse` for more information.
    def set_timeout_micros(timeout_micros : UInt64) : Nil
      LibTreeSitter.ts_parser_set_timeout_micros(to_unsafe, timeout_micros)
    end

    # Get the duration in microseconds that parsing is allowed to take.
    def timeout_micros : UInt64
      LibTreeSitter.ts_parser_timeout_micros(to_unsafe)
    end

    # Set the logging callback that the parser should use during parsing.
    #
    # The parser does not take ownership over the logger payload. If a logger was
    # previously assigned, the caller is responsible for releasing any memory
    # owned by the previous logger.
    def set_logger(&block : (LibTreeSitter::TSLogType, String) -> Nil) : Nil
      payload = Box.box(block)
      logger = LibTreeSitter::TSLogger.new
      logger.payload = payload
      logger.log = ->(p : Void*, type : LibTreeSitter::TSLogType, msg : LibC::Char*) do
        callback = Box(typeof(block)).unbox(p)
        callback.call(type, String.new(msg))
      end
      LibTreeSitter.ts_parser_set_logger(to_unsafe, logger)
    end

    # Stop the parsing logger, disabling any log output.
    def stop_logging : Nil
      logger = LibTreeSitter::TSLogger.new
      logger.payload = Pointer(Void).null
      logger.log = ->(p : Void*, type : LibTreeSitter::TSLogType, msg : LibC::Char*) { }
      LibTreeSitter.ts_parser_set_logger(to_unsafe, logger)
    end

    # :nodoc:
    def to_unsafe
      @parser
    end
  end
end
