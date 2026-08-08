# frozen_string_literal: true

require "socket"

# The control for scripts/cloudflare.rb: the cheapest possible HTTP responder, so
# that "Ruby client + loopback" can be subtracted from "Ruby client + loopback +
# workerd". Without it every workerd figure carries the client's own cost and the
# runtime cannot be told apart from the transport.
#
# Keep-alive is honoured because Net::HTTP holds one connection open for the whole
# run; a server that closed after each response would measure TCP setup instead.
server = TCPServer.new("127.0.0.1", Integer(ARGV[0]))
BODY = "42"
RESPONSE = "HTTP/1.1 200 OK\r\nContent-Length: #{BODY.bytesize}\r\n\r\n#{BODY}"

loop do
  conn = server.accept
  Thread.new(conn) do |c|
    loop do
      line = c.gets
      break if line.nil?
      break if line.strip.empty?

      # Drain the headers; the request itself carries nothing worth reading.
      while (header = c.gets)
        break if header == "\r\n"
      end
      c.write(RESPONSE)
    end
    c.close
  rescue StandardError
    c.close rescue nil
  end
end
