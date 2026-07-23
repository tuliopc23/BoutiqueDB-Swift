# Sync & Turso performance benchmarks

Track these on a release branch before tagging. Use a Release build of the host app or a dedicated benchmark target (never `--release` for the Rust engine rebuild unless CI requires it).

## Methodology

- Device: M-series Mac or recent iPhone simulator/device
- Dataset: N notes with title/body/updatedAt + optional embedding column
- Metrics: median of 5 runs after one warm-up

## Benchmarks

> Measured numbers are not yet populated. Fill these tables during the v1.0 RC and attach Instruments traces for regressions.

### 1. `drainCDC`

| N local writes | Limit | Median ms | Notes |
|---|---|---|---|
| 100 | 500 | | |
| 500 | 500 | | |
| 2_000 | 500 (loop) | | multiple drain passes |

```swift
let t0 = ContinuousClock.now
_ = try engine.drainCDC(limit: 500)
let ms = (ContinuousClock.now - t0).components.attoseconds // convert
```

### 2. Sync round-trip (simulated, no network)

| Scenario | Median ms |
|---|---|
| A insert → makeRecord → B applyRemoteRecord | |
| A delete → B applyRemoteDeletion | |
| 100 row batch apply | |

### 3. `writeConcurrent` (MVCC)

| Concurrent writers | Rows each | Median ms | Conflicts/retries |
|---|---|---|---|
| 1 | 100 | | |
| 2 | 100 | | |
| 4 | 100 | | |

```swift
let db = try BoutiqueDB(url: url, concurrentWrites: true)
// time writeConcurrent inserts
```

### 4. LiveQuery refresh after write

| Rows in table | Median refresh ms |
|---|---|
| 100 | target &lt; 500 |
| 1_000 | |

## Targets (v1.0 aspirational)

| Op | Target |
|---|---|
| drainCDC 500 | &lt; 50 ms on M-series |
| Simulated record apply | &lt; 5 ms |
| LiveQuery after local write | &lt; 500 ms |
| writeConcurrent single writer 100 rows | competitive with plain `write` |

Fill tables during RC; attach Instruments traces for regressions.
