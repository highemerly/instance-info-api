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
