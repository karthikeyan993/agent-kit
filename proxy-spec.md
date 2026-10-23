Below is a complete, system-ready Technical Architecture & Implementation Specification that you can copy directly into your coding agent or code-generation system. It defines all behavioral rules, edge cases, concurrency locks, header sanitation, and infrastructure constraints without prescribing boilerplate implementation code.

Technical Specification: Zendesk Advanced AI Reverse Proxy with Automated Secret Rotation

1. System Objective & Context

Build a low-latency, transparent HTTP Reverse Proxy running on Google Cloud Run (min-instances=1) in Python.

⚬ Upstream Caller: Zendesk Advanced AI (Chatbot API Integration).
⚬ Downstream Target: Internal/External API Platform ([https://api.platform.com](https://api.platform.com)).
⚬ Core Purpose: Accept incoming HTTP requests from Zendesk at https://<proxy-domain>/<arbitrary-path>, authenticate the caller, inject a dynamically rotated downstream credential fetched from GCP Secret Manager, forward the exact request (method, path, query parameters, headers, and body) to [https://api.platform.com/](https://api.platform.com/)<arbitrary-path>, and return the downstream response transparently to Zendesk.
⚬ Hard SLA Constraint: Zendesk Advanced AI enforces a hard 9-second timeout on external webhook/API calls. The proxy must complete all operations (including any secret refresh retries) within 8.0 seconds.

2. Runtime & Stack Requirements

⚬ Language: Python 3.12+
⚬ Compute Platform: Google Cloud Run Service (min-instances=1, cpu-boost enabled).
⚬ Web Framework: ASGI (FastAPI + uvicorn) OR WSGI (functions-framework + gunicorn), configured for persistent outbound connection pooling.
⚬ Core Dependencies:
  ⚬ httpx (if async ASGI) or requests (if sync WSGI) for persistent TCP/TLS connection pooling.
  ⚬ google-cloud-secret-manager for programmatic access to secret versions.
  ⚬ pydantic-settings (or os.environ) for strict environment variable validation on startup.

3. Environment Configuration Contract

The application must validate the presence of the following environment variables on startup and fail fast if required variables are missing:

Variable Name	Required	Default	Description
GCP_PROJECT_ID	Yes	—	Google Cloud Project ID hosting Secret Manager.
DOWNSTREAM_SECRET_ID	Yes	—	Secret Manager Secret ID holding the downstream API credential (rotated externally by CircleCI).
PROXY_AUTH_SECRET_ID	Yes	—	Secret Manager Secret ID (or env-injected secret) holding the shared inbound authentication token expected from Zendesk.
TARGET_BASE_URL	Yes	—	Base URL of the target platform (e.g., [https://api.platform.com](https://api.platform.com)). Must strip any trailing slash on initialization.
DOWNSTREAM_AUTH_HEADER	No	Authorization	Header name used by api.platform.com for authentication.
DOWNSTREAM_AUTH_SCHEME	No	Bearer	Prefix scheme for the auth header (e.g., Bearer <secret>). If set to empty string "", inject raw secret value without prefix.
SECRET_CACHE_TTL_SECONDS	No	300	Time-to-live (in seconds) for the in-memory downstream secret cache before proactive background refresh.
UPSTREAM_TIMEOUT_SECONDS	No	7.5	Maximum timeout (connect + read) for outbound calls to api.platform.com.

4. Functional Requirements

FR-1: Inbound Authentication (Zendesk -> Proxy)

1. Because Zendesk Advanced AI does not natively sign GCP IAM OIDC tokens, Cloud Run ingress is deployed with --allow-unauthenticated, and authentication is enforced at the application layer.
2. Every incoming request (except /health) must include a custom header: X-Proxy-Auth: <token>.
3. Compare the incoming X-Proxy-Auth header against the configured PROXY_AUTH_SECRET_ID value using a constant-time comparison (secrets.compare_digest) to prevent timing attacks.
4. If the header is missing or invalid, immediately return 401 Unauthorized with JSON body {"error": "Unauthorized proxy caller"} and do not forward the request.

FR-2: Transparent URL, Path, Query, and Body Forwarding

1. Catch-All Route: Expose a wildcard route matching /{path:path} that accepts GET, POST, PUT, PATCH, and DELETE.
2. Path Preservation:
  ⚬ Example: Incoming request POST [https://mydomain.com/api/software/getSoftware](https://mydomain.com/api/software/getSoftware) must map to POST [https://api.platform.com/api/software/getSoftware](https://api.platform.com/api/software/getSoftware).
  ⚬ Ensure leading/trailing slashes are normalized so double slashes (//api/...) are never generated.
3. Query Parameter Preservation:
  ⚬ Forward the exact raw query string (including repeated keys like ?id=1&id=2 and URL-encoded special characters) without mutating or dropping parameters.
  ⚬ Example: GET [https://mydomain.com/api/software/getSoftware?env=prod&version=2](https://mydomain.com/api/software/getSoftware?env=prod&version=2) -> GET [https://api.platform.com/api/software/getSoftware?env=prod&version=2](https://api.platform.com/api/software/getSoftware?env=prod&version=2).
4. Request Body Preservation:
  ⚬ Read the raw request body bytes (request.body()) and forward them unmodified for POST, PUT, PATCH, and DELETE requests (supporting JSON, form-urlencoded, or empty bodies).

FR-3: Header Sanitization & Injection

1. Inbound-to-Outbound Header Filtering:
  ⚬ Forward all incoming headers from Zendesk (such as Content-Type, Accept, User-Agent, custom correlation headers) EXCEPT:
    ⚬ Hop-by-hop headers: host, connection, keep-alive, transfer-encoding, te, trailer, upgrade, proxy-authorization, proxy-authenticate.
    ⚬ content-length (let the HTTP client recalculate it accurately).
    ⚬ x-proxy-auth (strip the proxy's own authentication header so it never leaks to api.platform.com).
    ⚬ authorization (strip any incoming Authorization header before injecting the downstream secret).
2. Downstream Auth Injection:
  ⚬ Inject the active secret fetched from the Secret Cache into DOWNSTREAM_AUTH_HEADER (e.g., Authorization: Bearer <secret>).
3. Outbound-to-Inbound Response Header Filtering:
  ⚬ Return the downstream HTTP status code, raw response bytes, and response headers back to Zendesk EXCEPT hop-by-hop headers and content-encoding / content-length (since the HTTP client automatically decompresses gzip/br payloads, forwarding the original content-encoding or content-length header will cause client parsing errors in Zendesk).

FR-4: Secret Caching & Zero-Downtime Rotation Handling

Because an external CircleCI pipeline rotates the secret in GCP Secret Manager asynchronously:

1. In-Memory Cache Manager:
  ⚬ Maintain an in-memory singleton (SecretCache) holding:
    ⚬ current_secret: str
    ⚬ last_fetched_monotonic: float
    ⚬ lock: asyncio.Lock (or threading.Lock)
2. Startup Pre-Warming:
  ⚬ During container startup, fetch projects/{GCP_PROJECT_ID}/secrets/{DOWNSTREAM_SECRET_ID}/versions/latest from GCP Secret Manager, strip trailing whitespace/newlines (.strip()), and store it in memory.
3. Warm Read Path (0 ms Latency):
  ⚬ If (now - last_fetched_monotonic) < SECRET_CACHE_TTL_SECONDS, return current_secret from memory immediately.
  ⚬ If TTL has expired, acquire lock, double-check the timestamp (to prevent a thundering herd of concurrent requests all calling Secret Manager), fetch :latest from Secret Manager, and update the cache.
4. Reactive 401/403 Self-Healing Retry (Critical for CircleCI Rotation):
  ⚬ If the downstream API (api.platform.com) responds with HTTP 401 Unauthorized or 403 Forbidden:
    1. Pass the used_secret into secret_cache.refresh_if_stale(failed_secret=used_secret).
    2. Inside the lock, if current_secret == failed_secret, force an immediate call to GCP Secret Manager for versions/latest regardless of TTL.
    3. Update current_secret and last_fetched_monotonic.
    4. Retry the downstream HTTP request exactly once using the newly fetched secret and return the retry response to Zendesk.
    5. If the newly fetched secret is identical to failed_secret (meaning CircleCI hasn't rotated the secret and the 401/403 is a genuine downstream permission error) OR if the retry also returns 401/403, return that 401/403 response directly to Zendesk without looping.

FR-5: Connection Pooling & Health Endpoint

1. Persistent Connection Pool:
  ⚬ Initialize a single global httpx.AsyncClient (or requests.Session with HTTPAdapter) at startup and reuse it across all requests. Do not instantiate a new HTTP client per request (avoids ~100–250 ms of repeated TCP + TLS handshakes to api.platform.com).
2. Health Check Route (GET /health):
  ⚬ Must precedes the wildcard /{path:path} route so it is not proxied to api.platform.com.
  ⚬ Does not require X-Proxy-Auth.
  ⚬ Returns 200 OK with {"status": "healthy"}.

5. Error Handling & Observability Specification

1. Downstream Timeout (httpx.TimeoutException):
  ⚬ Catch timeouts at 7.5s (before Zendesk's 9s disconnect) and return HTTP 504 Gateway Timeout with JSON body {"error": "Downstream API timed out"}.
2. Downstream Network/DNS Failure (httpx.RequestError):
  ⚬ Return HTTP 502 Bad Gateway with JSON body {"error": "Bad gateway communicating with target platform"}.
3. Structured JSON Logging (Cloud Logging compatible):
  ⚬ Log every request as a single structured JSON line to stdout containing: method, path, status_code, latency_ms, secret_refreshed_on_retry (boolean).
  ⚬ Security Guardrail: NEVER log request bodies, response bodies, query parameters (if they contain PII), X-Proxy-Auth, or Authorization headers.

6. Repository Directory Structure to Generate

Instruct your code generation tool to produce the following files:

zendesk-api-proxy/
├── app/
│   ├── __init__.py
│   ├── main.py            # FastAPI app, lifespan hook, /health, and /{path:path} proxy route
│   ├── config.py          # Environment variable validation
│   ├── secret_manager.py  # SecretCache class with TTL, asyncio.Lock, and force-refresh logic
│   └── proxy_client.py    # Header sanitization and httpx request + 401/403 retry logic
├── tests/
│   └── test_proxy.py      # Unit tests covering path/query forwarding, header stripping, and 401 retry
├── Dockerfile             # python:3.12-slim production image running uvicorn
├── requirements.txt       # Pinned production dependencies
└── README.md              # gcloud run deploy command and IAM role instructions


7. Acceptance Criteria Checklist (For Code Verification)

Ensure the generated codebase passes these 5 verification scenarios:

⚬ [ ] Scenario 1 (Path + Query + Body): Calling POST /api/software/getSoftware?dept=eng with a JSON body forwards the exact path, query string ?dept=eng, and JSON bytes to [https://api.platform.com/api/software/getSoftware?dept=eng](https://api.platform.com/api/software/getSoftware?dept=eng).
⚬ [ ] Scenario 2 (Unauthorized Caller): Calling any endpoint without a valid X-Proxy-Auth header returns 401 immediately and makes zero outbound calls.
⚬ [ ] Scenario 3 (CircleCI Rotation Recovery): When api.platform.com returns 401 because CircleCI just rotated the secret, the proxy fetches :latest from Secret Manager once, retries the request with the new key, and returns 200 OK to Zendesk in a single HTTP cycle.
⚬ [ ] Scenario 4 (Header Hygiene): X-Proxy-Auth is stripped before reaching api.platform.com, and content-encoding is stripped before returning to Zendesk.
⚬ [ ] Scenario 5 (Secret Whitespace Safety): Secret values read from Secret Manager have trailing \n or \r stripped before being placed into the HTTP Authorization header.
