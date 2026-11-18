# Cache-Control for API responses. Browsers follow max-age; Cloudflare follows
# s-maxage (its Cache Rule is set to respect the origin's Cache-Control).
#
# The CDN never keeps a row past the moment it goes stale in our cache, so a
# client sees data at most FRESH_FOR old plus the minute a stale answer is
# cached while the background refresh runs.
module CacheHeaders
  extend ActiveSupport::Concern

  BROWSER_MAX_AGE = 5.minutes
  CDN_MAX_AGE = 6.hours
  CDN_MAX_AGE_NOT_FEDIVERSE = 1.hour
  CDN_MAX_AGE_STALE = 1.minute
  CDN_MIN_AGE = 1.minute

  private

  def cache_lookup(result)
    if result.cache == :builtin
      cache_publicly(browser: 1.hour, cdn: 1.hour)
    elsif result.cache == :stale
      cache_publicly(browser: 0, cdn: CDN_MAX_AGE_STALE)
    elsif result.record
      cap = result.error == :not_fediverse ? CDN_MAX_AGE_NOT_FEDIVERSE : CDN_MAX_AGE
      remaining = (result.fresh_until - Time.current).to_i
      cdn = remaining.clamp(CDN_MIN_AGE.to_i, cap.to_i)
      cache_publicly(browser: [BROWSER_MAX_AGE.to_i, cdn].min, cdn: cdn)
    elsif result.error == :upstream_unavailable
      no_store
    else
      # invalid_name, unresolvable: not cached by us; a short CDN cache keeps
      # repeats off the DNS.
      cache_publicly(browser: 1.minute, cdn: 5.minutes)
    end
  end

  def cache_publicly(browser:, cdn:)
    expires_in browser.to_i, public: true, "s-maxage": cdn.to_i
  end
end
