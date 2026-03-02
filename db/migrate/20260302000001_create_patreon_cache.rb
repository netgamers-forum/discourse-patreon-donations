# frozen_string_literal: true

class CreatePatreonCache < ActiveRecord::Migration[7.0]
  def change
    create_table :patreon_cache do |t|
      t.string :campaign_id, null: false
      t.text :data, null: false
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :patreon_cache, :campaign_id, unique: true
  end
end
