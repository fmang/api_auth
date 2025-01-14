module ApiAuth
  # Builds the canonical string given a request object.
  class Headers
    include RequestDrivers

    def initialize(request, authorize_md5: false)
      @original_request = request
      @request = initialize_request_driver(request, authorize_md5: authorize_md5)
      true
    end

    def initialize_request_driver(request, authorize_md5: false)
      new_request =
        case request.class.to_s
        when /Net::HTTP/
          NetHttpRequest.new(request)
        when /RestClient/
          RestClientRequest.new(request)
        when /Curl::Easy/
          CurbRequest.new(request)
        when /ActionController::Request/
          ActionControllerRequest.new(request)
        when /ActionController::TestRequest/
          if defined?(ActionDispatch)
            ActionDispatchRequest.new(request)
          else
            ActionControllerRequest.new(request)
          end
        when /Grape::Request/
          GrapeRequest.new(request)
        when /ActionDispatch::Request/
          ActionDispatchRequest.new(request, authorize_md5: authorize_md5)
        when /ActionController::CgiRequest/
          ActionControllerRequest.new(request)
        when /HTTPI::Request/
          HttpiRequest.new(request)
        when /Faraday::Request/
          FaradayRequest.new(request)
        when /HTTP::Request/
          HttpRequest.new(request)
        end

      return new_request if new_request
      return RackRequest.new(request) if request.is_a?(Rack::Request)

      raise UnknownHTTPRequest, "#{request.class} is not yet supported."
    end
    private :initialize_request_driver

    # Returns the request timestamp
    def timestamp
      @request.timestamp
    end

    def canonical_string(override_method = nil, headers_to_sign = [])
      request_method = override_method || @request.http_method

      raise ArgumentError, 'unable to determine the http method from the request, please supply an override' if request_method.nil?

      headers = @request.fetch_headers

      canonical_array = [request_method.upcase,
                         @request.content_type,
                         @request.content_hash,
                         parse_uri(@request.original_uri || @request.request_uri),
                         @request.timestamp]

      if headers_to_sign.is_a?(Array) && headers_to_sign.any?
        headers_to_sign.each { |h| canonical_array << headers[h] if headers[h].present? }
      end

      canonical_array.join(',')
    end

    # Returns the authorization header from the request's headers
    def authorization_header
      @request.authorization_header
    end

    def set_date
      @request.set_date if @request.timestamp.nil?
    end

    def calculate_hash
      @request.populate_content_hash if @request.content_hash.nil?
    end

    def content_hash_mismatch?
      if @request.content_hash.nil?
        false
      else
        @request.content_hash_mismatch?
      end
    end

    # Sets the request's authorization header with the passed in value.
    # The header should be the ApiAuth HMAC signature.
    #
    # This will return the original request object with the signed Authorization
    # header already in place.
    def sign_header(header)
      @request.set_auth_header header
    end

    private

    def parse_uri(uri)
      parsed_uri = URI.parse(uri)

      return parsed_uri.request_uri if parsed_uri.respond_to?(:request_uri)

      uri.empty? ? '/' : uri
    end
  end
end
