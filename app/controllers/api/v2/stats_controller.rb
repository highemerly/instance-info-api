module Api
  module V2
    # GET /api/v2/stats — what this Pod's cache holds: the servers people have
    # looked up through the API, not the whole fediverse. The cache lives with
    # the Pod, so the numbers start over when it's replaced.
    class StatsController < BaseController
      def show
        cache_publicly(browser: 1.minute, cdn: 5.minutes)
        fediverse = Instance.where.not(instance_type: "unknown")

        render json: {
          pod: ENV.fetch("HOSTNAME", nil),
          generated_at: Time.current.iso8601,
          since: Instance.minimum(:created_at)&.iso8601,
          instances: {
            fediverse: fediverse.count,
            not_fediverse: Instance.where(instance_type: "unknown").count
          },
          types: by_count(fediverse.group(:instance_type).count),
          software: by_count(fediverse.where.not(software: [nil, ""]).group(:software).count)
        }
      end

      private

      # Most common first; ties alphabetically.
      def by_count(counts)
        counts.sort_by { |name, count| [-count, name.to_s] }.to_h
      end
    end
  end
end
