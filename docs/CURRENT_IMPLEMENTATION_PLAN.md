# Current Implementation Plan

This document contains detailed code examples and patterns for implementing the Discourse Patreon Donations plugin.

## File Structure

```
discourse-patreon-donations/
├── plugin.rb                           # Main plugin entry point
├── config/
│   ├── locales/
│   │   └── en.yml                      # English translations
│   └── settings.yml                     # Admin-configurable settings
├── app/
│   ├── controllers/
│   │   └── patreon_stats_controller.rb # API endpoint for stats
│   ├── models/
│   │   └── patreon_cache.rb            # Cache model
│   ├── services/
│   │   ├── patreon_api_client.rb       # API client wrapper
│   │   ├── patreon_stats_calculator.rb # Stats calculation logic
│   │   └── patreon_campaign_discovery.rb # Auto-discover campaign ID
│   └── jobs/
│       └── sync_patreon_data.rb        # Background sync job
├── assets/
│   └── javascripts/
│       └── discourse/
│           ├── routes/
│           │   └── patreon-stats.js.es6
│           ├── controllers/
│           │   └── patreon-stats.js.es6
│           └── templates/
│               └── patreon-stats.hbs
└── spec/
    ├── requests/
    ├── models/
    └── services/
```

## Code Examples

### Ruby

#### Good: Simple, clear, follows DRY

```ruby
class PatreonStatsCalculator
  def initialize(members)
    @members = members
  end

  def monthly_estimate
    active_members.sum(&:entitled_amount) / 100.0
  end

  private

  def active_members
    @active_members ||= @members.select { |m| m.patron_status == 'active_patron' }
  end
end
```

#### Bad: Complex, repeats logic

```ruby
class PatreonStatsCalculator
  # Calculate monthly estimate for patrons
  def monthly_estimate
    total = 0
    @members.each do |member|
      if member.patron_status == 'active_patron'
        total += member.entitled_amount
      end
    end
    total / 100.0
  end

  # Calculate last month total
  def last_month_total
    total = 0
    @members.each do |member|
      if member.last_charge_status == 'Paid' && last_month?(member.last_charge_date)
        total += member.entitled_amount
      end
    end
    total / 100.0
  end
end
```

### JavaScript/Ember

#### Good: Simple, clear

```javascript
export default Route.extend({
  model() {
    return ajax('/patreon-stats.json');
  }
});
```

#### Bad: Overly complex

```javascript
export default Route.extend({
  model() {
    return new Promise((resolve, reject) => {
      ajax('/patreon-stats.json')
        .then(response => {
          if (response && response.stats) {
            resolve(response);
          } else {
            reject('Invalid response');
          }
        })
        .catch(error => reject(error));
    });
  }
});
```

### Templates (Handlebars)

#### Good: Clean structure

```handlebars
{{! Good: Clean structure }}
<div class="patreon-stats">
  <div class="stat-card">
    <h3>Active Subscribers</h3>
    <p class="stat-value">{{model.patron_count}}</p>
  </div>
</div>
```

#### Bad: Unnecessary nesting

```handlebars
<div class="patreon-stats-container">
  <div class="patreon-stats-wrapper">
    <div class="patreon-stats-inner">
      <div class="stat-card-container">
        <div class="stat-card">
          <h3>Active Subscribers</h3>
          <p>{{model.patron_count}}</p>
        </div>
      </div>
    </div>
  </div>
</div>
```

## Common Patterns

### API Error Handling

```ruby
def fetch_campaign_data
  response = http_client.get('/campaigns')
  handle_api_response(response)
rescue Net::HTTPError => e
  handle_http_error(e)
rescue JSON::ParserError => e
  handle_parse_error(e)
end

private

def handle_api_response(response)
  return response.parsed_body if response.success?
  
  case response.status
  when 429
    handle_rate_limit(response)
  when 401
    refresh_token_and_retry
  else
    log_error("API error: #{response.status}")
    nil
  end
end
```

### Caching Strategy

```ruby
def cached_stats
  Rails.cache.fetch(cache_key, expires_in: cache_duration) do
    calculate_stats
  end
end

def cache_key
  "patreon_stats:#{campaign_id}"
end

def cache_duration
  SiteSetting.patreon_cache_duration.minutes
end
```

### Background Jobs

```ruby
module Jobs
  class SyncPatreonData < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless SiteSetting.patreon_enabled
      
      PatreonSyncService.new.sync
    rescue StandardError => e
      Rails.logger.error("Patreon sync failed: #{e.message}")
      raise
    end
  end
end
```

### Campaign ID Auto-Discovery

The plugin automatically discovers your campaign ID when you save your Access Token, eliminating manual configuration:

```ruby
# app/services/patreon_campaign_discovery.rb
module DiscoursePatreonDonations
  class PatreonCampaignDiscovery
    def self.discover_and_save
      return false unless SiteSetting.patreon_creator_access_token.present?

      client = PatreonApiClient.new
      campaign_id = client.discover_campaign_id

      if campaign_id.present?
        SiteSetting.patreon_campaign_id = campaign_id
        Rails.logger.info("Patreon campaign ID auto-discovered: #{campaign_id}")
        true
      else
        Rails.logger.error("Failed to auto-discover Patreon campaign ID")
        false
      end
    rescue StandardError => e
      Rails.logger.error("Error discovering campaign ID: #{e.message}")
      false
    end
  end
end
```

The auto-discovery is triggered by a site setting change event in `plugin.rb`:

```ruby
DiscourseEvent.on(:site_setting_changed) do |name, old_value, new_value|
  if name == :patreon_creator_access_token && new_value.present?
    DiscoursePatreonDonations::PatreonCampaignDiscovery.discover_and_save
  end
end
```

This feature:
- Runs automatically when Access Token is saved
- Fetches the first campaign from the Patreon API
- Saves the campaign ID to site settings
- Logs success or failure for debugging
- Gracefully handles errors without breaking the settings page

## Testing

### Test Structure

```ruby
RSpec.describe PatreonStatsCalculator do
  let(:active_member) do
    build(:member, patron_status: 'active_patron', entitled_amount: 500)
  end
  
  let(:declined_member) do
    build(:member, patron_status: 'declined_patron', entitled_amount: 300)
  end
  
  describe '#monthly_estimate' do
    it 'sums only active patron amounts' do
      calculator = described_class.new([active_member, declined_member])
      expect(calculator.monthly_estimate).to eq(5.0)
    end
  end
end
```

### Test Guidelines

- Fast to run
- Easy to understand
- Independent of each other
- Testing one thing at a time

## Security

### Credential Storage

```ruby
# Good: Encrypted storage
def access_token
  SiteSetting.patreon_access_token.decrypt
end

# Bad: Plain text
def access_token
  SiteSetting.patreon_access_token
end
```

### Security Checklist

- Store OAuth credentials encrypted in database
- Never log sensitive credentials
- Use SiteSettings for configuration
- Rotate tokens regularly
- Respect API rate limits
- Implement exponential backoff
- Cache aggressively to reduce API calls

## Performance

### Database Queries

```ruby
# Good: Eager loading
def fetch_with_relationships
  Member.includes(:campaign, :tiers).where(campaign_id: id)
end

# Bad: N+1 queries
def fetch_with_relationships
  Member.where(campaign_id: id).each do |member|
    member.campaign.name
    member.tiers.each(&:title)
  end
end
```

### Caching Strategy

- Cache API responses for 15-30 minutes
- Cache calculated statistics
- Use Rails.cache for temporary data
- Implement cache invalidation strategy

### Background Processing

- Fetch API data in background jobs
- Avoid blocking user requests
- Use Sidekiq for async operations
- Schedule regular data syncs

## Discourse-Specific Patterns

### Site Settings

```yaml
# settings.yml
patreon:
  patreon_enabled:
    default: false
    client: true
  patreon_client_id:
    default: ''
    secret: true
  patreon_sync_frequency:
    default: 24
    min: 1
    max: 168
```

### Routes

```ruby
# plugin.rb
Discourse::Application.routes.append do
  get '/patreon-stats' => 'patreon_stats#index'
  get '/patreon-stats.json' => 'patreon_stats#show'
end
```

### Permissions

```ruby
def ensure_staff
  raise Discourse::InvalidAccess unless current_user&.staff?
end
```

## API Integration

### Making Requests

```ruby
def fetch_data(endpoint)
  uri = URI("#{base_url}#{endpoint}")
  request = build_request(uri)
  
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end
  
  parse_response(response)
end

private

def build_request(uri)
  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{access_token}"
  request['User-Agent'] = user_agent
  request
end

def user_agent
  "Discourse-Patreon-Plugin/#{PluginVersion}"
end
```

### Pagination Handling

```ruby
def fetch_all_members(campaign_id)
  members = []
  cursor = nil
  
  loop do
    response = fetch_members_page(campaign_id, cursor)
    members.concat(response[:data])
    
    cursor = response.dig(:meta, :pagination, :cursors, :next)
    break if cursor.nil?
  end
  
  members
end
```

## Error Messages

### User-Facing Messages

```ruby
# Good: Clear and actionable
"Unable to sync Patreon data. Please verify your API credentials in settings."

# Bad: Technical jargon
"HTTP 401: Unauthorized - Token expired or invalid scope"
```

### Log Messages

```ruby
# Good: Detailed for debugging
Rails.logger.error(
  "Patreon API error: status=#{response.code}, " \
  "endpoint=#{endpoint}, message=#{error_message}"
)

# Bad: Not enough context
Rails.logger.error("API error")
```

## Example Workflow

When implementing a new feature:

1. Read existing code to understand patterns
2. Check if similar functionality exists
3. Design simple solution following KISS
4. Extract reusable components for DRY
5. Write tests first (TDD approach)
6. Implement feature
7. Test manually in development
8. Update documentation
9. Submit for review

## Example Commit Sequence

```bash
1. git commit -m "Add PatreonApiClient service"
2. git commit -m "Add PatreonStatsCalculator service"
3. git commit -m "Add PatreonStatsController with show action"
4. git commit -m "Add Patreon stats Ember route and template"
5. git commit -m "Add SyncPatreonData background job"
6. git commit -m "Add specs for PatreonStatsCalculator"
7. git commit -m "Add Patreon configuration to settings.yml"
8. git commit -m "Update README with installation instructions"
```

Each commit is small, focused, and can be reviewed independently.

## Next Steps

Now that the initial plugin structure is complete, the following steps remain:

### 1. Add Database Migration ✓ COMPLETED

The migration file for the `patreon_cache` table has been created:

**File**: `db/migrate/20260302000001_create_patreon_cache.rb`

**Schema**:
- `campaign_id` (string, not null) - Patreon campaign identifier
- `data` (text, not null) - JSON-serialized stats data
- `last_synced_at` (datetime) - Timestamp of last sync
- `created_at`, `updated_at` (timestamps) - Rails standard timestamps
- Unique index on `campaign_id`

**Running the migration in Discourse**:

When you install or update the plugin, Discourse will automatically run pending migrations during the rebuild process:

```bash
cd /var/discourse
./launcher rebuild app
```

For development environments:

```bash
# From Discourse root directory
bundle exec rake db:migrate
```

To verify the migration ran successfully:

```bash
# Rails console
rails c
# Check if table exists
ActiveRecord::Base.connection.table_exists?(:patreon_cache)
# => true
```

**Monthly Statistics Tracking**: ✓ ADDED

An additional migration was added to track historical monthly data:

**File**: `db/migrate/20260302000002_create_patreon_monthly_stats.rb`

**Schema**:
- `campaign_id` (string, not null) - Patreon campaign identifier
- `year` (integer, not null) - Year of the snapshot
- `month` (integer, not null) - Month of the snapshot (1-12)
- `patron_count` (integer, not null) - Number of patrons that month
- `total_amount_cents` (integer, not null) - Total monthly pledges in cents
- `created_at`, `updated_at` (timestamps) - Rails standard timestamps
- Unique index on `(campaign_id, year, month)` - Prevents duplicate monthly records

**Features**:
- Automatically records monthly snapshots during sync job
- Stores last 12 months of data (older records auto-deleted)
- Provides historical data for trend analysis and charting
- Accessible via `/patreon-stats.json` API endpoint

**Model**: `PatreonMonthlyStat` provides methods:
- `record_monthly_snapshot(campaign_id, patron_count, total_amount_cents, date)` - Create or update monthly record
- `last_12_months(campaign_id)` - Retrieve 12 most recent months
- `cleanup_old_records(campaign_id, keep_months)` - Remove old data beyond retention period

### 2. Write Tests

Write comprehensive tests for services and controllers:

**Service Tests**:
- `spec/services/patreon_api_client_spec.rb` - Test API client methods, error handling, pagination
- `spec/services/patreon_stats_calculator_spec.rb` - Test stat calculations with various scenarios
- `spec/models/patreon_cache_spec.rb` - Test cache model methods and expiration logic

**Controller Tests**:
- `spec/requests/patreon_stats_controller_spec.rb` - Test HTTP endpoints, caching, error responses

**Job Tests**:
- `spec/jobs/sync_patreon_data_spec.rb` - Test background job execution and scheduling

### 3. Test in Development Discourse Instance

Deploy and test the plugin in a local Discourse development environment:

1. Clone Discourse repository
2. Symlink plugin to `plugins/` directory
3. Run database migrations
4. Start Discourse server
5. Configure OAuth credentials in admin settings
6. Access `/patreon-stats` route
7. Verify stats display correctly
8. Monitor background job execution
9. Test error scenarios (invalid credentials, API failures)

### 4. Configure OAuth Credentials

Set up Patreon OAuth application and configure credentials:

1. Register application at: https://www.patreon.com/portal/registration/register-clients
2. Note Client ID and Client Secret
3. Complete OAuth flow to obtain Creator Access Token and Refresh Token
4. In Discourse admin settings (`/admin/site_settings/category/patreon`):
   - Enable Patreon integration
   - Enter Client ID
   - Enter Client Secret
   - Enter Creator Access Token
   - Enter Creator Refresh Token
   - Enter Campaign ID
   - Configure cache duration (default: 30 minutes)
   - Configure sync frequency (default: 24 hours)

### 5. Additional Enhancements (Optional)

Consider these improvements for future iterations:

- Add token refresh logic in API client
- Implement exponential backoff for rate limits
- Add staff-only access control to stats page
- Create admin dashboard widgets for quick stats view
- Add historical data tracking and trend charts
- Implement webhook support for real-time updates
- Add email notifications for milestone achievements
