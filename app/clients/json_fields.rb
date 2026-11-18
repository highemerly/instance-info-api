require "uri"

# Picks typed values out of JSON that remote servers hand us. Anything of the
# wrong shape becomes nil instead of raising, so one odd server can't break a
# lookup (Hash#dig raises when it meets a String midway, for example).
module JsonFields
  MAX_TEXT_LENGTH = 200
  MAX_URL_LENGTH = 2048
  URL_SCHEMES = %w[http https].freeze

  module_function

  def dig(object, *keys)
    keys.reduce(object) { |current, key| current.is_a?(Hash) ? current[key] : nil }
  end

  # Non-negative integer (user and post counts).
  def count(value)
    value.is_a?(Integer) && value >= 0 ? value : nil
  end

  # Positive integer (limits).
  def limit(value)
    value.is_a?(Integer) && value > 0 ? value : nil
  end

  def boolean(value)
    value == true || value == false ? value : nil
  end

  def text(value)
    return nil unless value.is_a?(String)
    value.strip.presence&.truncate(MAX_TEXT_LENGTH)
  end

  # An http(s) URL, made absolute against the server it came from. We only
  # hand these to clients; we never fetch them.
  def url(value, base:)
    return nil unless value.is_a?(String) && value.present? && value.length <= MAX_URL_LENGTH
    uri = URI.join(base, value.strip)
    URL_SCHEMES.include?(uri.scheme&.downcase) && uri.host.present? ? uri.to_s : nil
  rescue URI::Error, ArgumentError
    nil
  end
end
