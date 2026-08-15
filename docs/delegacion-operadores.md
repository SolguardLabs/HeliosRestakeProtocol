# Delegación y operadores

## Registro

Cada operador tiene controlador, receptor de comisión, límite de shares, estado y hash de metadatos. La contabilidad conserva shares delegadas, salidas en cola, activos, recompensas y slashes acumulados.

```mermaid
flowchart LR
    G["Governor"] --> R["Operator Registry"]
    R --> C["Config"]
    R --> A["Accounting"]
    U["Restaker"] --> D["Delegation Manager"]
    D --> R
    D --> V["Vault"]
```

## Ciclo

```mermaid
stateDiagram-v2
    [*] --> None
    None --> Active: delegate
    Active --> CoolingDown: undelegate
    CoolingDown --> None: release
    Active --> Active: increase or decrease
```

El usuario no puede cambiar de operador mientras mantenga shares delegadas. La capacidad se comprueba antes de actualizar cuenta y agregado.

## Recompensa

```mermaid
sequenceDiagram
    participant R as Rewarder
    participant D as Delegation
    participant O as Operator
    participant U as User
    R->>D: finalize epoch index
    D->>D: checkpoint reward debt
    D-->>U: pending reward
    D-->>O: attributed commission
```

## Límites

- sólo operadores activos admiten nuevas delegaciones;
- el límite se mide en shares, no en activos estimados;
- pausa y retiro no borran contabilidad acumulada;
- los metadatos se verifican fuera de cadena antes de mostrarlos.

## Supervisión

Observa concentración por operador, capacidad libre, cooldown pendiente, frecuencia y magnitud de slash y relación entre activos registrados y valor actual de shares delegadas.
