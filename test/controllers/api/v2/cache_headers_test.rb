require "test_helper"

class Api::V2::CacheHeadersTest < ActionDispatch::IntegrationTest
  include RemoteStubs

  setup { Typhoeus::Config.block_connection = true }

  teardown do
    Typhoeus::Expectation.clear
    Typhoeus::Config.block_connection = false
  end

  test "a fresh row: the CDN keeps it no longer than it stays fresh, at most 6 hours" do
    Instance.create!(name: "young.example", instance_type: "mastodon", software: "mastodon", updated_at: 1.hour.ago)
    Instance.create!(name: "old.example", instance_type: "mastodon", software: "mastodon", updated_at: 23.hours.ago)

    get "/api/v2/instances/young.example"
    assert_equal "max-age=300, public, s-maxage=21600", response.headers["Cache-Control"]

    get "/api/v2/instances/old.example"
    assert_match(/\Amax-age=300, public, s-maxage=(35\d\d|3600)\z/, response.headers["Cache-Control"])
  end

  test "builtin services and the software list are cached for an hour" do
    get "/api/v2/instances/x.com"
    assert_equal "max-age=3600, public, s-maxage=3600", response.headers["Cache-Control"]

    get "/api/v2/software"
    assert_equal "max-age=3600, public, s-maxage=3600", response.headers["Cache-Control"]
  end

  test "errors" do
    Typhoeus.stub(/down\.example/).and_return(Typhoeus::Response.new(code: 502, body: ""))
    get "/api/v2/instances/down.example"
    assert_equal 503, response.status
    assert_equal "no-store", response.headers["Cache-Control"]

    get "/api/v2/instances/down.example:8443"
    assert_equal "max-age=60, public, s-maxage=300", response.headers["Cache-Control"]
  end

  test "stats" do
    get "/api/v2/stats"
    assert_equal "max-age=60, public, s-maxage=300", response.headers["Cache-Control"]
  end
end
