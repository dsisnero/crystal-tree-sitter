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
