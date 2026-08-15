# Gobernanza

## Roles

```mermaid
flowchart TB
    G["Governor"] --> C["Configuration"]
    H["Guardian"] --> P["Pauses and cancellation"]
    S["Slasher"] --> Q["Slash proposals"]
    R["Rewarder"] --> E["Epoch funding"]
    K["Keeper"] --> X["Delayed execution"]
```

Las identidades se separan y las claves se custodian fuera del repositorio. El guardián contiene; no puede reconfigurar libremente la economía.

## Cambio de parámetros

```mermaid
sequenceDiagram
    participant P as Proponente
    participant R as Riesgo
    participant T as Revisión técnica
    participant O as Operaciones
    P->>R: valores y escenarios
    R-->>P: dictamen
    P->>T: cambio versionado
    T-->>O: artefacto aprobado
    O->>O: ejecutar en ventana
    O-->>R: conciliación
```

Incluye valor anterior y nuevo, unidad, contratos, hipótesis, proyecciones de liquidez, instante efectivo y reversión.

```mermaid
stateDiagram-v2
    [*] --> Draft
    Draft --> Simulated
    Simulated --> Approved
    Approved --> Timelocked
    Timelocked --> Executed
    Executed --> Reconciled
    Executed --> RolledBack: threshold breach
    RolledBack --> Reconciled
    Reconciled --> [*]
```

## Parámetros sensibles

- máximos de delegación y comisión;
- demoras de undelegación, retirada y slash;
- máximo de slash;
- duración y presupuesto de épocas;
- límites de riesgo y reserva;
- roles y direcciones de módulos.

## Evidencia

Se conserva propuesta, simulación, aprobaciones, commit, bytecode, transacción, bloque, eventos y conciliación. Los cambios de emergencia reciben revisión retrospectiva y fecha de caducidad.
