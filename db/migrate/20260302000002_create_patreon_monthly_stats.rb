# frozen_string_literal: true

class CreatePatreonMonthlyStats < ActiveRecord::Migration[7.0]
  def change
    create_table :patreon_monthly_stats do |t|
      t.string :campaign_id, null: false
      t.integer :year, null: false
      t.integer :month, null: false
      t.integer :patron_count, null: false, default: 0
      t.integer :total_amount_cents, null: false, default: 0
      t.timestamps
    end

    add_index :patreon_monthly_stats, [:campaign_id, :year, :month], unique: true, name: 'index_patreon_monthly_stats_unique'
    add_index :patreon_monthly_stats, :campaign_id
  end
end
