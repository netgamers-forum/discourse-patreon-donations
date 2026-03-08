# frozen_string_literal: true

class AddProcessingFeesToPatreonMonthlyStats < ActiveRecord::Migration[7.0]
  def change
    add_column :patreon_monthly_stats, :processing_fee_total_cents, :integer
  end
end
