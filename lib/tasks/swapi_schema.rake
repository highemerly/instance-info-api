require "graphql/client"
require "graphql/client/http"

namespace :swapi do
  namespace :schema do
    desc "Dump fediverse.observer GraphQL schema to db/swapi_schema.json"
    task :dump do
      endpoint = "https://api.fediverse.observer/graphql"
      output = Rails.root.join("db", "swapi_schema.json")

      http = GraphQL::Client::HTTP.new(endpoint)
      GraphQL::Client.dump_schema(http, output.to_s)

      puts "Wrote schema to #{output}"
    end
  end
end
