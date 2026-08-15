# Operación

## Despliegue

```mermaid
flowchart LR
    A["Access"] --> V["Vault"]
    V --> M["Modules"]
    M --> C["Cross-configure"]
    C --> R["Grant roles"]
    R --> Q["Verify bytecode"]
    Q --> O["Open operations"]
```

El despliegue valida tokens, gobierno y guardián; configura relaciones recíprocas; otorga roles; y confirma valores de espera y límites antes de recibir activos.

## Rutina

```mermaid
sequenceDiagram
    participant O as Operator
    participant L as Lens
    participant M as Monitor
    participant V as Vault
    O->>L: snapshot
    O->>M: health
    M-->>O: queue reserve buffer
    O->>V: advance epoch or execute batch
    V-->>O: events
    O->>L: reconcile snapshot
```

## Pausas

```mermaid
stateDiagram-v2
    [*] --> Normal
    Normal --> DepositsPaused
    Normal --> WithdrawalsPaused
    Normal --> DelegationsPaused
    Normal --> SlashingPaused
    DepositsPaused --> Normal: reconciled
    WithdrawalsPaused --> Normal: reconciled
    DelegationsPaused --> Normal: reconciled
    SlashingPaused --> Normal: reconciled
```

Aplica la pausa mínima que contenga la señal. Una pausa de slashing no debe detener retiros salvo que la liquidez o custodia también estén comprometidas.

## Runbook

1. Fijar bloque y conservar eventos.
2. Leer snapshot, cola, operadores, rewarder y reserva.
3. Ejecutar proyecciones base y adversa.
4. Comparar saldos ERC-20 con libros internos.
5. Decidir pausa, financiación o migración.
6. Reanudar tras doble revisión y conciliación.

## Versiones

Cada entrega conserva commit, compilador, configuración Foundry, hashes de artefactos y resultados de Ubuntu y Windows. Una etiqueta publicada no se mueve.
