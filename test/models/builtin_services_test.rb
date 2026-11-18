require "test_helper"

class BuiltinServicesTest < ActiveSupport::TestCase
  # Everything db/seeds.rb used to insert, so moving to the YAML file lost none.
  FORMER_SEEDS = %w[
    twitter.com x.com facebook.com www.facebook.com line.me line b.hatena.ne.jp hatena.ne.jp
    linkedin.com www.linkedin.com pinterest.com www.pinterest.com pinterest.jp www.pinterest.jp
    www.xing.com xing.com www.threads.net threads.net www.threads.com threads.com bsky.app bluesky
    www.reddit.com reddit.com reddit www.whatsapp.com whatsapp.com wa.me whatsapp telegram.org
    telegram www.tumblr.com tumblr.com tumblr taittsuu.com taittsuu
  ].freeze

  test "covers every domain the seeds had" do
    FORMER_SEEDS.each { |domain| assert BuiltinServices.find(domain), domain }
  end

  test "domains are written the way InstanceName normalizes them" do
    BuiltinServices::ALL.flat_map(&:domains).each do |domain|
      assert_equal domain, InstanceName.normalize(domain)
    end
  end

  test "limits have both widths, and the fullwidth one is never larger" do
    BuiltinServices::ALL.filter_map(&:max_characters).each do |limits|
      assert_operator limits[:fullwidth], :<=, limits[:halfwidth]
    end
  end
end
