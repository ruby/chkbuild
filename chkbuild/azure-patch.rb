# lib/azure/core/service.rb
module Azure
  module Core
    class Service
      def call(method, uri, body=nil, headers=nil)
        request = Core::Http::HttpRequest.new(method, uri, body)
        request.headers.merge!(headers) if headers

        request.headers['connection'] = 'keep-alive' if request.respond_to? :headers

        yield request if block_given?

        response = request.call

        response
      end
    end


    module Http
      class HttpRequest
        def default_headers(current_time)
          headers["User-Agent"] = "Azure-SDK-For-Ruby/" + Azure::Version.to_s
          headers["x-ms-date"] = current_time
          headers["x-ms-version"] = "2012-02-12"
          headers["DataServiceVersion"] = "1.0;NetFx"
          headers["MaxDataServiceVersion"] = "2.0;NetFx"

          if body
            headers["Content-Type"]   = "application/atom+xml; charset=utf-8"
            if IO === body
              headers["Content-Length"] = body.size.to_s
              headers["Content-MD5"]    = Digest::MD5.file(body.path).base64digest
            else
              headers["Content-Length"] = body.bytesize.to_s
              headers["Content-MD5"]    = Base64.strict_encode64(Digest::MD5.digest(body))
            end
          else
            headers["Content-Length"] = "0"
            headers["Content-Type"] = ""
          end
        end

        def call
          request = http_request_class.new(uri.request_uri, headers)
          if IO === body
            request.body_stream = body
          elsif body
            request.body = body
          end

          http = nil
          if ENV['HTTP_PROXY'] || ENV['HTTPS_PROXY']
            if ENV['HTTP_PROXY']
              proxy_uri = URI::parse(ENV['HTTP_PROXY'])
            else
              proxy_uri = URI::parse(ENV['HTTPS_PROXY'])
            end

            http = Net::HTTP::Proxy(proxy_uri.host, proxy_uri.port).new(uri.host, uri.port)
          else
            http = Net::HTTP.new(uri.host, uri.port)
          end

          if uri.scheme.downcase == 'https'
            # require 'net/https'
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end

          response = HttpResponse.new(http.request(request))
          response.uri = uri
          raise response.error unless response.success?
          response
        end
      end
    end
  end
end
