require "./spec_helper"

describe "TreeSitter::Node API completeness" do
  it "reports that parent() should return Node? but returns Node" do
    # Check the method signature by reading source
    # This is a documentation test since we can't test the type at runtime
    source_file = File.read("src/tree_sitter/node.cr")

    # Look for parent method definition
    if source_file.includes?("def parent : Node\n") && !source_file.includes?("def parent : Node?\n")
      # Current implementation returns Node (without ?)
      puts "  ❌ parent() returns Node (should return Node?)"
      false.should be_true # This will fail
    elsif source_file.includes?("def parent : Node?\n")
      puts "  ✓ parent() returns Node?"
      true.should be_true
    else
      puts "  ? Could not find parent method with expected signature"
      # Check if it's there but with different formatting
      if source_file.includes?("def parent")
        puts "  Found parent method but signature check failed"
      end
      true.should be_true
    end
  end

  it "reports missing children iterator" do
    source_file = File.read("src/tree_sitter/node.cr")

    if source_file.includes?("def children") || source_file.includes?("def each_child")
      puts "  ✓ Has children iterator"
      true.should be_true
    else
      puts "  ❌ Missing children iterator"
      false.should be_true # This will fail
    end
  end

  it "reports missing child_by_field_name method" do
    source_file = File.read("src/tree_sitter/node.cr")

    if source_file.includes?("def child_by_field_name")
      puts "  ✓ Has child_by_field_name method"
      true.should be_true
    else
      puts "  ❌ Missing child_by_field_name method"
      false.should be_true # This will fail
    end
  end

  it "reports missing sibling methods" do
    source_file = File.read("src/tree_sitter/node.cr")

    has_next_sibling = source_file.includes?("def next_sibling")
    has_prev_sibling = source_file.includes?("def prev_sibling")

    if has_next_sibling && has_prev_sibling
      puts "  ✓ Has both sibling methods"
      true.should be_true
    else
      puts "  ❌ Missing sibling methods (next_sibling: #{has_next_sibling}, prev_sibling: #{has_prev_sibling})"
      false.should be_true # This will fail
    end
  end
end