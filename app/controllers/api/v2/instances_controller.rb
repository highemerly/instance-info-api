module Api
  module V2
    # GET /api/v2/instances/:name
    #
    # Every key is always present (null when unknown), so clients get one
    # shape for fediverse servers and builtin services alike. Errors come back
    # as { domain, error: { code, message } }. A stale row is answered at once
    # and refreshed in the background (`cache: "stale"`).
    class InstancesController < BaseController
      ERRORS = {
        invalid_name: [400, "not a hostname"],
        unresolvable: [404, "the domain does not resolve"],
        not_fediverse: [404, "no nodeinfo; not a fediverse server"],
        upstream_unavailable: [503, "the server could not be reached; try again later"]
      }.freeze

      def show
        result = InstanceLookup.new(revalidate: :async).call(params[:name])
        cache_lookup(result)

        if result.error
          status, message = ERRORS.fetch(result.error)
          render status: status, json: { domain: result.name, error: { code: result.error, message: message } }
        elsif result.service
          render json: service_json(result.name, result.service)
        else
          render json: instance_json(result.name, result.record, cache: result.cache)
        end
      end

      private

      def instance_json(domain, record, cache:)
        {
          domain: domain,
          kind: "fediverse",
          type: record.instance_type,
          software: record.software.present? ? { name: record.software, version: record.version.presence } : nil,
          node_name: record.node_name,
          thumbnail_url: record.thumbnail_url,
          icon_url: record.icon_url,
          # Fediverse software counts a CJK character as one, like a letter.
          max_characters: record.max_characters && { halfwidth: record.max_characters, fullwidth: record.max_characters },
          open_registrations: record.open_registrations,
          usage: {
            total_users: record.total_users,
            active_month: record.active_month,
            active_halfyear: record.active_halfyear,
            local_posts: record.local_posts
          },
          fetched_at: record.updated_at.iso8601,
          cache: cache
        }
      end

      def service_json(domain, service)
        {
          domain: domain,
          kind: "service",
          type: service.type,
          software: nil,
          node_name: service.node_name,
          thumbnail_url: nil,
          icon_url: nil,
          max_characters: service.max_characters,
          open_registrations: service.open_registrations,
          usage: nil,
          fetched_at: nil,
          cache: "builtin"
        }
      end
    end
  end
end
