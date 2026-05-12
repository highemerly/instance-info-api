class AddUniqueIndexToInstancesName < ActiveRecord::Migration[8.0]
  def up
    # Collapse any pre-existing duplicates by name before adding the unique index.
    # Preference order: permanent rows first, then the most recently updated row.
    execute <<~SQL
      DELETE FROM instances
      WHERE id NOT IN (
        SELECT id FROM (
          SELECT id,
                 ROW_NUMBER() OVER (
                   PARTITION BY name
                   ORDER BY COALESCE(permanent, 0) DESC, updated_at DESC, id DESC
                 ) AS rn
          FROM instances
        )
        WHERE rn = 1
      )
    SQL

    add_index :instances, :name, unique: true
  end

  def down
    remove_index :instances, :name
  end
end
