class AddSourceToInstances < ActiveRecord::Migration[8.0]
  def change
    add_column :instances, :source, :string
    reversible do |dir|
      dir.up do
        execute "UPDATE instances SET source = 'fediverse.observer' WHERE permanent IS NOT 1 AND instance_type != 'unknown'"
        execute "UPDATE instances SET source = 'error:no-data' WHERE permanent IS NOT 1 AND instance_type = 'unknown'"
      end
    end
  end
end
