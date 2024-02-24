# frozen_string_literal: true

require 'socket'
require 'json'

server = TCPServer.new(3000)
puts 'Listening on port 3000'

loop do
  client = server.accept
  status = 200
  while (line = client.gets)
    puts line
  end
  body = {}
  client.puts "HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
  client.close
end
