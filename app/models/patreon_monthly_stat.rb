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

    def self.backfill_historical_data(months_back = 12)
      return { success: false, error: "Campaign ID not configured" } unless SiteSetting.patreon_donations_campaign_id.present?

      begin
        client = DiscoursePatreonDonations::PatreonApiClient.new
        campaign_data = client.fetch_campaign_data
        members = client.fetch_members

        return { success: false, error: "Failed to fetch current Patreon data" } unless campaign_data && members

        calculator = DiscoursePatreonDonations::PatreonStatsCalculator.new(campaign_data, members)
        current_patron_count = calculator.patron_count
        current_amount_cents = (calculator.monthly_estimate * 100).to_i

        campaign_id = SiteSetting.patreon_donations_campaign_id
        now = Time.now.utc
        created_count = 0

        months_back.times do |i|
          date = now - i.months
          year = date.year
          month = date.month

          existing = find_by(campaign_id: campaign_id, year: year, month: month)
          next if existing

          create!(
            campaign_id: campaign_id,
            year: year,
            month: month,
            patron_count: current_patron_count,
            total_amount_cents: current_amount_cents
          )
          created_count += 1
        end

        Rails.logger.info("Backfilled #{created_count} months of historical data for campaign #{campaign_id}")
        { success: true, created: created_count, message: "Backfilled #{created_count} month(s)" }
      rescue StandardError => e
        Rails.logger.error("Backfill failed: #{e.message}")
        { success: false, error: e.message }
      end
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
