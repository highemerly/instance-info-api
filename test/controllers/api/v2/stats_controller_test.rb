require "test_helper"

class Api::V2::StatsControllerTest < ActionDispatch::IntegrationTest
  test "counts what the cache holds, most common first" do
    Instance.create!(name: "a.example", instance_type: "misskey", software: "sharkey")
    Instance.create!(name: "b.example", instance_type: "misskey", software: "misskey")
    Instance.create!(name: "c.example", instance_type: "unknown", source: "error:no-data")

    get "/api/v2/stats"

    assert_response :ok
    body = response.parsed_body
    # The stale.example fixture is a mastodon row.
    assert_equal({ "fediverse" => 3, "not_fediverse" => 1 }, body["instances"])
    assert_equal({ "misskey" => 2, "mastodon" => 1 }, body["types"])
    assert_equal({ "mastodon" => 1, "misskey" => 1, "sharkey" => 1 }, body["software"])
    assert body["since"].present?
  end
end
