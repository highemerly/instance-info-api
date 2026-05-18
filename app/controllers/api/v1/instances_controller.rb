require "resolv"
require "graphql/client"
require "typhoeus"

NameServer = '8.8.8.8'

module Api
  module V1
    class InstancesController < ApplicationController
      def show
        response.set_header('Access-Control-Allow-Origin', '*') # (tmp) For debug only

        instance_name = params[:name]
        instance_type = ""
        instance_software = nil
        instance_version = nil
        instance_total_users = nil
        instance_status = nil
        instance_updated_at = nil
        source = ""

        instance = Instance.find_by(name: instance_name)

        unless instance == nil then
          unless stale_cache?(instance) then
            instance_type = instance[:instance_type]
            instance_software = instance[:software]
            instance_version = instance[:version]
            instance_total_users = instance[:total_users]
            instance_status = instance[:status]
            instance_updated_at = instance[:updated_at]
            source = cached_source(instance)
          else
            begin
              nodes = fetch_swapi_nodes(instance_name)
            rescue
              # fediverse.observer unavailable — serve stale cache as a fallback
              # rather than failing, since we still have something useful to return.
              instance_type = instance[:instance_type]
              instance_software = instance[:software]
              instance_version = instance[:version]
              instance_total_users = instance[:total_users]
              instance_status = instance[:status]
              instance_updated_at = instance[:updated_at]
              source = stale_fallback_source(instance)
            else
              if nodes.length == 0 then
                instance_type = instance[:instance_type]
                instance_software = instance[:software]
                instance_version = instance[:version]
                instance_total_users = instance[:total_users]
                instance_status = instance[:status]
                instance_updated_at = instance[:updated_at]
                source = "cache:cache-stale"
              else
                nodes.each do |node|
                  instance_software = node.softwarename
                  instance_type = SoftwareFamilies.normalize(node.softwarename)
                  instance_version = node.fullversion
                  instance_total_users = node.total_users
                  instance_status = node.status

                  if node.softwarename == instance[:software] then
                    source = "fediverse.observer:cache-revalidated"
                  else
                    source = "fediverse.observer:cache-refleshed"
                  end
                  updated_record = Instance.update(instance[:id], name: instance_name, instance_type: instance_type, software: instance_software, version: instance_version, total_users: instance_total_users, status: instance_status, source: "fediverse.observer")
                  instance_updated_at = updated_record.updated_at
                end
              end
            end
          end
        end

        instance_addr = ""
        if instance_type == "" then
          begin
            instance_ipaddr = Resolv::DNS.new(:nameserver => NameServer).getaddress(instance_name).to_s
          rescue
            instance_type = "unknown"
            source = "error:dns-error"
            # DNS error is NOT cached to ActiveRecord
          end
        end

        if instance_type == "" && instance_ipaddr != "" then
          begin
            nodes = fetch_swapi_nodes(instance_name)
          rescue
            instance_type = "unknown"
            source = "error:observer-unavailable"
            # observer-unavailable is transient and NOT cached
          else
            unless nodes.length == 0 then
              nodes.each do |node|
                instance_software = node.softwarename
                instance_type = SoftwareFamilies.normalize(node.softwarename)
                instance_version = node.fullversion
                instance_total_users = node.total_users
                instance_status = node.status
                source = "fediverse.observer"
                created_record = upsert_instance(
                  name: instance_name,
                  instance_type: instance_type,
                  software: instance_software,
                  version: instance_version,
                  total_users: instance_total_users,
                  status: instance_status,
                  source: "fediverse.observer"
                )
                instance_updated_at = created_record.updated_at
              end
            else
              instance_type = "unknown"
              source = "error:no-data"
              created_record = upsert_instance(name: instance_name, instance_type: "unknown", version: "", source: "error:no-data")
              instance_updated_at = created_record.updated_at
            end
          end
        end

        render status: status_for_response(source, instance_type), json: response_json(instance_name, instance_type, instance_software, instance_version, instance_total_users, instance_status, instance_updated_at, source)
      end

      private

      # graphql-client surfaces non-2xx/400 upstream responses (e.g. 403 IP
      # blocks, 5xx) as a Response with errors but nil data, which would
      # NoMethodError on `.node` downstream. Raise so the caller's rescue path
      # handles it as observer-unavailable / stale-fallback instead of 500ing.
      def fetch_swapi_nodes(domain)
        variables = { domain: domain, key: SWAPI::API_KEY }
        result = SWAPI::Client.query(SWAPI::Query, variables: variables)
        raise "fediverse.observer returned no data" if result.data.nil?
        result.data.node
      end

      def response_json(name, type, software, version, total_users, status, updated_at, source)
        json = { name: name, type: type }
        if type == "unknown"
          json[:software] = "unknown"
          json[:version] = "unknown"
        else
          json[:software] = software if software.present?
          json[:version] = version if version.present?
        end
        json[:total_users] = total_users unless total_users.nil?
        json[:status] = status unless status.nil?
        json[:updated_at] = updated_at.iso8601 unless updated_at.nil?
        json[:source] = source unless source == ""
        json
      end

      # Atomically create or fetch the instance row by name. The DB has a unique
      # index on `name`, so concurrent requests racing past `find_by` cannot both
      # insert — the loser gets RecordNotUnique and falls back to the winner's row.
      def upsert_instance(attrs)
        Instance.create!(attrs)
      rescue ActiveRecord::RecordNotUnique
        Instance.find_by!(name: attrs[:name])
      end

      def stale_cache?(instance)
        if instance[:permanent] then
          false
        elsif instance[:instance_type] == "unknown" then
          instance[:updated_at] < Time.current.ago(1.days)
        else
          instance[:updated_at] < Time.current.ago(3.days)
        end
      end

      # Permanent rows always render as "builtin"; otherwise prefix the original
      # source recorded at write time with "cache:". Falls back for legacy rows
      # written before the source column existed.
      def cached_source(instance)
        return "builtin" if instance[:permanent]
        stored = instance[:source].presence || "fediverse.observer"
        "cache:#{stored}"
      end

      # Used when refreshing a stale cache fails because fediverse.observer is
      # unreachable. We still serve the cached payload but flag the response so
      # clients can tell the data wasn't revalidated.
      def stale_fallback_source(instance)
        stored = instance[:source].presence || "fediverse.observer"
        "cache:#{stored}:stale-fallback"
      end

      # HTTP status is driven by the data nature, not by whether the response
      # came from cache. instance_type == "unknown" backstops the cache-stale
      # case where the source string doesn't carry the original error tag.
      def status_for_response(source, instance_type)
        return 400 if source.start_with?("error:dns-error")
        return 503 if source.start_with?("error:observer-unavailable")
        return 404 if source.include?("error:no-data")
        return 404 if instance_type == "unknown"
        200
      end

    end
  end
end

module SWAPI
  # API key issued by fediverse.observer. Requests without a valid key are
  # blocked by Cloudflare (HTTP 403) for traffic from datacenter IP ranges.
  # Provide via the SWAPI_API_KEY environment variable; rotate yearly.
  API_KEY = ENV["SWAPI_API_KEY"].to_s

  # Drop-in replacement for GraphQL::Client::HTTP that routes requests through
  # libcurl (via Typhoeus). Required because Cloudflare bot management blocks
  # Ruby Net::HTTP's TLS fingerprint when the source is a datacenter IP; curl
  # passes from the same IP. Contract: respond to #execute(document:,
  # operation_name:, variables:, context:) and return a parsed JSON hash —
  # this is what GraphQL::Client and ::dump_schema rely on.
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

      # Mirror GraphQL::Client::HTTP: parse the body on 200/400, otherwise
      # synthesise an errors-only payload so the client surfaces it as a
      # Response with nil data (which fetch_swapi_nodes raises on).
      if response.code == 200 || response.code == 400
        JSON.parse(response.body)
      else
        { "errors" => [{ "message" => "#{response.code} #{response.return_message}" }] }
      end
    end
  end

  HTTP = CurlTransport.new(
    "https://api.fediverse.observer/graphql",
    headers: { "User-Agent" => "instance-info-api/1.0 (+https://github.com/highemerly/instance-info-api)" }
  )
  # Load the schema from a checked-in JSON dump rather than running an
  # introspection query against fediverse.observer at boot. The introspection
  # request was a hard boot-time dependency on a third-party API, so any
  # degraded response (e.g. missing the "data" key) used to crash Puma start.
  # Refresh the file with `bundle exec rake swapi:schema:dump`.
  Schema = GraphQL::Client.load_schema(Rails.root.join("db", "swapi_schema.json").to_s)
  Client = GraphQL::Client.new(schema: Schema, execute: HTTP)
  Query = Client.parse <<-'GRAPHQL'
  query($domain: String!, $key: String) {
    node(domain: $domain, key: $key) {
      softwarename
      fullversion
      total_users
      status
    }
  }
  GRAPHQL
end
