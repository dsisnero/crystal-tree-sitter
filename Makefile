CRYSTAL  ?= crystal
TREE_SITTER ?= tree-sitter

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  LIB_EXT := dylib
else
  LIB_EXT := so
endif

# Grammar fixture directory and tags, pinned for reproducibility.
GRAMMAR_DIR := vendor/grammars
TREE_SITTER_JSON_TAG := v0.24.8
TREE_SITTER_GO_TAG   := v0.23.4
TREE_SITTER_JSON_URL := https://github.com/tree-sitter/tree-sitter-json
TREE_SITTER_GO_URL   := https://github.com/tree-sitter/tree-sitter-go

# Repo-local XDG config so `make test` is independent of the user's global
# tree-sitter CLI config. Its parser-directories point at GRAMMAR_DIR.
TEST_CONFIG      := .tree-sitter-config
CONFIG_FILE      := $(TEST_CONFIG)/tree-sitter/config.json
BUILD_STAMP      := $(GRAMMAR_DIR)/.build

GRAMMAR_JSON_LIB := $(GRAMMAR_DIR)/tree-sitter-json/libtree-sitter-json.$(LIB_EXT)
GRAMMAR_GO_LIB   := $(GRAMMAR_DIR)/tree-sitter-go/libtree-sitter-go.$(LIB_EXT)

.PHONY: all test lint grammars config clean help

all: test

# `make test` first ensures grammars + local config are present, then runs specs
# against them regardless of the user's global tree-sitter config.
test: config $(GRAMMAR_JSON_LIB) $(GRAMMAR_GO_LIB)
	XDG_CONFIG_HOME="$(CURDIR)/$(TEST_CONFIG)" $(CRYSTAL) spec $(SPEC_ARGS)

lint:
	$(CRYSTAL) run bin/ameba $(AMEBARGS)

grammars: $(GRAMMAR_JSON_LIB) $(GRAMMAR_GO_LIB)

# Local config file (written fresh each time so it always tracks GRAMMAR_DIR).
config: $(CONFIG_FILE)

$(CONFIG_FILE):
	@mkdir -p "$(dir $@)"
	@printf '{\n  "parser-directories": [\n    "%s"\n  ]\n}\n' "$(CURDIR)/$(GRAMMAR_DIR)" > "$@"
	@echo "wrote $@"

# JSON grammar
$(GRAMMAR_JSON_LIB): $(BUILD_STAMP)
	@echo "==> building tree-sitter-json"
	@rm -rf "$(GRAMMAR_DIR)/tree-sitter-json" "$(TEST_CONFIG)/.build/json"
	@mkdir -p "$(GRAMMAR_DIR)" "$(TEST_CONFIG)/.build"
	git clone --depth 1 --branch "$(TREE_SITTER_JSON_TAG)" "$(TREE_SITTER_JSON_URL)" "$(TEST_CONFIG)/.build/json" \
	  || { echo "tag $(TREE_SITTER_JSON_TAG) failed, falling back to default"; \
	       git clone --depth 1 "$(TREE_SITTER_JSON_URL)" "$(TEST_CONFIG)/.build/json"; }
	@cd "$(TEST_CONFIG)/.build/json" && $(TREE_SITTER) build
	@mkdir -p "$(GRAMMAR_DIR)/tree-sitter-json/src" "$(GRAMMAR_DIR)/tree-sitter-json/queries"
	@cp "$(TEST_CONFIG)/.build/json"/src/*.c "$(GRAMMAR_DIR)/tree-sitter-json/src/"
	@cp "$(TEST_CONFIG)/.build/json"/src/grammar.json "$(GRAMMAR_DIR)/tree-sitter-json/src/"
	@cp "$(TEST_CONFIG)/.build/json"/src/parser.c "$(GRAMMAR_DIR)/tree-sitter-json/src/"
	@if [ -d "$(TEST_CONFIG)/.build/json/queries" ]; then \
	    cp "$(TEST_CONFIG)/.build/json"/queries/*.scm "$(GRAMMAR_DIR)/tree-sitter-json/queries/"; fi
	@mv "$(TEST_CONFIG)/.build/json/parser.$(LIB_EXT)" "$@"
	@rm -rf "$(TEST_CONFIG)/.build/json"
	@echo "==> built $@"

# Go grammar
$(GRAMMAR_GO_LIB): $(BUILD_STAMP)
	@echo "==> building tree-sitter-go"
	@rm -rf "$(GRAMMAR_DIR)/tree-sitter-go" "$(TEST_CONFIG)/.build/go"
	@mkdir -p "$(GRAMMAR_DIR)" "$(TEST_CONFIG)/.build"
	git clone --depth 1 --branch "$(TREE_SITTER_GO_TAG)" "$(TREE_SITTER_GO_URL)" "$(TEST_CONFIG)/.build/go" \
	  || { echo "tag $(TREE_SITTER_GO_TAG) failed, falling back to default"; \
	       git clone --depth 1 "$(TREE_SITTER_GO_URL)" "$(TEST_CONFIG)/.build/go"; }
	@cd "$(TEST_CONFIG)/.build/go" && $(TREE_SITTER) build
	@mkdir -p "$(GRAMMAR_DIR)/tree-sitter-go/src" "$(GRAMMAR_DIR)/tree-sitter-go/queries"
	@cp "$(TEST_CONFIG)/.build/go"/src/*.c "$(GRAMMAR_DIR)/tree-sitter-go/src/"
	@cp "$(TEST_CONFIG)/.build/go"/src/grammar.json "$(GRAMMAR_DIR)/tree-sitter-go/src/"
	@cp "$(TEST_CONFIG)/.build/go"/src/parser.c "$(GRAMMAR_DIR)/tree-sitter-go/src/"
	@if [ -d "$(TEST_CONFIG)/.build/go/queries" ]; then \
	    cp "$(TEST_CONFIG)/.build/go"/queries/*.scm "$(GRAMMAR_DIR)/tree-sitter-go/queries/"; fi
	@mv "$(TEST_CONFIG)/.build/go/parser.$(LIB_EXT)" "$@"
	@rm -rf "$(TEST_CONFIG)/.build/go"
	@echo "==> built $@"

# Dummy stamp forcing the language libs to be (re)built. The grammar rules are
# keyed off this stamp rather than content-agnostic file checks so a fresh clone
# always produces a consistent fixture set, even if sources change upstream.
$(BUILD_STAMP):
	@mkdir -p "$(GRAMMAR_DIR)"
	@touch "$@"

clean:
	rm -rf "$(GRAMMAR_DIR)" "$(TEST_CONFIG)"

help:
	@echo "make test        - build grammar fixtures + run crystal spec (independent of global config)"
	@echo "make grammars    - build/download grammar fixtures into $(GRAMMAR_DIR)"
	@echo "make lint        - run ameba"
	@echo "make clean       - remove grammar fixtures and local config"