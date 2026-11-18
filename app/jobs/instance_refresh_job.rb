# Refreshes a stale row after the request has already been answered with it
# (stale-while-revalidate, v2). Runs in-process on the :async adapter: a job
# lost to a restart is simply claimed again by the next request for the row.
class InstanceRefreshJob < ApplicationJob
  queue_as :default

  def perform(name)
    InstanceLookup.new.revalidate(name)
  end
end
