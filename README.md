# MiniSERP

A Rails 8 API-only service that turns a search-results HTML page into clean, structured JSON —
in the spirit of SerpApi. It parses organic results with Nokogiri, caches them in MongoDB via
Mongoid, detects anti-bot interstitials, and sits behind API-key auth and per-key rate limiting.

```text
GET /search?q=ruby+on+rails&engine=google
X-API-Key: dev-key
```

```json
{
  "query": "ruby on rails",
  "engine": "google",
  "cached": false,
  "results_count": 3,
  "results": [
    {
      "position": 1,
      "title": "Ruby on Rails — A web-app framework",
      "link": "https://rubyonrails.org/",
      "snippet": "Ruby on Rails is a full-stack framework. It ships with all the tools needed..."
    }
  ]
}
```

> **On live scraping.** MiniSERP ships in **fixture mode** by default: it reads saved HTML from
> `spec/fixtures/html/` and makes **no network requests at all**. Scraping Google or Bing live
> violates their Terms of Service and gets IPs flagged, and none of the interesting engineering
> here needs a real request to exercise. A live HTTP transport exists behind
> `MINISERP_SOURCE=live` for use against a source you are permitted to scrape.

---

## Stack

| Concern       | Choice                                     |
| ------------- | ------------------------------------------ |
| Framework     | Rails 8.1, `--api` mode                    |
| Datastore     | MongoDB via **Mongoid** (no Active Record) |
| HTML parsing  | Nokogiri                                   |
| HTTP          | HTTParty                                   |
| Rate limiting | rack-attack                                |
| Tests         | RSpec + WebMock, fixture-driven            |

---

## Setup

### 1. Prerequisites

- Ruby 3.3+
- MongoDB 6/7 running locally

Start MongoDB however you prefer — Docker is the quickest:

```bash
docker run -d --name miniserp-mongo -p 27017:27017 --restart unless-stopped mongo:7
```

### 2. Install dependencies

```bash
bundle install
```

### 3. Configure environment

```bash
cp .env.example .env
```

`dotenv-rails` loads `.env` in development and test. Every variable has a working default, so the
app runs with no `.env` at all in development (the API key defaults to `dev-key`).

| Variable                         | Default                                         | Purpose                                    |
| -------------------------------- | ----------------------------------------------- | ------------------------------------------ |
| `MINISERP_API_KEYS`              | `dev-key` in dev/test, **empty in production**  | Comma-separated valid `X-API-Key` values   |
| `MINISERP_SOURCE`                | `fixture`                                       | `fixture` (offline) or `live` (real HTTP)  |
| `MINISERP_FIXTURE`               | —                                               | Force one fixture file regardless of query |
| `MINISERP_CACHE_TTL_HOURS`       | `6`                                             | Cache freshness window; `0` disables it    |
| `MINISERP_RATE_LIMIT_PER_MINUTE` | `30`                                            | Requests per minute per API key            |
| `MINISERP_HTTP_TIMEOUT`          | `8`                                             | Per-request timeout, seconds               |
| `MINISERP_HTTP_RETRY_BACKOFF`    | `0.5`                                           | Backoff before the single retry            |
| `MINISERP_MAX_RESULTS`           | `20`                                            | Max organic results returned               |
| `MONGODB_URI`                    | `mongodb://localhost:27017/miniserp_development` | Mongoid connection                        |
| `MONGODB_URI_TEST`               | `mongodb://localhost:27017/miniserp_test`       | Mongoid connection for the suite           |

**Production has no default API key.** `MINISERP_API_KEYS` must be set or every request 401s.

### 4. Run

```bash
bin/rails server
```

### 5. Test

```bash
bundle exec rspec
```

```text
85 examples, 0 failures
```

The suite never touches the network: `WebMock.disable_net_connect!` is on, and `rails_helper`
forces `MINISERP_SOURCE=fixture` before the app boots, so a stray `.env` cannot leak a live
request into CI.

---

## API

Authentication is required on every endpoint except `/` and `/up`:

```text
X-API-Key: <your key>
```

| Method | Path              | Description                             |
| ------ | ----------------- | --------------------------------------- |
| `GET`  | `/search`         | Run a search (unversioned alias)        |
| `GET`  | `/api/v1/search`  | Same endpoint, version-pinned           |
| `GET`  | `/api/v1/engines` | Supported engines and the active source |
| `GET`  | `/`               | Service description (no auth)           |
| `GET`  | `/up`             | Liveness probe (no auth)                |

### `GET /search`

| Param     | Required | Default  | Notes                          |
| --------- | -------- | -------- | ------------------------------ |
| `q`       | yes      | —        | The search query               |
| `engine`  | no       | `google` | Currently `google`             |
| `refresh` | no       | `false`  | Bypass the cache and re-scrape |

### Response

| Field               | Meaning                                            |
| ------------------- | -------------------------------------------------- |
| `query`, `engine`   | Echo of what was searched                          |
| `cached`            | `true` when served from MongoDB                    |
| `cache_age_seconds` | Age of the cached document (`0` on a fresh scrape) |
| `scraped_at`        | ISO-8601 UTC timestamp of the underlying scrape    |
| `results_count`     | Number of organic results                          |
| `no_results`        | `true` when the engine explicitly matched nothing  |
| `results[]`         | `position`, `title`, `link`, `snippet`             |

### Errors

Every error uses the same envelope: `{"error": "<code>", "message": "<human readable>"}`.

| HTTP | `error`               | When                                                    |
| ---- | --------------------- | ------------------------------------------------------- |
| 400  | `invalid_query`       | `q` missing or blank                                    |
| 400  | `unsupported_engine`  | `engine` is not one we parse                            |
| 401  | `unauthorized`        | `X-API-Key` missing or wrong                            |
| 403  | `blocked`             | The engine served a CAPTCHA / "unusual traffic" page    |
| 429  | `rate_limit_exceeded` | Per-key budget spent (includes `Retry-After`)           |
| 502  | `request_failed`      | Non-2xx or connection failure that survived the retry   |
| 502  | `parse_failed`        | 200 OK, but no known layout matched — selectors are stale |
| 504  | `timeout`             | Both the request and its retry timed out                |

---

## Example requests

In fixture mode the query routes to a saved page, so every path below is reproducible offline:
`captcha` → block page, `zznomatch` → no-results page, `nokogiri` → the newer Google layout,
anything else → the standard results page.

**Successful search**

```bash
curl -s -H "X-API-Key: dev-key" \
  "http://localhost:3000/search?q=ruby+on+rails"
```

```json
{
  "query": "ruby on rails",
  "engine": "google",
  "cached": false,
  "cache_age_seconds": 0,
  "scraped_at": "2026-08-24T10:05:17Z",
  "results_count": 3,
  "no_results": false,
  "results": [
    {
      "position": 1,
      "title": "Ruby on Rails — A web-app framework",
      "link": "https://rubyonrails.org/",
      "snippet": "Ruby on Rails is a full-stack framework. It ships with all the tools needed to build amazing web apps on both the front and back end."
    },
    {
      "position": 2,
      "title": "Ruby on Rails Guides",
      "link": "https://guides.rubyonrails.org/",
      "snippet": "These guides are designed to make you immediately productive with Rails, and to help you understand how all of the pieces fit together."
    },
    {
      "position": 3,
      "title": "rails/rails: Ruby on Rails - GitHub",
      "link": "https://github.com/rails/rails",
      "snippet": "Ruby on Rails is a full-stack web framework optimized for programmer happiness and sustainable productivity."
    }
  ]
}
```

**Cache hit** — repeat the same request; only the envelope changes.

```json
{ "query": "ruby on rails", "cached": true, "cache_age_seconds": 41, "results_count": 3 }
```

**Blocked** (`HTTP 403`)

```bash
curl -s -H "X-API-Key: dev-key" "http://localhost:3000/search?q=captcha"
```

```json
{ "error": "blocked", "message": "google served an anti-bot page instead of results" }
```

**Empty result set** (`HTTP 200` — an empty search is a valid answer, not an error)

```bash
curl -s -H "X-API-Key: dev-key" "http://localhost:3000/search?q=zznomatch"
```

```json
{
  "query": "zznomatch",
  "engine": "google",
  "cached": false,
  "results_count": 0,
  "no_results": true,
  "results": []
}
```

**Missing API key** (`HTTP 401`)

```bash
curl -s "http://localhost:3000/search?q=ruby+on+rails"
```

```json
{ "error": "unauthorized", "message": "missing X-API-Key header" }
```

**Rate limited** (`HTTP 429`)

```json
{
  "error": "rate_limit_exceeded",
  "message": "too many requests: limit is 30 per 60 seconds",
  "retry_after": 27
}
```

---

## Architecture

```text
app/
├── controllers/
│   ├── application_controller.rb          ErrorHandling only
│   ├── meta_controller.rb                 GET /  (unauthenticated)
│   ├── concerns/
│   │   ├── api_key_authentication.rb      X-API-Key, constant-time compare
│   │   └── error_handling.rb              exceptions -> JSON envelope
│   └── api/v1/
│       ├── base_controller.rb             authenticated base
│       ├── searches_controller.rb         GET /search  (one thin action)
│       └── engines_controller.rb          GET /api/v1/engines
├── models/
│   └── search_result.rb                   Mongoid doc + cache lookup
├── serializers/
│   └── search_response_serializer.rb      the public JSON shape
└── services/
    ├── scraper_service.rb                 orchestration: cache -> fetch -> parse -> cache
    └── scraper/
        ├── client.rb                      live HTTP, timeout + single retry
        ├── fixture_client.rb              offline transport (default)
        ├── response.rb                    transport-agnostic value object
        ├── registry.rb                    ?engine= -> parser
        ├── errors.rb                      each error carries its code + HTTP status
        └── engines/
            ├── base.rb                    the engine contract
            └── google.rb                  layered selectors + structural fallback
```

Three ideas hold this together:

**The controller does nothing.** `SearchesController#show` calls one service and renders one
serializer. Authentication is a concern, error-to-HTTP mapping is a concern, and each error class
knows its own `code` and `http_status` — so there is not a single `rescue` or `case` statement in
a controller action.

**Transport is injected, not chosen.** `ScraperService` never knows whether bytes came from
HTTParty or from disk; both satisfy the same `#get(url) -> Scraper::Response` contract. That is
what lets the whole suite drive real parsing code with zero network, and what makes "never hit
Google by accident" a single environment variable rather than a habit.

**Parsers are pluggable.** Adding Bing is a `Scraper::Engines::Bing` plus one line in the registry.

### Caching

Every scrape inserts a new `SearchResult` document rather than updating one, so the collection
doubles as an audit log of what the engine returned and when. Reads take the newest document
whose `scraped_at` falls inside `MINISERP_CACHE_TTL_HOURS`, indexed on
`{ engine: 1, query_key: 1, scraped_at: -1 }`.

`query_key` normalises whitespace only — `"ruby  on rails"` and `"ruby on rails"` are one cache
entry, but `"Ruby on Rails"` is a separate one. Case is preserved deliberately: the cache should
not decide that two queries are the same when the engine might not agree.

Empty result sets are cached too. A query that genuinely matches nothing will still match nothing
in five minutes, and re-scraping it is exactly the kind of pointless traffic that gets a scraper
blocked. A Mongo outage degrades to a cache miss rather than a 500 — both the read and the write
are guarded.

---

## Engineering notes: the day `div.g` stopped existing

The first version of the Google parser was one line of Nokogiri, and it was beautiful:

```ruby
document.css("div.g").map { |result| ... }
```

`div.g` had been the organic-result wrapper on Google for years. Every scraping tutorial uses it.
It worked perfectly against the page I had saved, gave me three clean results, and I moved on.

Then I saved a **second** page — same engine, different query, captured a little differently — and
the parser returned `[]`. Not an error. Not a crash. An empty array and `HTTP 200`, which is the
worst possible failure mode for a scraper, because it looks exactly like "this query had no
results."

`grep -c 'class="g"'` on the new page: **zero**. The wrapper was now `div.MjjYud`, with the inner
structure rearranged and the obfuscated class names (`kb0PBd`, `N54PNb`) rotated. Google ships
these changes continuously and without warning; there is no versioned DOM to code against.

The fix was to stop believing in any single selector.

**1. An ordered list of container strategies, not one selector.** The parser now walks a list and
takes the first that yields usable blocks:

```ruby
CONTAINER_STRATEGIES = [
  "#rso div.g",
  "#search div.g",
  "#rso div.MjjYud",
  "#search div.MjjYud"
].freeze
```

**2. A structural fallback that uses no class names at all.** When every strategy misses, the
parser stops looking at classes and looks at *shape*: find each `<h3>`, walk up to the nearest
`<div>` that also contains a link, and treat that as the result block. An organic result is
fundamentally "a heading that is a link, with text under it" — that shape has survived every
redesign, even as the class names churned. There is a test that feeds the parser a container
called `div.totally-new-class` and asserts it still extracts the result.

**3. "Usable" is a real filter.** A container only counts if it holds both an `<h3>` and an
`a[href]`. This dropped the "People also ask" block out of the results for free — it lives in a
`div.g` too, but has no `<h3>`. Nested matches are de-duplicated by preferring the innermost
container, since `div.MjjYud` sometimes wraps `div.g`.

**4. Empty must never be silent.** The most important change was not a selector at all. The parser
now distinguishes two cases that used to look identical:

- Google explicitly said *"did not match any documents"* → return `[]`, respond `200`,
  `"no_results": true`. This is a real answer.
- No known layout matched and Google said nothing of the sort → raise
  `Scraper::Errors::ParseFailed` → respond `502`, `"error": "parse_failed"`. This is **my bug**,
  and it should page me, not quietly hand the caller an empty array.

That distinction is the difference between an API you can trust and one that lies when it breaks.

### A second, smaller trap: the links were not links

With the containers fixed, result #2 came back with a `link` of:

```text
/url?q=https://guides.rubyonrails.org/&sa=U&ved=2ahUKEwj&usg=AOvVaw0
```

Because we send no JavaScript and a plain `User-Agent`, Google serves the no-JS variant of the
page, where every result href is wrapped in its `/url?q=` redirect tracker. Half the results had
real hrefs and half had wrapped ones, in the same page, depending on which layout the block used.
`normalize_link` now unwraps `/url?q=` (and `?url=`), rejects anything that is not `http(s)`, and
drops Google's own navigation links — so callers get a URL they can actually fetch.

### What I would do differently at real scale

The layered-selector approach buys resilience, not immortality. In production I would add a
canary: scrape a handful of known-stable queries on a schedule and alert when `results_count`
drops to zero across all of them at once. A parser that fails loudly the day the DOM changes is
worth more than one that squeezes two extra selectors out of the current layout.

---

## Adding an engine

1. Subclass `Scraper::Engines::Base` and implement `.key`, `#search_url`, `#parse`, and —
   importantly — `#blocked?` and `#no_results?`.
2. Register it in `Scraper::Registry::ENGINES`.
3. Save a results page to `spec/fixtures/html/` and add a parser spec.

Nothing above the engine layer changes.

## Production notes

- **Rate-limit store.** `Rack::Attack.cache.store` is an in-process `MemoryStore`, which is
  correct for one Puma process and for tests. Multi-process or multi-dyno deploys need a shared
  store — point it at Redis; nothing else in that initializer changes.
- **API keys** are compared with `ActiveSupport::SecurityUtils.secure_compare`, so a wrong key
  cannot be discovered by timing the 401.
- **Retries are deliberately conservative**: one retry, only for timeouts, connection resets, 429
  and 5xx. A 403 or a CAPTCHA is never retried — hammering an engine that just blocked you is how
  a soft block becomes a hard one.
