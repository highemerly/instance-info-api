module Api
  module V1
    class HealthController < ApplicationController
      # GET /api/v1/health/sources
      #
      # Returns the current Pod's view of per-source success/failure tallies
      # since process start. State is in-memory and not shared across replicas;
      # aggregate externally if needed.
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
