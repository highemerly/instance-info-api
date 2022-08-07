require "resolv"
require "graphql/client"
require "graphql/client/http"

NameServer = '8.8.8.8'

module Api
  module V1
    class InstancesController < ApplicationController
      def show
        response.set_header('Access-Control-Allow-Origin', '*') # (tmp) For debug only

        instance_name = params[:name]
        instance_type = ""
        source = ""

        instance = Instance.find_by(name: instance_name)

        unless instance == nil then
          unless stale_cache?(instance) then
            instance_type = instance[:instance_type]
            source = "cache"
          else
            graphQL_result = SWAPI::Client.query(SWAPI::Query, variables: {domain: instance_name})

            if graphQL_result.data.node.length == 0 then
              instance_type = instance[:instance_type]
              source = "cache:cache-stale"
            else
              graphQL_result.data.node.each do |type|
                if type.softwarename == instance[:instance_type] then
                  instance_type = instance[:instance_type]
                  source = "fediverse.observer:cache-revalidated"
                  instance.touch
                else
                  instance_type = type.softwarename
                  source = "fediverse.observer:cache-refleshed"
                  Instance.update(instance[:id], name: instance_name, instance_type: instance_type, version: "")
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
          result = SWAPI::Client.query(SWAPI::Query, variables: {domain: instance_name})

          unless result.data.node.length == 0 then
            result.data.node.each do |type|
              instance_type = type.softwarename
              source = "fediverse.observer"
              Instance.create(name: instance_name, instance_type: instance_type, version: "")
            end
          else
            instance_type = "unknown"
            source = "error:no-data"
            Instance.create(name: instance_name, instance_type: "unknown", version: "")
          end
        end

        render status: 200, json: response_json(instance_name, instance_type, source)
      end

      private

      def response_json(name, type, source)
        if source == "" then
          {name: name, type: type}
        else
          {name: name, type: type, source: source}
        end
      end

      def stale_cache?(instance)
        if instance[:parmanent] then
          false
        elsif instance[:instance_type] == "unknown" then
          instance[:updated_at] < Time.current.ago(1.days)
        else
          instance[:updated_at] < Time.current.ago(3.days)
        end
      end

    end
  end
end

module SWAPI
  HTTP = GraphQL::Client::HTTP.new("https://api.fediverse.observer/graphql")
  Schema = GraphQL::Client.load_schema(HTTP)
  Client = GraphQL::Client.new(schema: Schema, execute: HTTP)
  Query = Client.parse <<-'GRAPHQL'
  query($domain: String!) {
    node(domain: $domain) {
      softwarename
    }
  }
  GRAPHQL
end
