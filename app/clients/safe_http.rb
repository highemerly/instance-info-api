require "ipaddr"
require "resolv"
require "socket"
require "uri"
require "typhoeus"

# GET for URLs we don't control: the instance name from the request path, the
# nodeinfo href a remote server hands us, and any redirect target. Without
# these checks the API could be made to fetch internal addresses (cluster
# services, cloud metadata) or speak gopher/dict/file through libcurl (SSRF).
#
# - Only http/https, enforced here and again in libcurl (protocols /
#   redir_protocols).
# - No userinfo in the URL; the host must be a plain hostname or IP literal.
# - Redirects are followed here, not by libcurl, so every hop gets the same
#   checks.
# - The host must resolve only to public addresses. The addresses we checked
#   are pinned with CURLOPT_RESOLVE, so libcurl can't re-resolve the name to
#   something else between our check and the connect (DNS rebinding).
#
# Typhoeus reuses curl handles, so a keep-alive connection to the same
# host:port can win over a newer pin. That connection was opened to an address
# we checked at the time, and each call re-checks the name before reaching
# libcurl, so this doesn't reopen the hole.
module SafeHttp
  # The target is not allowed (bad scheme/URL, or a non-public address).
  class BlockedError < StandardError; end
  # The host didn't resolve. Transient as far as callers are concerned.
  class ResolveError < StandardError; end

  ALLOWED_SCHEMES = %w[http https].freeze
  CURL_PROTOCOLS = %i[http https].freeze
  REDIRECT_CODES = [301, 302, 303, 307, 308].freeze
  # The last label (TLD) must start with a letter: libcurl reads all-numeric
  # names like "2130706433" or "0x7f.1" as IPv4, which would sidestep the pin.
  HOSTNAME = /\A([a-z0-9_-]+\.)*[a-z][a-z0-9-]*\z/i
  MAX_HOSTNAME_LENGTH = 253

  # Not reachable from the public internet, or special-purpose. IPv6 forms
  # that embed an IPv4 address are unwrapped first (see EMBEDDED_IPV4).
  BLOCKED_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
    172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15
    224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 2002::/16
  ].map { |cidr| IPAddr.new(cidr) }.freeze

  # IPv4-compatible (::a.b.c.d), IPv4-mapped (::ffff:a.b.c.d) and NAT64
  # (64:ff9b::a.b.c.d): judged by the IPv4 address in the low 32 bits.
  EMBEDDED_IPV4 = %w[::/96 ::ffff:0:0/96 64:ff9b::/96].map { |cidr| IPAddr.new(cidr) }.freeze

  class << self
    # Swappable so tests don't hit real DNS. Takes a hostname, returns
    # address strings ([] when it doesn't resolve).
    attr_writer :resolver

    def resolver
      @resolver ||= ->(host) { Resolv.getaddresses(host) }
    end

    # Returns the final Typhoeus::Response. After max_redirects hops the last
    # 3xx response is returned as-is (callers treat non-200 as a failure).
    def get(url, headers: {}, timeout:, max_redirects: 3)
      uri = parse!(url)
      hops = 0
      loop do
        response = request(uri, headers: headers, timeout: timeout)
        location = response.headers&.[]("Location")
        return response unless REDIRECT_CODES.include?(response.code) && location.present?
        return response if hops >= max_redirects

        hops += 1
        uri = parse!(join(uri, location))
      end
    end

    def valid_hostname?(host)
      host.is_a?(String) && host.length <= MAX_HOSTNAME_LENGTH && HOSTNAME.match?(host)
    end

    def public_address?(address)
      ip = address.is_a?(IPAddr) ? address : IPAddr.new(address)
      if ip.ipv6? && EMBEDDED_IPV4.any? { |range| range.include?(ip) }
        ip = IPAddr.new(ip.to_i & 0xffff_ffff, Socket::AF_INET)
      end
      BLOCKED_RANGES.none? { |range| range.include?(ip) }
    rescue IPAddr::Error
      false
    end

    private

    def parse!(url)
      uri = URI.parse(url)
      raise BlockedError, "scheme not allowed: #{uri.scheme.inspect}" unless ALLOWED_SCHEMES.include?(uri.scheme&.downcase)
      raise BlockedError, "userinfo not allowed" if uri.userinfo
      host = uri.hostname
      raise BlockedError, "invalid host: #{host.inspect}" unless ip_literal?(host) || valid_hostname?(host)
      uri.host = uri.host.downcase
      uri
    rescue URI::Error
      raise BlockedError, "invalid URL"
    end

    def join(base, location)
      URI.join(base.to_s, location).to_s
    rescue URI::Error
      raise BlockedError, "invalid redirect location"
    end

    def request(uri, headers:, timeout:)
      host = uri.hostname
      options = {
        headers: headers,
        timeout: timeout,
        connecttimeout: timeout,
        followlocation: false,
        protocols: CURL_PROTOCOLS,
        redir_protocols: CURL_PROTOCOLS
      }

      if ip_literal?(host)
        # libcurl doesn't resolve IP literals, so there is nothing to pin.
        raise BlockedError, "non-public address: #{host}" unless public_address?(host)
      else
        addresses = resolver.call(host)
        raise ResolveError, "could not resolve #{host}" if addresses.blank?
        blocked = addresses.reject { |a| public_address?(a) }
        raise BlockedError, "#{host} resolves to non-public address #{blocked.join(', ')}" if blocked.any?
        options[:resolve] = pin(host, uri.port, addresses)
      end

      # `options` holds the pinned list's pointer until the request is done.
      Typhoeus.get(uri.to_s, **options)
    end

    def ip_literal?(host)
      IPAddr.new(host)
      true
    rescue IPAddr::Error
      false
    end

    # CURLOPT_RESOLVE entry "host:port:addr[,addr...]", IPv6 in brackets.
    def pin(host, port, addresses)
      formatted = addresses.map { |a| IPAddr.new(a).ipv6? ? "[#{a}]" : a }
      list = Ethon::Curl.slist_append(nil, "#{host}:#{port}:#{formatted.join(',')}")
      FFI::AutoPointer.new(list, Ethon::Curl.method(:slist_free_all))
    end
  end
end
