require "test_helper"

class NodeinfoClientTest < ActiveSupport::TestCase
  INTERNAL_URL = "http://internal.example/nodeinfo/2.0".freeze

  setup do
    Typhoeus::Config.block_connection = true
    @backend = NodeinfoClient::Backend.new
    @requested = []
    Typhoeus.before { |request| @requested << request.base_url; true }
    SafeHttp.resolver = ->(host) { host == "internal.example" ? ["10.0.0.5"] : [FAKE_PUBLIC_ADDRESS] }
    # If the client ever reached the internal URL, it would get a valid document.
    Typhoeus.stub(INTERNAL_URL).and_return(json(software: { name: "mastodon", version: "4.5.0" }))
  end

  teardown do
    Typhoeus.before.clear
    Typhoeus::Expectation.clear
    Typhoeus::Config.block_connection = false
  end

  test "fetches nodeinfo from a public server" do
    stub_well_known("good.example", href: "https://good.example/nodeinfo/2.0")
    Typhoeus.stub("https://good.example/nodeinfo/2.0").and_return(
      json(software: { name: "misskey", version: "2025.1.0" }, usage: { users: { total: 7 } })
    )

    result = @backend.fetch("good.example")

    assert result.ok?
    assert_equal ["misskey", "2025.1.0", 7], [result.software, result.version, result.total_users]
  end

  test "does not follow a nodeinfo href that points at an internal address" do
    stub_well_known("evil.example", href: INTERNAL_URL)

    result = @backend.fetch("evil.example")

    assert result.no_data?
    assert_match(/blocked/, result.error_message)
    assert_not_includes @requested, INTERNAL_URL
  end

  test "does not follow a nodeinfo href with a non-http scheme" do
    stub_well_known("evil.example", href: "gopher://evil.example:6379/_FLUSHALL")

    assert @backend.fetch("evil.example").no_data?
    assert_equal ["https://evil.example/.well-known/nodeinfo"], @requested
  end

  test "does not follow a well-known redirect to an internal address" do
    Typhoeus.stub("https://evil.example/.well-known/nodeinfo").and_return(
      Typhoeus::Response.new(code: 302, headers: { "Location" => INTERNAL_URL })
    )

    assert @backend.fetch("evil.example").no_data?
    assert_not_includes @requested, INTERNAL_URL
  end

  test "does not contact a domain that resolves to an internal address" do
    assert @backend.fetch("internal.example").no_data?
    assert_empty @requested
  end

  test "rejects domains that aren't plain hostnames" do
    ["a@internal.example", "good.example:8080", "127.0.0.1", "2130706433"].each do |domain|
      assert @backend.fetch(domain).no_data?, domain
    end
    assert_empty @requested
  end

  test "reports an unresolvable domain as unavailable" do
    SafeHttp.resolver = ->(_host) { [] }

    assert @backend.fetch("gone.example").unavailable?
  end

  private

  def stub_well_known(domain, href:)
    Typhoeus.stub("https://#{domain}#{NodeinfoClient::WELL_KNOWN_PATH}").and_return(
      json(links: [{ rel: "#{NodeinfoClient::NODEINFO_REL_PREFIX}2.0", href: href }])
    )
  end

  def json(body)
    Typhoeus::Response.new(code: 200, body: JSON.generate(body))
  end
end
