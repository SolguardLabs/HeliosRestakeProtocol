# Salidas y liquidez

## Solicitud

La cola registra propietario, receptor, operador de origen, shares, activos cotizados, mínimo, tiempos, época y estado.

```mermaid
sequenceDiagram
    participant U as Usuario
    participant V as Vault
    participant T as Receipt Token
    participant Q as Queue
    U->>V: request withdrawal
    V->>V: verify free shares
    V->>T: lock shares
    V->>Q: open request
    Q-->>U: request id and window
```

## Ventana

```mermaid
stateDiagram-v2
    [*] --> Pending
    Pending --> Claimable: delay elapsed
    Pending --> Cancelled: owner cancels
    Claimable --> Claimed: keeper executes
    Claimable --> Cancelled: owner cancels
    Claimable --> Expired: ttl elapsed
    Claimed --> [*]
    Cancelled --> [*]
```

## Proyección de liquidez

```mermaid
flowchart TD
    P["Pooled assets"] --> S["Slash shock"]
    S --> H["Liquidity haircut"]
    H --> E["Post-shock assets"]
    R["Recoverable reserve"] --> E
    E --> Q["Queue coverage"]
    Q --> A["Active backing"]
    A --> D["Capital shortfall"]
```

`ExitLiquidityStress` asigna primero cobertura a obligaciones en cola y calcula después el respaldo activo. También entrega cobertura global y nivel operativo.

## Escenarios mínimos

| Escenario | Variables |
| --- | --- |
| base | sin slash, reserva disponible |
| operador concentrado | slash alto |
| mercado ilíquido | recorte adicional |
| reserva parcial | recovery inferior al 100 % |
| ola de salidas | queued assets elevados |

## Operación

Antes de ejecutar un lote, compara saldo, activos agrupados, activos en cola, shares bloqueadas, reserva recuperable y proyección. Registra el bloque y los parámetros de estrés usados.
