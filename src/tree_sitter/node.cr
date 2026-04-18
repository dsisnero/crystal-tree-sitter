require "string_pool"
require "./point.cr"

module TreeSitter
  # A `Node` represents a single node in the syntax tree. It tracks its start and end positions in
  # the source code, as well as its relation to other nodes like its parent, siblings and children.
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
      return nil if LibTreeSitter.ts_node_is_null(node)
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
    def parent : Node?
      parent_node = LibTreeSitter.ts_node_parent(self)
      return nil if LibTreeSitter.ts_node_is_null(parent_node)
      Node.new_unsafe(parent_node)
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

    def descendant(start_byte : UInt32, end_byte : UInt32) : Node?
      ptr = LibTreeSitter.ts_node_descendant_for_byte_range(to_unsafe, start_byte, end_byte)
      return nil if LibTreeSitter.ts_node_is_null(ptr)
      Node.new_unsafe(ptr)
    end

    def descendant(start_point : Point, end_point : Point) : Node?
      ptr = LibTreeSitter.ts_node_descendant_for_point_range(to_unsafe, start_point, end_point)
      return nil if LibTreeSitter.ts_node_is_null(ptr)
      Node.new_unsafe(ptr)
    end

    def ==(other : Node) : Bool
      LibTreeSitter.ts_node_eq(self, other)
    end

    # Get the node's next sibling.
    def next_sibling : Node?
      node = LibTreeSitter.ts_node_next_sibling(self)
      return nil if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the node's previous sibling.
    def prev_sibling : Node?
      node = LibTreeSitter.ts_node_prev_sibling(self)
      return nil if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the node's child with the given field name.
    def child_by_field_name(field_name : String) : Node?
      node = LibTreeSitter.ts_node_child_by_field_name(self, field_name, field_name.bytesize.to_u32)
      return nil if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the field name of this node's child at the given index.
    def field_name_for_child(child_index : UInt32) : String?
      ptr = LibTreeSitter.ts_node_field_name_for_child(self, child_index)
      return nil if ptr.null?
      @@string_pool.get(ptr, LibC.strlen(ptr))
    end

    # Get the field name of this node's named child at the given index.
    def field_name_for_named_child(named_child_index : UInt32) : String?
      ptr = LibTreeSitter.ts_node_field_name_for_named_child(self, named_child_index)
      return nil if ptr.null?
      @@string_pool.get(ptr, LibC.strlen(ptr))
    end

    # Get the smallest node within this node that spans the given byte range.
    def descendant_for_byte_range(start_byte : UInt32, end_byte : UInt32) : Node?
      node = LibTreeSitter.ts_node_descendant_for_byte_range(self, start_byte, end_byte)
      return nil if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the smallest node within this node that spans the given point range.
    def descendant_for_point_range(start_point : Point, end_point : Point) : Node?
      node = LibTreeSitter.ts_node_descendant_for_point_range(self, start_point, end_point)
      return nil if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Create a tree cursor for walking the subtree rooted at this node
    def walk : TreeCursor
      TreeCursor.new(self)
    end

    # Get an S-expression representing the node as a string.
    def to_s(io : IO)
      ptr = LibTreeSitter.ts_node_string(to_unsafe)
      bytes = Bytes.new(ptr, LibC.strlen(ptr))
      io.write(bytes)
    end

    def text(source : String) : String
      start_pos = start_byte
      end_pos = end_byte
      slice = source.byte_slice(start_pos, end_pos - start_pos)
      @@string_pool.get(slice)
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
      @index = 0
      @count = @node.child_count
    end

    def next : Node | Iterator::Stop
      if @index < @count
        child = @node.child(@index)
        @index += 1
        child
      else
        stop
      end
    end
  end

  # A stateful cursor for walking a syntax tree efficiently
  class TreeCursor
    @cursor : LibTreeSitter::TSTreeCursor

    # Create a new cursor starting at the given node
    def initialize(node : Node)
      @cursor = LibTreeSitter.ts_tree_cursor_new(node)
    end

    # :nodoc:
    def finalize
      LibTreeSitter.ts_tree_cursor_delete(pointerof(@cursor))
    end

    # Get the cursor's current node
    def current_node : Node?
      node = LibTreeSitter.ts_tree_cursor_current_node(pointerof(@cursor))
      return nil if LibTreeSitter.ts_node_is_null(node)
      Node.new_unsafe(node)
    end

    # Get the field name of the cursor's current node
    def current_field_name : String?
      ptr = LibTreeSitter.ts_tree_cursor_current_field_name(pointerof(@cursor))
      return nil if ptr.null?
      # Access the string pool through a class method
      Node.string_pool.get(ptr, LibC.strlen(ptr))
    end

    # Get the field id of the cursor's current node
    def current_field_id : UInt16
      LibTreeSitter.ts_tree_cursor_current_field_id(pointerof(@cursor))
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
  end
end
