# frozen_string_literal: true

module DiscoursePatreonDonations
  class PatreonMonthlyStat < ActiveRecord::Base
    self.table_name = 'patreon_monthly_stats'

    validates :campaign_id, presence: true
    validates :year, presence: true
    validates :month, presence: true, inclusion: { in: 1..12 }
    validates :patron_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :total_amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }

    def self.record_monthly_snapshot(campaign_id, patron_count, total_amount_cents, date = Time.now.utc, platform_fee_percentage: nil, tax_rate_percentage: nil, active_member_ids: nil, declined_count: nil)
      year = date.year
      month = date.month

      stat = find_or_initialize_by(
        campaign_id: campaign_id,
        year: year,
        month: month
      )

      stat.patron_count = patron_count
      stat.total_amount_cents = total_amount_cents
      stat.platform_fee_percentage = platform_fee_percentage
      stat.tax_rate_percentage = tax_rate_percentage
      stat.active_member_ids = active_member_ids&.to_json
      stat.declined_count = declined_count
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

    def self.snapshot_current_month
      return { success: false, error: "Campaign ID not configured" } unless SiteSetting.patreon_donations_campaign_id.present?

      begin
        client = DiscoursePatreonDonations::PatreonApiClient.new
        campaign_data = client.fetch_campaign_data
        members = client.fetch_members

        return { success: false, error: "Failed to fetch current Patreon data" } unless campaign_data && members

        calculator = DiscoursePatreonDonations::PatreonStatsCalculator.new(campaign_data, members)
        current_patron_count = calculator.active_patron_count
        current_amount_cents = (calculator.monthly_estimate * 100).to_i

        campaign_id = SiteSetting.patreon_donations_campaign_id
        now = Time.now.utc
        year = now.year
        month = now.month

        # Create or update only the current month
        stat = record_monthly_snapshot(
          campaign_id,
          current_patron_count,
          current_amount_cents,
          now,
          platform_fee_percentage: SiteSetting.patreon_donations_platform_fee_percentage,
          tax_rate_percentage: SiteSetting.patreon_donations_tax_rate_percentage,
          active_member_ids: calculator.active_member_ids,
          declined_count: calculator.declined_patrons_count
        )

        Rails.logger.info("Created/updated current month snapshot for campaign #{campaign_id}: #{current_patron_count} patrons, $#{current_amount_cents / 100.0}")
        { success: true, message: "Snapshot created for #{year}-#{month}: #{current_patron_count} patrons, $#{current_amount_cents / 100.0}" }
      rescue StandardError => e
        Rails.logger.error("Snapshot failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def parsed_member_ids
      return nil unless active_member_ids.present?
      JSON.parse(active_member_ids)
    rescue JSON::ParserError
      nil
    end

    def total_amount
      total_amount_cents / 100.0
    end

    def net_amount
      return nil unless platform_fee_percentage && tax_rate_percentage

      after_platform = total_amount * (1 - platform_fee_percentage / 100.0)
      after_platform * (1 - tax_rate_percentage / 100.0)
    end

    def to_h
      {
        year: year,
        month: month,
        patron_count: patron_count,
        total_amount: total_amount,
        total_amount_cents: total_amount_cents,
        net_amount: net_amount,
        declined_count: declined_count,
        snapshot_taken_at: created_at&.iso8601
      }
    end
  end
end
