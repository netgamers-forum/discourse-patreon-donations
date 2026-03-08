# frozen_string_literal: true

class AddDeclinedCountToPatreonMonthlyStats < ActiveRecord::Migration[7.0]
  def change
    add_column :patreon_monthly_stats, :declined_count, :integer
  end
end
