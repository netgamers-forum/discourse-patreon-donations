# Monthly Snapshots

Since Patreon's API doesn't provide historical payment data, the plugin creates monthly snapshots of current patron data.

## Usage

### Manual Snapshot (One-time Setup)

When first setting up the plugin, create a snapshot for the current month:

```bash
cd /var/www/discourse
rake patreon_donations:snapshot
```

### View Historical Data

```bash
rake patreon_donations:status
```

### Via Rails Console

```bash
cd /var/www/discourse
rails console

# Create current month snapshot
result = DiscoursePatreonDonations::PatreonMonthlyStat.snapshot_current_month
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
2. Creates/updates a snapshot for the current month only
3. Does NOT create fake historical data for past months
4. Historical data accumulates naturally as months pass

## Important Notes

- **No Historical Backfill**: The plugin only creates snapshots for the current month
- **Data Accumulation**: Historical data builds up month-by-month as the sync job runs
- **Retention**: Keeps most recent 12 months (older records are auto-deleted)
- **Automatic Sync**: The background job runs hourly and updates the current month snapshot
- **First Month**: After initial setup, only the current month will show data; previous months will be empty until time passes
