require "json"

# Extras that nodeinfo doesn't carry, or carries only for some software: the
# post length limit, a wide thumbnail (banner), a square icon, and the
# server's display name. Each family exposes them through its own API, so the
# family picks where to ask; anything not known to lack one is asked as
# Mastodon-compatible (Mastodon and its forks, Pleroma/Akkoma, GoToSocial,
# Pixelfed, Friendica, Sharkey, ...). Checked against live servers 2026-11.
#
# Best effort: an error (timeout, non-200, bad JSON, blocked target) leaves
# the fields nil and never fails the lookup. `reached` tells the caller
# whether the server answered at all, so a passing failure on refresh doesn't
# wipe values we already have. Every request goes through SafeHttp.
module InstanceDetailsClient
  TIMEOUT_SECONDS = 3
  HEADERS = { "Accept" => "application/json", "User-Agent" => NodeinfoClient::USER_AGENT }.freeze
  # Icons come in several sizes: take the smallest at least this wide (crisp
  # at 2x in a list), else the largest there is.
  PREFERRED_ICON_WIDTH = 192
  # No instance API with any of these fields.
  NO_API_FAMILIES = %w[mbin hubzilla writefreely bookwyrm plume funkwhale].freeze

  Details = Struct.new(:reached, :node_name, :max_characters, :thumbnail_url, :icon_url, keyword_init: true)

  class << self
    def fetch(domain, software:)
      case SoftwareFamilies.normalize(software)
      when "misskey" then misskey(domain)
      when "lemmy" then lemmy_like(domain, "/api/v3/site", %w[site_view site])
      when "piefed" then lemmy_like(domain, "/api/alpha/site", %w[site])
      when "peertube" then peertube(domain)
      when *NO_API_FAMILIES then Details.new(reached: true)
      else mastodon_compatible(domain)
      end
    rescue StandardError => e
      # Best effort means best effort: log and carry on without the extras.
      Rails.logger.warn(%(instance_details_failed domain=#{domain.inspect} error=#{e.class} message=#{e.message.inspect}))
      Details.new(reached: false)
    end

    private

    # /api/v2/instance (Mastodon 4+, GoToSocial, Pixelfed, Friendica), then
    # /api/v1/instance for what v2 lacked: Pleroma/Akkoma have no v2 and keep
    # the limit in v1's max_toot_chars; Sharkey and older Mastodon only have v1.
    def mastodon_compatible(domain)
      v2 = get_json(domain, "/api/v2/instance")
      details = Details.new(
        reached: !v2.nil?,
        node_name: JsonFields.text(v2&.dig("title")),
        max_characters: JsonFields.limit(JsonFields.dig(v2, "configuration", "statuses", "max_characters")),
        thumbnail_url: url(domain, JsonFields.dig(v2, "thumbnail", "url")),
        icon_url: mastodon_icon(domain, v2&.dig("icon"))
      )
      return details if details.max_characters && details.thumbnail_url

      v1 = get_json(domain, "/api/v1/instance")
      return details if v1.nil?

      details.reached = true
      details.node_name ||= JsonFields.text(v1["title"])
      details.max_characters ||= JsonFields.limit(JsonFields.dig(v1, "configuration", "statuses", "max_characters")) ||
                                 JsonFields.limit(v1["max_toot_chars"])
      details.thumbnail_url ||= url(domain, v1["thumbnail"])
      details
    end

    # Misskey and its forks. Sharkey answers only POST here (GET is 405).
    def misskey(domain)
      meta = post_json(domain, "/api/meta", {})
      Details.new(
        reached: !meta.nil?,
        node_name: JsonFields.text(meta&.dig("name")),
        max_characters: JsonFields.limit(meta&.dig("maxNoteTextLength")),
        thumbnail_url: url(domain, meta&.dig("bannerUrl")),
        icon_url: url(domain, meta&.dig("iconUrl"))
      )
    end

    # Lemmy (/api/v3/site -> site_view.site) and PieFed (/api/alpha/site ->
    # site). Posts have no configured length limit there.
    def lemmy_like(domain, path, site_keys)
      site = JsonFields.dig(get_json(domain, path), *site_keys)
      Details.new(
        reached: !site.nil?,
        node_name: JsonFields.text(JsonFields.dig(site, "name")),
        thumbnail_url: url(domain, JsonFields.dig(site, "banner")),
        icon_url: url(domain, JsonFields.dig(site, "icon"))
      )
    end

    # PeerTube 6+ lists banners and avatars in several sizes.
    def peertube(domain)
      instance = JsonFields.dig(get_json(domain, "/api/v1/config/about"), "instance")
      banners = images(domain, JsonFields.dig(instance, "banners"), url_key: "fileUrl") { |i| i["width"] }
      avatars = images(domain, JsonFields.dig(instance, "avatars"), url_key: "fileUrl") { |i| i["width"] }
      Details.new(
        reached: !instance.nil?,
        node_name: JsonFields.text(JsonFields.dig(instance, "name")),
        thumbnail_url: banners.max_by { |_, width| width }&.first,
        icon_url: pick_icon(avatars)
      )
    end

    # Mastodon 4.3+: [{ "src": ..., "size": "192x192" }, ...]; Fedibird
    # returns a single object instead of an array.
    def mastodon_icon(domain, value)
      pick_icon(images(domain, value, url_key: "src") { |i| i["size"].to_s[/\A(\d+)x\d+\z/, 1]&.to_i })
    end

    # [[url, width], ...] from an image list; drops entries without a usable URL.
    def images(domain, value, url_key:)
      list = value.is_a?(Hash) ? [value] : Array(value)
      list.filter_map do |item|
        next unless item.is_a?(Hash)
        image_url = url(domain, item[url_key])
        width = yield(item)
        [image_url, width.is_a?(Integer) ? width : 0] if image_url
      end
    end

    def pick_icon(candidates)
      large_enough = candidates.select { |_, width| width >= PREFERRED_ICON_WIDTH }
      (large_enough.min_by { |_, width| width } || candidates.max_by { |_, width| width })&.first
    end

    def url(domain, value)
      JsonFields.url(value, base: "https://#{domain}/")
    end

    def get_json(domain, path)
      parse(SafeHttp.get("https://#{domain}#{path}", headers: HEADERS, timeout: TIMEOUT_SECONDS, max_redirects: 1))
    end

    def post_json(domain, path, body)
      headers = HEADERS.merge("Content-Type" => "application/json")
      parse(SafeHttp.post("https://#{domain}#{path}", body: JSON.generate(body), headers: headers, timeout: TIMEOUT_SECONDS))
    end

    def parse(response)
      return nil unless response.code == 200
      json = JSON.parse(response.body)
      json.is_a?(Hash) ? json : nil
    rescue JSON::ParserError
      nil
    end
  end
end
