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
        instance_software = nil
        instance_version = nil
        instance_total_users = nil
        instance_status = nil
        source = ""

        instance = Instance.find_by(name: instance_name)

        unless instance == nil then
          unless stale_cache?(instance) then
            instance_type = instance[:instance_type]
            instance_software = instance[:software]
            instance_version = instance[:version]
            instance_total_users = instance[:total_users]
            instance_status = instance[:status]
            source = instance[:permanent] ? "builtin" : "cache"
          else
            graphQL_result = SWAPI::Client.query(SWAPI::Query, variables: {domain: instance_name})

            if graphQL_result.data.node.length == 0 then
              instance_type = instance[:instance_type]
              instance_software = instance[:software]
              instance_version = instance[:version]
              instance_total_users = instance[:total_users]
              instance_status = instance[:status]
              source = "cache:cache-stale"
            else
              graphQL_result.data.node.each do |node|
                instance_software = node.softwarename
                instance_type = SoftwareFamilies.normalize(node.softwarename)
                instance_version = node.fullversion
                instance_total_users = node.total_users
                instance_status = node.status

                if node.softwarename == instance[:software] then
                  source = "fediverse.observer:cache-revalidated"
                else
                  source = "fediverse.observer:cache-refleshed"
                end
                Instance.update(instance[:id], name: instance_name, instance_type: instance_type, software: instance_software, version: instance_version, total_users: instance_total_users, status: instance_status)
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
            result.data.node.each do |node|
              instance_software = node.softwarename
              instance_type = SoftwareFamilies.normalize(node.softwarename)
              instance_version = node.fullversion
              instance_total_users = node.total_users
              instance_status = node.status
              source = "fediverse.observer"
              Instance.create(name: instance_name, instance_type: instance_type, software: instance_software, version: instance_version, total_users: instance_total_users, status: instance_status)
            end
          else
            instance_type = "unknown"
            source = "error:no-data"
            Instance.create(name: instance_name, instance_type: "unknown", version: "")
          end
        end

        render status: 200, json: response_json(instance_name, instance_type, instance_software, instance_version, instance_total_users, instance_status, source)
      end

      private

      def response_json(name, type, software, version, total_users, status, source)
        json = { name: name, type: type }
        json[:software] = software if software.present?
        json[:version] = version if version.present?
        json[:total_users] = total_users unless total_users.nil?
        json[:status] = status unless status.nil?
        json[:source] = source unless source == ""
        json
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
      fullversion
      total_users
      status
    }
  }
  GRAPHQL
end
