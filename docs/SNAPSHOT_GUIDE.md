# Monthly Snapshots

Since Patreon's API doesn't provide historical payment data, the plugin creates monthly snapshots of current patron data. These snapshots enable month-over-month comparison to track donation growth or decline.

## How It Works

The background sync job writes a snapshot for the current month on its first run of each new calendar month. Once written, that snapshot is not overwritten again during the same month. Historical data accumulates naturally as each month passes.

The "Change from Last Month" metric is calculated by comparing the current live estimate against the most recent snapshot, regardless of which month that snapshot belongs to. The `N/A` indicator appears only when no snapshot data exists at all.

## Usage

All rake tasks must be run inside the Discourse Docker container. Enter the container first:

```bash
cd /var/discourse
./launcher enter app
```

### Create a Manual Snapshot

Force a snapshot for the current month. Unlike the auto-sync, this always writes and will overwrite any existing snapshot for this month:

```bash
rake patreon_donations:snapshot
```

Useful after initial setup or to capture current data immediately without waiting for the next scheduled sync.

### View Historical Data

```bash
rake patreon_donations:status
```

### Clear All Historical Data

Removes all snapshots and clears the cache. Use before recreating correct data:

```bash
rake patreon_donations:clear
```

### Via Rails Console

```ruby
# Force-create or overwrite the current month snapshot
result = DiscoursePatreonDonations::PatreonMonthlyStat.snapshot_current_month
puts result.inspect

# View all records
campaign_id = SiteSetting.patreon_donations_campaign_id
DiscoursePatreonDonations::PatreonMonthlyStat
  .where(campaign_id: campaign_id)
  .order(year: :desc, month: :desc)
  .each { |r| puts "#{r.year}-#{r.month}: #{r.patron_count} patrons, #{r.total_amount}" }

# Delete a bad snapshot so the next sync recreates it
DiscoursePatreonDonations::PatreonMonthlyStat
  .where(campaign_id: campaign_id, year: 2026, month: 3)
  .delete_all
```

## Important Notes

- **Data Accumulation**: Historical data builds up month-by-month as the auto-sync job runs.
- **Retention**: Keeps the most recent 12 months; older records are deleted automatically.
- **Auto-Sync**: The background job writes a snapshot once per month (on the first sync of a new month) and does not overwrite it again within the same month.
- **Manual Snapshots**: The rake task and `snapshot_current_month` method always write, overwriting any existing snapshot for the current month. This is intentional for manual intervention.

## Month-Over-Month Change Tracking

The plugin displays a "Change from Last Month" metric that compares:
- **Current live estimate** (from cached Patreon API data)
- **Most recent snapshot** (the latest entry in the historical data table, regardless of which month it is from)

**Display Format**:
- Positive growth: `+£23.80` (shown in green)
- Negative decline: `-£15.30` (shown in red)
- No snapshot data at all: `N/A` (shown in gray)

**Important**: The `N/A` indicator appears only when no snapshot data exists at all. Once the first snapshot is recorded — either by the auto-sync job or the rake task — the metric will show the difference between the current live estimate and that snapshot.
