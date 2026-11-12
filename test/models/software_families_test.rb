require "test_helper"

class SoftwareFamiliesTest < ActiveSupport::TestCase
  test "maps forks to their family" do
    assert_equal "misskey", SoftwareFamilies.normalize("sharkey")
    assert_equal "pleroma", SoftwareFamilies.normalize("akkoma")
  end

  test "keeps Mbin and kbin out of the lemmy family" do
    assert_equal "mbin", SoftwareFamilies.normalize("mbin")
    assert_equal "mbin", SoftwareFamilies.normalize("kbin")
    assert_equal "lemmy", SoftwareFamilies.normalize("lemmy")
  end

  test "Iceshrimp.NET is not the Misskey fork iceshrimp" do
    assert_equal "iceshrimp.net", SoftwareFamilies.normalize("Iceshrimp.NET")
    assert_equal "misskey", SoftwareFamilies.normalize("iceshrimp")
  end

  test "returns unmapped names as-is, lowercased" do
    assert_equal "somethingnew", SoftwareFamilies.normalize("SomethingNew")
  end
end
