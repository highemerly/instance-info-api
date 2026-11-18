require "test_helper"

class Api::V2::SoftwareControllerTest < ActionDispatch::IntegrationTest
  test "lists fediverse families and builtin services" do
    get "/api/v2/software"

    assert_response :ok
    body = response.parsed_body
    assert_includes body["fediverse"], { "type" => "misskey", "software" => SoftwareFamilies::FAMILIES["misskey"] }
    twitter = body["services"].find { |s| s["type"] == "twitter" }
    assert_equal ["twitter.com", "x.com"], twitter["domains"]
    assert_equal({ "halfwidth" => 280, "fullwidth" => 140 }, twitter["max_characters"])
  end
end
