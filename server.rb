# frozen_string_literal: true

require 'socket'
require 'json'
require 'time'
require 'pg'

class InvalidDataError < StandardError; end
class NotFoundError < StandardError; end

STATUS = { 200 => 'OK', 404 => 'Not Found', 422 => 'Unprocessable Entity', 500 => 'Internal Server Error' }.freeze
ROTA = %r{\A/clientes/(\d+)/(extrato|transacoes)\z}

conn = PG.connect(host: ENV.fetch('DB_HOST', 'localhost'), user: 'postgres', password: 'postgres', dbname: 'postgres')

# Uma única instrução por request: snapshot consistente no extrato e débito atômico sem SELECT FOR UPDATE.
# O extrato não é preparado: um plano guardado com transactions vazia lê todas as transações da conta
# em vez das 10 mais recentes pelo índice, e o custo cresce com a tabela até o primeiro autovacuum.
SQL_EXTRATO = <<~SQL
  SELECT balance, limit_amount, COALESCE((
    SELECT json_agg(t) FROM (
      SELECT amount AS valor, transaction_type AS tipo, description AS descricao, date AS realizada_em
      FROM transactions WHERE account_id = accounts.id ORDER BY id DESC LIMIT 10
    ) t
  ), '[]') AS ultimas_transacoes
  FROM accounts WHERE id = $1
SQL
conn.prepare('transacao', <<~SQL)
  WITH conta AS (
    UPDATE accounts SET balance = balance + $2
    WHERE id = $1 AND balance + $2 >= -limit_amount
    RETURNING balance, limit_amount
  ), nova AS (
    INSERT INTO transactions (account_id, amount, transaction_type, description)
    SELECT $1, $3, $4, $5 FROM conta
  )
  SELECT balance, limit_amount FROM conta
SQL

# Clientes não são criados em runtime: distingue 404 de 422 sem ida ao banco.
CLIENTES = conn.exec('SELECT id FROM accounts').column_values(0).map(&:to_i).freeze

def ler_request(client)
  verbo, caminho = client.gets&.split(' ', 3)
  tamanho = 0
  while (linha = client.gets) && linha != "\r\n"
    tamanho = linha.split(':', 2)[1].to_i if linha.downcase.start_with?('content-length:')
  end
  [verbo, caminho, tamanho.positive? ? client.read(tamanho) : nil]
end

def extrato(conn, id)
  conta = conn.exec_params(SQL_EXTRATO, [id]).first
  saldo = { total: conta['balance'].to_i, data_extrato: Time.now.utc.iso8601(6), limite: conta['limit_amount'].to_i }
  %({"saldo":#{saldo.to_json},"ultimas_transacoes":#{conta['ultimas_transacoes']}})
end

def transacao(conn, id, body)
  dados = JSON.parse(body.to_s)
  raise InvalidDataError unless dados.is_a?(Hash)

  valor, tipo, descricao = dados.values_at('valor', 'tipo', 'descricao')
  raise InvalidDataError unless valor.is_a?(Integer) && valor.positive? && %w[c d].include?(tipo)
  raise InvalidDataError unless descricao.is_a?(String) && descricao.length.between?(1, 10)

  conta = conn.exec_prepared('transacao', [id, tipo == 'd' ? -valor : valor, valor, tipo, descricao]).first
  raise InvalidDataError unless conta

  { saldo: conta['balance'].to_i, limite: conta['limit_amount'].to_i }.to_json
end

def atender(client, conn)
  verbo, caminho, body = ler_request(client)
  _, id, acao = ROTA.match(caminho.to_s).to_a
  raise NotFoundError unless CLIENTES.include?(id.to_i)

  case [verbo, acao]
  in ['GET', 'extrato'] then [200, extrato(conn, id.to_i)]
  in ['POST', 'transacoes'] then [200, transacao(conn, id.to_i, body)]
  else raise NotFoundError
  end
rescue NotFoundError
  [404, '{}']
rescue InvalidDataError, JSON::ParserError
  [422, '{}']
rescue StandardError => e
  warn e.full_message
  [500, '{}']
end

# Atrás do nginx, unix socket (SOCKET) custa menos CPU que TCP; sem SOCKET, escuta na 3000.
server = if (caminho = ENV['SOCKET'])
  File.unlink(caminho) if File.exist?(caminho)
  UNIXServer.new(caminho).tap { File.chmod(0o666, caminho) }
else
  TCPServer.new(3000)
end
puts 'Server started'
$stdout.flush

loop do
  client = server.accept
  status, body = atender(client, conn)
  client.write("HTTP/1.1 #{status} #{STATUS[status]}\r\nContent-Type: application/json\r\n" \
               "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
rescue SystemCallError, IOError
  nil # cliente desconectou antes da resposta
ensure
  client&.close
end
