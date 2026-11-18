require "simpleidn"

# Turns what people type into the name we look up and cache under: a bare,
# lowercase, ASCII (punycode) hostname. Returns nil when the input can't be one.
#
#   "Mastodon.Social"            -> "mastodon.social"
#   "mastodon.social."           -> "mastodon.social"
#   "mastodon.social:443"        -> "mastodon.social"
#   "@alice@mastodon.social"     -> "mastodon.social"  (the handle's domain; no WebFinger)
#   "ｍａｓｔｏｄｏｎ。ｓｏｃｉａｌ" -> "mastodon.social"
#   "例え.jp"                    -> "xn--r8jz45g.jp"
#   "mastodon.social:8443"       -> nil                (we only fetch over 443)
#
# URLs aren't accepted: they carry "/", which the route doesn't let through.
# "www." is left alone; builtin rows list their www. aliases themselves.
module InstanceName
  # NFKC turns the fullwidth full stop into ".", but IDNA (UTS #46) also
  # treats the ideographic ones as label separators.
  IDEOGRAPHIC_FULL_STOPS = /[\u3002\uFF61]/
  HTTPS_PORT = "443".freeze

  def self.normalize(input)
    name = input.to_s.dup.force_encoding(Encoding::UTF_8).scrub("")
    name = name.unicode_normalize(:nfkc).strip.gsub(IDEOGRAPHIC_FULL_STOPS, ".")

    # "@user@host" / "user@host" -> "host"
    name = name.rpartition("@").last

    host, colon, port = name.rpartition(":")
    unless colon.empty?
      return nil unless port == HTTPS_PORT
      name = host
    end

    name = name.delete_suffix(".").downcase
    name = SimpleIDN.to_ascii(name) unless name.ascii_only?

    SafeHttp.valid_hostname?(name) ? name : nil
  rescue SimpleIDN::ConversionError
    nil
  end
end
