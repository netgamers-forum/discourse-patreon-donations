# Monthly Snapshots

Since Patreon's API doesn't provide historical payment data, the plugin creates monthly snapshots of current patron data. These snapshots enable month-over-month comparison to track donation growth or decline.

## Usage

### Manual Snapshot (One-time Setup)

When first setting up the plugin, create a snapshot for the current month:

```bash
cd /var/www/discourse
rake patreon_donations:snapshot
```

### Clear All Historical Data

If you need to remove all snapshots (useful when removing fake backfilled data):

```bash
rake patreon_donations:clear
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

## Month-Over-Month Change Tracking

The plugin displays a "Change from Last Month" metric that compares:
- **Current month's live estimate** (from real-time API data)
- **Last completed month's snapshot** (from historical data)

**Display Format**:
- Positive growth: `+$23.80` (shown in green)
- Negative decline: `-$15.30` (shown in red)
- No previous data: `N/A` (shown in gray)

**Important**: The change metric will show `N/A` until you have at least one completed month of snapshot data. For example:
- **March 2026 (first month)**: Shows `N/A` because there's no February snapshot to compare against
- **April 2026 onwards**: Shows actual month-over-month change comparing current estimate vs previous month's snapshot

This provides a true growth/decline indicator that accounts for patrons joining, leaving, upgrading, or downgrading their pledges.
