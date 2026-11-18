ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Tests stub Typhoeus and use names like stale.example that don't resolve, so
  # SafeHttp gets a resolver that maps every name to a public address. Tests
  # about addresses set their own; LiveNodeinfoTest puts the real one back.
  FAKE_PUBLIC_ADDRESS = "203.0.113.10"

  setup { SafeHttp.resolver = ->(_host) { [FAKE_PUBLIC_ADDRESS] } }
  teardown { SafeHttp.resolver = nil }
end

# Typhoeus stubs for a server's nodeinfo and instance API, shared by the v1 and
# v2 controller tests.
module RemoteStubs
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
