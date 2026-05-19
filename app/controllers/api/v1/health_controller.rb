module Api
  module V1
    class HealthController < ApplicationController
      # GET /api/v1/health/live
      #
      # Liveness probe. Returns 200 as long as Puma is serving requests; any
      # other response means the process is wedged and k8s should restart it.
      # Intentionally does not touch the DB or remote sources — those failure
      # modes belong to readiness, not liveness (we don't want external
      # outages to trigger a restart loop).
      def live
        render json: { status: "ok" }
      end

      # GET /api/v1/health/ready
      #
      # Readiness probe. 200 when this Pod can serve traffic, 503 when it
      # can't — currently gated on the cache DB being reachable, since every
      # request reads/writes it. External upstreams (observer / nodeinfo)
      # are deliberately excluded; their failures are handled by the
      # backend-chain fallback, not by removing the Pod from the service.
      def ready
        ActiveRecord::Base.connection.execute("SELECT 1")
        render json: { status: "ok", db: "ok" }
      rescue => e
        render status: 503, json: { status: "error", db: "down", error: e.message }
      end

      # GET /api/v1/health/sources
      #
      # Returns the current Pod's view of per-source success/failure tallies
      # since process start. State is in-memory and not shared across replicas;
      # aggregate externally if needed. Not suitable as a k8s probe — it
      # always returns 200 even when every upstream is failing, by design.
      def sources
        response.set_header('Access-Control-Allow-Origin', '*') # (tmp) For debug only

        render json: {
          pod: ENV.fetch("HOSTNAME", nil),
          generated_at: Time.current.iso8601,
          sources: SourceFailureTracker.snapshot
        }
      end
    end
  end
end
