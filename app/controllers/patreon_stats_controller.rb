# frozen_string_literal: true

class PatreonStatsController < ::ApplicationController
  requires_plugin 'discourse-patreon-donations'

  def index
    # Render the patreon stats page
  end

  def show
    unless SiteSetting.patreon_enabled
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
    return [] unless SiteSetting.patreon_campaign_id.present?

    DiscoursePatreonDonations::PatreonMonthlyStat
      .last_12_months(SiteSetting.patreon_campaign_id)
      .map(&:to_h)
  rescue StandardError => e
    Rails.logger.error("Error fetching monthly history: #{e.message}")
    []
  end

  def calculate_fresh_stats
    client = DiscoursePatreonDonations::PatreonApiClient.new
    campaign_data = client.fetch_campaign_data
    members = client.fetch_members

    return nil unless campaign_data && members

    calculator = DiscoursePatreonDonations::PatreonStatsCalculator.new(campaign_data, members)

    {
      patron_count: calculator.patron_count,
      monthly_estimate: calculator.monthly_estimate,
      last_month_total: calculator.last_month_total,
      updated_at: Time.now.utc
    }
  end

  def cache_key
    "patreon_stats:#{SiteSetting.patreon_campaign_id}"
  end

  def cache_duration
    SiteSetting.patreon_cache_duration.minutes
  end
end
