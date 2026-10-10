import scala.concurrent.duration._
import scala.util.Random

import io.gatling.core.Predef._
import io.gatling.http.Predef._

// Vazão máxima em modelo fechado: N clientes fazendo requests sem parar, na mesma mistura da Rinha
// (220 débitos : 110 créditos : 10 extratos por segundo). Sem taxa fixa não há fila crescendo nem
// colapso, então a diferença entre implementações aparece direto em requests/s, em poucos segundos.
class CapacidadeSimulation extends Simulation {
  val clientes = Integer.getInteger("clientes", 256).intValue
  val duracao = Integer.getInteger("duracao", 10).intValue

  def clienteId() = Random.between(1, 5 + 1)

  // Connection: close abre uma conexão por request, como a simulação oficial da Rinha
  val httpProtocol = http
    .baseUrl("http://nginx:9999")
    .header("Connection", "close")
    .userAgentHeader("Capacidade")

  def transacao(tipo: String) =
    http(if (tipo == "d") "débitos" else "créditos")
      .post(_ => s"/clientes/${clienteId()}/transacoes")
      .header("content-type", "application/json")
      .body(StringBody(_ => s"""{"valor": ${Random.between(1, 10000 + 1)}, "tipo": "$tipo", "descricao": "${Random.alphanumeric.take(10).mkString}"}"""))
      .check(status.in(200, 422))

  val extrato = http("extratos").get(_ => s"/clientes/${clienteId()}/extrato").check(status.is(200))

  val mistura = scenario("capacidade").during(duracao.seconds) {
    randomSwitch(
      64.7 -> exec(transacao("d")),
      32.4 -> exec(transacao("c")),
      2.9 -> exec(extrato)
    )
  }

  setUp(mistura.inject(atOnceUsers(clientes))).protocols(httpProtocol)
}
