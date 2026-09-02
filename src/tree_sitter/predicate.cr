module TreeSitter
  # A property attached to a query pattern by `#set!`, `#is?`, or `#is-not?`.
  struct QueryProperty
    getter key : String
    getter value : String?
    getter capture_id : UInt32?

    def initialize(@key, @value, @capture_id)
    end
  end

  # A `Predicate` represents a parsed query predicate.
  # Predicates are attached to query patterns using S-expression syntax:
  # `(#eq? @capture_name "expected_value")`
  #
  # Each predicate has a name (like `eq?`, `match?`, `set!`) and a list of arguments.
  class Predicate
    getter name : String
    getter args : Array(Arg)

    def initialize(@name, @args)
    end

    # An argument to a predicate, which can be either a capture name or a string literal.
    struct Arg
      enum Type
        Capture
        String
      end

      getter type : Type
      getter value : String

      def self.capture(name : String) : Arg
        Arg.new(Type::Capture, name)
      end

      def self.string(value : String) : Arg
        Arg.new(Type::String, value)
      end

      def initialize(@type, @value)
      end

      def capture?
        @type.capture?
      end

      def string?
        @type.string?
      end

      def ==(other : Arg) : Bool
        @type == other.@type && @value == other.@value
      end
    end
  end
end
