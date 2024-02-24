# frozen_string_literal: true

require 'socket'
require 'json'

server = TCPServer.new(ENV['PORT'] || 3000)
puts "Server started at port #{ENV['PORT'] || 3000}"

loop do
  client = server.accept
  request = client.gets
  next unless request
  method, full_path = request.split(' ')

  case [method, full_path]
  in ['GET', /\/clientes\/\d+\/extrato/]
    id = full_path.split('/')[2]
    status = 200
    puts "Extrato do cliente #{id}"
    body = { message: "Extrato do cliente #{id}" }
  in ['GET', /\/clientes\/\d+\/transacoes/]
    id = full_path.split('/')[2]
    status = 200
    puts "Transações do cliente #{id}"
    body = { message: "Transações do cliente #{id}" }
  else
    status = 404
    body = { }
  end

  client.puts "HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
  client.close
end