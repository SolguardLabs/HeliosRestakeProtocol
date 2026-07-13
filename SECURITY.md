# Política de seguridad

HeliosRestakeProtocol protege custodia de staking tokens, receipt shares,
delegación a operadores, recompensas por epoch, slashing y retiradas diferidas.

## Alcance

Dentro del alcance:

- contratos bajo `src/`;
- pruebas públicas en `test/`;
- scripts de despliegue y CI;
- comportamiento económico alrededor de staking, delegación, rewards, slashing y
  retiradas.

Fuera del alcance:

- supply chain del tooling local de Foundry;
- sistemas externos de multisig, timelock, oráculos o monitorización;
- micro-optimizaciones de gas sin impacto en seguridad o accounting.

## Supuestos de seguridad

- Los operadores se registran bajo límites de capacidad configurados.
- Los rewards se financian por epoch antes de su distribución.
- Las retiradas respetan delay y bloqueo de receipt shares.
- Las solicitudes de slashing incluyen evidencia y siguen el flujo de estado
  configurado.
- Las funciones de gobierno y pausa están restringidas por roles.

## Invariantes esperadas

- Las receipt shares emitidas reflejan staking token custodiado, menos estados de
  penalización correctamente contabilizados.
- Las shares bloqueadas por retirada no deben poder volver a delegarse.
- Los rewards solo se distribuyen sobre shares elegibles del epoch.
- El slashing reduce exposición de operador y actualiza reservas de forma
  consistente.
- Las rutas de claim, exit y slashing no deben romper accounting global.

## Validación local

```bash
forge fmt --check
forge build
forge test
bash scripts/ci.sh
```

## Reporte responsable

Un reporte debe incluir:

- contrato y función afectados;
- secuencia mínima de verificación;
- impacto contable o económico;
- precondiciones;
- comportamiento esperado y observado;
- propuesta de mitigación;
- tests recomendados.

No incluyas claves privadas, credenciales ni datos de terceros.
