require "yaml"

module SoftwareFamilies
  CONFIG_PATH = Rails.root.join("config", "software_families.yml")

  # { "mastodon" => ["mastodon", "hometown", ...], ... } as written in the file.
  FAMILIES = YAML.load_file(CONFIG_PATH).to_h do |canonical, variants|
    [canonical.to_s, Array(variants).map(&:to_s).freeze]
  end.freeze

  MAPPING = FAMILIES.each_with_object({}) do |(canonical, variants), hash|
    variants.each { |variant| hash[variant.downcase] = canonical }
  end.freeze

  def self.normalize(softwarename)
    return nil if softwarename.nil?
    key = softwarename.to_s.downcase
    return nil if key.empty?
    MAPPING.fetch(key, key)
  end
end
