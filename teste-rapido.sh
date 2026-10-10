#!/usr/bin/env bash
# Vazão máxima em ~10s (simulacoes/CapacidadeSimulation.scala): compara implementações pelo requests/s.
# CLIENTES (padrão 256) clientes simultâneos durante DURACAO segundos (padrão 10).
export JAVA_OPTS="-Dclientes=${CLIENTES:-256} -Dduracao=${DURACAO:-10}"
exec env SIMULACAO=CapacidadeSimulation "$(dirname "$0")/teste-carga.sh"
