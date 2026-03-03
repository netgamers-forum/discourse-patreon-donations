# frozen_string_literal: true

module DiscoursePatreonDonations
  class PatreonCampaignDiscovery
    def self.discover_and_save
      return false unless SiteSetting.patreon_creator_access_token.present?
      return false unless SiteSetting.patreon_donations_campaign_url.present?

      client = PatreonApiClient.new
      campaign_id = client.discover_campaign_id(SiteSetting.patreon_donations_campaign_url)

      if campaign_id.present?
        SiteSetting.patreon_donations_campaign_id = campaign_id
        Rails.logger.info("Patreon campaign ID auto-discovered and saved: #{campaign_id}")
        true
      else
        Rails.logger.error("Failed to auto-discover Patreon campaign ID from URL: #{SiteSetting.patreon_donations_campaign_url}")
        false
      end
    rescue StandardError => e
      Rails.logger.error("Error discovering Patreon campaign ID: #{e.message}")
      false
    end
  end
end
