require "test_helper"

class InstancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Typhoeus::Config.block_connection = true
    SourceFailureTracker.reset!
  end

  teardown do
    Typhoeus::Expectation.clear
    Typhoeus::Config.block_connection = false
  end

  test "rejects source=fediverse.observer" do
    get "/api/v1/instances/stale.example", params: { source: "fediverse.observer" }

    assert_response :bad_request
    assert_equal({ "error" => "invalid source", "given" => "fediverse.observer", "valid" => ["nodeinfo"] }, response.parsed_body)
  end

  test "rejects unknown source values" do
    get "/api/v1/instances/stale.example", params: { source: "bogus" }

    assert_response :bad_request
  end

  test "serves builtin rows without touching upstreams" do
    get "/api/v1/instances/twitter.com"

    assert_response :ok
    assert_equal "builtin", response.parsed_body["source"]
  end

  test "normalizes the name before looking it up" do
    ["TWITTER.COM", "twitter.com.", "twitter.com:443", "@alice@Twitter.com"].each do |input|
      get "/api/v1/instances/#{ERB::Util.url_encode(input)}"

      assert_response :ok, input
      assert_equal "twitter.com", response.parsed_body["name"], input
      assert_equal "builtin", response.parsed_body["source"], input
    end
  end

  test "rejects names that can't be a hostname" do
    get "/api/v1/instances/twitter.com:8443"

    assert_response :bad_request
    assert_equal "error:invalid-name", response.parsed_body["source"]
    assert_equal "twitter.com:8443", response.parsed_body["name"]
  end

  test "reports a domain that doesn't resolve as a DNS error, without caching it" do
    SafeHttp.resolver = ->(_host) { [] }

    get "/api/v1/instances/gone.example"

    assert_response :bad_request
    assert_equal "error:dns-error", response.parsed_body["source"]
    assert_nil Instance.find_by(name: "gone.example")
    assert_empty SourceFailureTracker.snapshot
  end

  test "keeps serving a stale row when its domain stops resolving" do
    SafeHttp.resolver = ->(_host) { [] }

    get "/api/v1/instances/stale.example"

    assert_response :ok
    assert_equal "cache:fediverse.observer:stale-fallback", response.parsed_body["source"]
    assert_equal "mastodon", response.parsed_body["software"]
  end

  [nil, "nodeinfo"].each do |source|
    test "refreshes stale rows from nodeinfo only (source=#{source.inspect})" do
      stub_observer_with_software("pleroma")
      stub_nodeinfo("stale.example", software: "mastodon", version: "4.5.0", users: 42)

      get "/api/v1/instances/stale.example", params: { source: source }.compact

      assert_response :ok
      body = response.parsed_body
      assert_equal "nodeinfo:cache-revalidated", body["source"]
      assert_equal "mastodon", body["software"]
      assert_equal "4.5.0", body["version"]
      assert_equal 42, body["total_users"]
      assert_nil body["status"]
      assert_not_includes SourceFailureTracker.snapshot.keys, "fediverse.observer"
    end
  end

  test "stores nodeinfo extras and the instance API's details on a fresh lookup" do
    stub_nodeinfo("new.example", software: "mastodon", version: "4.5.0", users: 42,
                  extra: { openRegistrations: true, metadata: { nodeName: "New" } })
    stub_json("https://new.example/api/v2/instance",
      configuration: { statuses: { max_characters: 500 } },
      thumbnail: { url: "https://new.example/t.png" },
      icon: [{ src: "https://new.example/i.png", size: "192x192" }])

    get "/api/v1/instances/new.example"

    assert_response :ok
    assert_equal "nodeinfo", response.parsed_body["source"]
    row = Instance.find_by!(name: "new.example")
    assert_equal ["New", true, 500, "https://new.example/t.png", "https://new.example/i.png"],
                 [row.node_name, row.open_registrations, row.max_characters, row.thumbnail_url, row.icon_url]
  end

  test "a refresh keeps the stored details when the instance API doesn't answer" do
    Instance.find_by!(name: "stale.example").update_columns(
      max_characters: 500, thumbnail_url: "https://stale.example/t.png", icon_url: "https://stale.example/i.png"
    )
    stub_nodeinfo("stale.example", software: "mastodon", version: "4.5.0", users: 42)
    Typhoeus.stub(%r{stale\.example/api/}).and_return(Typhoeus::Response.new(code: 502, body: ""))

    get "/api/v1/instances/stale.example"

    assert_response :ok
    row = Instance.find_by!(name: "stale.example")
    assert_equal ["4.5.0", 500, "https://stale.example/t.png", "https://stale.example/i.png"],
                 [row.version, row.max_characters, row.thumbnail_url, row.icon_url]
  end

  test "does not fetch a nodeinfo href that points at an internal address" do
    internal_url = "http://169.254.169.254/nodeinfo/2.0"
    Typhoeus.stub("https://stale.example#{NodeinfoClient::WELL_KNOWN_PATH}").and_return(
      json_response(links: [{ rel: "#{NodeinfoClient::NODEINFO_REL_PREFIX}2.0", href: internal_url }])
    )
    Typhoeus.stub(internal_url).and_return(json_response(software: { name: "pleroma", version: "1.0" }))
    requested = []
    Typhoeus.before { |request| requested << request.base_url; true }

    get "/api/v1/instances/stale.example"

    assert_response :ok
    assert_equal "cache:cache-stale", response.parsed_body["source"]
    assert_equal "mastodon", response.parsed_body["software"]
    assert_not_includes requested, internal_url
  ensure
    Typhoeus.before.clear
  end

  private

  # If the controller ever consults observer again, it would get "pleroma" and
  # the software assertions above would fail.
  def stub_observer_with_software(software)
    body = { data: { node: [{ softwarename: software, fullversion: "1.0", total_users: 1, status: 1 }] } }
    Typhoeus.stub(FediverseObserverClient::ENDPOINT).and_return(json_response(body))
  end

  def stub_nodeinfo(domain, software:, version:, users:, extra: {})
    doc_url = "https://#{domain}/nodeinfo/2.0"
    Typhoeus.stub("https://#{domain}#{NodeinfoClient::WELL_KNOWN_PATH}").and_return(
      json_response(links: [{ rel: "#{NodeinfoClient::NODEINFO_REL_PREFIX}2.0", href: doc_url }])
    )
    Typhoeus.stub(doc_url).and_return(
      json_response({ software: { name: software, version: version }, usage: { users: { total: users } } }.merge(extra))
    )
  end

  def stub_json(url, body)
    Typhoeus.stub(url).and_return(json_response(body))
  end

  def json_response(body)
    Typhoeus::Response.new(code: 200, body: JSON.generate(body))
  end
end
