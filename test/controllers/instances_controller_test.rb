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

  private

  # If the controller ever consults observer again, it would get "pleroma" and
  # the software assertions above would fail.
  def stub_observer_with_software(software)
    body = { data: { node: [{ softwarename: software, fullversion: "1.0", total_users: 1, status: 1 }] } }
    Typhoeus.stub(FediverseObserverClient::ENDPOINT).and_return(json_response(body))
  end

  def stub_nodeinfo(domain, software:, version:, users:)
    doc_url = "https://#{domain}/nodeinfo/2.0"
    Typhoeus.stub("https://#{domain}#{NodeinfoClient::WELL_KNOWN_PATH}").and_return(
      json_response(links: [{ rel: "#{NodeinfoClient::NODEINFO_REL_PREFIX}2.0", href: doc_url }])
    )
    Typhoeus.stub(doc_url).and_return(
      json_response(software: { name: software, version: version }, usage: { users: { total: users } })
    )
  end

  def json_response(body)
    Typhoeus::Response.new(code: 200, body: JSON.generate(body))
  end
end
