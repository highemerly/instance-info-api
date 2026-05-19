require "resolv"

NameServer = '8.8.8.8'

module Api
  module V1
    class InstancesController < ApplicationController
      VALID_SOURCE_PARAMS = %w[fediverse.observer nodeinfo].freeze

      def show
        response.set_header('Access-Control-Allow-Origin', '*') # (tmp) For debug only

        backends = backends_for_param(params[:source])
        return render_invalid_source(params[:source]) if backends.nil?

        instance_name = params[:name]
        instance = Instance.find_by(name: instance_name)

        outcome =
          if instance && !stale_cache?(instance)
            serve_cached(instance, instance_name)
          elsif instance
            refresh_stale(instance, instance_name, backends)
          else
            fresh_lookup(instance_name, backends)
          end

        render status: outcome[:http_status], json: outcome[:body]
      end

      private

      # nil  -> default chain (observer first, nodeinfo fallback on 50x/403)
      # "fediverse.observer" / "nodeinfo" -> single-backend pin
      # anything else -> caller renders 400
      def backends_for_param(value)
        case value
        when nil, ""
          [FediverseObserverClient::Backend.new, NodeinfoClient::Backend.new]
        when "fediverse.observer"
          [FediverseObserverClient::Backend.new]
        when "nodeinfo"
          [NodeinfoClient::Backend.new]
        end
      end

      def render_invalid_source(value)
        render status: 400, json: {
          error: "invalid source",
          given: value,
          valid: VALID_SOURCE_PARAMS
        }
      end

      def serve_cached(instance, instance_name)
        view = view_from_instance(instance, instance_name, source: cached_source(instance))
        wrap_outcome(view)
      end

      def refresh_stale(instance, instance_name, backends)
        result, used = try_backends(backends, instance_name)

        if result.nil?
          # Every backend was :unavailable — keep serving what we have.
          view = view_from_instance(instance, instance_name, source: stale_fallback_source(instance))
          return wrap_outcome(view)
        end

        if result.no_data?
          # Observer/nodeinfo says this domain isn't a known node anymore, but
          # we still have a cache row. Surface the cached payload with a
          # cache-stale marker; clients can interpret that however they like.
          view = view_from_instance(instance, instance_name, source: "cache:cache-stale")
          return wrap_outcome(view)
        end

        type = SoftwareFamilies.normalize(result.software)
        same_software = result.software == instance[:software]
        source = "#{used.name}:#{same_software ? 'cache-revalidated' : 'cache-refleshed'}"

        updated_record = Instance.update(
          instance[:id],
          name: instance_name,
          instance_type: type,
          software: result.software,
          version: result.version,
          total_users: result.total_users,
          status: result.node_status,
          source: used.name
        )

        wrap_outcome(view_from_result(instance_name, result, source: source, instance_updated_at: updated_record.updated_at))
      end

      def fresh_lookup(instance_name, backends)
        begin
          Resolv::DNS.new(nameserver: NameServer).getaddress(instance_name)
        rescue
          return wrap_outcome(blank_view(instance_name, instance_type: "unknown", source: "error:dns-error"))
        end

        result, used = try_backends(backends, instance_name)

        if result.nil?
          last_backend = backends.last
          return wrap_outcome(blank_view(instance_name, instance_type: "unknown", source: last_backend.unavailable_source))
        end

        if result.no_data?
          created_record = upsert_instance(name: instance_name, instance_type: "unknown", version: "", source: "error:no-data")
          return wrap_outcome(blank_view(instance_name, instance_type: "unknown", source: "error:no-data", instance_updated_at: created_record.updated_at))
        end

        type = SoftwareFamilies.normalize(result.software)
        created_record = upsert_instance(
          name: instance_name,
          instance_type: type,
          software: result.software,
          version: result.version,
          total_users: result.total_users,
          status: result.node_status,
          source: used.name
        )

        wrap_outcome(view_from_result(instance_name, result, source: used.name, instance_updated_at: created_record.updated_at))
      end

      # Returns [result, backend] for the first backend that produced :ok or
      # :no_data; both terminate the chain (only :unavailable falls through to
      # the next backend, per the explicit 50x/403-only fallback rule).
      def try_backends(backends, domain)
        backends.each do |b|
          r = b.fetch(domain)
          record_outcome(b, r, domain)
          return [r, b] unless r.unavailable?
        end
        [nil, nil]
      end

      def record_outcome(backend, result, domain)
        if result.unavailable?
          SourceFailureTracker.record_failure(
            backend.name,
            http_status: result.http_status,
            message: result.error_message,
            domain: domain
          )
        else
          SourceFailureTracker.record_success(backend.name, domain: domain)
        end
      end

      def view_from_instance(instance, instance_name, source:)
        {
          name: instance_name,
          type: instance[:instance_type],
          software: instance[:software],
          version: instance[:version],
          total_users: instance[:total_users],
          status: instance[:status],
          updated_at: instance[:updated_at],
          source: source
        }
      end

      def view_from_result(instance_name, result, source:, instance_updated_at:)
        {
          name: instance_name,
          type: SoftwareFamilies.normalize(result.software),
          software: result.software,
          version: result.version,
          total_users: result.total_users,
          status: result.node_status,
          updated_at: instance_updated_at,
          source: source
        }
      end

      def blank_view(instance_name, instance_type:, source:, instance_updated_at: nil)
        {
          name: instance_name,
          type: instance_type,
          software: nil,
          version: nil,
          total_users: nil,
          status: nil,
          updated_at: instance_updated_at,
          source: source
        }
      end

      def wrap_outcome(view)
        {
          http_status: status_for_response(view[:source], view[:type]),
          body: response_json(**view)
        }
      end

      def response_json(name:, type:, software:, version:, total_users:, status:, updated_at:, source:)
        json = { name: name, type: type }
        if type == "unknown"
          json[:software] = "unknown"
          json[:version] = "unknown"
        else
          json[:software] = software if software.present?
          json[:version] = version if version.present?
        end
        json[:total_users] = total_users unless total_users.nil?

        # nodeinfo rows intentionally carry a null `status` so clients can
        # distinguish "fediverse, up enough to serve nodeinfo, but no
        # poduptime-style status history" from observer-derived integers.
        if source.to_s.include?("nodeinfo")
          json[:status] = status
        elsif !status.nil?
          json[:status] = status
        end

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

      # Used when refreshing a stale cache fails because every remote source
      # we tried was unavailable. We still serve the cached payload but flag
      # the response so clients can tell the data wasn't revalidated.
      def stale_fallback_source(instance)
        stored = instance[:source].presence || "fediverse.observer"
        "cache:#{stored}:stale-fallback"
      end

      # HTTP status is driven by the data nature, not by whether the response
      # came from cache. instance_type == "unknown" backstops the cache-stale
      # case where the source string doesn't carry the original error tag.
      def status_for_response(source, instance_type)
        return 400 if source.start_with?("error:dns-error")
        return 503 if source.start_with?("error:") && source.end_with?("-unavailable")
        return 404 if source.include?("error:no-data")
        return 404 if instance_type == "unknown"
        200
      end

    end
  end
end
