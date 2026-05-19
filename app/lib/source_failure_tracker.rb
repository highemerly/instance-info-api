# Per-Pod, in-memory tally of remote-source outcomes. Drives /api/v1/health/sources
# and emits a structured warn line on each failure so log aggregators can
# pick it up without polling the endpoint.
#
# Multi-Pod aggregation is intentionally out of scope — each replica reports
# its own view; combine externally (Grafana/Loki, kubectl logs, etc.).
class SourceFailureTracker
  @mutex = Mutex.new
  @states = {}

  class << self
    def record_success(name, domain:)
      @mutex.synchronize do
        s = (@states[name] ||= blank_state)
        s[:consecutive_failures] = 0
        s[:total_attempts] += 1
        s[:last_success] = { domain: domain, at: Time.current.iso8601 }
      end
    end

    def record_failure(name, http_status:, message:, domain:)
      @mutex.synchronize do
        s = (@states[name] ||= blank_state)
        s[:consecutive_failures] += 1
        s[:total_failures] += 1
        s[:total_attempts] += 1
        s[:last_failure] = {
          domain: domain,
          http_status: http_status,
          message: message.to_s,
          at: Time.current.iso8601
        }
      end
      Rails.logger.warn(
        %(source_failure name=#{name} status=#{http_status} domain=#{domain} message=#{message.to_s.inspect})
      )
    end

    def snapshot
      @mutex.synchronize { @states.deep_dup }
    end

    def reset!
      @mutex.synchronize { @states.clear }
    end

    private

    def blank_state
      {
        consecutive_failures: 0,
        total_failures: 0,
        total_attempts: 0,
        last_failure: nil,
        last_success: nil
      }
    end
  end
end
