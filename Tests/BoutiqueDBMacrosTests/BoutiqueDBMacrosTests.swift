import BoutiqueDBMacros
import MacroTesting
import Testing

@Suite(
  .macros(
    [
      "BoutiqueTable": BoutiqueTableMacro.self,
      "FTSIndex": FTSIndexMacro.self,
      "VectorIndex": VectorIndexMacro.self,
      "MaterializedView": MaterializedViewMacro.self,
    ],
    record: .missing
  )
)
struct BoutiqueDBMacrosTests {
  @Test func boutiqueTableGeneratesStrictDDL() {
    assertMacro {
      """
      @BoutiqueTable(strict: true)
      struct Note {
        let id: String
        var title: String
        var body: String
      }
      """
    } expansion: {
      """
      struct Note {
        let id: String
        var title: String
        var body: String

        public static var boutiqueTableName: String {
          "notes"
        }

        public static var boutiqueCreateStatements: [String] {
          [
            "CREATE TABLE IF NOT EXISTS \\"notes\\" (\\n  \\"id\\" TEXT PRIMARY KEY NOT NULL,\\n  \\"title\\" TEXT NOT NULL,\\n  \\"body\\" TEXT NOT NULL\\n) STRICT"
          ]
        }

        public static var boutiqueColumns: [BoutiqueColumnSpec] {
          [
            BoutiqueColumnSpec(name: "id", sqlType: "TEXT", defaultSQL: nil, isNullable: false, isPrimaryKey: true, generatedExpression: nil),
              BoutiqueColumnSpec(name: "title", sqlType: "TEXT", defaultSQL: nil, isNullable: false, isPrimaryKey: false, generatedExpression: nil),
              BoutiqueColumnSpec(name: "body", sqlType: "TEXT", defaultSQL: nil, isNullable: false, isPrimaryKey: false, generatedExpression: nil)
          ]
        }
      }

      extension Note: BoutiqueSchemaColumns {
      }
      """
    }
  }

  @Test func ftsIndexGeneratesTursoFTS() {
    assertMacro {
      """
      @FTSIndex("title", "body", tokenizer: .default)
      struct Article {
      }
      """
    } expansion: {
      """
      struct Article {

          public static var boutiqueCreateStatements: [String] {
              ["CREATE INDEX IF NOT EXISTS \\"articles_title_body_fts\\" ON \\"articles\\" USING fts(\\"title\\", \\"body\\") WITH (tokenizer = 'default')"]
          }
      }

      extension Article: BoutiqueSchema {
      }
      """
    }
  }

  @Test func vectorIndexGeneratesTursoVector() {
    assertMacro {
      """
      @VectorIndex("embedding", metric: .cosine)
      struct Document {
      }
      """
    } expansion: {
      """
      struct Document {

          public static var boutiqueCreateStatements: [String] {
              ["CREATE INDEX IF NOT EXISTS \\"documents_embedding_vector\\" ON \\"documents\\" USING vector(\\"embedding\\") WITH (metric = 'cosine')"]
          }
      }

      extension Document: BoutiqueSchema {
      }
      """
    }
  }

  @Test func materializedViewGeneratesIVM() {
    assertMacro {
      """
      @MaterializedView(as: "SELECT customer_id, SUM(amount) AS total FROM orders GROUP BY customer_id")
      struct CustomerTotals {
      }
      """
    } expansion: {
      """
      struct CustomerTotals {

          public static var boutiqueTableName: String {
              "customerTotals"
          }

          public static var boutiqueCreateStatements: [String] { ["CREATE MATERIALIZED VIEW IF NOT EXISTS \\"customerTotals\\" AS SELECT customer_id, SUM(amount) AS total FROM orders GROUP BY customer_id"] }
      }

      extension CustomerTotals: BoutiqueSchema {
      }
      """
    }
  }

  @Test func ftsRejectsBadTokenizer() {
    assertMacro {
      """
      @FTSIndex("title", tokenizer: .bogus)
      struct Bad {
      }
      """
    } diagnostics: {
      """
      @FTSIndex("title", tokenizer: .bogus)
      ┬────────────────────────────────────
      ╰─ 🛑 Unsupported FTS tokenizer '.bogus'. Allowed: .default, .raw, .simple, .whitespace, .ngram
      struct Bad {
      }
      """
    }
  }

  @Test func boutiqueTableRejectsUnsupportedStoredTypes() {
    assertMacro {
      """
      @BoutiqueTable
      struct InvalidModel {
        let id: String
        var payload: CustomPayload
      }
      """
    } diagnostics: {
      """
      @BoutiqueTable
      ┬─────────────
      ╰─ 🛑 Unsupported persisted property type 'CustomPayload'; add an explicit supported storage representation
      struct InvalidModel {
        let id: String
        var payload: CustomPayload
      }
      """
    }
  }
}
