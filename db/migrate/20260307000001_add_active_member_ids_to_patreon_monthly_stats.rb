# frozen_string_literal: true

class AddActiveMemberIdsToPatreonMonthlyStats < ActiveRecord::Migration[7.0]
  def change
    add_column :patreon_monthly_stats, :active_member_ids, :text
  end
end
