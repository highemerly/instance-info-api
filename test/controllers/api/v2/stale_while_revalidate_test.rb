require "test_helper"

class Api::V2::StaleWhileRevalidateTest < ActionDispatch::IntegrationTest
  include RemoteStubs

  setup do
    Typhoeus::Config.block_connection = true
    SourceFailureTracker.reset!
  end

  teardown do
    Typhoeus::Expectation.clear
    Typhoeus::Config.block_connection = false
  end

  test "a stale row is answered at once and refreshed in the background" do
    assert_enqueued_with(job: InstanceRefreshJob, args: ["stale.example"]) do
      get "/api/v2/instances/stale.example"
    end

    assert_response :ok
    assert_equal ["stale", "4.0.0"], [response.parsed_body["cache"], response.parsed_body.dig("software", "version")]
    assert_equal "max-age=0, public, s-maxage=60", response.headers["Cache-Control"]

    stub_nodeinfo("stale.example", software: "mastodon", version: "4.5.0", users: 42)
    perform_enqueued_jobs

    get "/api/v2/instances/stale.example"

    assert_equal ["hit", "4.5.0"], [response.parsed_body["cache"], response.parsed_body.dig("software", "version")]
  end

  test "concurrent requests for a stale row enqueue one refresh, and a failed one waits 10 minutes" do
    assert_enqueued_jobs(1, only: InstanceRefreshJob) do
      3.times { get "/api/v2/instances/stale.example" }
    end

    # The refresh fails: the row stays stale and keeps being served.
    Typhoeus.stub(/stale\.example/).and_return(Typhoeus::Response.new(code: 503, body: ""))
    perform_enqueued_jobs
    assert_equal "stale", response.parsed_body["cache"]

    travel 5.minutes do
      assert_no_enqueued_jobs { get "/api/v2/instances/stale.example" }
    end
    travel 11.minutes do
      assert_enqueued_jobs(1, only: InstanceRefreshJob) { get "/api/v2/instances/stale.example" }
    end
  end

  test "a refresh that finds no nodeinfo turns the row into not_fediverse" do
    get "/api/v2/instances/stale.example"
    Typhoeus.stub("https://stale.example#{NodeinfoClient::WELL_KNOWN_PATH}").and_return(Typhoeus::Response.new(code: 404, body: ""))
    perform_enqueued_jobs

    get "/api/v2/instances/stale.example"

    assert_response :not_found
    assert_equal "not_fediverse", response.parsed_body.dig("error", "code")
    assert_equal "max-age=300, public, s-maxage=3600", response.headers["Cache-Control"]
  end

  test "the job leaves a row alone that's already fresh again" do
    Instance.find_by!(name: "stale.example").update!(updated_at: Time.current)
    requested = []
    Typhoeus.before { |request| requested << request.base_url; true }

    InstanceRefreshJob.perform_now("stale.example")

    assert_empty requested
  ensure
    Typhoeus.before.clear
  end
end
