require "./spec_helper"

describe TreeSitter::Repository do
  # parsers for json and C must be installed at least
  it "can fetch installed languages" do
    TreeSitter::Repository.language_names.should_not eq(%w[])
  end

  it "uses the platform's shared library suffix" do
    extension = {% if flag?(:win32) %}
                  "dll"
                {% elsif flag?(:darwin) %}
                  "dylib"
                {% else %}
                  "so"
                {% end %}

    error = expect_raises(TreeSitter::Error) do
      TreeSitter::Repository.load_shared_object("missing", Path.new("missing-tree-sitter-language"))
    end

    error.message.not_nil!.should contain("libtree-sitter-missing.#{extension}")
  end
end
