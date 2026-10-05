# Felipe Route

Beta de um aplicativo Android para entregadores, com foco em importacao de manifesto, organizacao de pacotes, agrupamento de paradas e otimizacao de rota.

## Objetivo do beta

O app deve:

- importar um manifesto de entregas;
- transformar o manifesto em paradas e pacotes;
- diferenciar parada logica de parada fisica;
- agrupar entregas relacionadas ao mesmo local;
- exibir quantos pacotes devem ser entregues em cada parada;
- mostrar quais numeros de parada estao agrupados;
- suportar identificadores como 11, 11+1 e 11+2;
- permitir marcar Entregue, Problema ou Pular;
- preparar a base para mapa, otimizacao e GPS proprio.

## Exemplo esperado

Parada fisica 11

- Total: 15 pacotes
- Parada 11: 8 pacotes
- Parada 12: 3 pacotes
- Parada 18: 2 pacotes
- Parada 11+1: 1 pacote
- Parada 11+2: 1 pacote

## Stack inicial

- Flutter
- Dart
- SQLite/Drift (fase seguinte)
- MapLibre (mapa)
- OpenStreetMap (dados de mapa)
- Valhalla/OSRM (roteamento)
- motor de otimizacao a definir no beta

## Status

Projeto em desenvolvimento. Primeira estrutura iniciada em outubro de 2026.
