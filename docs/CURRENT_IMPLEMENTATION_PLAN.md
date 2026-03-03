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

## Completed Milestones

The following have been completed and tested on the staging environment:

- **Database Migration** - Consolidated migration creating `patreon_cache` and `patreon_monthly_stats` tables
- **Core Backend** - All services (PatreonApiClient, PatreonStatsCalculator, PatreonCampaignDiscovery), controller, model, and background job
- **Frontend** - Ember route, template, helpers (format-change, month-name, multiply), SCSS styling
- **Patreon API Integration** - Dual v1/v2 support with pagination, tested against live Patreon API
- **OAuth Configuration** - Credentials configured and working in staging
- **Monthly Snapshots** - Recording current month data, rake tasks for manual management
- **Staging Deployment** - Plugin deployed, data syncing, UI rendering correctly

Testing strategy: manual testing on staging environment (no automated test suite).

## Next Steps

### 1. UI and Configuration Improvements

#### 1.1. Align Historical Data Table Columns

The monthly history table needs proper column alignment for better readability.

**Current Issue**: Column titles and row content may not be properly aligned.

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

#### 1.2. Make Revenue Breakdown Percentages Configurable

Currently, Patreon fee (10%) and tax rate (43%) are hardcoded. Make them configurable site settings.

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

#### 1.3. Add Group-Based Access Control

Make the stats page visible only to specific Discourse groups (admins by default).

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

### 2. Token Refresh and Exponential Backoff

#### 2.1. Automatic Token Refresh

Add OAuth token refresh logic to `PatreonApiClient` so expired access tokens are automatically renewed using the refresh token.

**Implementation** (`app/services/patreon_api_client.rb`):
```ruby
def refresh_access_token
  uri = URI("https://www.patreon.com/api/oauth2/token")
  request = Net::HTTP::Post.new(uri)
  request.set_form_data(
    grant_type: "refresh_token",
    refresh_token: SiteSetting.patreon_donations_creator_refresh_token,
    client_id: SiteSetting.patreon_donations_client_id,
    client_secret: SiteSetting.patreon_donations_client_secret
  )

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  if response.is_a?(Net::HTTPSuccess)
    data = JSON.parse(response.body)
    SiteSetting.patreon_donations_creator_access_token = data["access_token"]
    SiteSetting.patreon_donations_creator_refresh_token = data["refresh_token"] if data["refresh_token"]
    Rails.logger.info("Patreon access token refreshed successfully")
    true
  else
    Rails.logger.error("Failed to refresh Patreon token: #{response.code} #{response.body}")
    false
  end
rescue StandardError => e
  Rails.logger.error("Error refreshing Patreon token: #{e.message}")
  false
end
```

**Integration**: On 401 response, call `refresh_access_token` and retry the original request once. If refresh also fails, log the error and return nil.

#### 2.2. Exponential Backoff for Rate Limits

Add retry logic with exponential backoff when receiving 429 (Too Many Requests) responses.

**Implementation** (`app/services/patreon_api_client.rb`):
```ruby
MAX_RETRIES = 3
BASE_DELAY = 2 # seconds

def make_request_with_backoff(uri, retry_count = 0)
  response = make_single_request(uri)

  case response
  when Net::HTTPTooManyRequests
    if retry_count < MAX_RETRIES
      delay = BASE_DELAY ** (retry_count + 1) # 2s, 4s, 8s
      retry_after = response["Retry-After"]&.to_i
      wait_time = [delay, retry_after || 0].max

      Rails.logger.warn("Patreon rate limited, retrying in #{wait_time}s (attempt #{retry_count + 1}/#{MAX_RETRIES})")
      sleep(wait_time)
      make_request_with_backoff(uri, retry_count + 1)
    else
      Rails.logger.error("Patreon rate limit exceeded after #{MAX_RETRIES} retries")
      nil
    end
  when Net::HTTPUnauthorized
    if retry_count == 0 && refresh_access_token
      Rails.logger.info("Retrying request after token refresh")
      make_request_with_backoff(uri, retry_count + 1)
    else
      Rails.logger.error("Patreon unauthorized after token refresh attempt")
      nil
    end
  else
    response
  end
end
```

**Key behaviors**:
- Retries up to 3 times on 429 responses
- Delays: 2s, 4s, 8s (exponential)
- Respects `Retry-After` header from Patreon if present
- On 401, attempts one token refresh then retries
- Logs each retry attempt for debugging
