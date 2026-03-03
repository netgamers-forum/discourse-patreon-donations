# Discourse Patreon Donations Plugin

A Discourse plugin that displays Patreon campaign statistics on a dedicated page, allowing your community to see real-time support metrics.

## Project Scope

This plugin adds a new read-only page to your Discourse forum (similar to the "About" or "FAQ" pages) that displays:

1. **Number of Active Subscribers** - Total count of current Patreon patrons
2. **Estimated Monthly Revenue** - Projected monthly income from all active pledges
3. **Last Month Total Donations** - Actual donations received in the previous calendar month
4. **12-Month Historical Data** - Monthly breakdown of patron count and total donations for trend analysis and charting

The page is **non-interactive** and serves purely as an informational dashboard to showcase community support and transparency around funding.

## Features

- **Real-time Statistics**: Syncs with Patreon API daily
- **Historical Tracking**: Automatically stores last 12 months of donation data
- **Monthly Snapshots**: Records patron count and total amounts each month
- **Discourse Native UI**: Matches your forum's theme and styling
- **Secure**: OAuth 2.0 authentication with encrypted credential storage
- **Performant**: Implements caching to minimize API calls
- **Responsive**: Mobile-friendly display with sortable history table
- **Automatic Updates**: Background job refreshes data daily

## Use Cases

- **Transparency**: Show your community how much support the forum receives
- **Motivation**: Encourage more users to become Patreon supporters
- **Accountability**: Demonstrate financial sustainability to your community
- **Recognition**: Highlight the impact of patron contributions

## Architecture

### Plugin Structure
```
discourse-patreon-donations/
├── plugin.rb                 # Main plugin definition
├── config/
│   ├── locales/
│   │   └── en.yml           # Translations
│   └── settings.yml         # Admin settings
├── app/
│   ├── controllers/
│   │   └── patreon_stats_controller.rb
│   ├── models/
│   │   └── patreon_cache.rb
│   └── jobs/
│       └── sync_patreon_data.rb
├── assets/
│   └── javascripts/
│       └── discourse/
│           ├── routes/
│           │   └── patreon-stats.js
│           ├── controllers/
│           │   └── patreon-stats.js
│           └── templates/
│               └── patreon-stats.hbs
└── README.md
```

### Data Flow

1. **Admin Configuration**: Site admin enters Patreon OAuth credentials in plugin settings
2. **Background Sync**: Scheduled job runs daily (configurable) to fetch data from Patreon API
3. **Caching**: Data is stored in Discourse database to minimize API calls
4. **Display**: Users navigate to `/patreon-stats` to view cached statistics
5. **Refresh**: Manual refresh option available for admins

## Technical Details

### Patreon API Integration

- **API Version**: v2 (v1 is deprecated)
- **Authentication**: OAuth 2.0
- **Required Scopes**: 
  - `campaigns` - Access campaign information
  - `campaigns.members` - Access member/patron data
- **Rate Limits**: 
  - 100 requests per 2 seconds (client level)
  - 100 requests per minute (token level)

See [PATREON_API_REFERENCE.md](./PATREON_API_REFERENCE.md) for detailed API documentation.

### Key Endpoints Used

1. `GET /api/oauth2/v2/campaigns` - Fetch patron count
2. `GET /api/oauth2/v2/campaigns/{id}/members` - Fetch member details and pledge amounts

### Calculation Logic

**Monthly Estimate**:
```
Sum of all currently_entitled_amount_cents 
  WHERE patron_status = 'active_patron'
  Divided by 100 (convert cents to dollars)
```

**Last Month Total**:
```
Sum of all currently_entitled_amount_cents
  WHERE last_charge_status = 'Paid'
  AND last_charge_date is within previous calendar month
  Divided by 100 (convert cents to dollars)
```

## Installation

### Prerequisites

- Discourse instance (self-hosted or managed)
- Patreon Creator account
- **[discourse-patreon](https://github.com/discourse/discourse-patreon) plugin installed and configured** with valid OAuth credentials (Client ID, Client Secret, Creator Access Token, Refresh Token). This plugin reads credentials from the core Patreon plugin -- it does not store its own copy.

### Steps

1. **Ensure the core Patreon plugin is configured**
   - Navigate to Admin → Settings → Plugins → Patreon
   - Verify that Client ID, Client Secret, Creator Access Token, and Refresh Token are filled in and working
   - If not already set up, follow the [core Patreon plugin instructions](https://github.com/discourse/discourse-patreon)

2. **Install Plugin**
   ```bash
   cd /var/discourse
   git clone https://github.com/yourusername/discourse-patreon-donations.git plugins/discourse-patreon-donations
   ./launcher rebuild app
   ```

3. **Configure Plugin**
   - Navigate to Admin → Settings → Plugins → Patreon Donations
   - Enable the plugin
   - Enter your Campaign URL (Campaign ID will be auto-discovered)
   - Adjust platform fee %, tax rate %, and allowed groups as needed
   - Set cache duration and sync frequency
   - Save settings

4. **Verify Installation**
   - Navigate to `https://your-forum.com/patreon-stats`
   - Verify data displays correctly

## Configuration

### Admin Settings

**Note:** OAuth credentials (Client ID, Client Secret, Access Token, Refresh Token) are read from the core [discourse-patreon](https://github.com/discourse/discourse-patreon) plugin. Configure them there, not here.

| Setting | Description | Default |
|---------|-------------|---------|
| `patreon_donations_enabled` | Enable the plugin | false |
| `patreon_donations_api_version` | Patreon API version (v1 or v2) | v2 |
| `patreon_donations_campaign_url` | Campaign URL for auto-discovery | - |
| `patreon_donations_platform_fee_percentage` | Patreon platform fee % | 10.0 |
| `patreon_donations_tax_rate_percentage` | Tax rate % on net revenue | 43.0 |
| `patreon_donations_allowed_groups` | Groups allowed to view stats | admins |
| `patreon_donations_cache_duration` | Cache duration (minutes) | 30 |
| `patreon_donations_sync_frequency` | Background sync frequency (hours) | 24 |

### How to Get Your Campaign ID

**Good News**: The plugin **automatically discovers your campaign ID** when you save your Access Token. You typically don't need to do anything manually!

However, if auto-discovery fails or you want to verify the ID, here are manual methods:

#### Option 1: Use the Patreon API

After obtaining your access token, make an API call:

```bash
curl --request GET \
  --url 'https://www.patreon.com/api/oauth2/v2/campaigns' \
  --header 'Authorization: Bearer YOUR_ACCESS_TOKEN'
```

The campaign ID will be in the response's `data[0].id` field (e.g., "9070965").

#### Option 2: From Patreon Creator Dashboard

1. Visit https://www.patreon.com/portal/campaigns
2. Click on your campaign
3. Look at the URL: `https://www.patreon.com/portal/campaigns/CAMPAIGN_ID/...`
4. Copy the numeric ID from the URL

#### Important Notes

- The public campaign URL (e.g., `patreon.com/yourname`) does **not** contain the campaign ID
- Most creators only have one campaign, which is auto-discovered automatically
- Manual entry is only needed if auto-discovery fails

For more details, see [PATREON_API_REFERENCE.md](docs/PATREON_API_REFERENCE.md#how-to-get-your-campaign-id).

### Permissions

- **View Stats**: All users (configurable)
- **Manual Refresh**: Admins only
- **Configure Settings**: Admins only

## Data Privacy

- **No User Data Stored**: Plugin only stores aggregate statistics
- **No Patron Names**: Individual patron information is not displayed
- **Encrypted Credentials**: OAuth tokens stored encrypted in database
- **GDPR Compliant**: No personal data processing

## Sync Behavior

- **Automatic Sync**: Runs via Sidekiq background job
- **Manual Trigger**: Admins can force sync from settings page
- **Error Handling**: Failed syncs are logged and retried with exponential backoff
- **Rate Limiting**: Respects Patreon API rate limits automatically

## Troubleshooting

### Data Not Updating

1. Check sync job is running: Admin → Sidekiq → Scheduled
2. Verify API credentials are correct
3. Check logs: `/var/discourse/shared/standalone/log/rails/production.log`
4. Test API connection manually from Rails console

### 401 Unauthorized Errors

- Access token may have expired
- Trigger token refresh or re-enter credentials

### 429 Rate Limit Errors

- Decrease sync frequency
- Increase cache duration
- Check for multiple instances hitting API

## Development

### Running Tests
```bash
bundle exec rspec plugins/discourse-patreon-donations
```

### Local Development
```bash
bin/docker/boot_dev --init
bin/docker/rails s
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for version history.

## License

[MIT License](./LICENSE)

## Credits

- Built for NetGamers community
- Uses [Patreon Platform API](https://docs.patreon.com/)
- Inspired by Discourse's transparency values

## Support

- **Issues**: https://github.com/yourusername/discourse-patreon-donations/issues
- **Discourse Meta**: https://meta.discourse.org/
- **Patreon Developer Forum**: https://www.patreondevelopers.com/

## Related Resources

- [Development Guidelines](./CLAUDE.md) - High-level approach and principles
- [Current Implementation Plan](./CURRENT_IMPLEMENTATION_PLAN.md) - Detailed code examples and patterns
- [Patreon API Reference](./PATREON_API_REFERENCE.md) - API endpoints and data mapping
- [Patreon API Documentation](https://docs.patreon.com/)
- [Discourse Plugin Development Guide](https://meta.discourse.org/t/beginners-guide-to-creating-discourse-plugins/30515)
