require "typhoeus"
require "json"

# Direct nodeinfo fetcher used as a fallback when fediverse.observer returns
# 50x/403. Two requests: /.well-known/nodeinfo for discovery, then the
# document itself. We use libcurl (Typhoeus) for consistency with the observer
# client, though most fediverse instances don't have the Cloudflare bot filter
# that forces our hand for observer.
#
# nodeinfo doesn't expose the observer's `status` integer (which is poduptime
# monitoring history); the controller emits `status: null` for nodeinfo rows
# to make that semantic gap explicit to clients.
module NodeinfoClient
  WELL_KNOWN_PATH = "/.well-known/nodeinfo".freeze
  USER_AGENT = "instance-info-api/1.0 (+https://github.com/highemerly/instance-info-api)".freeze
  TIMEOUT_SECONDS = 5

  # nodeinfo "rel" values look like http://nodeinfo.diaspora.software/ns/schema/2.0
  # — only entries with this prefix are nodeinfo descriptors.
  NODEINFO_REL_PREFIX = "http://nodeinfo.diaspora.software/ns/schema/".freeze

  class Backend
    NAME = "nodeinfo".freeze
    UNAVAILABLE_SOURCE = "error:nodeinfo-unavailable".freeze

    def name
      NAME
    end

    def unavailable_source
      UNAVAILABLE_SOURCE
    end

    def fetch(domain)
      discovery = get("https://#{domain}#{WELL_KNOWN_PATH}")

      # 404 at well-known means "this domain isn't a fediverse instance" —
      # observer-style :no_data, not a transient failure.
      return SourceResult.new(state: :no_data, http_status: discovery.code) if discovery.code == 404

      unless discovery.code == 200
        return SourceResult.new(
          state: :unavailable,
          http_status: discovery.code,
          error_message: discovery.return_message.presence || "well-known fetch failed"
        )
      end

      links = parse_well_known_links(discovery)
      return SourceResult.new(state: :unavailable, http_status: discovery.code, error_message: "well-known JSON parse error") if links == :parse_error
      return SourceResult.new(state: :no_data, http_status: discovery.code) unless links

      nodeinfo_url = pick_nodeinfo_url(links)
      return SourceResult.new(state: :no_data, http_status: discovery.code) unless nodeinfo_url

      parse_document(get(nodeinfo_url))
    end

    private

    def parse_well_known_links(response)
      links = JSON.parse(response.body)["links"]
      links.is_a?(Array) ? links : nil
    rescue JSON::ParserError
      :parse_error
    end

    def get(url)
      Typhoeus.get(
        url,
        headers: { "Accept" => "application/json", "User-Agent" => USER_AGENT },
        timeout: TIMEOUT_SECONDS,
        connecttimeout: TIMEOUT_SECONDS,
        followlocation: true,
        maxredirs: 3
      )
    end

    # Highest-version nodeinfo schema wins. Lexical sort works for 1.x/2.x
    # since the version segment has the same width; revisit if 10.x ships.
    def pick_nodeinfo_url(links)
      candidates = links.select { |l| l.is_a?(Hash) && l["rel"].to_s.start_with?(NODEINFO_REL_PREFIX) && l["href"].is_a?(String) }
      candidates.max_by { |l| l["rel"] }&.dig("href")
    end

    def parse_document(response)
      return SourceResult.new(state: :no_data, http_status: response.code) if response.code == 404
      unless response.code == 200
        return SourceResult.new(
          state: :unavailable,
          http_status: response.code,
          error_message: response.return_message.presence || "nodeinfo fetch failed"
        )
      end

      doc = JSON.parse(response.body)
      software = doc.dig("software", "name")
      return SourceResult.new(state: :no_data, http_status: response.code) if software.blank?

      SourceResult.new(
        state: :ok,
        software: software,
        version: doc.dig("software", "version"),
        total_users: doc.dig("usage", "users", "total"),
        node_status: nil,
        http_status: response.code
      )
    rescue JSON::ParserError => e
      SourceResult.new(state: :unavailable, http_status: response.code, error_message: "nodeinfo JSON parse error: #{e.message}")
    end
  end
end
