require "./lib_tree_sitter"
require "./tree_sitter/parser"
require "./tree_sitter/repository"
require "./tree_sitter/highlighter"
require "./tree_sitter/query"
require "./tree_sitter/query_cursor"
require "./tree_sitter/editor"
require "./tree_sitter/range"
require "./tree_sitter/lookahead_iterator"

private def calloc(n : LibC::SizeT, size : LibC::SizeT) : Pointer(Void)
  GC.malloc(n * size)
end

module TreeSitter
  VERSION = "0.1.0"

  LANGUAGE_VERSION                = LibTreeSitter::TREE_SITTER_LANGUAGE_VERSION
  MIN_COMPATIBLE_LANGUAGE_VERSION = LibTreeSitter::TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION

  # Base class for all TreeSitter errors.
  class Error < RuntimeError
  end

  class QueryError < Error
    enum Kind
      Syntax
      NodeType
      Field
      Capture
      Structure
      Language
    end

    getter offset : UInt32
    getter kind : Kind
    getter row : UInt32
    getter column : UInt32

    def initialize(@offset, @kind, @row = 0, @column = 0)
      super("#{kind} at offset #{offset}")
    end

    def self.from_c(error_offset : UInt32, error_type : LibTreeSitter::TSQueryError) : self
      kind = case error_type
             when .syntax?    then Kind::Syntax
             when .node_type? then Kind::NodeType
             when .field?     then Kind::Field
             when .capture?   then Kind::Capture
             when .structure? then Kind::Structure
             when .language?  then Kind::Language
             else                  Kind::Syntax
             end
      new(error_offset, kind)
    end
  end

  enum CaptureQuantifier
    Zero       = 0
    ZeroOrOne  = 1
    ZeroOrMore = 2
    One        = 3
    OneOrMore  = 4
  end

  enum SymbolType
    Regular
    Anonymous
    Auxiliary
  end

  protected class_getter string_pool = StringPool.new

  # Init tree-sitter by telling it to use the Crystal GC as memory allocator.
  # This is called automatically when you require tree-sitter unless you compile with `-Dcrystal_tree_sitter_no_init`.
  def init
    LibTreeSitter.ts_set_allocator(->GC.malloc, ->calloc, ->GC.realloc, ->GC.free)
  end

  extend self

  def format_sexp(sexp : String, initial_indent_level : UInt32 = 0) : String
    String.build do |io|
      indent = initial_indent_level
      last_was_close = false
      sexp.each_char do |c|
        case c
        when '('
          unless last_was_close
            io << '\n'
            indent.times { io << ' ' }
          end
          io << '('
          indent += 1
          last_was_close = false
        when ')'
          indent -= 1
          io << ')'
          last_was_close = true
        when ' '
          io << ' '
        else
          io << c
        end
      end
    end
  end
end

{% unless flag?(:crystal_tree_sitter_no_init) %}
  TreeSitter.init
{% end %}
