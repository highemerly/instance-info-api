require "test_helper"

class InstanceNameTest < ActiveSupport::TestCase
  {
    "mastodon.social" => "mastodon.social",
    "Mastodon.Social" => "mastodon.social",
    "  mastodon.social  " => "mastodon.social",
    "mastodon.social." => "mastodon.social",
    "mastodon.social:443" => "mastodon.social",
    "@alice@mastodon.social" => "mastodon.social",
    "alice@Mastodon.Social" => "mastodon.social",
    "ｍａｓｔｏｄｏｎ．ｓｏｃｉａｌ" => "mastodon.social",
    "mastodon。social" => "mastodon.social",
    "例え.jp" => "xn--r8jz45g.jp",
    "例え.ＪＰ" => "xn--r8jz45g.jp",
    "XN--R8JZ45G.JP" => "xn--r8jz45g.jp",
    "www.facebook.com" => "www.facebook.com",
    "bluesky" => "bluesky"
  }.each do |input, expected|
    test "normalizes #{input.inspect} to #{expected.inspect}" do
      assert_equal expected, InstanceName.normalize(input)
    end
  end

  [
    nil, "", "   ", "@", "alice@", "mastodon.social:8443", "mastodon.social:",
    "mastodon.social..", "127.0.0.1", "[::1]", "a b.example", "\xFF".b
  ].each do |input|
    test "rejects #{input.inspect}" do
      assert_nil InstanceName.normalize(input)
    end
  end
end
