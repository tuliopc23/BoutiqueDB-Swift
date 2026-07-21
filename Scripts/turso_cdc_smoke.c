#include <stdio.h>
#include <stdlib.h>
#include "sqlite3.h"

int main(void) {
  sqlite3 *db = NULL;
  char *err = NULL;
  int rc = sqlite3_open("/tmp/turso_cdc_smoke.db", &db);
  if (rc != SQLITE_OK) {
    printf("open fail %d\n", rc);
    return 1;
  }

  rc = sqlite3_exec(db, "DROP TABLE IF EXISTS users;", NULL, NULL, &err);
  rc = sqlite3_exec(db, "CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT);", NULL, NULL, &err);
  if (rc != SQLITE_OK) {
    printf("create fail %s\n", err ? err : "");
    return 1;
  }

  rc = sqlite3_exec(db, "PRAGMA capture_data_changes_conn('full');", NULL, NULL, &err);
  if (rc != SQLITE_OK) {
    printf("cdc pragma fail %d %s\n", rc, err ? err : "");
  }

  rc = sqlite3_exec(db, "INSERT INTO users VALUES (1, 'Alice');", NULL, NULL, &err);
  if (rc != SQLITE_OK) {
    printf("insert fail %s\n", err ? err : "");
    return 1;
  }

  sqlite3_stmt *stmt = NULL;
  rc = sqlite3_prepare_v2(
    db,
    "SELECT change_id, change_type, table_name FROM turso_cdc WHERE change_type != 2;",
    -1,
    &stmt,
    NULL
  );
  if (rc != SQLITE_OK) {
    printf("prepare fail %d %s\n", rc, sqlite3_errmsg(db));
    return 1;
  }

  int rows = 0;
  while (sqlite3_step(stmt) == SQLITE_ROW) {
    rows++;
    printf(
      "cdc row: id=%lld type=%lld table=%s\n",
      (long long)sqlite3_column_int64(stmt, 0),
      (long long)sqlite3_column_int64(stmt, 1),
      (const char *)sqlite3_column_text(stmt, 2)
    );
  }
  sqlite3_finalize(stmt);
  sqlite3_close(db);
  printf("ok rows=%d\n", rows);
  return rows > 0 ? 0 : 2;
}
