#!/usr/bin/env bash
# Teste oficial da Rinha de Backend 2024/Q1 (Gatling 3.10.3) rodando em Docker contra o nginx do compose.
# Recria a stack do zero (down -v) e falha se houver KO ou saldo inconsistente no banco ao final.
# CARGA multiplica as requisições/s de débitos, créditos e extratos (1 = carga oficial). Ex.: CARGA=3 ./teste-carga.sh
set -euo pipefail
cd "$(dirname "$0")"

VERSAO=3.10.3
SHA1_GATLING=a776a88138357301651e797ffd1f4e662f54ea21
COMMIT_RINHA=03af80bb8de97b5723580e9e9a39838382e6e365
DIR=${DIR:-load-test}
PROJETO=${PROJETO:-bef}
CARGA=${CARGA:-1}
export PORTA=${PORTA:-9999}
OFICIAL="$DIR/rinha-oficial.scala"
SIM="$DIR/user-files/simulations/rinhabackend/RinhaBackendCrebitosSimulation.scala"
LOG="$DIR/ultimo-teste.log"

compose() { docker compose -p "$PROJETO" "$@"; }
falha() { echo "FALHOU: $1" >&2; exit 1; }

[[ $CARGA =~ ^[0-9]+(\.[0-9]+)?$ ]] || falha "CARGA deve ser um número, recebido: $CARGA"

mkdir -p "$DIR"
if [ ! -d "$DIR/gatling" ]; then
  curl -sSfL "https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/$VERSAO/gatling-charts-highcharts-bundle-$VERSAO-bundle.zip" -o "$DIR/gatling.zip"
  echo "$SHA1_GATLING  $DIR/gatling.zip" | shasum -a 1 -c --status || { rm "$DIR/gatling.zip"; falha "sha1 do Gatling não confere"; }
  unzip -q "$DIR/gatling.zip" -d "$DIR" && mv "$DIR/gatling-charts-highcharts-bundle-$VERSAO" "$DIR/gatling" && rm "$DIR/gatling.zip"
fi

if [ ! -f "$OFICIAL" ]; then
  curl -sSfL "https://raw.githubusercontent.com/zanfranceschi/rinha-de-backend-2024-q1/$COMMIT_RINHA/load-test/user-files/simulations/rinhabackend/RinhaBackendCrebitosSimulation.scala" -o "$OFICIAL.tmp"
  mv "$OFICIAL.tmp" "$OFICIAL"
fi
mkdir -p "$(dirname "$SIM")"
sed -e 's#http://localhost:9999#http://nginx:9999#' \
    -e "s/\.to(\([0-9]*\))/.to(\1 * $CARGA)/" \
    -e "s/constantUsersPerSec(\([0-9]*\))/constantUsersPerSec(\1 * $CARGA)/" "$OFICIAL" > "$SIM"

compose down -v --remove-orphans
compose up -d --build

for _ in $(seq 120); do curl -sf "http://localhost:$PORTA/clientes/1/extrato" > /dev/null && break; sleep 1; done
curl -sf "http://localhost:$PORTA/clientes/1/extrato" > /dev/null || falha "API não respondeu em 120s"

# Cada usuário virtual abre uma conexão nova; sem ampliar as portas e reaproveitar TIME_WAIT,
# o Gatling esgota as portas de saída (~470 conexões/s) antes do backend.
docker run --rm --network "${PROJETO}_default" \
  --sysctl net.ipv4.ip_local_port_range="1024 65535" --sysctl net.ipv4.tcp_tw_reuse=1 \
  -v "$(cd "$DIR" && pwd):/load-test" eclipse-temurin:21-jdk \
  /load-test/gatling/bin/gatling.sh -rm local -s RinhaBackendCrebitosSimulation \
  -rd "Rinha de Backend - 2024/Q1: Crébito (carga x$CARGA)" \
  -rf /load-test/results -sf /load-test/user-files/simulations | tee "$LOG"

grep -q 'request count.*KO=0 ' "$LOG" || falha "houve KO, veja $LOG"

INCONSISTENTES=$(compose exec -T postgres psql -U postgres -tAc "
  SELECT count(*) FROM accounts a
  WHERE a.balance < -a.limit_amount
     OR a.balance <> (SELECT COALESCE(SUM(CASE transaction_type WHEN 'c' THEN amount ELSE -amount END), 0)
                      FROM transactions WHERE account_id = a.id)")
[ "$INCONSISTENTES" = 0 ] || falha "$INCONSISTENTES conta(s) com saldo inconsistente"

echo "OK: 0 KO e saldos consistentes"
