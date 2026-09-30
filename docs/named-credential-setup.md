# Named Credential setup (no secrets in source control)

The Apex client calls `callout:Financing_API`. Create these in **Setup** in your own org; never commit real endpoints, client IDs or secrets.

1. **External Credential** – Setup → Named Credentials → External Credentials → New
   - Label / Name: `Financing API` / `Financing_API_Auth`
   - Authentication Protocol: *OAuth 2.0*, Flow: *Client Credentials with Client Secret*
   - Identity Provider URL: the provider's token URL (for the local mock: not required – use *No Authentication*)
   - Add a **Principal** (Named Principal) and enter the client ID / secret there. They are stored encrypted by Salesforce.
2. **Named Credential** – New
   - Label / Name: `Financing API` / `Financing_API`
   - URL: provider base URL (for the local mock exposed through a tunnel, e.g. `https://<your-tunnel>.example`)
   - External Credential: `Financing_API_Auth`
   - Generate Authorization Header: checked
3. **Permission set** – grant *External Credential Principal Access* for `Financing_API_Auth` to the integration user only.

Apex tests use `HttpCalloutMock`, so they pass without any of the above.
