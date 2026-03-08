# Patreon API Reference

This document outlines the Patreon API v2 endpoints used by this plugin.

## API Version

The plugin uses the **Patreon API v2** exclusively.

- Base URL: `https://www.patreon.com/api/oauth2/v2`
- Full JSON:API spec compliance

## Authentication

- **OAuth 2.0** required
- Must register a client at: https://www.patreon.com/portal/registration/register-clients
- Select **API Version 2** when creating the client
- Credentials needed:
  - Client ID
  - Client Secret
  - Creator's Access Token
  - Creator's Refresh Token

These are stored in the plugin's own settings, separate from any other Patreon plugin.

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
```json
{
  "data": [{
    "attributes": {
      "patron_count": 138,
      "is_monthly": true,
      "creation_name": "online communities"
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

**Note**: `patron_count` includes both paid and free members. To get only paying patrons, count members with `patron_status == "active_patron"` from the members endpoint.

### 2. Get Campaign Members

**Endpoint**: `GET /api/oauth2/v2/campaigns/{campaign_id}/members`

**Purpose**: Fetch all patrons/members for a campaign

**Authentication**: `Authorization: Bearer <access_token>`

**Pagination**:
- Returns up to 1000 results per page
- Use `page[count]` and `page[cursor]` query parameters
- Check `meta.pagination.cursors.next` for additional pages

**Key Fields Per Member**:
```json
{
  "data": [{
    "attributes": {
      "currently_entitled_amount_cents": 400,
      "patron_status": "active_patron",
      "last_charge_date": "2018-04-01T21:28:06+00:00",
      "last_charge_status": "Paid"
    },
    "id": "03ca69c3-ebea-4b9a-8fac-e4a837873254",
    "type": "member"
  }]
}
```

**Patron Status Values**:
- `active_patron` - Currently paying patron
- `declined_patron` - Payment declined
- `former_patron` - Cancelled patron
- `null` - Free member (no payment)

**Example Request**:
```bash
curl --request GET \
  --url 'https://www.patreon.com/api/oauth2/v2/campaigns/CAMPAIGN_ID/members?fields[member]=currently_entitled_amount_cents,patron_status,last_charge_date,last_charge_status&page[count]=1000' \
  --header 'Authorization: Bearer YOUR_ACCESS_TOKEN'
```

## Data Mapping for Plugin Features

### 1. Number of Active Patrons
**Source**: `GET /api/oauth2/v2/campaigns/{campaign_id}/members`
- Count members where `patron_status == "active_patron"`
- This gives the number of currently paying patrons

### 2. Estimated Amount Per Month
**Source**: `GET /api/oauth2/v2/campaigns/{campaign_id}/members`
- Calculation: Sum all `currently_entitled_amount_cents` where `patron_status == "active_patron"`
- Convert from cents to dollars: `total_cents / 100`
- Filter out declined/former/free members

**Algorithm**:
```javascript
let totalCents = 0;
members.forEach(member => {
  if (member.attributes.patron_status === 'active_patron') {
    totalCents += member.attributes.currently_entitled_amount_cents;
  }
});
const monthlyEstimate = totalCents / 100;
```

### 3. Change from Last Month
**Source**: Calculated from monthly snapshots (not directly from API)
- Compares current month's live estimate against last completed month's snapshot
- Calculation: `current_estimate - last_month_snapshot.total_amount`
- Since the API doesn't provide historical payment data, the plugin stores monthly snapshots in the database

### 4. Patron Changes (Joined/Left)
**Source**: Calculated by diffing stored member ID arrays between consecutive snapshots
- Each snapshot stores the list of active member IDs
- Joined = IDs in current snapshot not in previous snapshot
- Left = IDs in previous snapshot not in current snapshot

## Important Notes

### Token Refresh
Access tokens expire after the duration specified in `expires_in` field. The plugin refreshes tokens automatically:

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
- `[` -> `%5B`
- `]` -> `%5D`

Example: `fields[campaign]` -> `fields%5Bcampaign%5D`

### User-Agent Header
**Required**: Always include a User-Agent header or requests may be dropped with 403 response.

Example: `User-Agent: Discourse-Patreon-Plugin/discourse-patreon-donations`

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
