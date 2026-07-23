import BoutiqueDB
import Foundation

@BoutiqueTable(strict: true)
@FTSIndex("title", "body")
struct Note {
  @Column(primaryKey: true) let id: String
  var title: String
  var body: String
}
