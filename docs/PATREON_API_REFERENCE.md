# Patreon API Reference

This document outlines the Patreon API v2 endpoints used by this plugin.

## API Version

**Use API v2** - API v1 is deprecated and will be removed soon.

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

### 2. Get Campaign Members

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

### 3. Last Month Total Donation Amount
**Source**: `GET /api/oauth2/v2/campaigns/{campaign_id}/members`
- Filter members where:
  - `last_charge_status === "Paid"`
  - `last_charge_date` is within the previous calendar month
- Sum `currently_entitled_amount_cents` for matching members
- **Note**: This is an approximation since the API doesn't provide historical payment data directly

**Algorithm**:
```javascript
const lastMonth = new Date();
lastMonth.setMonth(lastMonth.getMonth() - 1);
const startOfLastMonth = new Date(lastMonth.getFullYear(), lastMonth.getMonth(), 1);
const endOfLastMonth = new Date(lastMonth.getFullYear(), lastMonth.getMonth() + 1, 0);

let lastMonthTotal = 0;
members.forEach(member => {
  const chargeDate = new Date(member.attributes.last_charge_date);
  if (
    member.attributes.last_charge_status === 'Paid' &&
    chargeDate >= startOfLastMonth &&
    chargeDate <= endOfLastMonth
  ) {
    lastMonthTotal += member.attributes.currently_entitled_amount_cents;
  }
});
const lastMonthDollars = lastMonthTotal / 100;
```

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
