require_relative 'spec_helper'
require_relative '../lib/is-term/string_helpers'

RSpec::describe "IS::Term::StringHelpers" do
  subject { IS::Term::StringHelpers }

  describe "#str_ellipsis" do
    it "raises on oversized marker" do
      expect { subject.str_ellipsis("A", 1, "中") }.to raise_error(ArgumentError)
    end
    it "truncates correctly" do
      expect(subject.str_ellipsis("中ABC", 3)).to eq "中…"
    end
  end

  describe "#str_truncate" do
    it "handles zero/negative" do
      expect(subject.str_truncate("test", 0)).to eq ""
      expect(subject.str_truncate("test", -1)).to eq ""
    end
  end

  describe "#str_width" do
    it "emoji + CJK" do
      expect(subject.str_width("中👨‍⚕️A中")).to eq 7  # 2+2+1+2
    end
    it "colored + accent" do
      expect(subject.str_width("\e[1mOlólo\e[0m")).to eq 5
    end
  end
end
