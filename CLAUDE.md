# Claude Development Guidelines

High-level development approach for AI assistants working on the Discourse Patreon Donations plugin.

## Project Overview

A Discourse plugin that displays Patreon campaign statistics on a read-only page:
- Number of active subscribers
- Estimated monthly revenue
- Last month total donations

## Core Principles

### KISS (Keep It Simple, Stupid)
- Write straightforward, easy-to-understand code
- Avoid over-engineering solutions
- One function should do one thing well
- If a solution feels complicated, reconsider the approach

### DRY (Don't Repeat Yourself)
- Extract common logic into reusable methods
- Use shared utilities for repeated operations
- Centralize configuration and constants
- Create helper methods for repeated patterns

### Code Style
- NO emoji in code comments, documentation, or commit messages
- Use clear, descriptive variable and function names
- Write self-documenting code
- Add comments only to explain "why", not "what"

## Technology Stack

**Backend**: Ruby on Rails (Discourse framework), PostgreSQL, Redis, Sidekiq
**Frontend**: Ember.js, Handlebars templates, SCSS
**External API**: Patreon API v2, OAuth 2.0

## Implementation Approach

### Architecture
- Services for business logic (PatreonApiClient, PatreonStatsCalculator)
- Controllers for HTTP endpoints (PatreonStatsController)
- Background jobs for async operations (SyncPatreonData)
- Models for data persistence (PatreonCache)
- Routes and templates for UI

### Key Patterns
- **API Integration**: Centralized client with error handling and token refresh
- **Caching**: Redis-backed caching with configurable TTL
- **Background Jobs**: Sidekiq scheduled jobs for daily data sync
- **Error Handling**: Graceful degradation with user-friendly messages
- **Security**: Encrypted credential storage, rate limit respect

### Testing
- Manual testing on staging environment (no automated test suite)
- Verify changes by deploying to staging and checking behavior

## Version Control Strategy

### Commit Guidelines
- **Small**: One commit = one logical change (50-200 lines typically)
- **Focused**: Don't mix unrelated changes
- **Contextual**: Group related changes together
- **Reviewable**: Can be understood in 5-10 minutes

### Commit Message Format
```
Short summary (50 chars or less)

Detailed explanation if needed (wrap at 72 chars)
- Why this change is necessary
- What problem it solves
```

### When to Commit
Commit when you complete:
- A single service class or controller action
- A background job or model
- A set of related specs
- A configuration or documentation change

### Separate Commits For
- Refactoring vs. new features
- Bug fixes vs. feature work
- Formatting changes vs. logic changes
- File moves/renames

### Example Commit Sequence
```bash
git commit -m "Add PatreonApiClient service"
git commit -m "Add PatreonStatsCalculator service"
git commit -m "Add PatreonStatsController with show action"
git commit -m "Add Patreon stats Ember route and template"
git commit -m "Add SyncPatreonData background job"
git commit -m "Add specs for PatreonStatsCalculator"
git commit -m "Add Patreon configuration to settings.yml"
```

## Development Checklist

### Before Coding
1. Is this the simplest solution? (KISS)
2. Am I repeating code that already exists? (DRY)
3. Is this code easy to test?
4. Does this follow Discourse conventions?
5. Have I considered error cases?
6. Is this performant enough?
7. Are credentials handled securely?

### When Making Changes
1. Check existing code for similar patterns
2. Reuse existing utilities and helpers
3. Keep changes minimal and focused
4. Add tests for new functionality
5. Update documentation if needed
6. Consider performance implications
7. Verify error handling is robust

### Implementation Steps
1. Read existing code to understand patterns
2. Check if similar functionality exists
3. Design simple solution following KISS
4. Extract reusable components for DRY
5. Write tests first (TDD approach)
6. Implement feature
7. Test manually in development
8. Update documentation
9. Submit for review

## Key Considerations

**Security**
- Encrypt OAuth credentials in database
- Never log sensitive credentials
- Rotate tokens regularly
- Respect API rate limits

**Performance**
- Cache API responses (15-30 minutes)
- Use eager loading for database queries
- Fetch data in background jobs
- Implement exponential backoff for retries

**Error Handling**
- User-facing messages should be clear and actionable
- Log messages should include context for debugging
- Handle rate limits (429), auth errors (401), and network failures

## References

- [Detailed Implementation Plan](./CURRENT_IMPLEMENTATION_PLAN.md)
- [Patreon API Reference](./PATREON_API_REFERENCE.md)
- [Discourse Plugin Development](https://meta.discourse.org/t/beginners-guide-to-creating-discourse-plugins/30515)
- [Patreon API Documentation](https://docs.patreon.com/)

Remember: Simple, clear code that works is better than complex, clever code that's hard to maintain.
