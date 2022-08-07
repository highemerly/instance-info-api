class CreateInstances < ActiveRecord::Migration[7.0]
  def change
    create_table :instances do |t|
      t.string :name
      t.string :instance_type
      t.string :version

      t.timestamps
    end
  end
end
