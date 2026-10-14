---
title: "BoutiqueDB for Swift"
sidebarTitle: "Overview"
description: "The local-first database for Swift apps, with reactive queries, CloudKit synchronization, and Turso-powered capabilities."
mode: "custom"
hidden: true
keywords: ["Swift database", "local-first", "LiveQuery", "CloudKit", "Turso", "SQLite"]
hideFooterPagination: true
---

<div className="bd-landing not-prose">
  <section className="bd-hero">
    <div className="bd-hero-grid" aria-hidden="true" />

    <div className="bd-hero-orb bd-hero-orb-coral" aria-hidden="true" />

    <div className="bd-hero-orb bd-hero-orb-blue" aria-hidden="true" />

    <div className="bd-hero-copy">
      <div className="bd-eyebrow">
        <span className="bd-eyebrow-dot" />

        Swift 6 · iOS · macOS
      </div>

      <h1>The local-first database built for Swift apps.</h1>

      <p className="bd-hero-lead">
        BoutiqueDB combines SQLite-compatible local persistence, CDC-backed <code>LiveQuery</code>, CloudKit synchronization, and Turso engine capabilities in one native Swift package.
      </p>

      <div className="bd-hero-actions">
        <a className="bd-button bd-button-primary" href="/getting-started/quick-start">
          Get started

          <Icon icon="arrow-right" size={15} />
        </a>

        <a className="bd-button bd-button-secondary" href="/advanced/boutiquedb-architecture">
          Explore architecture
        </a>
      </div>

      <div className="bd-platform-strip" aria-label="BoutiqueDB platform capabilities">
        <span>Local-first</span>
        <span>SQLite-compatible</span>
        <span>Reactive SwiftUI</span>
        <span>Optional CloudKit</span>
      </div>
    </div>

    <div className="bd-engine-visual" aria-label="BoutiqueDB engine stack">
      <div className="bd-engine-shadow" aria-hidden="true" />

      <div className="bd-engine-card bd-engine-card-back">
        <span className="bd-engine-label">Turso engine</span>
        <span className="bd-engine-detail">SQLite · FTS · vectors · encryption</span>
      </div>

      <div className="bd-engine-card bd-engine-card-middle">
        <span className="bd-engine-label">BoutiqueDB actor</span>
        <span className="bd-engine-detail">Queries · migrations · transactions</span>
      </div>

      <div className="bd-engine-card bd-engine-card-front">
        <div className="bd-engine-icon-wrap">
          <img src="/icon.png" alt="BoutiqueDB" className="bd-engine-icon" />
        </div>

        <div>
          <span className="bd-engine-product">BoutiqueDB</span>
          <span className="bd-engine-caption">Native persistence for Apple platforms</span>
        </div>
      </div>

      <div className="bd-engine-chip bd-engine-chip-live"><Icon icon="bolt" size={13} /> LiveQuery</div>
      <div className="bd-engine-chip bd-engine-chip-cloud"><Icon icon="cloud" size={13} /> CloudKit</div>
      <div className="bd-engine-chip bd-engine-chip-swift"><Icon icon="swift" iconType="brands" size={13} /> Swift</div>
    </div>
  </section>

  <section className="bd-section bd-feature-section">
    <div className="bd-section-heading">
      <span className="bd-section-kicker">One native data layer</span>
      <h2>Start simple. Keep the ceiling high.</h2>

      <p>
        BoutiqueDB handles the local database path first, then lets the app adopt reactive observation, private synchronization, search, vectors, and encryption only when they are useful.
      </p>
    </div>

    <div className="bd-feature-grid">
      <a className="bd-feature-card bd-feature-coral" href="/core-concepts">
        <div className="bd-feature-topline" />

        <div className="bd-feature-icon">
          <Icon icon="database" size={20} />
        </div>

        <span className="bd-feature-label">Core engine</span>
        <h3>Local-first by construction</h3>
        <p>Durable storage lives inside the app sandbox, with actor-isolated access and type-safe Structured Queries.</p>
        <span className="bd-feature-link">Explore the engine <Icon icon="arrow-right" size={12} /></span>
      </a>

      <a className="bd-feature-card bd-feature-blue" href="/guides/live-queries">
        <div className="bd-feature-topline" />

        <div className="bd-feature-icon">
          <Icon icon="bolt" size={20} />
        </div>

        <span className="bd-feature-label">Reactive UI</span>
        <h3>CDC-backed live queries</h3>
        <p><code>@LiveQuery</code> and <code>@LiveQueryOne</code> update SwiftUI from database changes without a manual refresh pipeline.</p>
        <span className="bd-feature-link">Build reactive views <Icon icon="arrow-right" size={12} /></span>
      </a>

      <a className="bd-feature-card bd-feature-violet" href="/guides/cloudkit-sync">
        <div className="bd-feature-topline" />

        <div className="bd-feature-icon">
          <Icon icon="cloud-arrow-up" size={20} />
        </div>

        <span className="bd-feature-label">Apple sync</span>
        <h3>CloudKit without a backend</h3>
        <p>Keep the local database authoritative while optionally synchronizing private user data through <code>CKSyncEngine</code>.</p>
        <span className="bd-feature-link">Configure synchronization <Icon icon="arrow-right" size={12} /></span>
      </a>

      <a className="bd-feature-card bd-feature-teal" href="/turso-features-in-apple-apps">
        <div className="bd-feature-topline" />

        <div className="bd-feature-icon">
          <Icon icon="wand-magic-sparkles" size={20} />
        </div>

        <span className="bd-feature-label">Engine extensions</span>
        <h3>Search, vectors, views, encryption</h3>
        <p>Opt into Tantivy FTS, dense and sparse vectors, incremental materialized views, and AEGIS encryption.</p>
        <span className="bd-feature-link">See Turso capabilities <Icon icon="arrow-right" size={12} /></span>
      </a>
    </div>
  </section>

  <section className="bd-section bd-architecture-section">
    <div className="bd-section-copy">
      <span className="bd-section-kicker">Designed as a system</span>
      <h2>A predictable path from SwiftUI to durable data.</h2>

      <p>
        The public API stays Swift-native. BoutiqueDB owns isolation and observation, the Turso engine owns storage, and CloudKit remains an optional synchronization layer.
      </p>

      <a className="bd-inline-link" href="/advanced/boutiquedb-architecture">
        Read the architecture guide <Icon icon="arrow-right" size={12} />
      </a>
    </div>

    <div className="bd-architecture-panel">
      <div className="bd-architecture-row">
        <div className="bd-architecture-node bd-node-swiftui">
          <span className="bd-node-icon">
            <Icon icon="mobile-screen-button" size={16} />
          </span>

          <span><strong>SwiftUI</strong><small>Views and app state</small></span>
        </div>

        <span className="bd-architecture-arrow">→</span>

        <div className="bd-architecture-node bd-node-live">
          <span className="bd-node-icon">
            <Icon icon="wave-square" size={16} />
          </span>

          <span><strong>LiveQuery</strong><small>CDC observation</small></span>
        </div>
      </div>

      <div className="bd-architecture-connector" />

      <div className="bd-architecture-core">
        <img src="/icon.png" alt="" />

        <span><strong>BoutiqueDB actor</strong><small>Queries · migrations · transactions · isolation</small></span>
      </div>

      <div className="bd-architecture-connector" />

      <div className="bd-architecture-row bd-architecture-row-bottom">
        <div className="bd-architecture-node bd-node-turso">
          <span className="bd-node-icon">
            <Icon icon="database" size={16} />
          </span>

          <span><strong>Turso engine</strong><small>Local durable storage</small></span>
        </div>

        <div className="bd-architecture-node bd-node-cloud">
          <span className="bd-node-icon">
            <Icon icon="cloud" size={16} />
          </span>

          <span><strong>CloudKit</strong><small>Optional private sync</small></span>
        </div>
      </div>
    </div>
  </section>

  <section className="bd-section bd-code-section">
    <div className="bd-code-copy">
      <span className="bd-section-kicker">Swift-native API</span>
      <h2>Define the model. Query it reactively.</h2>

      <p>
        Schema macros, structured queries, and property wrappers keep database code legible without hiding the underlying persistence model.
      </p>

      <div className="bd-check-list">
        <span><Icon icon="check" size={11} /> Type-safe query construction</span>
        <span><Icon icon="check" size={11} /> Local operation without a service</span>
        <span><Icon icon="check" size={11} /> Reactive SwiftUI observation</span>
      </div>
    </div>

    <div className="bd-code-window">
      <div className="bd-code-titlebar">
        <div className="bd-window-dots">
          <span />

          <span />

          <span />
        </div>

        <span>NotesView\.swift</span>
        <span className="bd-code-language">Swift</span>
      </div>

      ```swift
      @Table
      struct Note {
          @Column(primaryKey: true) let id: UUID
          var title: String
      }

      struct NotesView: View {
          @LiveQuery var notes: [Note]

          init(db: BoutiqueDB) {
              _notes = LiveQuery(db) {
                  Note.order { $0.title }.asSelect()
              }
          }
      }
      ```
    </div>
  </section>

  <section className="bd-section bd-principles-section">
    <div className="bd-section-heading bd-section-heading-compact">
      <span className="bd-section-kicker">Why BoutiqueDB</span>
      <h2>Native ergonomics without a low ceiling.</h2>
    </div>

    <div className="bd-principles-grid">
      <div className="bd-principle-card">
        <span className="bd-principle-number">01</span>
        <h3>Apple-platform shaped</h3>
        <p>Swift concurrency, SwiftUI observation, CloudKit, and app-sandbox storage are first-class constraints.</p>
      </div>

      <div className="bd-principle-card">
        <span className="bd-principle-number">02</span>
        <h3>SQLite-compatible foundation</h3>
        <p>Begin with familiar local persistence and selectively adopt advanced engine features as the product grows.</p>
      </div>

      <div className="bd-principle-card">
        <span className="bd-principle-number">03</span>
        <h3>No backend requirement</h3>
        <p>The application remains useful offline before synchronization or remote infrastructure is introduced.</p>
      </div>
    </div>

    <a className="bd-inline-link bd-inline-link-centered" href="/sqlite-comparison">
      Compare persistence options <Icon icon="arrow-right" size={12} />
    </a>
  </section>

  <section className="bd-final-cta">
    <div>
      <span className="bd-section-kicker">Start with the local database</span>
      <h2>Build the first reactive model in minutes.</h2>
      <p>Add the package, define a table, open the database, and connect the result to SwiftUI.</p>
    </div>

    <div className="bd-final-actions">
      <a className="bd-button bd-button-primary" href="/getting-started/quick-start">
        Open Quick Start <Icon icon="arrow-right" size={15} />
      </a>

      <a className="bd-button bd-button-ghost" href="https://github.com/tuliopc23/BoutiqueDB-Swift">
        <Icon icon="github" iconType="brands" size={15} /> GitHub
      </a>
    </div>
  </section>
</div>