# frozen_string_literal: true

require 'socket'
require 'json'
require 'pg'

server = TCPServer.new(3000)
puts 'Server started'
$stdout.flush

class InvalidDataError < StandardError; end
class NotFoundError < StandardError; end

def parse_request(client)
  line = client.gets
  verb, path, version = line.split(' ')
  puts "Verb: #{verb}, Path: #{path}, Version: #{version}"
  id = path.split('/')[2].to_i
  puts id
  action = path.split('/')[3]
  request = "#{verb} /clientes/:id/#{action}"

  params = { 'id' => id }

  headers = {}
  while (line = client.gets)
    break if line == "\r\n"

    key, value = line.split(': ')
    headers[key] = value.strip
  end
  if headers['Content-Length']
    body = client.read(headers['Content-Length'].to_i)
    params.merge!(JSON.parse(body))
  end
  [request, params]
end

conn = PG.connect(host: ENV['DB_HOST'] || 'localhost',
                  user: 'postgres',
                  password: 'postgres',
                  dbname: 'postgres',
                  port: 5432)

loop do
  client = server.accept
  request, params = parse_request(client)
  raise NotFoundError if params.empty?
  puts "Request: #{request}, Params: #{params}"
  id = params['id']
  raise NotFoundError if id.nil?
  raise NotFoundError unless id.is_a?(Integer) && id.positive?

  case request
  in 'GET /clientes/:id/extrato'
    sql_account = "SELECT * FROM accounts WHERE id = #{id} LIMIT 1 FOR UPDATE"
    sql_transactions = <<~SQL
      SELECT amount, transaction_type, description, TO_CHAR(date, 'YYYY-MM-DD HH:MI:SS.US') AS date
      FROM transactions
      WHERE transactions.account_id = #{id}
      ORDER BY date DESC
      LIMIT 10
    SQL

    conn.transaction do |c|
      account = c.exec(sql_account).first
      raise NotFoundError unless account

      transactions = c.exec(sql_transactions)

      body = {
        "saldo": {
          "total": account['balance'].to_i,
          "data_extrato": Time.now.strftime('%Y-%m-%d'),
          "limite": account['limit_amount'].to_i
        },
        "ultimas_transacoes": transactions.map do |transaction|
          {
            "valor": transaction['amount'].to_i,
            "tipo": transaction['transaction_type'],
            "descricao": transaction['description'],
            "realizada_em": transaction['date']
          }
        end
      }
      puts 'Success!'
      client.puts "HTTP/1.1 200\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
      client.close
    end
  in 'POST /clientes/:id/transacoes'
    raise InvalidDataError if params.empty? || params.nil?

    valor = params['valor']
    tipo = params['tipo']
    descricao = params['descricao']

    raise InvalidDataError if id.nil? || valor.nil? || tipo.nil? || descricao.nil?
    raise InvalidDataError if valor && (!valor.is_a?(Integer) || !valor.positive?)
    raise InvalidDataError if descricao&.empty?
    raise InvalidDataError if descricao && descricao.size > 10
    raise InvalidDataError unless %w[d c].include?(params['tipo'])

    puts "Id: #{id}, Valor: #{valor}, Tipo: #{tipo}, Descricao: #{descricao}"

    conn.transaction do |c|
      sql_account = "SELECT * FROM accounts WHERE id = #{id} LIMIT 1 FOR UPDATE"
      
      account = conn.exec(sql_account).first
      raise NotFoundError if account.nil?
      operator = '+'
      puts "Account: {id: #{account['id']}}"
      if tipo == 'd'
        operator = '-'
        raise InvalidDataError if (account['limit_amount'].to_i + account['balance'].to_i) <= valor
      end

      sql_insert_transaction = "INSERT INTO transactions (account_id, amount, transaction_type, description, date) VALUES (#{id}, #{valor}, '#{tipo}', '#{descricao}', NOW())"

      sql_update_balance = "UPDATE accounts SET balance = balance #{operator} #{valor} WHERE id = #{id} RETURNING *"

      c.exec(sql_insert_transaction)
      account = c.exec(sql_update_balance).first

      body = {
          "saldo": account['balance'].to_i,
          "limite": account['limit_amount'].to_i
      }

      puts 'Success!'
      client.puts "HTTP/1.1 200\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
      client.close
    end
  else
    raise NotFoundError
  end
rescue NotFoundError
  puts 'Not found'
  status = 404
  body = {}
  client.puts "HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
  client.close
rescue InvalidDataError
  puts 'Invalid data'
  status = 422
  body = {}
  client.puts "HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n\r\n#{body.to_json}"
  client.close
end
