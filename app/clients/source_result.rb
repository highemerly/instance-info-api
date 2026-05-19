# Outcome of a single backend fetch, normalized so observer and nodeinfo can
# be looped over interchangeably. `state` drives the controller's branching:
# `:ok` consumes the row, `:no_data` short-circuits with cache-stale/no-data
# semantics, `:unavailable` triggers the next backend (50x/403/network).
SourceResult = Struct.new(
  :state,
  :software, :version, :total_users, :node_status,
  :http_status, :error_message,
  keyword_init: true
) do
  def ok?
    state == :ok
  end

  def no_data?
    state == :no_data
  end

  def unavailable?
    state == :unavailable
  end
end
