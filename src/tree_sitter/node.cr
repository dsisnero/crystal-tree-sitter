require "string_pool"
require "./point.cr"

module TreeSitter
  # A `Node` represents a single node in the syntax tree. It tracks its start and end positions in
  # the source code, as well as its relation to other nodes like its parent, siblings and children.
  #
  # `Node` is a value type (a `struct`) referencing its parent tree, so it is copied on assignment
  # and safe to pass between fibers/threads as long as the referenced tree is alive.
  struct Node
    @node : LibTreeSitter::TSNode
    @@string_pool = StringPool.new

    # :nodoc:
    def self.string_pool : StringPool
      @@string_pool
    end

    # :nodoc:
    protected def self.new_unsafe(node : LibTreeSitter::TSNode) : Node
      Node.new(node)
    end

    # :nodoc:
    def initialize(@node)
      # Check if the underlying C node is null
      if LibTreeSitter.ts_node_is_null(@node)
        raise ArgumentError.new("Cannot create Node from null TSNode")
      end
    end

    # Get the node's number of children
    def child_count : UInt32
      LibTreeSitter.ts_node_child_count(to_unsafe)
    end

    # Get the node's number of *named* children.
    #
    # See also `#named?`
    def named_child_count : UInt32
      LibTreeSitter.ts_node_named_child_count(to_unsafe)
    end

    # Get the node's *named* child at the given index.
    #
    # See also `#named?`
    def named_child(index : Int32) : Node?
      raise IndexError.new if index < 0 || index >= named_child_count
      node = LibTreeSitter.ts_node_named_child(to_unsafe, index)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Check if the node is *named*. Named nodes correspond to named rules in the
    # grammar, whereas *anonymous* nodes correspond to string literals in the
    # grammar.
    def named? : Bool
      LibTreeSitter.ts_node_is_named(to_unsafe)
    end

    # Check if the node is *missing*. Missing nodes are inserted by the parser in
    # order to recover from certain kinds of syntax errors.
    def missing? : Bool
      LibTreeSitter.ts_node_is_missing(to_unsafe)
    end

    # Check if the node is *extra*. Extra nodes represent things like comments,
    # which are not required the grammar, but can appear anywhere.
    def extra? : Bool
      LibTreeSitter.ts_node_is_extra(to_unsafe)
    end

    # Check if a syntax node has been edited.
    def has_changes? : Bool
      LibTreeSitter.ts_node_has_changes(self)
    end

    # Check if the node is a syntax error or contains any syntax errors.
    def has_error? : Bool
      LibTreeSitter.ts_node_has_error(self)
    end

    # Get the node's immediate parent.
    #
    # Prefer `#child_with_descendant` for iterating over ancestors.
    def parent : Node?
      parent_node = LibTreeSitter.ts_node_parent(self)
      return if LibTreeSitter.ts_node_is_null(parent_node)
      Node.new_unsafe(parent_node)
    end

    def child_with_descendant(descendant : Node) : Node?
      node = LibTreeSitter.ts_node_child_with_descendant(self, descendant)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the node's child at the given index, where zero represents the first
    # child.
    #
    # Raises `IndexError` if index is out of bounds.
    def child(index : Int32) : Node
      raise IndexError.new if index < 0 || index >= child_count

      node = LibTreeSitter.ts_node_child(self, index.to_u32)
      if LibTreeSitter.ts_node_is_null(node)
        raise "TreeSitter returned null node for child at index #{index}"
      end
      Node.new_unsafe(node)
    end

    # Iterate over all children of this node.
    def children : Iterator(Node)
      ChildrenIterator.new(self)
    end

    # Yield each child to a block. Faster than `children.each` for tight loops.
    def each_child(& : Node ->) : Nil
      unsafe = to_unsafe
      count = LibTreeSitter.ts_node_child_count(unsafe)
      i = 0u32
      while i < count
        node = LibTreeSitter.ts_node_child(unsafe, i)
        unless LibTreeSitter.ts_node_is_null(node)
          yield Node.new_unsafe(node)
        end
        i += 1
      end
    end

    # Yield each *named* child to a block. Faster than `named_children.each`
    # because it avoids cursor allocation and Iterator overhead.
    #
    # For cursor reuse across multiple iterations, use `named_children(cursor)`.
    # For single-use iteration with zero overhead, use `each_named_child`.
    def each_named_child(& : Node ->) : Nil
      unsafe = to_unsafe
      count = LibTreeSitter.ts_node_named_child_count(unsafe)
      i = 0u32
      while i < count
        node = LibTreeSitter.ts_node_named_child(unsafe, i)
        unless LibTreeSitter.ts_node_is_null(node)
          yield Node.new_unsafe(node)
        end
        i += 1
      end
    end

    # Iterate over only named children using a reusable cursor.
    #
    # See also `#named?`
    def named_children(cursor : TreeCursor) : NamedChildrenIterator
      cursor.reset(self)
      cursor.goto_first_child
      NamedChildrenIterator.new(cursor, named_child_count)
    end

    # Convenience overload that creates its own cursor.
    #
    # For repeated iterations, prefer `named_children(cursor)` with a reused
    # cursor to avoid allocating a new `TreeCursor` each time (~6.5× faster).
    def named_children : NamedChildrenIterator
      named_children(walk)
    end

    # Iterate over children with a given field name using a reusable cursor.
    def children_by_field_name(field_name : String, cursor : TreeCursor) : ChildrenByFieldNameIterator
      field_id = language.field_id_for_name(field_name)
      cursor.reset(self)
      cursor.goto_first_child
      ChildrenByFieldNameIterator.new(cursor, field_id)
    end

    # Iterate over children with a given field id using a reusable cursor.
    #
    # See also `#children_by_field_name`
    def children_by_field_id(field_id : UInt16, cursor : TreeCursor) : ChildrenByFieldIdIterator
      cursor.reset(self)
      cursor.goto_first_child
      ChildrenByFieldIdIterator.new(cursor, field_id)
    end

    # Get the node's type as a String.
    def type : String
      cstr = LibTreeSitter.ts_node_type(to_unsafe)
      @@string_pool.get(cstr, LibC.strlen(cstr))
    end

    # Get the node's start byte.
    def start_byte : UInt32
      LibTreeSitter.ts_node_start_byte(to_unsafe)
    end

    # Get the node's end byte.
    def end_byte : UInt32
      LibTreeSitter.ts_node_end_byte(to_unsafe)
    end

    # Get the node's start position in terms of rows and columns.
    def start_point : Point
      Point.new(LibTreeSitter.ts_node_start_point(to_unsafe))
    end

    # Get the node's end position in terms of rows and columns.
    def end_point : Point
      Point.new(LibTreeSitter.ts_node_end_point(to_unsafe))
    end

    # Get the smallest node within this node that spans the given byte range.
    def descendant(start_byte : UInt32, end_byte : UInt32) : Node?
      ptr = LibTreeSitter.ts_node_descendant_for_byte_range(to_unsafe, start_byte, end_byte)
      return if LibTreeSitter.ts_node_is_null(ptr)
      Node.new_unsafe(ptr)
    end

    # Get the smallest node within this node that spans the given point range.
    def descendant(start_point : Point, end_point : Point) : Node?
      ptr = LibTreeSitter.ts_node_descendant_for_point_range(to_unsafe, start_point, end_point)
      return if LibTreeSitter.ts_node_is_null(ptr)
      Node.new_unsafe(ptr)
    end

    def ==(other : Node) : Bool
      LibTreeSitter.ts_node_eq(self, other)
    end

    # Get the node's next sibling.
    def next_sibling : Node?
      node = LibTreeSitter.ts_node_next_sibling(self)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the node's previous sibling.
    def prev_sibling : Node?
      node = LibTreeSitter.ts_node_prev_sibling(self)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the node's next named sibling.
    def next_named_sibling : Node?
      node = LibTreeSitter.ts_node_next_named_sibling(self)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the node's previous named sibling.
    def prev_named_sibling : Node?
      node = LibTreeSitter.ts_node_prev_named_sibling(self)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Check if the node is a syntax error. Syntax errors represent parts of the
    # code that could not be incorporated into a valid syntax tree.
    def error? : Bool
      LibTreeSitter.ts_node_is_error(self)
    end

    # Get the node's child with the given numerical field id.
    #
    # See also `#child_by_field_name`
    def child_by_field_id(field_id : UInt16) : Node?
      node = LibTreeSitter.ts_node_child_by_field_id(self, field_id)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the parse state after this node.
    def next_parse_state : UInt16
      LibTreeSitter.ts_node_next_parse_state(to_unsafe).to_u16
    end

    # Get the node's child with the given field name.
    def child_by_field_name(field_name : String) : Node?
      node = LibTreeSitter.ts_node_child_by_field_name(self, field_name, field_name.bytesize.to_u32)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the field name of this node's child at the given index.
    def field_name_for_child(child_index : UInt32) : String?
      ptr = LibTreeSitter.ts_node_field_name_for_child(self, child_index)
      return if ptr.null?
      @@string_pool.get(ptr, LibC.strlen(ptr))
    end

    # Get the field name of this node's named child at the given index.
    def field_name_for_named_child(named_child_index : UInt32) : String?
      ptr = LibTreeSitter.ts_node_field_name_for_named_child(self, named_child_index)
      return if ptr.null?
      @@string_pool.get(ptr, LibC.strlen(ptr))
    end

    # Get the smallest node within this node that spans the given byte range.
    def descendant_for_byte_range(start_byte : UInt32, end_byte : UInt32) : Node?
      node = LibTreeSitter.ts_node_descendant_for_byte_range(self, start_byte, end_byte)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the smallest node within this node that spans the given point range.
    def descendant_for_point_range(start_point : Point, end_point : Point) : Node?
      node = LibTreeSitter.ts_node_descendant_for_point_range(self, start_point, end_point)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the Language that was used to parse this node's syntax tree.
    def language : Language
      ptr = LibTreeSitter.ts_node_language(to_unsafe)
      Language.new(ptr)
    end

    # Get the node's parse state.
    def parse_state : UInt16
      LibTreeSitter.ts_node_parse_state(to_unsafe).to_u16
    end

    # Create a new TreeCursor starting from this node.
    def walk : TreeCursor
      TreeCursor.new(self)
    end

    # Get the node's first child that contains or starts after the given byte offset.
    def first_child_for_byte(byte : UInt32) : Node?
      node = LibTreeSitter.ts_node_first_child_for_byte(self, byte)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the node's first named child that contains or starts after the given byte offset.
    def first_named_child_for_byte(byte : UInt32) : Node?
      node = LibTreeSitter.ts_node_first_named_child_for_byte(self, byte)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the node's number of descendants, including one for the node itself.
    def descendant_count : UInt32
      LibTreeSitter.ts_node_descendant_count(self)
    end

    # Get the smallest named node within this node that spans the given byte range.
    def named_descendant_for_byte_range(start_byte : UInt32, end_byte : UInt32) : Node?
      node = LibTreeSitter.ts_node_named_descendant_for_byte_range(self, start_byte, end_byte)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the smallest named node within this node that spans the given point range.
    def named_descendant_for_point_range(start_point : Point, end_point : Point) : Node?
      node = LibTreeSitter.ts_node_named_descendant_for_point_range(self, start_point, end_point)
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the byte range of source code that this node represents.
    def byte_range : Tuple(UInt32, UInt32)
      {start_byte, end_byte}
    end

    # Get the complete source range represented by this node.
    def range : Range
      Range.new(start_byte, end_byte, start_point, end_point)
    end

    # Get a numeric id for this node that is unique. Within a given syntax tree,
    # no two nodes have the same id.
    def id : LibC::ULong
      @node.id.address
    end

    # Get the node's type as a numerical id.
    def kind_id : UInt16
      LibTreeSitter.ts_node_symbol(to_unsafe).to_u16
    end

    # Get the node's type as a numerical id as it appears in the grammar ignoring aliases.
    def grammar_id : UInt16
      LibTreeSitter.ts_node_grammar_symbol(to_unsafe).to_u16
    end

    # Get the node's symbol name as it appears in the grammar ignoring aliases.
    def grammar_name : String
      ptr = LibTreeSitter.ts_node_grammar_type(to_unsafe)
      @@string_pool.get(ptr, LibC.strlen(ptr))
    end

    # Get an S-expression representing the node as a string.
    def to_s(io : IO)
      ptr = LibTreeSitter.ts_node_string(to_unsafe)
      bytes = Bytes.new(ptr, LibC.strlen(ptr))
      io.write(bytes)
    end

    # Get the source text covered by this node.
    def text(source : String) : String
      start_pos = start_byte
      end_pos = end_byte
      slice = source.byte_slice(start_pos, end_pos - start_pos)
      @@string_pool.get(slice)
    end

    # Get the UTF-16 code units covered by this node.
    def utf16_text(source : Slice(UInt16)) : Slice(UInt16)
      source[start_byte // 2, (end_byte - start_byte) // 2]
    end

    # :nodoc:
    def to_unsafe
      @node
    end
  end

  # Iterator for node children
  private class ChildrenIterator
    include Iterator(Node)

    def initialize(@node : Node)
      @index = 0u32
      @count = LibTreeSitter.ts_node_child_count(@node.to_unsafe)
    end

    def next : Node | Iterator::Stop
      if @index < @count
        raw = LibTreeSitter.ts_node_child(@node.to_unsafe, @index)
        @index += 1
        return Node.new_unsafe(raw) unless LibTreeSitter.ts_node_is_null(raw)
        self.next
      else
        stop
      end
    end
  end

  # Iterator for named children using a tree cursor.
  private class NamedChildrenIterator
    include Iterator(Node)

    def initialize(@cursor : TreeCursor, @remaining : UInt32)
      @started = false
    end

    def next : Node | Iterator::Stop
      return stop if @remaining == 0
      cursor_ptr = @cursor.unsafe_cursor_ptr
      if @started
        unless LibTreeSitter.ts_tree_cursor_goto_next_sibling(cursor_ptr)
          return stop
        end
      else
        @started = true
      end
      loop do
        raw_node = LibTreeSitter.ts_tree_cursor_current_node(cursor_ptr)
        if LibTreeSitter.ts_node_is_named(raw_node)
          @remaining -= 1
          return Node.new_unsafe(raw_node)
        end
        unless LibTreeSitter.ts_tree_cursor_goto_next_sibling(cursor_ptr)
          return stop
        end
      end
    end
  end

  # Iterator for children with a given field name using a tree cursor.
  private class ChildrenByFieldNameIterator
    include Iterator(Node)

    @field_id : UInt16

    def initialize(@cursor : TreeCursor, field_id : UInt16)
      @field_id = field_id
      @done = @field_id == 0
    end

    def next : Node | Iterator::Stop
      return stop if @done
      cursor_ptr = @cursor.unsafe_cursor_ptr
      while @cursor.current_field_id != @field_id
        unless LibTreeSitter.ts_tree_cursor_goto_next_sibling(cursor_ptr)
          @done = true
          return stop
        end
      end
      raw_node = LibTreeSitter.ts_tree_cursor_current_node(cursor_ptr)
      unless LibTreeSitter.ts_tree_cursor_goto_next_sibling(cursor_ptr)
        @done = true
      end
      Node.new_unsafe(raw_node)
    end
  end

  # Iterator for children with a given field id using a tree cursor.
  private class ChildrenByFieldIdIterator
    include Iterator(Node)

    @field_id : UInt16

    def initialize(@cursor : TreeCursor, field_id : UInt16)
      @field_id = field_id
      @done = @field_id == 0
    end

    def next : Node | Iterator::Stop
      return stop if @done
      cursor_ptr = @cursor.unsafe_cursor_ptr
      while @cursor.current_field_id != @field_id
        unless LibTreeSitter.ts_tree_cursor_goto_next_sibling(cursor_ptr)
          @done = true
          return stop
        end
      end
      raw_node = LibTreeSitter.ts_tree_cursor_current_node(cursor_ptr)
      unless LibTreeSitter.ts_tree_cursor_goto_next_sibling(cursor_ptr)
        @done = true
      end
      Node.new_unsafe(raw_node)
    end
  end

  # A stateful cursor for walking a syntax tree efficiently
  #
  # A `TreeCursor` carries mutable walk state and must not be shared across
  # fibers/threads simultaneously.
  class TreeCursor
    @cursor : LibTreeSitter::TSTreeCursor

    # Create a new cursor starting at the given node
    def initialize(node : Node)
      @cursor = LibTreeSitter.ts_tree_cursor_new(node)
    end

    # :nodoc:
    protected def initialize_copy(other : TreeCursor)
      @cursor = LibTreeSitter.ts_tree_cursor_copy(pointerof(other.@cursor))
    end

    # :nodoc:
    def finalize
      LibTreeSitter.ts_tree_cursor_delete(pointerof(@cursor))
    end

    # Get the cursor's current node
    def current_node : Node?
      node = LibTreeSitter.ts_tree_cursor_current_node(pointerof(@cursor))
      return if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the field name of the cursor's current node
    def current_field_name : String?
      ptr = LibTreeSitter.ts_tree_cursor_current_field_name(pointerof(@cursor))
      return if ptr.null?
      # Access the string pool through a class method
      Node.string_pool.get(ptr, LibC.strlen(ptr))
    end

    # Get the field id of the cursor's current node
    def current_field_id : UInt16
      LibTreeSitter.ts_tree_cursor_current_field_id(pointerof(@cursor)).to_u16
    end

    # Move the cursor to the parent of its current node
    def goto_parent : Bool
      LibTreeSitter.ts_tree_cursor_goto_parent(pointerof(@cursor))
    end

    # Move the cursor to the next sibling of its current node
    def goto_next_sibling : Bool
      LibTreeSitter.ts_tree_cursor_goto_next_sibling(pointerof(@cursor))
    end

    # Move the cursor to the previous sibling of its current node
    def goto_previous_sibling : Bool
      LibTreeSitter.ts_tree_cursor_goto_previous_sibling(pointerof(@cursor))
    end

    # Move the cursor to the first child of its current node
    def goto_first_child : Bool
      LibTreeSitter.ts_tree_cursor_goto_first_child(pointerof(@cursor))
    end

    # Move the cursor to the last child of its current node
    def goto_last_child : Bool
      LibTreeSitter.ts_tree_cursor_goto_last_child(pointerof(@cursor))
    end

    # Get the current depth of the cursor
    def current_depth : UInt32
      LibTreeSitter.ts_tree_cursor_current_depth(pointerof(@cursor))
    end

    # Reset the cursor to a new node
    def reset(node : Node) : Nil
      LibTreeSitter.ts_tree_cursor_reset(pointerof(@cursor), node)
    end

    # Reset the cursor to another cursor's position
    def reset_to(other : TreeCursor) : Nil
      LibTreeSitter.ts_tree_cursor_reset_to(pointerof(@cursor), pointerof(other.@cursor))
    end

    # Get the index of the cursor's current node out of all descendants of the
    # original node that the cursor was constructed with.
    def descendant_index : UInt32
      LibTreeSitter.ts_tree_cursor_current_descendant_index(pointerof(@cursor))
    end

    # Move the cursor to the nth descendant of the original node, where zero
    # represents the original node itself.
    def goto_descendant(goal_descendant_index : UInt32) : Nil
      LibTreeSitter.ts_tree_cursor_goto_descendant(pointerof(@cursor), goal_descendant_index)
    end

    # Move the cursor to the first child of its current node that contains or
    # starts after the given byte offset. Returns the child index.
    def goto_first_child_for_byte(start_byte : UInt32, end_byte : UInt32) : UInt64
      LibTreeSitter.ts_tree_cursor_goto_first_child_for_byte(pointerof(@cursor), start_byte, end_byte)
    end

    # Move the cursor to the first child of its current node that contains or
    # starts after the given point. Returns the child index.
    def goto_first_child_for_point(start_point : Point, end_point : Point) : UInt64
      LibTreeSitter.ts_tree_cursor_goto_first_child_for_point(pointerof(@cursor), start_point, end_point)
    end

    def copy : TreeCursor
      result = TreeCursor.allocate
      result.initialize_copy(self)
      result
    end

    protected def unsafe_cursor_ptr
      pointerof(@cursor)
    end
  end
end
