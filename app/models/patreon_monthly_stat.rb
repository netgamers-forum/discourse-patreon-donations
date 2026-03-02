# frozen_string_literal: true

module DiscoursePatreonDonations
  class PatreonMonthlyStat < ActiveRecord::Base
    self.table_name = 'patreon_monthly_stats'

    validates :campaign_id, presence: true
    validates :year, presence: true
    validates :month, presence: true, inclusion: { in: 1..12 }
    validates :patron_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :total_amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }

    def self.record_monthly_snapshot(campaign_id, patron_count, total_amount_cents, date = Time.now.utc)
      year = date.year
      month = date.month

      stat = find_or_initialize_by(
        campaign_id: campaign_id,
        year: year,
        month: month
      )

      stat.patron_count = patron_count
      stat.total_amount_cents = total_amount_cents
      stat.save!

      cleanup_old_records(campaign_id)
      stat
    end

    def self.last_12_months(campaign_id)
      where(campaign_id: campaign_id)
        .order(year: :desc, month: :desc)
        .limit(12)
        .reverse
    end

    def self.cleanup_old_records(campaign_id, keep_months = 12)
      records = where(campaign_id: campaign_id)
                  .order(year: :desc, month: :desc)
                  .offset(keep_months)
      
      records.delete_all if records.any?
    end

    def total_amount
      total_amount_cents / 100.0
    end

    def to_h
      {
        year: year,
        month: month,
        patron_count: patron_count,
        total_amount: total_amount,
        total_amount_cents: total_amount_cents
      }
    end
  end
end
