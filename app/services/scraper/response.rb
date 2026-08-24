# frozen_string_literal: true

module Scraper
  # Minimal transport-agnostic response so engines and specs never care whether
  # the bytes came from HTTParty or from a file on disk.
  Response = Struct.new(:body, :status, :url, :headers, keyword_init: true) do
    def success? = status.to_i.between?(200, 299)

    def document
      @document ||= Nokogiri::HTML(body.to_s)
    end
  end
end
