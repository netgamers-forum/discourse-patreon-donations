# frozen_string_literal: true

class PatreonStatsController < ::ApplicationController
  requires_plugin 'discourse-patreon-donations'
  before_action :ensure_logged_in
  before_action :ensure_authorized

  def show
    Rails.logger.info("PatreonStatsController#show - Plugin enabled: #{SiteSetting.patreon_donations_enabled}")
    Rails.logger.info("PatreonStatsController#show - API version: #{SiteSetting.patreon_donations_api_version}")
    Rails.logger.info("PatreonStatsController#show - Campaign ID: #{SiteSetting.patreon_donations_campaign_id}")
    
    unless SiteSetting.patreon_donations_enabled
      return render_json_error(I18n.t('patreon_stats.error.not_configured'), status: 503)
    end

    stats = fetch_cached_stats
    monthly_history = fetch_monthly_history

    Rails.logger.info("PatreonStatsController#show - Stats present: #{stats.present?}")
    Rails.logger.info("PatreonStatsController#show - Stats: #{stats.inspect}")
    
    if stats
      monthly_change = calculate_monthly_change(stats[:monthly_estimate], monthly_history)
      
      render json: { 
        stats: stats.merge(monthly_change: monthly_change),
        monthly_history: monthly_history
      }
    else
      render_json_error(I18n.t('patreon_stats.error.fetch_failed'), status: 503)
    end
  end

  private

  def ensure_authorized
    allowed_group_names = SiteSetting.patreon_donations_allowed_groups.split('|')
    user_groups = current_user.groups.pluck(:name)

    unless current_user.admin? || (allowed_group_names & user_groups).any?
      raise Discourse::InvalidAccess.new(
        I18n.t('patreon_stats.error.not_authorized'),
        nil,
        custom_message: 'patreon_stats.error.not_authorized'
      )
    end
  end

  def fetch_cached_stats
    cached = Rails.cache.read(cache_key)
    return cached if cached.present?

    stats = calculate_fresh_stats
    Rails.cache.write(cache_key, stats, expires_in: cache_duration) if stats.present?
    stats
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

  def calculate_monthly_change(current_estimate, monthly_history)
    return nil if monthly_history.empty?

    # Use the most recent snapshot as the baseline regardless of which month it belongs to.
    # N/A is only appropriate when there is no historical data at all.
    last_snapshot = monthly_history.last
    return nil unless last_snapshot

    change = current_estimate - last_snapshot[:total_amount]
    Rails.logger.info("Monthly change: #{current_estimate} (current) - #{last_snapshot[:total_amount]} (#{last_snapshot[:year]}-#{last_snapshot[:month]} snapshot) = #{change}")
    change
  rescue StandardError => e
    Rails.logger.error("Error calculating monthly change: #{e.message}")
    nil
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
      currency: calculator.currency,
      updated_at: Time.now.utc
    }
  rescue StandardError => e
    Rails.logger.error("Patreon API - Error calculating stats: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    nil
  end

  def cache_key
    campaign_id = SiteSetting.patreon_donations_campaign_id.presence || "default"
    "patreon_stats:#{campaign_id}"
  end

  def cache_duration
    SiteSetting.patreon_donations_cache_duration.hours
  end
end
