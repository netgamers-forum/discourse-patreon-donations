# Backfill Historical Data

Since Patreon's API doesn't provide historical payment data, you can backfill up to 12 months of historical snapshots using current patron data.

## Usage

### Via Rake Task (Recommended)

From the Discourse app container:

```bash
cd /var/www/discourse
rake patreon_donations:backfill
```

To view current historical data:

```bash
rake patreon_donations:status
```

### Via Rails Console

```bash
cd /var/www/discourse
rails console

# Backfill 12 months
result = DiscoursePatreonDonations::PatreonMonthlyStat.backfill_historical_data(12)
puts result.inspect

# View records
campaign_id = SiteSetting.patreon_donations_campaign_id
DiscoursePatreonDonations::PatreonMonthlyStat
  .where(campaign_id: campaign_id)
  .order(year: :desc, month: :desc)
  .each { |r| puts "#{r.year}-#{r.month}: #{r.patron_count} patrons, $#{r.total_amount}" }
```

## How It Works

1. Fetches current Patreon campaign data
2. Creates historical records for past N months using current patron count
3. Skips months that already have data
4. Returns count of created records

## Important Notes

- **Data Limitation**: Backfilled data uses current patron counts for all past months
- **Retention**: Only keeps most recent 12 months (older records are auto-deleted)
- **One-time Use**: Primarily useful when first setting up the plugin
- **Going Forward**: The sync job runs hourly and creates real monthly snapshots
