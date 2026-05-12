class AddObserverFieldsToInstances < ActiveRecord::Migration[8.0]
  def change
    add_column :instances, :total_users, :integer
    add_column :instances, :status, :integer
  end
end
