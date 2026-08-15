# Contabilidad de shares

## Conversión

```mermaid
flowchart LR
    A["Assets"] --> D["previewDeposit"]
    S["Supply"] --> D
    P["Pooled assets"] --> D
    D --> H["Shares minted"]
    H --> R["previewRedeem"]
    P --> R
    S --> R
    R --> O["Assets quoted"]
```

Después del primer depósito, la conversión se basa en el cociente entre activos agrupados y supply. La división redondea hacia abajo.

```text
depositShares = assets × supply / pooled
redeemAssets = shares × pooled / supply
exchangeRateRay = pooled × 10²⁷ / supply
```

## Estados de una share

```mermaid
stateDiagram-v2
    [*] --> Active: mint
    Active --> Delegated: delegate
    Delegated --> Cooling: undelegate
    Cooling --> Active: cooldown complete
    Active --> Locked: request withdrawal
    Locked --> Active: cancel
    Locked --> Burned: execute
    Burned --> [*]
```

Una share delegada o bloqueada no puede reutilizarse para otra operación. `totalSupply`, `totalLocked` y las cuentas de delegación permiten reconciliar los estados.

## Reconciliación

```mermaid
flowchart TD
    TS["Total supply"] --> I1["active + locked = supply"]
    AS["Active balances"] --> I1
    LS["Locked balances"] --> I1
    PA["Pooled assets"] --> I2["token balance + external flows"]
    Q["Queued shares"] --> I3["queue = locked requests"]
    LS --> I3
```

## Redondeo

Los restos no se asignan al usuario. Las pruebas deben cubrir cantidades pequeñas, supply alto, tipo inferior y superior a uno, y secuencias de depósito y pérdida.

## Snapshot

`VaultSnapshot` publica activos, supply, shares activas, bloqueadas, delegadas y en cola, acumulados y tipo RAY. Se conserva junto al bloque para comparación histórica.
