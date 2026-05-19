require "typhoeus"
require "json"

# fediverse.observer GraphQL client and the SourceResult-shaped backend the
# controller iterates over.
#
# The HTTP transport is libcurl-backed (via Typhoeus): Cloudflare blocks Ruby
# Net::HTTP's TLS fingerprint when traffic originates from a datacenter IP,
# but lets libcurl through. We also keep the GraphQL::Client-compatible
# CurlTransport so the swapi:schema:dump rake task can keep using
# GraphQL::Client.dump_schema; runtime queries hit Typhoeus directly to avoid
# threading a status code through graphql-client's hash-returning contract.
module FediverseObserverClient
  ENDPOINT = "https://api.fediverse.observer/graphql".freeze
  USER_AGENT = "instance-info-api/1.0 (+https://github.com/highemerly/instance-info-api)".freeze
  TIMEOUT_SECONDS = 8

  # API key issued by fediverse.observer. Cloudflare still requires libcurl-class
  # TLS for datacenter IPs even with a key, but observer validates the key at
  # the application layer. Provide via SWAPI_API_KEY; rotate yearly.
  API_KEY = ENV["SWAPI_API_KEY"].to_s

  QUERY = <<~GRAPHQL.freeze
    query($domain: String!, $key: String) {
      node(domain: $domain, key: $key) {
        softwarename
        fullversion
        total_users
        status
      }
    }
  GRAPHQL

  # Drop-in for GraphQL::Client::HTTP, kept around because GraphQL::Client.dump_schema
  # speaks this interface. Runtime queries bypass it.
  class CurlTransport
    def initialize(url, headers: {})
      @url = url
      @headers = headers
    end

    def execute(document:, operation_name: nil, variables: {}, context: {})
      body = { "query" => document.to_query_string }
      body["variables"] = variables if variables.any?
      body["operationName"] = operation_name if operation_name

      response = Typhoeus.post(
        @url,
        body: JSON.generate(body),
        headers: @headers.merge(
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        )
      )

      if response.code == 200 || response.code == 400
        JSON.parse(response.body)
      else
        { "errors" => [{ "message" => "#{response.code} #{response.return_message}" }] }
      end
    end
  end

  HTTP = CurlTransport.new(ENDPOINT, headers: { "User-Agent" => USER_AGENT })

  # Looped over by the controller alongside NodeinfoClient::Backend. Maps the
  # observer's GraphQL response onto SourceResult — including the 50x/403 split
  # we need for backend fallback.
  class Backend
    NAME = "fediverse.observer".freeze
    UNAVAILABLE_SOURCE = "error:observer-unavailable".freeze

    def name
      NAME
    end

    def unavailable_source
      UNAVAILABLE_SOURCE
    end

    def fetch(domain)
      response = Typhoeus.post(
        ENDPOINT,
        body: JSON.generate(
          query: QUERY,
          variables: { domain: domain, key: API_KEY }
        ),
        headers: {
          "Content-Type" => "application/json",
          "Accept" => "application/json",
          "User-Agent" => USER_AGENT
        },
        timeout: TIMEOUT_SECONDS,
        connecttimeout: TIMEOUT_SECONDS
      )

      # 50x and 403 are the only codes the controller treats as "try the next
      # backend"; everything else (incl. network errors, where code == 0) is
      # surfaced as :unavailable but with a different http_status for logs.
      unless response.code == 200 || response.code == 400
        return SourceResult.new(
          state: :unavailable,
          http_status: response.code,
          error_message: response.return_message
        )
      end

      body = JSON.parse(response.body)

      if body["data"].nil?
        message = Array(body["errors"]).map { |e| e["message"] }.join("; ").presence || "missing data key"
        return SourceResult.new(state: :unavailable, http_status: response.code, error_message: message)
      end

      nodes = body.dig("data", "node") || []
      return SourceResult.new(state: :no_data, http_status: response.code) if nodes.empty?

      node = nodes.first
      SourceResult.new(
        state: :ok,
        software: node["softwarename"],
        version: node["fullversion"],
        total_users: node["total_users"],
        node_status: node["status"],
        http_status: response.code
      )
    rescue JSON::ParserError => e
      SourceResult.new(state: :unavailable, http_status: response&.code, error_message: "JSON parse error: #{e.message}")
    end
  end
end
