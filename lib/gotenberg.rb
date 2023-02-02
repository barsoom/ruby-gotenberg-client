require 'net/http'
require 'uri'
require 'faraday'
require 'faraday/multipart'
require 'tempfile'
require_relative "gotenberg/version"

module Gotenberg
  class Error < StandardError; end

  class Assets
    def self.include_css(file)
      raise "Not in Rails project" unless defined?(Rails)

      abs_path = Rails.root.join('public', 'stylesheets', file)
      return "<style type='text/css'>#{File.read(abs_path)}</style>".html_safe
    end
  end

  class Client
    PERMITTED_OPTIONS = {
      prefer_css_page_size: "preferCssPageSize",
      margin_top: "marginTop",
      margin_bottom: "marginBottom",
      margin_left: "marginLeft",
      margin_right: "marginRight",
    }

    def initialize(api_url)
      @api_url = api_url
    end

    # Write the PDF of given HTML in output file.
    #
    # @param render [String] HTML to convert
    # @param output [File, Pathname, #write] Output file
    # @return true if everything OK
    def html(render, output, **kwargs)
      return false unless up?

      content = {
        "index.html": Faraday::Multipart::FilePart.new(
          StringIO.new(render),
          'text/html',
          "index.html"
        ),
      }

      payload = content.merge(filter_and_transform_params(**kwargs))

      url = "#{@api_url}/forms/chromium/convert/html"
      begin
        conn = Faraday.new(url) do |f|
          f.request :multipart, flat_encode: true
          f.adapter :net_http
        end
        response = conn.post(url, payload)
      rescue StandardError
        response = ""
      end

      output.write(response.body.force_encoding("utf-8"))
      true
    end

    def up?
      uri = URI.parse("#{@api_url}/health")
      request = Net::HTTP::Get.new(uri)
      req_options = {
        use_ssl: uri.scheme == "https",
      }

      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      response.code == "200" && JSON.parse(response.body)["status"] == "up"
    rescue StandardError
      false
    end

    private

    # Takes the parameters passed in to #html, filters out the ones we don't want to use
    # And transforms them from snake_case to the corresponding camelCased API parameter for Gotenberg
    #
    # @param params [Hash] with snake_cased symbols as keys
    # @return a Hash containing the stringified and camelCased keys with the original values
    def filter_and_transform_params(**params)
      params.select { PERMITTED_OPTIONS.key?(_1) }.transform_keys { PERMITTED_OPTIONS[_1] }
    end
  end
end
