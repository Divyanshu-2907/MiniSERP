# MiniSERP

**A Rails 8 API-only service that turns a search-results HTML page into clean, structured JSON** —
in the spirit of SerpApi. It parses organic results with Nokogiri, caches them in MongoDB via
Mongoid, detects anti-bot interstitials, and sits behind API-key auth and per-key rate limiting.

`Ruby 3.3` · `Rails 8.1` · `MongoDB Atlas` · `Nokogiri` · `RSpec — 97 examples, 0 failures`

**Live:** <https://miniserp.onrender.com>

## Try it right now

```bash
curl -s -H "X-API-Key: demo-key" \
  "https://miniserp.onrender.com/search?q=ruby+on+rails"
```

```json
{
  "query": "ruby on rails",
  "engine": "google",
  "cached": false,
  "cache_age_seconds": 0,
  "scraped_at": "2026-08-24T11:44:29Z",
  "results_count": 3,
  "no_results": false,
  "results": [
    {
      "position": 1,
      "title": "Ruby on Rails — A web-app framework",
      "link": "https://rubyonrails.org/",
      "snippet": "Ruby on Rails is a full-stack framework. It ships with all the tools needed to build amazing web apps on both the front and back end."
    }
  ]
}
```

Run the same command twice — the second response comes back with `"cached": true` and a
`cache_age_seconds` counter, served from MongoDB instead of re-parsing.

Other paths worth poking at:

```bash
curl -H "X-API-Key: demo-key" "https://miniserp.onrender.com/search?q=captcha"    # 403 blocked
curl -H "X-API-Key: demo-key" "https://miniserp.onrender.com/search?q=zznomatch"  # 200, no_results
curl -H "X-API-Key: demo-key" "https://miniserp.onrender.com/search?q=nokogiri"   # newer DOM layout
curl "https://miniserp.onrender.com/search?q=ruby"                                # 401 unauthorized
```

> **The free instance sleeps after 15 minutes of inactivity**, so the first request may take
> ~50 seconds while it wakes. Subsequent requests are fast.

---

## Why it doesn't scrape Google

MiniSERP ships in **fixture mode** by default: it reads saved HTML from `spec/fixtures/html/` and
makes **no network requests at all**.

Scraping Google or Bing live violates their Terms of Service and gets IPs flagged — and none of
the engineering that makes this project interesting needs a real request to exercise. Parsing
resilience, cache semantics, block detection, retry policy and error mapping are all fully
exercised against saved pages, deterministically, in 4 seconds.

A live HTTP transport (`Scraper::Client`) is implemented and tested, and switches on with
`MINISERP_SOURCE=live` for use against a source you are permitted to scrape. Choosing that
transport is a single config value, not a code change — see [Architecture](#architecture).

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
| Deployment    | Render (free tier) + MongoDB Atlas (M0)    |

---

## Local setup

### 1. Prerequisites

- Ruby 3.3+
- MongoDB 6/7

```bash
docker run -d --name miniserp-mongo -p 27017:27017 --restart unless-stopped mongo:7
```

### 2. Install and configure

```bash
bundle install
cp .env.example .env
```

`dotenv-rails` loads `.env` in development and test. Every variable has a working default, so the
app runs with no `.env` at all locally (the API key defaults to `dev-key`).

| Variable                         | Default                                          | Purpose                                    |
| -------------------------------- | ------------------------------------------------ | ------------------------------------------ |
| `MINISERP_API_KEYS`              | `dev-key` in dev/test, **empty in production**   | Comma-separated valid `X-API-Key` values   |
| `MINISERP_SOURCE`                | `fixture`                                        | `fixture` (offline) or `live` (real HTTP)  |
| `MINISERP_FIXTURE`               | —                                                | Force one fixture file regardless of query |
| `MINISERP_CACHE_TTL_HOURS`       | `6`                                              | Cache freshness window; `0` disables it    |
| `MINISERP_RATE_LIMIT_PER_MINUTE` | `30`                                             | Requests per minute per API key            |
| `MINISERP_HTTP_TIMEOUT`          | `8`                                              | Per-request timeout, seconds               |
| `MINISERP_HTTP_RETRY_BACKOFF`    | `0.5`                                            | Backoff before the single retry            |
| `MINISERP_MAX_RESULTS`           | `20`                                             | Max organic results returned               |
| `MONGODB_URI`                    | `mongodb://localhost:27017/miniserp_development` | Mongoid connection                         |
| `MONGODB_URI_TEST`               | `mongodb://localhost:27017/miniserp_test`        | Mongoid connection for the suite           |

**Production has no default API key.** `MINISERP_API_KEYS` must be set or every request 401s.

### 3. Run and test

```bash
bin/rails server
bundle exec rspec
```

```text
97 examples, 0 failures
```

The suite never touches the network: `WebMock.disable_net_connect!` is on, and `rails_helper`
forces `MINISERP_SOURCE=fixture` **before the app boots**, so a stray `.env` cannot leak a live
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

### Parameters

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

| HTTP | `error`               | When                                                      |
| ---- | --------------------- | --------------------------------------------------------- |
| 400  | `invalid_query`       | `q` missing or blank                                      |
| 400  | `unsupported_engine`  | `engine` is not one we parse                              |
| 401  | `unauthorized`        | `X-API-Key` missing or wrong                              |
| 403  | `blocked`             | The engine served a CAPTCHA / "unusual traffic" page      |
| 429  | `rate_limit_exceeded` | Per-key budget spent (includes `Retry-After`)             |
| 502  | `request_failed`      | Non-2xx or connection failure that survived the retry     |
| 502  | `parse_failed`        | 200 OK, but no known layout matched — selectors are stale |
| 504  | `timeout`             | Both the request and its retry timed out                  |

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

Every scrape **inserts** a new `SearchResult` rather than updating one, so the collection doubles
as an audit log of what the engine returned and when. Reads take the newest document whose
`scraped_at` falls inside `MINISERP_CACHE_TTL_HOURS`, indexed on
`{ engine: 1, query_key: 1, scraped_at: -1 }`.

`query_key` normalises whitespace only — `"ruby  on rails"` and `"ruby on rails"` are one cache
entry, but `"Ruby on Rails"` is a separate one. Case is preserved deliberately: the cache should
not decide that two queries are the same when the engine might not agree.

Empty result sets are cached too. A query that genuinely matches nothing will still match nothing
in five minutes, and re-scraping it is exactly the kind of pointless traffic that gets a scraper
blocked.

---

## Engineering notes

Three problems that actually happened while building and shipping this. The second and third only
appeared in production — which is the interesting part.

### 1. The day `div.g` stopped existing

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

**An ordered list of container strategies.** The parser walks a list and takes the first that
yields usable blocks:

```ruby
CONTAINER_STRATEGIES = [
  "#rso div.g",
  "#search div.g",
  "#rso div.MjjYud",
  "#search div.MjjYud"
].freeze
```

**A structural fallback that uses no class names at all.** When every strategy misses, the parser
stops looking at classes and looks at *shape*: find each `<h3>`, walk up to the nearest `<div>`
that also contains a link, and treat that as the result block. An organic result is fundamentally
"a heading that is a link, with text under it" — that shape has survived every redesign. There is
a test that feeds the parser a container called `div.totally-new-class` and asserts it still
extracts the result.

**"Usable" is a real filter.** A container only counts if it holds both an `<h3>` and an
`a[href]`. This dropped the "People also ask" block out of the results for free — it lives in a
`div.g` too, but has no `<h3>`.

**Empty must never be silent.** The most important change was not a selector at all. The parser
now distinguishes two cases that used to look identical:

- Google explicitly said *"did not match any documents"* → return `[]`, respond `200`,
  `"no_results": true`. This is a real answer.
- No known layout matched and Google said nothing of the sort → raise
  `Scraper::Errors::ParseFailed` → respond `502`. This is **my bug**, and it should page me, not
  quietly hand the caller an empty array.

That distinction is the difference between an API you can trust and one that lies when it breaks.

A smaller trap fell out of the same work: because we send no JavaScript, Google serves the no-JS
page, where hrefs are wrapped in its `/url?q=...` redirect tracker. Half the results had real
hrefs and half were wrapped, *in the same page*, depending on the layout of the block.
`normalize_link` unwraps them, rejects anything that isn't `http(s)`, and drops Google's own
navigation links.

### 2. 97 passing tests, and every error was a 500

The app deployed cleanly. Then every single `/search` request returned:

```json
{"error":"internal_error","message":"something went wrong on our side"}
```

Including `/search` with no `q`, which should be a `400`, and which never touches the network or
the database. Meanwhile `/api/v1/engines` was fine. The whole test suite was green.

The cause was one line:

```ruby
rescue_from Scraper::Errors::Base, with: :render_scraper_error
rescue_from StandardError, with: :render_unexpected_error unless Rails.env.local?
```

Two defects, stacked.

**Rails matches `rescue_from` handlers in reverse registration order** — the *last* matching
handler registered wins. Registering `StandardError` last means it swallows every specific handler
above it. Deliberate `400`s and `403`s all came out as `500`s.

**And the tests could never have caught it.** That `unless Rails.env.local?` meant the catch-all
was only registered *outside* dev and test. The suite exercised a genuinely different handler
chain than production ran. 97 green examples proved nothing about the code path that actually
shipped.

The fix registers the broadest handler **first**, and registers it in *every* environment — it
simply re-raises when local, so development still gets real backtraces:

```ruby
rescue_from StandardError, with: :render_unexpected_error   # broadest FIRST
rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
rescue_from Scraper::Errors::Base, with: :render_scraper_error

def render_unexpected_error(error)
  raise error if Rails.env.local?
  # ... render the generic 500 envelope
end
```

Now all three environments run one identical chain. `spec/requests/error_handling_spec.rb` stubs
`Rails.env.local?` to `false` and asserts production behaviour directly — and I verified it fails
against the old ordering before keeping it.

The lesson isn't "know that `rescue_from` is reverse-ordered." It's that **a conditional that
makes production behave differently from your tests will eventually hide a bug in the half you
can't see.**

### 3. The database error that wasn't a database error

With the error mapping fixed, the real exception finally surfaced in the logs:

```text
Mongo::Auth::Unauthorized: bad auth : Authentication failed
  (auth source: miniserp_production)
```

Two separate problems in one line.

**The config problem.** MongoDB Atlas stores database users in the `admin` database. When your
connection string names a database, the driver defaults the auth source to *that* database unless
told otherwise. The user simply doesn't exist there. It had worked locally because Atlas's SRV
`TXT` record supplies `authSource=admin`, and that resolved on my laptop but not from the
deployment. Pinning it explicitly removes the dependency on DNS behaving identically everywhere:

```text
mongodb+srv://user:pass@cluster.mongodb.net/miniserp_production?authSource=admin
```

**The code problem, which was worse.** This README already claimed that a Mongo outage degrades to
a cache miss rather than a 500. That claim was false, and this is why:

```ruby
Mongo::Auth::Unauthorized.ancestors.include?(Mongo::Error)  # => false
```

`Mongo::Auth::Unauthorized` does **not** descend from `Mongo::Error`. It inherits from
`Mongo::Error::AuthError`, which is merely *namespaced* under it. `rescue Mongo::Error` — the
obvious, reasonable-looking thing to write — catches connection failures, timeouts and server
errors, and silently misses every credentials problem. So a misconfigured cache took down every
search on the service, on a code path specifically written to prevent exactly that.

`ScraperService::CACHE_ERRORS` now names all three, and `spec/services/cache_resilience_spec.rb`
asserts the inheritance trap itself, so the assumption can't quietly rot:

```ruby
expect(Mongo::Auth::Unauthorized.ancestors).not_to include(Mongo::Error)
expect(ScraperService::CACHE_ERRORS).to include(Mongo::Error::AuthError)
```

Worth sitting with: **a namespace is not a hierarchy.** `Foo::Error::Bar` tells you nothing about
what `Bar` inherits from, and a rescue clause built on that assumption fails silently in exactly
the situation it was written for.

### What I'd do differently at real scale

The layered-selector approach buys resilience, not immortality. In production I'd add a canary:
scrape a handful of known-stable queries on a schedule and alert when `results_count` drops to
zero across all of them at once. A parser that fails loudly the day the DOM changes is worth more
than one that squeezes two extra selectors out of the current layout.

---

## Deployment

Running on **Render** (free web service) + **MongoDB Atlas** (free M0 cluster).

**Atlas:** create an M0 cluster, add a database user, and allow `0.0.0.0/0` in Network Access
(free-tier hosts have no static outbound IP). Then build the URI — and **pin `authSource=admin`**,
for the reason in [engineering note 3](#3-the-database-error-that-wasnt-a-database-error).

**Render:** New Web Service → Ruby runtime.

| Setting           | Value                              |
| ----------------- | ---------------------------------- |
| Build Command     | `bundle install`                   |
| Start Command     | `bundle exec puma -C config/puma.rb` |
| Health Check Path | `/up`                              |

Render pre-fills a build command containing `rake assets:precompile`. **Delete it** — this is an
API-only app with no asset pipeline, so that task doesn't exist and the build aborts.

Environment variables: `RAILS_ENV=production`, `RAILS_MASTER_KEY`, `MONGODB_URI`,
`MINISERP_API_KEYS`, and `WEB_CONCURRENCY=1` (see below).

If you're deploying from Windows, add the Linux platform to the lockfile first or Bundler will
refuse to install on the build host:

```bash
bundle lock --add-platform x86_64-linux
```

---

## Adding an engine

1. Subclass `Scraper::Engines::Base` and implement `.key`, `#search_url`, `#parse`, and —
   importantly — `#blocked?` and `#no_results?`.
2. Register it in `Scraper::Registry::ENGINES`.
3. Save a results page to `spec/fixtures/html/` and add a parser spec.

Nothing above the engine layer changes.

## Production notes

- **`WEB_CONCURRENCY=1` on a single small instance.** Puma reads it natively, and the rate
  limiter's counter is in-process — two workers means two independent counters and roughly double
  the intended limit.
- **Rate-limit store.** `Rack::Attack.cache.store` is an in-process `MemoryStore`, correct for one
  process and for tests. Multi-process or multi-instance deploys need a shared store — point it at
  Redis; nothing else in that initializer changes.
- **API keys** are compared with `ActiveSupport::SecurityUtils.secure_compare`, so a wrong key
  cannot be discovered by timing the 401.
- **Retries are deliberately conservative**: one retry, only for timeouts, connection resets, 429
  and 5xx. A 403 or a CAPTCHA is never retried — hammering an engine that just blocked you is how
  a soft block becomes a hard one.
