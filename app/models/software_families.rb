require "yaml"

module SoftwareFamilies
  CONFIG_PATH = Rails.root.join("config", "software_families.yml")

  MAPPING = YAML.load_file(CONFIG_PATH).each_with_object({}) do |(canonical, variants), hash|
    Array(variants).each { |variant| hash[variant.to_s.downcase] = canonical.to_s }
  end.freeze

  def self.normalize(softwarename)
    return nil if softwarename.nil?
    key = softwarename.to_s.downcase
    return nil if key.empty?
    MAPPING.fetch(key, key)
  end
end
