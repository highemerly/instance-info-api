# Looks an instance up: builtin services (config), then the cache DB, then the
# backends (nodeinfo, plus each software's instance API). The v1 and v2
# controllers only render the Result differently.
#
# Result:
#   name      normalized domain (the raw input when it isn't a hostname)
#   service   BuiltinServices::Service, for builtin names
#   record    Instance row, when there is one to show
#   cache     :builtin | :hit (fresh row) | :miss (fetched now) |
#             :stale (old row served because the refresh got nothing usable)
#   error     nil | :invalid_name | :unresolvable | :not_fediverse | :upstream_unavailable
#   v1_source the v1 `source` string for the same outcome
class InstanceLookup
  FRESH_FOR = 3.days
  UNKNOWN_FRESH_FOR = 1.day

  Result = Struct.new(:name, :service, :record, :cache, :error, :v1_source, keyword_init: true)

  def initialize(backends: [NodeinfoClient::Backend.new])
    @backends = backends
  end

  def call(input)
    name = InstanceName.normalize(input)
    return Result.new(name: input.to_s, error: :invalid_name, v1_source: "error:invalid-name") if name.nil?

    service = BuiltinServices.find(name)
    return Result.new(name: name, service: service, cache: :builtin, v1_source: "builtin") if service

    instance = Instance.find_by(name: name)
    if instance.nil?
      fresh_lookup(name)
    elsif stale?(instance)
      refresh(instance, name)
    else
      row_result(name, instance, cache: :hit, v1_source: "cache:#{stored_source(instance)}")
    end
  end

  private

  def fresh_lookup(name)
    result, used = try_backends(name)

    if result.nil?
      return Result.new(name: name, error: :upstream_unavailable, v1_source: @backends.last.unavailable_source)
    end
    return Result.new(name: name, error: :unresolvable, v1_source: "error:dns-error") if result.unresolvable?

    if result.no_data?
      record = upsert_instance(name: name, instance_type: "unknown", version: "", source: "error:no-data")
      return row_result(name, record, cache: :miss, v1_source: "error:no-data")
    end

    record = upsert_instance(name: name, source: used.name, **fetched_attributes(result, name))
    row_result(name, record, cache: :miss, v1_source: used.name)
  end

  def refresh(instance, name)
    result, used = try_backends(name)

    if result.nil? || result.unresolvable?
      # Every backend was :unavailable, or the name stopped resolving (likely
      # passing) — keep serving what we have.
      return row_result(name, instance, cache: :stale, v1_source: "cache:#{stored_source(instance)}:stale-fallback")
    end

    if result.no_data?
      # The server no longer serves nodeinfo, but we still have a row. Serve it
      # marked stale; clients can interpret that however they like.
      return row_result(name, instance, cache: :stale, v1_source: "cache:cache-stale")
    end

    same_software = result.software == instance[:software]
    instance.update!(name: name, source: used.name, **fetched_attributes(result, name, previous: instance))
    row_result(name, instance, cache: :miss,
               v1_source: "#{used.name}:#{same_software ? 'cache-revalidated' : 'cache-refleshed'}")
  end

  def row_result(name, record, cache:, v1_source:)
    error = record.instance_type == "unknown" ? :not_fediverse : nil
    Result.new(name: name, record: record, cache: cache, error: error, v1_source: v1_source)
  end

  # Returns [result, backend] for the first backend that produced anything but
  # :unavailable (only that falls through to the next backend).
  def try_backends(domain)
    @backends.each do |backend|
      result = backend.fetch(domain)
      record_outcome(backend, result, domain)
      return [result, backend] unless result.unavailable?
    end
    [nil, nil]
  end

  def record_outcome(backend, result, domain)
    # A domain that doesn't resolve says nothing about the source's health.
    return if result.unresolvable?

    if result.unavailable?
      SourceFailureTracker.record_failure(backend.name, http_status: result.http_status, message: result.error_message, domain: domain)
    else
      SourceFailureTracker.record_success(backend.name, domain: domain)
    end
  end

  # Columns for a row from a successful fetch: the nodeinfo result plus the
  # software's instance API (InstanceDetailsClient). When that API didn't
  # answer this time, a refresh falls back to the values the row already had
  # rather than blanking them over a passing failure.
  def fetched_attributes(result, name, previous: nil)
    details = InstanceDetailsClient.fetch(name, software: result.software)
    kept = ->(column) { previous && !details.reached ? previous[column] : nil }

    {
      instance_type: SoftwareFamilies.normalize(result.software),
      software: result.software,
      version: result.version,
      total_users: result.total_users,
      status: result.node_status,
      node_name: result.node_name || details.node_name || kept.(:node_name),
      open_registrations: result.open_registrations,
      active_month: result.active_month,
      active_halfyear: result.active_halfyear,
      local_posts: result.local_posts,
      max_characters: details.max_characters || result.max_characters || kept.(:max_characters),
      thumbnail_url: details.thumbnail_url || kept.(:thumbnail_url),
      icon_url: details.icon_url || kept.(:icon_url)
    }
  end

  # The DB has a unique index on `name`, so concurrent requests racing past
  # `find_by` cannot both insert — the loser falls back to the winner's row.
  def upsert_instance(attrs)
    Instance.create!(attrs)
  rescue ActiveRecord::RecordNotUnique
    Instance.find_by!(name: attrs[:name])
  end

  def stale?(instance)
    ttl = instance[:instance_type] == "unknown" ? UNKNOWN_FRESH_FOR : FRESH_FOR
    instance[:updated_at] < ttl.ago
  end

  # Rows written before the source column existed came from fediverse.observer.
  def stored_source(instance)
    instance[:source].presence || "fediverse.observer"
  end
end
