# frozen_string_literal: true

class PatreonStatsController < ::ApplicationController
  requires_plugin 'discourse-patreon-donations'

  def show
    unless SiteSetting.patreon_donations_enabled
      return render_json_error(I18n.t('patreon_stats.error.not_configured'), status: 503)
    end

    stats = fetch_cached_stats
    monthly_history = fetch_monthly_history

    if stats
      render json: { 
        stats: stats,
        monthly_history: monthly_history
      }
    else
      render_json_error(I18n.t('patreon_stats.error.fetch_failed'), status: 503)
    end
  end

  private

  def fetch_cached_stats
    Rails.cache.fetch(cache_key, expires_in: cache_duration) do
      calculate_fresh_stats
    end
  rescue StandardError => e
    Rails.logger.error("Error fetching Patreon stats: #{e.message}")
    nil
  end

  def fetch_monthly_history
    return [] unless SiteSetting.patreon_donations_campaign_id.present?

    DiscoursePatreonDonations::PatreonMonthlyStat
      .last_12_months(SiteSetting.patreon_donations_campaign_id)
      .map(&:to_h)
  rescue StandardError => e
    Rails.logger.error("Error fetching monthly history: #{e.message}")
    []
  end

  def calculate_fresh_stats
    client = DiscoursePatreonDonations::PatreonApiClient.new
    campaign_data = client.fetch_campaign_data
    members = client.fetch_members

    Rails.logger.info("Patreon API - Campaign data present: #{campaign_data.present?}")
    Rails.logger.info("Patreon API - Members count: #{members&.length || 0}")
    
    if campaign_data.nil?
      Rails.logger.error("Patreon API - Failed to fetch campaign data. Check access token and campaign ID.")
      return nil
    end
    
    if members.nil? || members.empty?
      Rails.logger.error("Patreon API - Failed to fetch members. Check API permissions (need 'campaigns.members' scope).")
      return nil
    end

    calculator = DiscoursePatreonDonations::PatreonStatsCalculator.new(campaign_data, members)

    {
      patron_count: calculator.patron_count,
      monthly_estimate: calculator.monthly_estimate,
      last_month_total: calculator.last_month_total,
      updated_at: Time.now.utc
    }
  rescue StandardError => e
    Rails.logger.error("Patreon API - Error calculating stats: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    nil
  end

  def cache_key
    "patreon_stats:#{SiteSetting.patreon_donations_campaign_id}"
  end

  def cache_duration
    SiteSetting.patreon_donations_cache_duration.minutes
  end
end
