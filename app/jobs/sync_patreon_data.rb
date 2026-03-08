# frozen_string_literal: true

module ::Jobs
  class SyncPatreonData < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      return unless SiteSetting.patreon_donations_enabled
      return unless should_sync?

      sync_patreon_data
    rescue StandardError => e
      Rails.logger.error("Patreon sync job failed: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end

    private

    def should_sync?
      sync_frequency = SiteSetting.patreon_donations_sync_frequency.hours
      last_sync = last_sync_time

      return true if last_sync.nil?
      
      last_sync < sync_frequency.ago
    end

    def sync_patreon_data
      client = DiscoursePatreonDonations::PatreonApiClient.new
      campaign_data = client.fetch_campaign_data
      members = client.fetch_members

      return unless campaign_data && members

      calculator = DiscoursePatreonDonations::PatreonStatsCalculator.new(campaign_data, members)

      stats = {
        patron_count: calculator.patron_count,
        active_patron_count: calculator.active_patron_count,
        free_member_count: calculator.free_member_count,
        total_member_count: calculator.total_member_count,
        monthly_estimate: calculator.monthly_estimate,
        tier_breakdown: calculator.tier_breakdown(tier_titles: client.tier_titles),
        last_month_total: calculator.last_month_total,
        currency: calculator.currency,
        active_member_ids: calculator.active_member_ids,
        recently_declined_count: calculator.recently_declined_count,
        recently_declined_amount: calculator.recently_declined_amount,
        updated_at: Time.now.utc
      }

      cache_stats(stats)
      record_monthly_snapshot(stats)
      update_sync_time
    end

    def cache_stats(stats)
      Rails.cache.write(
        "patreon_stats:#{SiteSetting.patreon_donations_campaign_id}",
        stats,
        expires_in: SiteSetting.patreon_donations_cache_duration.minutes
      )
    end

    def record_monthly_snapshot(stats)
      campaign_id = SiteSetting.patreon_donations_campaign_id
      return unless campaign_id.present?

      now = Time.now.utc
      existing = DiscoursePatreonDonations::PatreonMonthlyStat
        .where(campaign_id: campaign_id, year: now.year, month: now.month)
        .first

      return if existing

      total_amount_cents = (stats[:monthly_estimate] * 100).to_i

      DiscoursePatreonDonations::PatreonMonthlyStat.record_monthly_snapshot(
        campaign_id,
        stats[:active_patron_count],
        total_amount_cents,
        now,
        platform_fee_percentage: SiteSetting.patreon_donations_platform_fee_percentage,
        tax_rate_percentage: SiteSetting.patreon_donations_tax_rate_percentage,
        active_member_ids: stats[:active_member_ids],
        declined_count: stats[:recently_declined_count]
      )

      Rails.logger.info("Recorded monthly snapshot for campaign #{campaign_id}: #{stats[:active_patron_count]} patrons, #{stats[:monthly_estimate]}")
    end

    def last_sync_time
      Rails.cache.read('patreon_last_sync_time')
    end

    def update_sync_time
      Rails.cache.write('patreon_last_sync_time', Time.now.utc)
    end
  end
end
