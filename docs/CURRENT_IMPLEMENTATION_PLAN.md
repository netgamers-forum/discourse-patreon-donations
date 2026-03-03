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
    <h3>Current Active Subscribers</h3>
    <p class="stat-value">{{model.stats.patron_count}}</p>
  </div>
  <div class="stat-card">
    <h3>Next Month Estimate</h3>
    <p class="stat-value">${{model.stats.monthly_estimate}}</p>
  </div>
  <div class="stat-card">
    <h3>Change from Last Month</h3>
    <p class="stat-value">{{{format-change model.stats.monthly_change}}}</p>
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
          <h3>Current Active Subscribers</h3>
          <p>{{model.stats.patron_count}}</p>
        </div>
      </div>
    </div>
  </div>
</div>
```

### Handlebar Helpers

#### Custom Helper for Signed Currency Display

```javascript
// Good: Reusable helper for formatting currency changes
import { registerUnbound } from "discourse-common/lib/helpers";
import { htmlSafe } from "@ember/template";

registerUnbound("format-change", function(value) {
  if (value === null || value === undefined) {
    return htmlSafe('<span class="change-neutral">N/A</span>');
  }
  
  const numValue = parseFloat(value);
  if (isNaN(numValue)) {
    return htmlSafe('<span class="change-neutral">N/A</span>');
  }
  
  const absValue = Math.abs(numValue).toFixed(2);
  
  if (numValue > 0) {
    return htmlSafe(`<span class="change-positive">+$${absValue}</span>`);
  } else if (numValue < 0) {
    return htmlSafe(`<span class="change-negative">-$${absValue}</span>`);
  } else {
    return htmlSafe('<span class="change-neutral">$0.00</span>');
  }
});
```

#### Custom Helper for Multiplication

```javascript
// Good: Simple helper for calculations in templates
import { registerUnbound } from "discourse-common/lib/helpers";

registerUnbound("multiply", function(value, multiplier) {
  const num = parseFloat(value) || 0;
  const mult = parseFloat(multiplier) || 0;
  return (num * mult).toFixed(2);
});
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

### Monthly Change Tracking

```ruby
# Calculate month-over-month change by comparing current estimate vs last completed month
def calculate_monthly_change(current_estimate, monthly_history)
  return nil if monthly_history.empty?

  current_date = Time.now.utc
  current_year = current_date.year
  current_month = current_date.month

  # Find the most recent snapshot that's NOT the current month
  # (we want last completed month to compare against)
  last_month_snapshot = monthly_history.reverse.find do |month|
    month[:year] != current_year || month[:month] != current_month
  end
  
  return nil unless last_month_snapshot
  
  # Compare current estimate vs last month's snapshot
  current_estimate - last_month_snapshot[:total_amount]
rescue StandardError => e
  Rails.logger.error("Error calculating monthly change: #{e.message}")
  nil
end
```

**Display in Template**:
```handlebars
<div class="stat-card">
  <h3>Change from Last Month</h3>
  <p class="stat-value">{{{format-change model.stats.monthly_change}}}</p>
</div>
```

**Helper Formatting**:
- Positive change: `+$23.80` (green)
- Negative change: `-$15.30` (red)
- No previous data: `N/A` (gray)

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

### Rake Tasks

The plugin provides rake tasks for managing monthly snapshots:

```bash
# Create/update snapshot for current month
rake patreon_donations:snapshot

# View all historical snapshots
rake patreon_donations:status

# Clear all historical data (useful when migrating from fake backfill)
rake patreon_donations:clear
```

**Implementation Example**:
```ruby
namespace :patreon_donations do
  desc "Create snapshot for current month"
  task snapshot: :environment do
    Rails.cache.delete("patreon_stats:#{SiteSetting.patreon_donations_campaign_id}")
    result = DiscoursePatreonDonations::PatreonMonthlyStat.snapshot_current_month
    puts result[:success] ? result[:message] : "Error: #{result[:error]}"
  end

  desc "Show all monthly snapshots"
  task status: :environment do
    campaign_id = SiteSetting.patreon_donations_campaign_id
    records = DiscoursePatreonDonations::PatreonMonthlyStat
      .where(campaign_id: campaign_id)
      .order(year: :desc, month: :desc)
    
    if records.empty?
      puts "No snapshots found. Run 'rake patreon_donations:snapshot' to create one."
    else
      records.each do |record|
        puts "#{record.year}-#{record.month}: #{record.patron_count} patrons, $#{record.total_amount}"
      end
    end
  end

  desc "Clear all monthly snapshots"
  task clear: :environment do
    campaign_id = SiteSetting.patreon_donations_campaign_id
    count = DiscoursePatreonDonations::PatreonMonthlyStat
      .where(campaign_id: campaign_id)
      .delete_all
    Rails.cache.delete("patreon_stats:#{campaign_id}")
    puts "Deleted #{count} snapshot(s) and cleared cache"
  end
end
```

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
# Good: Complete pagination for V1 API
def fetch_all_members(campaign_id)
  members = []
  endpoint = "/campaigns/#{campaign_id}/pledges"
  page = 0
  max_pages = 20 # Safety limit
  
  loop do
    page += 1
    break if page > max_pages
    
    response = make_request(endpoint)
    members.concat(response['data'])
    
    next_url = response.dig('links', 'next')
    break unless next_url
    
    # Extract path from next URL (remove base URL)
    endpoint = extract_path_from_url(next_url)
    Rails.logger.warn("Fetching page #{page}, total so far: #{members.count}")
  end
  
  Rails.logger.warn("Total fetched: #{members.count}")
  members
end

private

def extract_path_from_url(url)
  return nil unless url
  
  uri = URI.parse(url)
  path = uri.path
  
  # Remove the API base path if it's included
  path = path.sub(%r{^/api/oauth2/api}, '')
  path = path.sub(%r{^/oauth2/api}, '')
  
  # Add query string if present
  path += "?#{uri.query}" if uri.query
  path
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

A single consolidated migration creates both required tables:

**File**: `db/migrate/20260302000001_create_patreon_tables.rb`

**Tables Created**:

#### patreon_cache - Current Statistics Cache
- `campaign_id` (string, not null) - Patreon campaign identifier
- `data` (text, not null) - JSON-serialized current stats data
- `last_synced_at` (datetime) - Timestamp of last sync
- `created_at`, `updated_at` (timestamps) - Rails standard timestamps
- Unique index on `campaign_id`

#### patreon_monthly_stats - Historical Monthly Data
- `campaign_id` (string, not null) - Patreon campaign identifier
- `year` (integer, not null) - Year of the snapshot
- `month` (integer, not null) - Month of the snapshot (1-12)
- `patron_count` (integer, not null) - Number of patrons that month
- `total_amount_cents` (integer, not null) - Total monthly pledges in cents
- `created_at`, `updated_at` (timestamps) - Rails standard timestamps
- Unique index on `(campaign_id, year, month)` - Prevents duplicate monthly records
- Index on `campaign_id` for efficient queries

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

To verify the migrations ran successfully:

```bash
# Rails console
rails c
# Check if tables exist
ActiveRecord::Base.connection.table_exists?(:patreon_cache)
# => true
ActiveRecord::Base.connection.table_exists?(:patreon_monthly_stats)
# => true
```

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

### 5. UI and Configuration Improvements

**Priority improvements for the current implementation:**

#### 5.1. Align Historical Data Table Columns

The monthly history table needs proper column alignment for better readability:

**Current Issue**: Column titles and row content may not be properly aligned

**Implementation**:
```scss
// assets/stylesheets/patreon-stats.scss
.monthly-history-table {
  table {
    width: 100%;
    border-collapse: collapse;
    
    th, td {
      text-align: left;
      padding: 0.75rem 1rem;
      
      &:nth-child(2), // Patrons column
      &:nth-child(3)  // Total Amount column
      {
        text-align: right; // Right-align numeric columns
      }
    }
  }
}
```

**Template Update**:
```handlebars
<table>
  <thead>
    <tr>
      <th class="align-left">Month</th>
      <th class="align-right">Patrons</th>
      <th class="align-right">Total Amount</th>
    </tr>
  </thead>
  <tbody>
    {{#each model.monthly_history as |month|}}
      <tr>
        <td class="align-left">{{month-name month.month}} {{month.year}}</td>
        <td class="align-right">{{month.patron_count}}</td>
        <td class="align-right">${{month.total_amount}}</td>
      </tr>
    {{/each}}
  </tbody>
</table>
```

#### 5.2. Make Revenue Breakdown Percentages Configurable

Currently, Patreon fee (10%) and tax rate (43%) are hardcoded. Make them configurable site settings:

**Settings Addition** (`config/settings.yml`):
```yaml
patreon_donations:
  patreon_donations_platform_fee_percentage:
    default: 10.0
    min: 0
    max: 100
    type: float
    description: "Patreon platform fee percentage (default: 10%)"
  
  patreon_donations_tax_rate_percentage:
    default: 43.0
    min: 0
    max: 100
    type: float
    description: "Tax rate percentage applied to net revenue after platform fees"
```

**Template Update** (`assets/javascripts/discourse/templates/patreon-stats.hbs`):
```handlebars
<div class="breakdown-row deduction">
  <span class="breakdown-label">Less Patreon fee ({{siteSettings.patreon_donations_platform_fee_percentage}}%):</span>
  <span class="breakdown-value">-${{multiply model.stats.monthly_estimate (divide siteSettings.patreon_donations_platform_fee_percentage 100)}}</span>
</div>

{{! Calculate subtotal after platform fee }}
{{#let (multiply model.stats.monthly_estimate (subtract 1 (divide siteSettings.patreon_donations_platform_fee_percentage 100))) as |afterPlatformFee|}}
  <div class="breakdown-row subtotal">
    <span class="breakdown-label">Subtotal after Patreon:</span>
    <span class="breakdown-value">${{afterPlatformFee}}</span>
  </div>
  
  <div class="breakdown-row deduction">
    <span class="breakdown-label">Less taxes ({{siteSettings.patreon_donations_tax_rate_percentage}}%):</span>
    <span class="breakdown-value">-${{multiply afterPlatformFee (divide siteSettings.patreon_donations_tax_rate_percentage 100)}}</span>
  </div>
  
  <div class="breakdown-row total">
    <span class="breakdown-label">Net income available:</span>
    <span class="breakdown-value">${{multiply afterPlatformFee (subtract 1 (divide siteSettings.patreon_donations_tax_rate_percentage 100))}}</span>
  </div>
{{/let}}
```

**Helper Addition** (`assets/javascripts/discourse/helpers/`):
```javascript
// divide.js.es6
import { registerUnbound } from "discourse-common/lib/helpers";

registerUnbound("divide", function(value, divisor) {
  const num = parseFloat(value) || 0;
  const div = parseFloat(divisor) || 1;
  return (num / div).toFixed(4);
});

// subtract.js.es6
import { registerUnbound } from "discourse-common/lib/helpers";

registerUnbound("subtract", function(value, subtrahend) {
  const num = parseFloat(value) || 0;
  const sub = parseFloat(subtrahend) || 0;
  return (num - sub).toFixed(4);
});
```

**Benefits**:
- Site-specific configuration for different tax jurisdictions
- No code changes needed to update percentages
- Accurate representation of actual financial breakdown

#### 5.3. Add Group-Based Access Control

Make the stats page visible only to specific Discourse groups (admins by default):

**Settings Addition** (`config/settings.yml`):
```yaml
patreon_donations:
  patreon_donations_allowed_groups:
    type: group_list
    default: "admins"
    list_type: compact
    description: "Discourse groups allowed to view Patreon donation statistics. Default: admins only"
```

**Controller Update** (`app/controllers/patreon_stats_controller.rb`):
```ruby
class PatreonStatsController < ::ApplicationController
  requires_plugin 'discourse-patreon-donations'
  before_action :ensure_logged_in
  before_action :ensure_authorized

  def show
    unless SiteSetting.patreon_donations_enabled
      return render_json_error(I18n.t('patreon_stats.error.not_configured'), status: 503)
    end

    stats = fetch_cached_stats
    monthly_history = fetch_monthly_history

    if stats
      monthly_change = calculate_monthly_change(stats[:monthly_estimate], monthly_history)
      
      render json: { 
        stats: stats.merge(monthly_change: monthly_change),
        monthly_history: monthly_history
      }
    else
      render_json_error(I18n.t('patreon_stats.error.fetch_failed'), status: 503)
    end
  end

  private

  def ensure_authorized
    allowed_group_names = SiteSetting.patreon_donations_allowed_groups.split('|')
    user_groups = current_user.groups.pluck(:name)
    
    unless current_user.admin? || (allowed_group_names & user_groups).any?
      raise Discourse::InvalidAccess.new(
        'You do not have permission to view Patreon statistics',
        custom_message: 'patreon_stats.error.not_authorized'
      )
    end
  end

  # ... rest of controller methods
end
```

**Route Update** (`assets/javascripts/discourse/routes/patreon-stats.js.es6`):
```javascript
import DiscourseRoute from "discourse/routes/discourse";

export default DiscourseRoute.extend({
  beforeModel() {
    if (!this.currentUser) {
      this.replaceWith("login");
    }
  },

  model() {
    return ajax("/patreon-stats.json").catch(error => {
      if (error.jqXHR && error.jqXHR.status === 403) {
        bootbox.alert(I18n.t("patreon_stats.error.not_authorized"));
        this.replaceWith("discovery");
      }
      return { error: true, message: error.message };
    });
  }
});
```

**Translation Update** (`config/locales/client.en.yml`):
```yaml
en:
  js:
    patreon_stats:
      title: "Patreon Donation Summary"
      error:
        fetch_failed: "Unable to fetch Patreon statistics. Please try again later."
        not_authorized: "You do not have permission to view this page. Contact an administrator if you believe this is an error."
```

**Benefits**:
- Control who can see financial data
- Flexible group-based permissions (e.g., "admins|moderators|donors")
- Prevents unauthorized access to sensitive donation information
- Works with Discourse's existing group system

### 6. Additional Enhancements (Future Iterations)

Consider these improvements for future iterations:

- Add token refresh logic in API client
- Implement exponential backoff for rate limits
- Create admin dashboard widgets for quick stats view
- Add data export to CSV functionality
- Implement webhook support for real-time updates
- Add email notifications for milestone achievements
- Add patron tier breakdown charts
- Implement forecasting based on historical trends
