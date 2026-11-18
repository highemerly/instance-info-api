# Builtin services (twitter.com, ...) now come from config/builtin_services.yml
# and never touch the DB, so their rows and the column marking them go.
class MoveBuiltinServicesToConfig < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM instances WHERE permanent = 1"
    remove_column :instances, :permanent
  end

  def down
    add_column :instances, :permanent, :boolean
  end
end
