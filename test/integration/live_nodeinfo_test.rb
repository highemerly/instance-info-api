require "test_helper"

# End-to-end lookup against a real fediverse server: DNS pre-check, nodeinfo
# discovery and document fetch over libcurl, then the cache path. Skipped
# unless LIVE_NODEINFO_HOST is set, so local `bin/rails test` stays offline;
# CI points it at handon.club (a Mastodon server we run).
class LiveNodeinfoTest < ActionDispatch::IntegrationTest
  HOST = ENV["LIVE_NODEINFO_HOST"]

  setup do
    skip "set LIVE_NODEINFO_HOST to run against a real server" if HOST.blank?
    Typhoeus::Config.block_connection = false
  end

  test "looks up a real Mastodon server via nodeinfo, then serves it from cache" do
    get "/api/v1/instances/#{HOST}"

    assert_response :ok
    body = response.parsed_body
    assert_equal "nodeinfo", body["source"]
    assert_equal "mastodon", body["type"]
    assert_equal "mastodon", body["software"]
    assert_match(/\A\d+\.\d+/, body["version"])
    assert_kind_of Integer, body["total_users"]
    assert body.key?("status") && body["status"].nil?, "nodeinfo rows carry an explicit null status"

    get "/api/v1/instances/#{HOST}"

    assert_response :ok
    assert_equal "cache:nodeinfo", response.parsed_body["source"]
  end
end
