require "graphql/client"

namespace :swapi do
  namespace :schema do
    desc "Dump fediverse.observer GraphQL schema to db/swapi_schema.json"
    task :dump => :environment do
      output = Rails.root.join("db", "swapi_schema.json")
      GraphQL::Client.dump_schema(SWAPI::HTTP, output.to_s)
      puts "Wrote schema to #{output}"
    end
  end
end
