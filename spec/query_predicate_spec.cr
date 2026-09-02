require "./spec_helper"

# Point to host project's grammar directories so tests can load grammars
TreeSitter::Config.parser_directories << Path.new(
  File.expand_path("../../../vendor/grammars", __DIR__)
)

describe TreeSitter::Query do
  describe "#predicates_for_pattern" do
    it "returns empty array for pattern with no predicates" do
      parser = TreeSitter::Parser.new("go")
      parser.parse(nil, "package main").not_nil!
      language = parser.language

      source = "(package_clause) @name"
      query = TreeSitter::Query.new(language, source)
      predicates = query.predicates_for_pattern(0)
      predicates.should be_empty
    end
  end

  it "validates malformed built-in predicates while new_raw permits them" do
    language = TreeSitter::Parser.new("go").language
    source = "((identifier) @name (#match? \"not-a-capture\" \".*\"))"

    expect_raises(TreeSitter::QueryError) { TreeSitter::Query.new(language, source) }
    TreeSitter::Query.new_raw(language, source).pattern_count.should eq(1)
  end
end

describe TreeSitter::QueryCursor do
  describe "#exec_with_options" do
    it "reports query progress and can cancel execution" do
      parser = TreeSitter::Parser.new("go")
      source = String.build do |io|
        io << "package main\n"
        10_000.times { |i| io << "func hello#{i}() {}\n" }
      end
      tree = parser.parse(nil, source)
      query = TreeSitter::Query.new(parser.language, "(identifier) @name")
      cursor = TreeSitter::QueryCursor.new(query)
      offsets = [] of UInt32

      cursor.exec_with_options(tree.root_node) do |state|
        offsets << state.current_byte_offset
        true
      end

      matches = [] of TreeSitter::Match
      cursor.each_match { |match| matches << match }
      offsets.should_not be_empty
      matches.size.should be < 10_000
    end

    it "continues to yield matches when progress returns false" do
      parser = TreeSitter::Parser.new("go")
      source = String.build do |io|
        io << "package main\n"
        1_000.times { |i| io << "func item#{i}() {}\n" }
      end
      tree = parser.parse(nil, source).not_nil!
      query = TreeSitter::Query.new(parser.language, "(identifier) @name")
      cursor = TreeSitter::QueryCursor.new(query)
      offsets = [] of UInt32

      cursor.exec_with_options(tree.root_node) { |state| offsets << state.current_byte_offset; false }
      matches = [] of TreeSitter::Match
      cursor.each_match { |match| matches << match }

      offsets.should_not be_empty
      matches.size.should eq(1_000)
    end
  end
end

describe TreeSitter::Query do
  it "separates property settings, property predicates, and general predicates" do
    language = TreeSitter::Parser.new("go").language
    source = "((identifier) @name (#set! @name \"scope\" \"local\") (#is? @name \"definition\") (#custom! @name \"marker\"))"
    query = TreeSitter::Query.new_raw(language, source)

    setting = query.property_settings(0).first
    setting.key.should eq("scope")
    setting.value.should eq("local")
    setting.capture_id.should eq(0)

    property, positive = query.property_predicates(0).first
    property.key.should eq("definition")
    property.capture_id.should eq(0)
    positive.should be_true

    predicate = query.general_predicates(0).first
    predicate.name.should eq("custom!")
    predicate.args.should eq([TreeSitter::Predicate::Arg.capture("name"), TreeSitter::Predicate::Arg.string("marker")])
  end
end

describe TreeSitter::Predicate do
  it "has a name and arguments" do
    pred = TreeSitter::Predicate.new("eq?", [
      TreeSitter::Predicate::Arg.capture("name"),
      TreeSitter::Predicate::Arg.string("hello"),
    ])
    pred.name.should eq("eq?")
    pred.args.size.should eq(2)
    pred.args[0].should eq(TreeSitter::Predicate::Arg.capture("name"))
    pred.args[1].should eq(TreeSitter::Predicate::Arg.string("hello"))
  end
end

describe TreeSitter::Predicate::Arg do
  it "equals works for same type and value" do
    a1 = TreeSitter::Predicate::Arg.capture("x")
    a2 = TreeSitter::Predicate::Arg.capture("x")
    a1.should eq(a2)
  end

  it "equals works for different values" do
    a1 = TreeSitter::Predicate::Arg.capture("x")
    a2 = TreeSitter::Predicate::Arg.capture("y")
    a1.should_not eq(a2)
  end

  it "equals works for different types" do
    a1 = TreeSitter::Predicate::Arg.capture("x")
    a2 = TreeSitter::Predicate::Arg.string("x")
    a1.should_not eq(a2)
  end
end

describe TreeSitter::Query do
  describe "#predicates_for_pattern" do
    it "parses #eq? predicate with capture and string args" do
      parser = TreeSitter::Parser.new("go")
      parser.parse(nil, "package main\nfunc hello() {}").not_nil!
      language = parser.language

      source = "(function_declaration name: (identifier) @name (#eq? @name \"hello\"))"
      query = TreeSitter::Query.new(language, source)
      predicates = query.predicates_for_pattern(0)
      predicates.size.should eq(1)

      pred = predicates[0]
      pred.name.should eq("eq?")
      pred.args.size.should eq(2)
      pred.args[0].should eq(TreeSitter::Predicate::Arg.capture("name"))
      pred.args[1].should eq(TreeSitter::Predicate::Arg.string("hello"))
    end

    it "parses #match? predicate with capture and regex arg" do
      parser = TreeSitter::Parser.new("go")
      parser.parse(nil, "package main\ntype Foo struct {}").not_nil!
      language = parser.language

      source = "(type_declaration (type_spec name: (type_identifier) @name) @def (#match? @def \"^type\"))"
      query = TreeSitter::Query.new(language, source)
      predicates = query.predicates_for_pattern(0)
      predicates.size.should eq(1)

      pred = predicates[0]
      pred.name.should eq("match?")
      pred.args.size.should eq(2)
      pred.args[0].should eq(TreeSitter::Predicate::Arg.capture("def"))
      pred.args[1].should eq(TreeSitter::Predicate::Arg.string("^type"))
    end

    it "parses #set! predicate with capture and key-value string args" do
      parser = TreeSitter::Parser.new("go")
      parser.parse(nil, "package main").not_nil!
      language = parser.language

      source = "(package_clause (package_identifier) @name @def (#set! @def is_export))"
      query = TreeSitter::Query.new(language, source)
      predicates = query.predicates_for_pattern(0)

      pred = predicates[0]
      pred.name.should eq("set!")
      pred.args.size.should eq(2)
      pred.args[0].should eq(TreeSitter::Predicate::Arg.capture("def"))
      pred.args[1].should eq(TreeSitter::Predicate::Arg.string("is_export"))
    end

    it "parses #has-type? predicate with multiple type string args" do
      parser = TreeSitter::Parser.new("go")
      parser.parse(nil, "package main\nfunc foo() {}").not_nil!
      language = parser.language

      source = "(function_declaration name: (identifier) @name @def (#has-type? @def \"function_declaration\" \"method_declaration\"))"
      query = TreeSitter::Query.new(language, source)
      predicates = query.predicates_for_pattern(0)
      predicates.size.should eq(1)

      pred = predicates[0]
      pred.name.should eq("has-type?")
      pred.args.size.should eq(3)
      pred.args[0].should eq(TreeSitter::Predicate::Arg.capture("def"))
      pred.args[1].should eq(TreeSitter::Predicate::Arg.string("function_declaration"))
      pred.args[2].should eq(TreeSitter::Predicate::Arg.string("method_declaration"))
    end

    it "parses #lineage-from-name! predicate with capture and delimiter" do
      parser = TreeSitter::Parser.new("go")
      parser.parse(nil, "package main").not_nil!
      language = parser.language

      source = "(package_clause (package_identifier) @name @def (#lineage-from-name! @name \"::\"))"
      query = TreeSitter::Query.new(language, source)
      predicates = query.predicates_for_pattern(0)
      predicates.size.should eq(1)

      pred = predicates[0]
      pred.name.should eq("lineage-from-name!")
      pred.args.size.should eq(2)
      pred.args[0].should eq(TreeSitter::Predicate::Arg.capture("name"))
      pred.args[1].should eq(TreeSitter::Predicate::Arg.string("::"))
    end

    it "parses multiple predicates on one pattern" do
      parser = TreeSitter::Parser.new("go")
      parser.parse(nil, "package main\nfunc hello() {}").not_nil!
      language = parser.language

      source = "(function_declaration name: (identifier) @name @def (#eq? @name \"hello\") (#set! @def exported))"
      query = TreeSitter::Query.new(language, source)
      predicates = query.predicates_for_pattern(0)
      predicates.size.should eq(2)
      predicates[0].name.should eq("eq?")
      predicates[1].name.should eq("set!")
    end

    it "parses #not-eq? predicate" do
      parser = TreeSitter::Parser.new("go")
      parser.parse(nil, "package main\nfunc foo() {}").not_nil!
      language = parser.language

      source = "(function_declaration name: (identifier) @name (#not-eq? @name \"constructor\"))"
      query = TreeSitter::Query.new(language, source)
      predicates = query.predicates_for_pattern(0)
      predicates.size.should eq(1)
      predicates[0].name.should eq("not-eq?")
    end

    it "parses #not-match? predicate" do
      parser = TreeSitter::Parser.new("go")
      parser.parse(nil, "package main\nfunc foo() {}").not_nil!
      language = parser.language

      source = "(function_declaration name: (identifier) @name (#not-match? @name \"^Test\"))"
      query = TreeSitter::Query.new(language, source)
      predicates = query.predicates_for_pattern(0)
      predicates.size.should eq(1)
      predicates[0].name.should eq("not-match?")
    end

    it "parses #not-has-parent? predicate" do
      parser = TreeSitter::Parser.new("go")
      parser.parse(nil, "package main\ntype T struct {}\nfunc (t T) Method() {}").not_nil!
      language = parser.language

      source = "(method_declaration name: (field_identifier) @name @def (#not-has-parent? @def export_statement))"
      query = TreeSitter::Query.new(language, source)
      predicates = query.predicates_for_pattern(0)
      predicates.size.should eq(1)
      predicates[0].name.should eq("not-has-parent?")
    end

    it "parses #strip! predicate with chars arg" do
      parser = TreeSitter::Parser.new("go")
      parser.parse(nil, "package main").not_nil!
      language = parser.language

      source = "(package_clause (package_identifier) @name (#strip! @name \"\\\\s\"))"
      query = TreeSitter::Query.new(language, source)
      predicates = query.predicates_for_pattern(0)
      predicates.size.should eq(1)
      predicates[0].name.should eq("strip!")
    end
  end
end
