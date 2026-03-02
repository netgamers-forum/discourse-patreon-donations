# frozen_string_literal: true

# name: discourse-patreon-donations
# about: Display Patreon campaign statistics including active subscribers and donation amounts
# version: 0.1.0
# authors: NetGamers
# url: https://github.com/netgamers/discourse-patreon-donations

enabled_site_setting :patreon_donations_enabled

register_asset 'stylesheets/patreon-stats.scss'

after_initialize do
  module ::DiscoursePatreonDonations
    PLUGIN_NAME = 'discourse-patreon-donations'
  end

  require_relative 'app/models/patreon_cache'
  require_relative 'app/models/patreon_monthly_stat'
  require_relative 'app/services/patreon_api_client'
  require_relative 'app/services/patreon_stats_calculator'
  require_relative 'app/services/patreon_campaign_discovery'
  require_relative 'app/controllers/patreon_stats_controller'
  require_relative 'app/jobs/sync_patreon_data'

  Discourse::Application.routes.append do
    get '/patreon-stats' => 'patreon_stats#index'
    get '/patreon-stats.json' => 'patreon_stats#show'
  end

  DiscourseEvent.on(:site_setting_changed) do |name, old_value, new_value|
    if name == :patreon_donations_campaign_url && new_value.present?
      DiscoursePatreonDonations::PatreonCampaignDiscovery.discover_and_save
    end
  end
end
