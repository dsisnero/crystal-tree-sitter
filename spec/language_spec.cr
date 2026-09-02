require "./spec_helper"

describe TreeSitter::Language do
  it "can be loaded" do
    lang = TreeSitter::Repository.load_language("json")
    lang.abi_version.should eq(14)
  end

  it "share the same instance" do
    lang1 = TreeSitter::Repository.load_language("json")
    TreeSitter::Repository.preload_all
    lang2 = TreeSitter::Repository.load_language("json")
    lang1.object_id.should eq(lang2.object_id)
  end

  it "is parseable when loaded from a shared library" do
    lang = TreeSitter::Repository.load_language("json")
    lang.parseable?.should be_true
  end

  it "copies to a usable language with the same name and ABI" do
    lang = TreeSitter::Repository.load_language("json")
    copy = lang.copy
    copy.name.should eq(lang.name)
    copy.abi_version.should eq(lang.abi_version)
    copy.parseable?.should be_true
  end

  pending "can detect language from file path" do
    # TreeSitter::Language.detect("foo.json").should be_a(TreeSitter::JSONLanguage)
    # TreeSitter::Language.detect("foo.c").should be_a(TreeSitter::CLanguage)
    # TreeSitter::Language.detect("foo.h").should be_a(TreeSitter::CLanguage)
    # TreeSitter::Language.detect("foo.abc").should eq(nil)
  end
end
