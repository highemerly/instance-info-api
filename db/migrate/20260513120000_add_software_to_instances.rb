class AddSoftwareToInstances < ActiveRecord::Migration[8.0]
  def up
    add_column :instances, :software, :string

    # Wipe cached fediverse rows so they get re-fetched with normalized
    # instance_type and a populated software column. Builtin seeds are
    # preserved.
    execute "DELETE FROM instances WHERE permanent IS NOT 1"
  end

  def down
    remove_column :instances, :software
  end
end
