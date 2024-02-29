wrk.method = "GET"
wrk.headers["Content-Type"] = "application/json"

-- wrk --latency -d3s -s req_get.lua http://localhost:3000/clientes/1/extrato

-- curl http://localhost:3000/clientes/1/extrato