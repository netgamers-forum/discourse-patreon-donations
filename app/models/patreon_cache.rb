# frozen_string_literal: true

module DiscoursePatreonDonations
  class PatreonCache < ActiveRecord::Base
    self.table_name = 'patreon_cache'

    validates :campaign_id, presence: true, uniqueness: true
    validates :data, presence: true

    def self.fetch_or_update(campaign_id)
      cache_record = find_or_initialize_by(campaign_id: campaign_id)
      
      if cache_record.expired?
        cache_record.refresh
      end

      cache_record.parsed_data
    end

    def expired?
      return true if last_synced_at.nil?
      
      cache_duration = SiteSetting.patreon_cache_duration.minutes
      last_synced_at < cache_duration.ago
    end

    def refresh
      client = PatreonApiClient.new
      campaign_data = client.fetch_campaign_data
      members = client.fetch_members

      return false unless campaign_data && members

      calculator = PatreonStatsCalculator.new(campaign_data, members)

      self.data = {
        patron_count: calculator.patron_count,
        monthly_estimate: calculator.monthly_estimate,
        last_month_total: calculator.last_month_total
      }.to_json

      self.last_synced_at = Time.now.utc
      save
    end

    def parsed_data
      JSON.parse(data).symbolize_keys
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse Patreon cache data: #{e.message}")
      {}
    end
  end
end
