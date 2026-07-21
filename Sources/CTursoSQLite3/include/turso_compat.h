#ifndef TURSO_COMPAT_H
#define TURSO_COMPAT_H

#include "sqlite3.h"
#include <stdint.h>

/* Turso's sqlite3.h omits open flags; open_v2 ignores them but callers still pass them. */
#ifndef SQLITE_OPEN_READONLY
#define SQLITE_OPEN_READONLY 0x00000001
#endif
#ifndef SQLITE_OPEN_READWRITE
#define SQLITE_OPEN_READWRITE 0x00000002
#endif
#ifndef SQLITE_OPEN_CREATE
#define SQLITE_OPEN_CREATE 0x00000004
#endif
#ifndef SQLITE_OPEN_URI
#define SQLITE_OPEN_URI 0x00000040
#endif
#ifndef SQLITE_OPEN_MEMORY
#define SQLITE_OPEN_MEMORY 0x00000080
#endif
#ifndef SQLITE_OPEN_NOMUTEX
#define SQLITE_OPEN_NOMUTEX 0x00008000
#endif
#ifndef SQLITE_OPEN_FULLMUTEX
#define SQLITE_OPEN_FULLMUTEX 0x00010000
#endif
#ifndef SQLITE_OPEN_SHAREDCACHE
#define SQLITE_OPEN_SHAREDCACHE 0x00020000
#endif
#ifndef SQLITE_OPEN_PRIVATECACHE
#define SQLITE_OPEN_PRIVATECACHE 0x00040000
#endif

/* Swift cannot import the SQLITE_TRANSIENT cast-macro; expose a function instead. */
static inline void *turso_sqlite_transient(void) {
  return (void *)(intptr_t)-1;
}

static inline void *turso_sqlite_static(void) {
  return (void *)0;
}

/* Not implemented in Turso's C shim — no-op for API compatibility. */
static inline int sqlite3_clear_bindings(sqlite3_stmt *stmt) {
  (void)stmt;
  return SQLITE_OK;
}

#endif /* TURSO_COMPAT_H */
