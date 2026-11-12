# Seeds only run when the database is first created, so changes to the builtin
# list in db/seeds.rb have to reach existing databases through a migration.
class UpdateBuiltinAndFamilyRows < ActiveRecord::Migration[8.1]
  TUMBLR = ["www.tumblr.com", "tumblr.com", "tumblr"].freeze

  def up
    # Pocket shut down in July 2025.
    execute "DELETE FROM instances WHERE permanent = 1 AND instance_type = 'pocket'"

    TUMBLR.each do |name|
      execute <<~SQL
        INSERT INTO instances (name, instance_type, version, permanent, created_at, updated_at)
        VALUES (#{quote(name)}, 'tumblr', '', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT(name) DO UPDATE SET instance_type = 'tumblr', permanent = 1, updated_at = CURRENT_TIMESTAMP
      SQL
    end

    # Mbin / kbin used to be normalized to "lemmy"; cached rows would keep that
    # type until their TTL ran out.
    execute "UPDATE instances SET instance_type = 'mbin' WHERE lower(software) IN ('mbin', 'kbin')"
  end

  def down
    execute "UPDATE instances SET instance_type = 'lemmy' WHERE lower(software) IN ('mbin', 'kbin')"
    execute "DELETE FROM instances WHERE permanent = 1 AND instance_type = 'tumblr'"
  end
end
