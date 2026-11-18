require "yaml"

# Non-fediverse services from config/builtin_services.yml, looked up by domain.
module BuiltinServices
  CONFIG_PATH = Rails.root.join("config", "builtin_services.yml")

  Service = Struct.new(:type, :node_name, :domains, :max_characters, :open_registrations, keyword_init: true)

  ALL = YAML.load_file(CONFIG_PATH).map do |type, attrs|
    limits = attrs["max_characters"]
    Service.new(
      type: type.to_s,
      node_name: attrs.fetch("node_name"),
      domains: Array(attrs.fetch("domains")).map(&:to_s).freeze,
      max_characters: limits && { halfwidth: Integer(limits.fetch("halfwidth")), fullwidth: Integer(limits.fetch("fullwidth")) }.freeze,
      open_registrations: attrs["open_registrations"]
    ).freeze
  end.freeze

  BY_DOMAIN = ALL.each_with_object({}) do |service, hash|
    service.domains.each do |domain|
      raise ArgumentError, "#{CONFIG_PATH}: #{domain} is listed twice" if hash.key?(domain)
      hash[domain] = service
    end
  end.freeze

  def self.find(domain)
    BY_DOMAIN[domain]
  end
end
