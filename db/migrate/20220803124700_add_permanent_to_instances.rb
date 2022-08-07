class AddPermanentToInstances < ActiveRecord::Migration[7.0]
  def change
    add_column :instances, :permanent, :boolean
  end
end
