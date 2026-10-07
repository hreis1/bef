#!/usr/bin/env bash
# Teste oficial da Rinha de Backend 2024/Q1 (Gatling 3.10.3) rodando em Docker contra o nginx do compose.
set -euo pipefail
cd "$(dirname "$0")"

VERSAO=3.10.3
DIR=${DIR:-load-test}
PORTA=${PORTA:-9999}
PROJETO=${PROJETO:-bef}
SIM=$DIR/user-files/simulations/rinhabackend/RinhaBackendCrebitosSimulation.scala

if [ ! -d $DIR/gatling ]; then
  curl -sSfL "https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/$VERSAO/gatling-charts-highcharts-bundle-$VERSAO-bundle.zip" -o $DIR/gatling.zip
  unzip -q $DIR/gatling.zip -d $DIR && mv $DIR/gatling-charts-highcharts-bundle-$VERSAO $DIR/gatling && rm $DIR/gatling.zip
fi

if [ ! -f $SIM ]; then
  mkdir -p "$(dirname $SIM)"
  curl -sSfL https://raw.githubusercontent.com/zanfranceschi/rinha-de-backend-2024-q1/main/load-test/user-files/simulations/rinhabackend/RinhaBackendCrebitosSimulation.scala \
    | sed 's#http://localhost:9999#http://nginx:9999#' > $SIM
fi

for _ in $(seq 120); do curl -sf http://localhost:$PORTA/clientes/1/extrato > /dev/null && break; sleep 1; done
curl -sf http://localhost:$PORTA/clientes/1/extrato > /dev/null || { echo "API não respondeu em 120s"; exit 1; }

docker run --rm --network ${PROJETO}_default -v "$(cd $DIR && pwd):/load-test" eclipse-temurin:21-jdk \
  /load-test/gatling/bin/gatling.sh -rm local -s RinhaBackendCrebitosSimulation \
  -rd "Rinha de Backend - 2024/Q1: Crébito" \
  -rf /load-test/results -sf /load-test/user-files/simulations
