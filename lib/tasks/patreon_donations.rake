# frozen_string_literal: true

desc "Patreon Donations tasks"
namespace :patreon_donations do
  desc "Backfill historical data (up to 12 months) - force refreshes all data"
  task backfill: :environment do
    puts "Starting backfill of Patreon historical data (force refresh)..."
    
    # Clear cache before backfilling
    campaign_id = SiteSetting.patreon_donations_campaign_id
    if campaign_id.present?
      Rails.cache.delete("patreon_stats:#{campaign_id}")
      Rails.cache.delete('patreon_last_sync_time')
      puts "Cleared cache for campaign #{campaign_id}"
    end
    
    result = DiscoursePatreonDonations::PatreonMonthlyStat.backfill_historical_data(12, true)
    
    if result[:success]
      puts "✓ Success: #{result[:message]}"
      puts "  Created: #{result[:created]} record(s)"
      puts "  Updated: #{result[:updated]} record(s)"
    else
      puts "✗ Error: #{result[:error]}"
      exit 1
    end
  end

  desc "Show current historical data"
  task status: :environment do
    campaign_id = SiteSetting.patreon_donations_campaign_id
    
    if campaign_id.blank?
      puts "Campaign ID is not configured"
      exit 1
    end
    
    records = DiscoursePatreonDonations::PatreonMonthlyStat
      .where(campaign_id: campaign_id)
      .order(year: :desc, month: :desc)
    
    puts "Historical records for campaign #{campaign_id}:"
    puts "-" * 60
    
    if records.empty?
      puts "No historical data found"
    else
      records.each do |record|
        puts "#{record.year}-#{record.month.to_s.rjust(2, '0')}: #{record.patron_count} patrons, $#{record.total_amount}"
      end
      puts "-" * 60
      puts "Total: #{records.count} record(s)"
    end
  end
end
