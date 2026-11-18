# What nodeinfo and each software's instance API tell us beyond the type and
# version. Stored now so the v2 response can serve them from cache.
class AddDetailsToInstances < ActiveRecord::Migration[8.1]
  def change
    change_table :instances, bulk: true do |t|
      t.string :node_name
      t.boolean :open_registrations
      t.integer :active_month
      t.integer :active_halfyear
      t.integer :local_posts
      t.integer :max_characters
      t.string :thumbnail_url
      t.string :icon_url
    end
  end
end
