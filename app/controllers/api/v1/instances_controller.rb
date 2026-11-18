module Api
  module V1
    # Deprecated in favor of /api/v2/instances; kept until clients move over.
    # Renders InstanceLookup's result in the v1 shape (`source` strings,
    # omitted fields, `status`).
    class InstancesController < ApplicationController
      include CacheHeaders

      # fediverse.observer shut down (2026-10), so it's out of the chain and
      # `?source=fediverse.observer` is rejected. FediverseObserverClient is
      # kept in case the service comes back.
      VALID_SOURCE_PARAMS = %w[nodeinfo].freeze

      def show
        response.set_header('Access-Control-Allow-Origin', '*') # (tmp) For debug only

        unless [nil, "", "nodeinfo"].include?(params[:source])
          cache_publicly(browser: 1.minute, cdn: 5.minutes)
          return render status: 400, json: { error: "invalid source", given: params[:source], valid: VALID_SOURCE_PARAMS }
        end

        result = InstanceLookup.new(revalidate: :sync).call(params[:name])
        cache_lookup(result)
        view =
          if result.service
            { name: result.name, type: result.service.type }
          elsif result.record
            view_from_record(result.record)
          else
            { name: result.name, type: "unknown" }
          end

        render status: status_for_response(result.v1_source, view[:type]),
               json: response_json(**view, source: result.v1_source)
      end

      private

      def view_from_record(record)
        {
          name: record.name,
          type: record.instance_type,
          software: record.software,
          version: record.version,
          total_users: record.total_users,
          status: record.status,
          updated_at: record.updated_at
        }
      end

      def response_json(name:, type:, source:, software: nil, version: nil, total_users: nil, status: nil, updated_at: nil)
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

      # HTTP status is driven by the data nature, not by whether the response
      # came from cache. type == "unknown" backstops the cache-stale case where
      # the source string doesn't carry the original error tag.
      def status_for_response(source, type)
        return 400 if source.start_with?("error:invalid-name", "error:dns-error")
        return 503 if source.start_with?("error:") && source.end_with?("-unavailable")
        return 404 if source.include?("error:no-data")
        return 404 if type == "unknown"
        200
      end
    end
  end
end
