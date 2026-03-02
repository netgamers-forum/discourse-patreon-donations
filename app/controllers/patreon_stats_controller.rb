# frozen_string_literal: true

module DiscoursePatreonDonations
  class PatreonStatsController < ::ApplicationController
    requires_plugin DiscoursePatreonDonations::PLUGIN_NAME

    def index
      render 'default/empty'
    end

    def show
      unless SiteSetting.patreon_enabled
        return render_json_error(I18n.t('patreon_stats.error.not_configured'), status: 503)
      end

      stats = fetch_cached_stats

      if stats
        render json: { stats: stats }
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

    def calculate_fresh_stats
      client = PatreonApiClient.new
      campaign_data = client.fetch_campaign_data
      members = client.fetch_members

      return nil unless campaign_data && members

      calculator = PatreonStatsCalculator.new(campaign_data, members)

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
end
