# frozen_string_literal: true

module Scraper
  module Engines
    # Parser for Google's organic results.
    #
    # Google's result markup has no stable class names -- the wrapper has been
    # `div.g`, then `div.MjjYud`, and the obfuscated inner classes rotate. So
    # instead of one selector we keep an ordered list of container strategies
    # and fall through them, ending in a structural heuristic that only relies
    # on "an <h3> wrapped in an <a>". See README > Engineering notes.
    class Google < Base
      SEARCH_HOST = "www.google.com"
      SEARCH_PATH = "/search"

      # Text that only ever appears on the "unusual traffic" interstitial.
      BLOCK_TEXT_MARKERS = [
        "our systems have detected unusual traffic",
        "unusual traffic from your computer network",
        "to continue, please type the characters",
        "why did this happen?"
      ].freeze

      # Structural tells for the same page, in case the copy is localised.
      BLOCK_SELECTORS = [
        "#recaptcha",
        ".g-recaptcha",
        "#captcha-form",
        "form[action*='/sorry/']"
      ].freeze

      NO_RESULTS_MARKERS = [
        "did not match any documents",
        "no results found for"
      ].freeze

      # Tried in order; first strategy that yields usable blocks wins.
      CONTAINER_STRATEGIES = [
        "#rso div.g",
        "#search div.g",
        "#rso div.MjjYud",
        "#search div.MjjYud"
      ].freeze

      SNIPPET_SELECTORS = [
        "div[data-sncf] span",
        "div[data-sncf]",
        ".VwiC3b",
        ".lyLwlc",
        ".lEBKkf",
        ".st"
      ].freeze

      # Google chrome/navigation links that can sit inside a result container.
      NON_RESULT_HOSTS = %w[
        webcache.googleusercontent.com
        translate.google.com
        policies.google.com
      ].freeze

      NON_RESULT_PATHS = %w[
        /search /preferences /setprefs /advanced_search /intl/ /policies
      ].freeze

      def self.key = "google"

      def search_url(query, limit: nil)
        params = {
          q: query.to_s,
          hl: "en",
          gl: "us",
          num: (limit || MiniSerp.config.max_results).to_i.clamp(1, 100),
          ie: "UTF-8",
          oe: "UTF-8"
        }

        URI::HTTPS.build(host: SEARCH_HOST, path: SEARCH_PATH, query: URI.encode_www_form(params)).to_s
      end

      def blocked?(response)
        document = response.document
        return true if BLOCK_SELECTORS.any? { |selector| document.at_css(selector) }

        # Only scan the visible text: script/style blobs produce false positives.
        text = squish(document.css("body").text).downcase
        BLOCK_TEXT_MARKERS.any? { |marker| text.include?(marker) }
      end

      def no_results?(document)
        text = squish(document.css("body").text).downcase
        NO_RESULTS_MARKERS.any? { |marker| text.include?(marker) }
      end

      def parse(document, limit: nil)
        limit ||= MiniSerp.config.max_results
        containers = candidate_containers(document)

        if containers.empty?
          return [] if no_results?(document)

          raise Errors::ParseFailed,
                "no result blocks matched any known Google layout (selectors are probably stale)"
        end

        seen = Set.new
        results = []

        containers.each do |container|
          entry = extract(container)
          next if entry.nil?
          next unless seen.add?(entry[:link])

          results << entry.merge(position: results.length + 1)
          break if results.length >= limit
        end

        results
      end

      private

      def candidate_containers(document)
        CONTAINER_STRATEGIES.each do |selector|
          nodes = usable(document.css(selector))
          return nodes if nodes.any?
        end

        usable(heuristic_containers(document))
      end

      # A container is only interesting if it holds a heading and a link.
      def usable(nodes)
        reject_nested(nodes.select { |node| node.at_css("h3") && node.at_css("a[href]") })
      end

      # When one matched container sits inside another, keep the inner one --
      # it is the tighter bound on a single result.
      def reject_nested(nodes)
        nodes.reject do |node|
          nodes.any? { |other| !other.equal?(node) && other.ancestors.include?(node) }
        end
      end

      # Last resort: forget class names entirely. Walk up from every <h3> to the
      # nearest <div> that also contains a link, and treat that as the result.
      def heuristic_containers(document)
        scope = document.at_css("#search") || document.at_css("#main") || document
        scope.css("h3").filter_map do |heading|
          heading.ancestors("div").find { |div| div.at_css("a[href]") }
        end.uniq
      end

      def extract(container)
        heading = container.at_css("h3")
        return nil if heading.nil?

        anchor = heading.ancestors("a").first || container.at_css("a[href]")
        return nil if anchor.nil?

        link = normalize_link(anchor["href"])
        return nil if link.nil?

        title = squish(heading.text)
        return nil if title.empty?

        { title: title, link: link, snippet: extract_snippet(container) }
      end

      def extract_snippet(container)
        SNIPPET_SELECTORS.each do |selector|
          node = container.at_css(selector)
          next if node.nil?

          text = squish(node.text)
          return text if text.present?
        end

        ""
      end

      # Google sometimes serves bare URLs and sometimes its /url?q=... redirect
      # wrapper (typically when JS is disabled, which is exactly our case).
      def normalize_link(href)
        value = href.to_s.strip
        return nil if value.empty?

        value = unwrap_redirect(value)
        return nil if value.nil?

        uri = URI.parse(value)
        return nil unless uri.is_a?(URI::HTTP) && uri.host.present?
        return nil if NON_RESULT_HOSTS.include?(uri.host)
        return nil if google_navigation?(uri)

        uri.to_s
      rescue URI::InvalidURIError
        nil
      end

      def unwrap_redirect(value)
        return value unless value.start_with?("/url?", "https://www.google.com/url?")

        params = URI.decode_www_form(URI.parse(value).query.to_s).to_h
        target = params["q"].presence || params["url"].presence
        target&.strip.presence
      rescue URI::InvalidURIError, ArgumentError
        nil
      end

      def google_navigation?(uri)
        return false unless uri.host.match?(/(\A|\.)google\.[a-z.]+\z/)

        NON_RESULT_PATHS.any? { |path| uri.path.start_with?(path) }
      end
    end
  end
end
