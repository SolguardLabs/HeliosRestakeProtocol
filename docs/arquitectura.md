# Arquitectura

## Límites de módulos

El vault coordina movimientos de valor; los módulos especializados mantienen su propio estado y exponen permisos mínimos.

```mermaid
flowchart TB
    A["HeliosAccess"] --> V["Vault"]
    V --> T["Receipt Token"]
    V --> D["Delegation Manager"]
    D --> O["Operator Registry"]
    V --> W["Withdrawal Queue"]
    V --> E["Epoch Rewarder"]
    V --> S["Slashing Controller"]
    V --> R["Reserve Vault"]
```

## Autoridad

Sólo el vault acuña o quema receipt shares. Sólo el controlador de slash puede invocar el ajuste de pérdida. Cola, rewarder, reserva y delegación validan la dirección del vault configurada.

```mermaid
classDiagram
    HeliosRestakeVault --> HeliosReceiptToken
    HeliosRestakeVault --> DelegationManager
    HeliosRestakeVault --> WithdrawalQueue
    HeliosRestakeVault --> EpochRewarder
    HeliosRestakeVault --> ReserveVault
    SlashingController --> HeliosRestakeVault
    DelegationManager --> OperatorRegistry
    HeliosLens --> HeliosRestakeVault
```

## Inicialización

```mermaid
sequenceDiagram
    participant G as Governor
    participant M as Modules
    participant V as Vault
    G->>M: deploy with access
    G->>M: set vault
    G->>V: initialize modules
    V->>V: verify reciprocal addresses
    G->>G: grant operational roles
    G-->>V: protocol ready
```

La inicialización es única y rechaza direcciones cero o relaciones inconsistentes. Los contratos principales son inmutables salvo parámetros gobernados explícitos.

## Reentrancia y transferencias

Las rutas de custodia usan guardia de reentrancia y comprueban transferencias ERC-20. El cambio de contabilidad precede o acompaña a la interacción externa de acuerdo con la operación.

## Lecturas

`HeliosLens` agrega vistas para clientes; `HeliosMonitor` emite salud operativa; `HeliosAccounting` construye libros por usuario, operador y época. Ninguno es fuente de custodia.
