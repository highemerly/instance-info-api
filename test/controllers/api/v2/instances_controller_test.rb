require "test_helper"

class Api::V2::InstancesControllerTest < ActionDispatch::IntegrationTest
  include RemoteStubs

  KEYS = %w[domain kind type software node_name thumbnail_url icon_url max_characters
            open_registrations usage fetched_at cache].freeze

  setup do
    Typhoeus::Config.block_connection = true
    SourceFailureTracker.reset!
  end

  teardown do
    Typhoeus::Expectation.clear
    Typhoeus::Config.block_connection = false
  end

  test "a fediverse server: every field, fetched now, then from cache" do
    stub_nodeinfo("new.example", software: "fedibird", version: "0.1", users: 42, extra: {
      openRegistrations: false,
      usage: { users: { total: 42, activeMonth: 7, activeHalfyear: 9 }, localPosts: 1000 }
    })
    stub_json("https://new.example/api/v2/instance",
      title: "New",
      configuration: { statuses: { max_characters: 560 } },
      thumbnail: { url: "https://new.example/t.png" },
      icon: { src: "https://new.example/i.svg", size: "192x192" })

    get "/api/v2/instances/New.Example"

    assert_response :ok
    body = response.parsed_body
    assert_equal KEYS, body.keys
    assert_equal({
      "domain" => "new.example", "kind" => "fediverse", "type" => "mastodon",
      "software" => { "name" => "fedibird", "version" => "0.1" },
      "node_name" => "New", "thumbnail_url" => "https://new.example/t.png", "icon_url" => "https://new.example/i.svg",
      "max_characters" => { "halfwidth" => 560, "fullwidth" => 560 },
      "open_registrations" => false,
      "usage" => { "total_users" => 42, "active_month" => 7, "active_halfyear" => 9, "local_posts" => 1000 },
      "cache" => "miss"
    }, body.except("fetched_at"))
    assert_match(/\A\d{4}-\d\d-\d\dT/, body["fetched_at"])
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]

    get "/api/v2/instances/new.example"

    assert_equal "hit", response.parsed_body["cache"]
  end

  test "unknown values are null, not missing" do
    stub_nodeinfo("bare.example", software: "hubzilla", version: "11.4", users: 3)

    get "/api/v2/instances/bare.example"

    assert_response :ok
    body = response.parsed_body
    assert_equal KEYS, body.keys
    assert_nil body["max_characters"]
    assert_nil body["thumbnail_url"]
    assert_nil body["usage"]["active_month"]
  end

  test "a builtin service" do
    get "/api/v2/instances/X.com"

    assert_response :ok
    assert_equal({
      "domain" => "x.com", "kind" => "service", "type" => "twitter", "software" => nil,
      "node_name" => "X", "thumbnail_url" => nil, "icon_url" => nil,
      "max_characters" => { "halfwidth" => 280, "fullwidth" => 140 },
      "open_registrations" => true, "usage" => nil, "fetched_at" => nil, "cache" => "builtin"
    }, response.parsed_body)
  end

  test "a refresh that can't reach the server serves the old row as stale" do
    Typhoeus.stub(/stale\.example/).and_return(Typhoeus::Response.new(code: 503, body: ""))

    get "/api/v2/instances/stale.example"

    assert_response :ok
    assert_equal ["mastodon", "stale"], response.parsed_body.values_at("type", "cache")
  end

  {
    "not_fediverse" => [:not_found, "plain.example", -> { Typhoeus.stub(/plain\.example/).and_return(Typhoeus::Response.new(code: 404, body: "")) }],
    "unresolvable" => [:not_found, "gone.example", -> { SafeHttp.resolver = ->(_host) { [] } }],
    "upstream_unavailable" => [:service_unavailable, "down.example", -> { Typhoeus.stub(/down\.example/).and_return(Typhoeus::Response.new(code: 502, body: "")) }],
    "invalid_name" => [:bad_request, "down.example:8443", -> {}]
  }.each do |code, (status, name, arrange)|
    test "error #{code}" do
      instance_exec(&arrange)

      get "/api/v2/instances/#{name}"

      assert_response status
      assert_equal name, response.parsed_body["domain"]
      assert_equal code, response.parsed_body.dig("error", "code")
      assert response.parsed_body.dig("error", "message").present?
    end
  end
end
