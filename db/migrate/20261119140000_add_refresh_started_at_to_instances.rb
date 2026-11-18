# When a background refresh was last claimed for the row, so concurrent
# requests for a stale row enqueue it once, and a failed refresh isn't retried
# on every request.
class AddRefreshStartedAtToInstances < ActiveRecord::Migration[8.1]
  def change
    add_column :instances, :refresh_started_at, :datetime
  end
end
