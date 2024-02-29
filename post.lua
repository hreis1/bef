wrk.method = "POST"
wrk.body   = '{"valor": 1000, "tipo" : "c", "descricao" : "descricao"}'
wrk.headers["Content-Type"] = "application/json"

-- wrk --latency -d3s -s req_post.lua http://localhost:3000/clientes/1/transacoes

-- curl -X POST -H "Content-Type: application/json" -d '{"valor": 1000, "tipo" : "c", "descricao" : "descricao"}' http://localhost:3000/clientes/1/transacoes
