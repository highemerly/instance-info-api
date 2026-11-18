require "test_helper"

# Response shapes are trimmed copies of what live servers returned (2026-11).
class InstanceDetailsClientTest < ActiveSupport::TestCase
  setup do
    Typhoeus::Config.block_connection = true
    @requests = []
    Typhoeus.before { |request| @requests << [request.options[:method], request.base_url]; true }
  end

  teardown do
    Typhoeus.before.clear
    Typhoeus::Expectation.clear
    Typhoeus::Config.block_connection = false
  end

  test "Mastodon: v2 has everything, so v1 isn't asked" do
    stub_json("https://m.example/api/v2/instance",
      title: "Mastodon.social",
      configuration: { statuses: { max_characters: 500 } },
      thumbnail: { url: "https://files.m.example/thumb.png" },
      icon: %w[36 72 192 512].map { |w| { src: "https://m.example/icon-#{w}.png", size: "#{w}x#{w}" } })

    details = fetch("m.example", "mastodon")

    assert details.reached
    assert_equal ["Mastodon.social", 500, "https://files.m.example/thumb.png", "https://m.example/icon-192.png"],
                 [details.node_name, details.max_characters, details.thumbnail_url, details.icon_url]
    assert_equal [[:get, "https://m.example/api/v2/instance"]], @requests
  end

  test "Fedibird: icon is a single object, not a list" do
    stub_json("https://f.example/api/v2/instance",
      configuration: { statuses: { max_characters: 560 } },
      thumbnail: { url: "https://f.example/t.png" },
      icon: { src: "https://f.example/logo.svg", size: "192x192" })

    assert_equal "https://f.example/logo.svg", fetch("f.example", "fedibird").icon_url
  end

  test "picks the largest icon when none is 192px or wider" do
    stub_json("https://m.example/api/v2/instance",
      configuration: { statuses: { max_characters: 500 } },
      thumbnail: { url: "https://m.example/t.png" },
      icon: [{ src: "/i48.png", size: "48x48" }, { src: "/i96.png", size: "96x96" }])

    assert_equal "https://m.example/i96.png", fetch("m.example", "mastodon").icon_url
  end

  test "Akkoma: no v2, so the limit and thumbnail come from v1" do
    Typhoeus.stub("https://a.example/api/v2/instance").and_return(Typhoeus::Response.new(code: 404, body: "{}"))
    stub_json("https://a.example/api/v1/instance",
      title: "Luna Nova", max_toot_chars: 65536, thumbnail: "https://media.a.example/t.png")

    details = fetch("a.example", "akkoma")

    assert details.reached
    assert_equal ["Luna Nova", 65536, "https://media.a.example/t.png", nil],
                 [details.node_name, details.max_characters, details.thumbnail_url, details.icon_url]
  end

  test "Misskey and forks: POST /api/meta" do
    stub_json("https://k.example/api/meta",
      name: "Misskey.io", maxNoteTextLength: 3000,
      bannerUrl: "https://media.k.example/banner.jpg", iconUrl: "https://media.k.example/icon.png")

    details = fetch("k.example", "sharkey")

    assert_equal ["Misskey.io", 3000, "https://media.k.example/banner.jpg", "https://media.k.example/icon.png"],
                 [details.node_name, details.max_characters, details.thumbnail_url, details.icon_url]
    assert_equal [[:post, "https://k.example/api/meta"]], @requests
  end

  test "Lemmy: site banner and icon, no length limit" do
    stub_json("https://l.example/api/v3/site",
      site_view: { site: { name: "Lemmy.World", banner: "https://l.example/b.png", icon: "https://l.example/i.png" } })

    details = fetch("l.example", "lemmy")

    assert_equal ["Lemmy.World", nil, "https://l.example/b.png", "https://l.example/i.png"],
                 [details.node_name, details.max_characters, details.thumbnail_url, details.icon_url]
  end

  test "PieFed: /api/alpha/site" do
    stub_json("https://p.example/api/alpha/site", site: { name: "PieFed", banner: nil, icon: "https://p.example/logo.png" })

    details = fetch("p.example", "piefed")

    assert_equal ["PieFed", nil, "https://p.example/logo.png"], [details.node_name, details.thumbnail_url, details.icon_url]
  end

  test "PeerTube: widest banner, avatar picked like icons" do
    stub_json("https://t.example/api/v1/config/about", instance: {
      name: "Framatube",
      banners: [{ width: 600, fileUrl: "https://t.example/b600.png" }, { width: 1920, fileUrl: "https://t.example/b1920.png" }],
      avatars: [{ width: 1500, fileUrl: "https://t.example/a1500.png" }, { width: 600, fileUrl: "https://t.example/a600.png" },
                { width: 48, fileUrl: "https://t.example/a48.png" }]
    })

    details = fetch("t.example", "peertube")

    assert_equal ["Framatube", "https://t.example/b1920.png", "https://t.example/a600.png"],
                 [details.node_name, details.thumbnail_url, details.icon_url]
  end

  test "families without an instance API aren't asked" do
    details = fetch("b.example", "mbin")

    assert details.reached
    assert_nil details.max_characters
    assert_empty @requests
  end

  test "a server that doesn't answer leaves everything nil, reached false" do
    Typhoeus.stub(/x\.example/).and_return(Typhoeus::Response.new(code: 503, body: ""))

    details = fetch("x.example", "mastodon")

    assert_not details.reached
    assert_equal [nil, nil, nil, nil], [details.node_name, details.max_characters, details.thumbnail_url, details.icon_url]
  end

  test "odd shapes and unsafe URLs become nil instead of raising" do
    stub_json("https://m.example/api/v2/instance",
      title: 42,
      configuration: { statuses: "500" },
      thumbnail: "https://m.example/not-an-object.png",
      icon: [{ src: "javascript:alert(1)", size: "192x192" }, "nope"])
    Typhoeus.stub("https://m.example/api/v1/instance").and_return(Typhoeus::Response.new(code: 200, body: "[1, 2]"))

    details = fetch("m.example", "mastodon")

    assert details.reached
    assert_equal [nil, nil, nil, nil], [details.node_name, details.max_characters, details.thumbnail_url, details.icon_url]
  end

  test "makes relative URLs absolute against the server" do
    stub_json("https://k.example/api/meta", bannerUrl: "/files/banner.jpg", iconUrl: nil)

    assert_equal "https://k.example/files/banner.jpg", fetch("k.example", "misskey").thumbnail_url
  end

  test "goes through SafeHttp: a domain on an internal address isn't contacted" do
    SafeHttp.resolver = ->(_host) { ["10.0.0.5"] }

    details = fetch("internal.example", "mastodon")

    assert_not details.reached
    assert_empty @requests
  end

  private

  def fetch(domain, software)
    InstanceDetailsClient.fetch(domain, software: software)
  end

  def stub_json(url, body)
    Typhoeus.stub(url).and_return(Typhoeus::Response.new(code: 200, body: JSON.generate(body)))
  end
end
