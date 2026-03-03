# frozen_string_literal: true

class AddFeesToPatreonMonthlyStats < ActiveRecord::Migration[7.0]
  def change
    add_column :patreon_monthly_stats, :platform_fee_percentage, :float
    add_column :patreon_monthly_stats, :tax_rate_percentage, :float
  end
end
