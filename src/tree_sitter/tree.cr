require "./node"

module TreeSitter
  # A `Tree` represents the syntax tree of an entire source code file. It contains `Node` instances
  # that indicate the structure of the source code. It can also be edited and used to produce a new
  # `Tree` in the event that the source code changes.
  #
  # Individual `Tree` instances are not thread-safe. To share a tree across fibers/threads, pass a
  # copy made with `#copy` (a fast, shallow, reference-counted copy).
  class Tree
    @tree : LibTreeSitter::TSTree*

    # :nodoc:
    protected def initialize(@tree)
    end

    # :nodoc:
    def finalize
      LibTreeSitter.ts_tree_delete(to_unsafe)
    end

    # Create a shallow copy of the syntax tree. This is very fast.
    #
    # You need to copy a syntax tree in order to use it on more than one thread at
    # a time, as syntax trees are not thread safe.
    def copy : Tree
      Tree.new(LibTreeSitter.ts_tree_copy(to_unsafe))
    end

    # Get the root node of the syntax tree.
    def root_node : Node
      Node.new(LibTreeSitter.ts_tree_root_node(to_unsafe))
    end

    def changed_ranges(old_tree : Tree) : Range::Iterator
      ranges = LibTreeSitter.ts_tree_get_changed_ranges(old_tree, self, out length)
      Range::Iterator.new(ranges, length)
    end

    # Get the root node of the syntax tree, but with its position
    # shifted forward by the given offset.
    def root_node_with_offset(offset_bytes : UInt32, offset_extent : Point) : Node
      Node.new(LibTreeSitter.ts_tree_root_node_with_offset(to_unsafe, offset_bytes, offset_extent))
    end

    # Get the language that was used to parse the syntax tree.
    def language : Language
      ptr = LibTreeSitter.ts_tree_language(to_unsafe)
      Language.new(ptr)
    end

    # Create a new `TreeCursor` starting from the root of the tree.
    def walk : TreeCursor
      TreeCursor.new(root_node)
    end

    # Get the array of included ranges that was used to parse the syntax tree.
    def included_ranges : Range::Iterator
      ranges = LibTreeSitter.ts_tree_included_ranges(to_unsafe, out length)
      Range::Iterator.new(ranges, length)
    end

    # Write a DOT graph describing the syntax tree to the given file.
    def save_dot(io : IO::FileDescriptor)
      LibTreeSitter.ts_tree_print_dot_graph(to_unsafe, io.fd)
    end

    # Write a DOT graph describing the syntax tree to the given file.
    def save_dot(file : Path | String)
      File.open(file, "w") do |f|
        save_dot(f)
      end
    end

    # Write a PNG graph describing the syntax tree to the given file.
    def save_png(file : Path | String) : Nil
      tempfile = File.tempfile("tree")
      save_dot(tempfile)
      tempfile.close
      `dot -Tpng #{tempfile.path} > #{file}`
    ensure
      tempfile.try(&.delete)
    end

    # :nodoc:
    def to_unsafe
      @tree
    end
  end
end
