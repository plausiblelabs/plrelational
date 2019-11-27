
// modulemaps don't automatically pull in SDK-relative system headers.
// But if we indirect through a header file, they do!
// So have the modulemap include this, which includes the system header.
#include <sqlite3.h>

// We also need SQLite's tokenizer declarations, which the standard header does not include.
#include "SQLiteTokenizerAPI.h"
