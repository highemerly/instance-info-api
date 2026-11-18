module Api
  module V2
    # GET /api/v2/software — the fediverse families we recognize (and the
    # nodeinfo software names folded into each) and the builtin services.
    class SoftwareController < BaseController
      def index
        cache_publicly(browser: 1.hour, cdn: 1.hour)
        render json: {
          fediverse: SoftwareFamilies::FAMILIES.map { |type, software| { type: type, software: software } },
          services: BuiltinServices::ALL.map do |service|
            {
              type: service.type,
              node_name: service.node_name,
              domains: service.domains,
              max_characters: service.max_characters,
              open_registrations: service.open_registrations
            }
          end
        }
      end
    end
  end
end
