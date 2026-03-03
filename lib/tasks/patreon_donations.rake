# frozen_string_literal: true

desc "Patreon Donations tasks"
namespace :patreon_donations do
  desc "Create snapshot of current month patron data"
  task snapshot: :environment do
    puts "Creating snapshot of current month..."
    
    # Clear cache before snapshot
    campaign_id = SiteSetting.patreon_donations_campaign_id
    if campaign_id.present?
      Rails.cache.delete("patreon_stats:#{campaign_id}")
      Rails.cache.delete('patreon_last_sync_time')
      puts "Cleared cache for campaign #{campaign_id}"
    end
    
    result = DiscoursePatreonDonations::PatreonMonthlyStat.snapshot_current_month
    
    if result[:success]
      puts "✓ Success: #{result[:message]}"
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
      puts "Run 'rake patreon_donations:snapshot' to create the current month"
    else
      records.each do |record|
        puts "#{record.year}-#{record.month.to_s.rjust(2, '0')}: #{record.patron_count} patrons, $#{record.total_amount}"
      end
      puts "-" * 60
      puts "Total: #{records.count} record(s)"
    end
  end

  desc "Clear all historical data (use before first snapshot)"
  task clear: :environment do
    campaign_id = SiteSetting.patreon_donations_campaign_id
    
    if campaign_id.blank?
      puts "Campaign ID is not configured"
      exit 1
    end
    
    count = DiscoursePatreonDonations::PatreonMonthlyStat
      .where(campaign_id: campaign_id)
      .delete_all
    
    Rails.cache.delete("patreon_stats:#{campaign_id}")
    Rails.cache.delete('patreon_last_sync_time')
    
    puts "✓ Deleted #{count} historical record(s) and cleared cache"
  end
end
