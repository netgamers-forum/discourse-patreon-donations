# Patreon API Reference

This document outlines the Patreon API endpoints used by this plugin.

## API Version

The plugin supports both **v1** and **v2** API endpoints:

- **v2 (Recommended)**: The current and actively maintained API version
  - Base URL: `https://www.patreon.com/api/oauth2/v2`
  - Full JSON:API spec compliance
  - Better documentation and support
  
- **v1 (Legacy)**: Older API version, use only if you have a v1 OAuth client
  - Base URL: `https://api.patreon.com/oauth2/api`  
  - Compatible with older OAuth clients
  - May have limited future support
  - Uses dedicated `/campaigns/{id}/pledges` endpoint with pagination

**Configuration**: Set the API version in plugin settings (`patreon_donations_api_version`). The plugin will automatically use the correct base URL and handle any differences between the versions.

**Note**: API v1 may be deprecated in the future. We recommend using v2 for new integrations.

## Authentication

- **OAuth 2.0** required
- Must register a client at: https://www.patreon.com/portal/registration/register-clients
- Credentials needed:
  - Client ID
  - Client Secret
  - Creator's Access Token
  - Creator's Refresh Token

## Required Scopes

- `campaigns` - To access campaign information
- `campaigns.members` - To access member/patron data

## How to Get Your Campaign ID

There are several ways to obtain your Patreon campaign ID:

### Method 1: Using the API (Recommended)

After obtaining your access token, call the campaigns endpoint:

```bash
curl --request GET \
  --url 'https://www.patreon.com/api/oauth2/v2/campaigns' \
  --header 'Authorization: Bearer YOUR_ACCESS_TOKEN'
```

The response will include your campaign ID in the `id` field:

```json
{
  "data": [{
    "id": "1234560",
    "type": "campaign",
    "attributes": { ... }
  }]
}
```

### Method 2: From Your Patreon Page URL

Your campaign ID may be visible in certain Patreon URLs:

- **Creator Dashboard**: Visit https://www.patreon.com/portal/campaigns
  - Click on your campaign
  - The URL will be: `https://www.patreon.com/portal/campaigns/CAMPAIGN_ID/...`
  - Extract the numeric ID from the URL

- **API Documentation Page**: When testing API calls in the Patreon developer portal, the campaign ID is often pre-filled in example URLs

### Method 3: From Browser Developer Tools

1. Log into Patreon as the creator
2. Visit your campaign page
3. Open browser developer tools (F12)
4. Go to the Network tab
5. Look for API calls to `patreon.com/api/oauth2/v2/campaigns`
6. Inspect the response to find the campaign `id`

### Important Notes

- The campaign ID is a numeric string (e.g., "1234560")
- You only need this ID if you have multiple campaigns (most creators have just one)
- If you only have one campaign, the API will return it automatically

## Rate Limits

- **Client level**: 100 requests per 2 seconds
- **Access Token level**: 100 requests per minute
- Handle HTTP 429 responses with exponential backoff

## Relevant Endpoints

### 1. Get Campaign Information

**Endpoint**: `GET /api/oauth2/v2/campaigns`

**Purpose**: Fetch basic campaign data including patron count

**Authentication**: `Authorization: Bearer <access_token>`

**Key Fields**:
```javascript
{
  "data": [{
    "attributes": {
      "patron_count": 1000,        // Number of active subscribers
      "is_monthly": true,
      "creation_name": "online communities",
      "patron_count": 2,
      // ... other fields
    },
    "id": "1234560",
    "type": "campaign"
  }]
}
```

**Example Request**:
```bash
curl --request GET \
  --url 'https://www.patreon.com/api/oauth2/v2/campaigns?fields[campaign]=patron_count,is_monthly,creation_name' \
  --header 'Authorization: Bearer YOUR_ACCESS_TOKEN'
```

### 2. Get Campaign Members (V2)

**Endpoint**: `GET /api/oauth2/v2/campaigns/{campaign_id}/members`

**Purpose**: Fetch all patrons/members for a campaign

**Authentication**: `Authorization: Bearer <access_token>`

**Pagination**: 
- Returns up to 1000 results per page
- Use `page[count]` and `page[cursor]` query parameters
- Check `meta.pagination.cursors.next` for additional pages

**Key Fields Per Member**:
```javascript
{
  "data": [{
    "attributes": {
      "currently_entitled_amount_cents": 400,  // Current pledge amount
      "patron_status": "active_patron",        // active_patron, declined_patron, former_patron
      "last_charge_date": "2018-04-01T21:28:06+00:00",
      "last_charge_status": "Paid",            // Paid, Declined, Deleted, Pending, etc.
      "campaign_lifetime_support_cents": 400,  // Total lifetime support
      "full_name": "Platform Team",
      // ... other fields
    },
    "id": "03ca69c3-ebea-4b9a-8fac-e4a837873254",
    "type": "member"
  }]
}
```

**Example Request**:
```bash
curl --request GET \
  --url 'https://www.patreon.com/api/oauth2/v2/campaigns/CAMPAIGN_ID/members?fields[member]=currently_entitled_amount_cents,patron_status,last_charge_date,last_charge_status&page[count]=1000' \
  --header 'Authorization: Bearer YOUR_ACCESS_TOKEN'
```

### 3. Get Campaign Pledges (V1)

**Endpoint**: `GET /oauth2/api/campaigns/{campaign_id}/pledges`

**Purpose**: Fetch all pledges for a campaign (V1 API)

**Base URL**: `https://api.patreon.com`

**Authentication**: `Authorization: Bearer <access_token>`

**Pagination**:
- Returns data in pages (typically 20 items per page)
- Use `links.next` field to get the next page URL
- Continue fetching until `links.next` is null

**Key Fields Per Pledge**:
```javascript
{
  "data": [{
    "attributes": {
      "amount_cents": 400,              // Pledge amount in cents
      "created_at": "2018-04-01T21:28:06+00:00",
      "declined_since": null,           // null if active, date if declined
      "patron_pays_fees": false
    },
    "id": "12345678",
    "type": "pledge"
  }],
  "links": {
    "next": "https://api.patreon.com/oauth2/api/campaigns/1234/pledges?page%5Bcursor%5D=abc123"
  }
}
```

**Example Request**:
```bash
curl --request GET \
  --url 'https://api.patreon.com/oauth2/api/campaigns/CAMPAIGN_ID/pledges' \
  --header 'Authorization: Bearer YOUR_ACCESS_TOKEN'
```

**Pagination Example**:
```ruby
def fetch_all_pledges(campaign_id)
  pledges = []
  endpoint = "/campaigns/#{campaign_id}/pledges"
  
  loop do
    response = make_request(endpoint)
    pledges.concat(response['data'])
    
    next_url = response.dig('links', 'next')
    break unless next_url
    
    # Extract path from next URL (remove base URL)
    endpoint = extract_path_from_url(next_url)
  end
  
  pledges
end
```

**Important Notes**:
- V1 pledges endpoint provides similar data to V2 members endpoint
- Use `declined_since` to filter active vs declined pledges
- Convert pledges to member format for consistency across API versions
- Pagination is required to fetch all pledges (can have 100+ pages for large campaigns)

## Data Mapping for Plugin Features

### 1. Number of Active Subscribers
**Source**: `GET /api/oauth2/v2/campaigns`
- Field: `patron_count`
- Direct value from campaign endpoint

### 2. Estimated Amount Per Month
**Source**: `GET /api/oauth2/v2/campaigns/{campaign_id}/members`
- Calculation: Sum all `currently_entitled_amount_cents` where `patron_status == "active_patron"`
- Convert from cents to dollars: `total_cents / 100`
- Filter out declined/former patrons

**Algorithm**:
```javascript
let totalCents = 0;
members.forEach(member => {
  if (member.attributes.patron_status === 'active_patron') {
    totalCents += member.attributes.currently_entitled_amount_cents;
  }
});
const monthlyEstimate = totalCents / 100; // Convert to dollars
```

### 3. Change from Last Month
**Source**: Calculated from monthly snapshots (not directly from API)
- Compares current month's live estimate against last completed month's snapshot
- Calculation: `current_estimate - last_month_snapshot.total_amount`
- **Note**: Since the API doesn't provide historical payment data, the plugin stores monthly snapshots in the database

**Algorithm**:
```javascript
// Get current month estimate from live API data
const currentEstimate = calculateMonthlyEstimate(members);

// Get last completed month's snapshot from database
const lastMonthSnapshot = await getLastCompletedMonthSnapshot(campaignId);

if (!lastMonthSnapshot) {
  return null; // Show "N/A" - no previous data
}

// Calculate change
const change = currentEstimate - lastMonthSnapshot.total_amount;

// Format for display
if (change > 0) {
  return `+$${change.toFixed(2)}`; // Green
} else if (change < 0) {
  return `-$${Math.abs(change).toFixed(2)}`; // Red
} else {
  return "$0.00"; // Neutral
}
```

**Display**:
- Positive change (growth): `+$23.80` in green
- Negative change (decline): `-$15.30` in red
- No previous data: `N/A` in gray (first month only)

## Important Notes

### Token Refresh
Access tokens expire after the duration specified in `expires_in` field. Implement token refresh:

```bash
POST https://www.patreon.com/api/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token
&refresh_token=<refresh_token>
&client_id=<client_id>
&client_secret=<client_secret>
```

### URL Encoding
Query parameters with brackets must be URL-encoded:
- `[` → `%5B`
- `]` → `%5D`

Example: `fields[campaign]` → `fields%5Bcampaign%5D`

### User-Agent Header
**Required**: Always include a User-Agent header or requests may be dropped with 403 response.

Example: `User-Agent: NetGamers-Discourse-Patreon-Plugin/1.0`

## Error Handling

### Common HTTP Status Codes

| Code | Meaning | Action |
|------|---------|--------|
| 400 | Bad Request | Check request syntax and parameters |
| 401 | Unauthorized | Refresh access token |
| 403 | Forbidden | Verify User-Agent header is set |
| 404 | Not Found | Check resource ID |
| 429 | Too Many Requests | Implement exponential backoff |
| 500 | Internal Server Error | Retry after delay |
| 503 | Service Unavailable | Retry after delay |

### Rate Limit Response
```json
{
  "errors": [{
    "code_name": "RequestThrottled",
    "detail": "You have made too many attempts. Please try again later.",
    "retry_after_seconds": 9,
    "status": "429"
  }]
}
```

## Caching Strategy

To minimize API calls and stay within rate limits:

1. **Campaign data**: Cache for 1 hour (patron count changes slowly)
2. **Member data**: Cache for 15-30 minutes (balances freshness vs. API limits)
3. Use database/Redis to store cached responses
4. Implement background job to refresh data periodically

## References

- Official Documentation: https://docs.patreon.com/
- Developer Portal: https://www.patreon.com/portal
- Developer Forum: https://www.patreondevelopers.com/
