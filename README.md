# Discourse Patreon Donations

A Discourse plugin that adds a read-only page at `/patreon-stats` displaying Patreon campaign statistics: active subscriber count, estimated monthly revenue with a net income breakdown, month-over-month change, and a 12-month historical table.

## Requirements

- A self-hosted Discourse instance deployed via [Docker](https://github.com/discourse/discourse/blob/main/docs/INSTALL-cloud.md)
- The [discourse-patreon](https://github.com/discourse/discourse-patreon) plugin installed and configured with valid OAuth credentials (Client ID, Client Secret, Creator Access Token, Refresh Token). This plugin reads those credentials directly and does not store its own copy.

## Installation

Add the plugin repository to your `app.yml` in the `hooks` section, alongside any other plugins:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/discourse/docker_manager.git
          - git clone https://github.com/discourse/discourse-patreon.git
          - git clone https://github.com/netgamers/discourse-patreon-donations.git
```

Then rebuild the container:

```bash
cd /var/discourse
./launcher rebuild app
```

## Configuration

After installation, navigate to **Admin > Settings > Plugins > Patreon Donations**.

| Setting | Description | Default |
|---------|-------------|---------|
| `patreon_donations_enabled` | Enables the plugin and the `/patreon-stats` route. | `false` |
| `patreon_donations_api_version` | Patreon API version. Use `v1` for legacy OAuth clients, `v2` for newer ones. | `v2` |
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

The three summary boxes show:
- Current active subscriber count from the Patreon campaign
- Estimated revenue for the current month, derived from the campaign's total pledge sum
- Difference between the current estimate and the most recent monthly snapshot (see below); shown as N/A only if no snapshots exist yet

**Monthly history**

During the first sync that runs in a new calendar month, the job records a snapshot of the patron count and total pledge amount for that month. Once written, the snapshot is not updated again within the same month. This gives a stable baseline for the month-over-month change calculation and populates the 12-month history table.

**Token refresh**

If the Patreon API returns a 401, the plugin attempts to refresh the access token automatically using the refresh token, client ID, and client secret stored in the core Patreon plugin settings. If the refresh token is also expired, new credentials must be generated from the Patreon developer portal and entered into the core plugin settings manually.

## License

MIT
