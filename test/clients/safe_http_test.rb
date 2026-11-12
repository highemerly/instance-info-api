require "test_helper"

class SafeHttpTest < ActiveSupport::TestCase
  setup do
    Typhoeus::Config.block_connection = true
    @requests = []
    Typhoeus.before { |request| @requests << request; true }
  end

  teardown do
    Typhoeus.before.clear
    Typhoeus::Expectation.clear
    Typhoeus::Config.block_connection = false
  end

  test "public_address? allows public IPv4 and IPv6" do
    %w[8.8.8.8 203.0.113.10 2001:4860:4860::8888].each do |a|
      assert SafeHttp.public_address?(a), a
    end
  end

  test "public_address? rejects internal, special-purpose and IPv4-embedding addresses" do
    %w[
      127.0.0.1 10.1.2.3 172.16.0.1 172.31.255.255 192.168.1.1 169.254.169.254
      100.64.0.1 0.0.0.0 224.0.0.1 255.255.255.255
      ::1 :: fe80::1 fc00::1 fd12::1
      ::ffff:127.0.0.1 ::ffff:169.254.169.254 ::127.0.0.1 64:ff9b::a00:1
      not-an-ip
    ].each do |a|
      assert_not SafeHttp.public_address?(a), a
    end
  end

  test "valid_hostname? accepts hostnames and rejects anything else" do
    %w[mastodon.social Misskey.IO a-b.example xn--r8jz45g.xn--zckzah localhost].each do |h|
      assert SafeHttp.valid_hostname?(h), h
    end
    ["", "a@b.example", "host.example:8080", "a b.example", "host.example.", "127.0.0.1",
     "2130706433", "0x7f.1", "[::1]", "a" * 250 + ".example", nil].each do |h|
      assert_not SafeHttp.valid_hostname?(h), h.inspect
    end
  end

  test "rejects non-http schemes without making a request" do
    %w[gopher://host.example/_x dict://host.example:6379/info file:///etc/passwd ftp://host.example/].each do |url|
      assert_raises(SafeHttp::BlockedError, url) { SafeHttp.get(url, timeout: 1) }
    end
    assert_empty @requests
  end

  test "rejects userinfo and IP literals that aren't public" do
    %w[https://user@host.example/ http://169.254.169.254/latest/meta-data/ http://127.0.0.1:3000/ http://[::1]/ http://[::ffff:10.0.0.1]/].each do |url|
      assert_raises(SafeHttp::BlockedError, url) { SafeHttp.get(url, timeout: 1) }
    end
    assert_empty @requests
  end

  test "rejects a host that resolves to any non-public address" do
    SafeHttp.resolver = ->(host) { host == "mixed.example" ? ["203.0.113.10", "10.0.0.5"] : ["127.0.0.1"] }

    assert_raises(SafeHttp::BlockedError) { SafeHttp.get("https://127.0.0.1.nip.io/", timeout: 1) }
    assert_raises(SafeHttp::BlockedError) { SafeHttp.get("https://mixed.example/", timeout: 1) }
    assert_empty @requests
  end

  test "raises ResolveError when the host doesn't resolve" do
    SafeHttp.resolver = ->(_host) { [] }

    assert_raises(SafeHttp::ResolveError) { SafeHttp.get("https://nowhere.example/", timeout: 1) }
  end

  test "restricts libcurl to http/https, disables its redirects and pins the checked address" do
    Typhoeus.stub("https://host.example/x").and_return(Typhoeus::Response.new(code: 200, body: "ok"))

    response = SafeHttp.get("https://Host.Example/x", timeout: 1)

    assert_equal 200, response.code
    options = @requests.sole.options
    assert_equal %i[http https], options[:protocols]
    assert_equal %i[http https], options[:redir_protocols]
    assert_equal false, options[:followlocation]
    assert_equal "host.example:443:#{FAKE_PUBLIC_ADDRESS}", options[:resolve].read_pointer.read_string
  end

  test "pins IPv6 addresses in brackets" do
    SafeHttp.resolver = ->(_host) { ["2001:db8::1", "203.0.113.10"] }
    Typhoeus.stub("http://host.example:8080/").and_return(Typhoeus::Response.new(code: 200))

    SafeHttp.get("http://host.example:8080/", timeout: 1)

    assert_equal "host.example:8080:[2001:db8::1],203.0.113.10", @requests.sole.options[:resolve].read_pointer.read_string
  end

  test "follows redirects, including relative ones" do
    Typhoeus.stub("https://a.example/start").and_return(redirect("https://b.example/next"))
    Typhoeus.stub("https://b.example/next").and_return(redirect("/final"))
    Typhoeus.stub("https://b.example/final").and_return(Typhoeus::Response.new(code: 200, body: "done"))

    response = SafeHttp.get("https://a.example/start", timeout: 1)

    assert_equal "done", response.body
    assert_equal %w[https://a.example/start https://b.example/next https://b.example/final], @requests.map(&:base_url)
  end

  test "checks every redirect target" do
    SafeHttp.resolver = ->(host) { host == "internal.example" ? ["10.0.0.5"] : [FAKE_PUBLIC_ADDRESS] }

    ["http://169.254.169.254/latest/meta-data/", "http://internal.example/admin", "gopher://a.example/_x"].each do |target|
      Typhoeus::Expectation.clear
      Typhoeus.stub("https://a.example/").and_return(redirect(target))

      assert_raises(SafeHttp::BlockedError, target) { SafeHttp.get("https://a.example/", timeout: 1) }
    end
  end

  test "returns the last redirect response once max_redirects is used up" do
    Typhoeus.stub("https://a.example/loop").and_return(redirect("https://a.example/loop"))

    response = SafeHttp.get("https://a.example/loop", timeout: 1, max_redirects: 2)

    assert_equal 302, response.code
    assert_equal 3, @requests.size
  end

  private

  def redirect(location)
    Typhoeus::Response.new(code: 302, headers: { "Location" => location })
  end
end
