# Discourse Patreon Donations

A Discourse plugin that adds a read-only page at `/patreon-stats` displaying Patreon campaign statistics: active patron count, estimated monthly revenue with a net income breakdown, patron changes, and a 12-month historical table.

## Requirements

- A self-hosted Discourse instance deployed via [Docker](https://github.com/discourse/discourse/blob/main/docs/INSTALL-cloud.md)
- A Patreon API v2 client with Creator Access Token (register at https://www.patreon.com/portal/registration/register-clients)

## Installation

Add the plugin repository to your `app.yml` in the `hooks` section, alongside any other plugins:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/discourse/docker_manager.git
          - git clone https://github.com/netgamers-forum/discourse-patreon-donations.git
```

Then rebuild the container:

```bash
cd /var/discourse
./launcher rebuild app
```

## Configuration

After installation, navigate to **Admin > Settings > Plugins > Patreon Donations**.

### API Credentials

| Setting | Description |
|---------|-------------|
| `patreon_donations_creator_access_token` | Creator Access Token from your Patreon API v2 client |
| `patreon_donations_creator_refresh_token` | Creator Refresh Token for automatic token renewal |
| `patreon_donations_client_id` | Patreon API Client ID |
| `patreon_donations_client_secret` | Patreon API Client Secret |

These are stored separately from any other Patreon plugin (e.g. discourse-patreon), so each plugin can use its own API client.

### Plugin Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `patreon_donations_enabled` | Enables the plugin and the `/patreon-stats` route. | `false` |
| `patreon_donations_campaign_url` | Your Patreon campaign URL (e.g. `patreon.com/yourcampaign`). Used to auto-discover the campaign ID. | empty |
| `patreon_donations_platform_fee_percentage` | Patreon's platform fee, used in the revenue breakdown on the stats page. | `10.0` |
| `patreon_donations_tax_rate_percentage` | Tax rate applied to net revenue (after platform fees) in the revenue breakdown. | `43.0` |
| `patreon_donations_allowed_groups` | Discourse groups whose members can view the stats page. Admins always have access. | `admins` |
| `patreon_donations_cache_duration` | How long API responses are cached, in hours. | `6` |
| `patreon_donations_sync_frequency` | How often the background job syncs data from Patreon, in hours. | `24` |

The campaign ID is stored internally in a hidden setting (`patreon_donations_campaign_id`) and is resolved automatically from the campaign URL. If auto-discovery fails, you can set it manually via the Rails console.

## How it works

**Live stats**

A Sidekiq background job syncs data from the Patreon API at the interval set by `patreon_donations_sync_frequency`. The result is cached in Redis for `patreon_donations_cache_duration` hours. When a user visits `/patreon-stats`, the controller serves the cached data; if the cache has expired it fetches fresh data from Patreon on demand.

The summary boxes show:
- Current active patron count (paying patrons only)
- Patron changes since the last snapshot (joined/left)
- Estimated revenue for the current month, derived from the sum of active patron pledges
- Difference between the current live estimate and the last snapshot amount

A patrons breakdown section shows how many patrons are on each tier. A revenue breakdown section shows the estimated net income after platform fees and taxes.

**Monthly snapshots**

During the first sync of each calendar month, the job records a snapshot of the patron count, total pledge amount, and active member IDs. Once written, the snapshot is immutable for that month. This provides a fixed baseline: the "Patron Changes" and "Change from Last Month" cards compare the current live data against this snapshot. For example, if the snapshot was taken on March 1st with $237.56 and 100 patrons, and a patron upgrades their tier on March 15th, the summary will show the difference in amount and any patron joins/leaves since that March 1st snapshot.

**Monthly history**

The 12-month history table is populated from these monthly snapshots. Patron changes between months (joined/left) are computed by comparing member IDs between consecutive snapshots.

**Token refresh**

If the Patreon API returns a 401, the plugin attempts to refresh the access token automatically using the refresh token, client ID, and client secret from the plugin's own settings. If the refresh token is also expired, new credentials must be generated from the Patreon developer portal and entered into the plugin settings manually.

## License

MIT
