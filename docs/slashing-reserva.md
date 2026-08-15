# Slashing y reserva

## Propuesta con evidencia

```mermaid
flowchart LR
    E["Evidence hash"] --> Q["Queue slash"]
    B["Slash BPS"] --> Q
    O["Operator"] --> Q
    Q --> D["Execution delay"]
    D --> G{"Review"}
    G -- cancel --> C["Cancelled"]
    G -- execute --> X["Pool loss"]
    X --> R["Reserve credit"]
```

El BPS debe ser positivo y no superar el máximo. Sólo el rol de slasher o gobierno propone; guardián o gobierno cancela; cualquier ejecutor puede materializar después de la demora si sigue en cola.

## Aplicación

```mermaid
sequenceDiagram
    participant K as Keeper
    participant S as Controller
    participant V as Vault
    participant O as Registry
    participant R as Reserve
    K->>S: execute slash
    S->>V: apply operator slash
    V->>O: delegated shares and assets
    V->>R: transfer and credit evidence
    V->>O: record remaining assets
    V-->>S: assets slashed
```

## Cálculo

```text
operatorAssets = delegatedShares × pooledAssets / receiptSupply
assetsSlashed = operatorAssets × slashBps / 10 000
remainingOperatorAssets = operatorAssets - assetsSlashed
```

```mermaid
flowchart TD
    OA["Operator assets"] --> L["Slash loss"]
    L --> PA["Reduce pooled assets"]
    L --> RB["Increase reserve balance"]
    PA --> ER["Lower exchange rate"]
    RB --> EV["Evidence accounting"]
```

## Controles

- evidencia no nula;
- estado activo del operador;
- demora entre propuesta y ejecución;
- pausa separada;
- id y estado monotónicos;
- crédito de reserva por operador y evidencia.

## Conciliación

Después de ejecutar, compara salida del vault, entrada a reserva, acumulado global, acumulado del operador, tipo de share y evento. Todas las cifras deben coincidir en la misma transacción.
