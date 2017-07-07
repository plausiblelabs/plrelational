//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// Apple's SQLite headers don't expose these tokenizer structures. We need to use them for
/// full text search. This is copy/pasted straight out of the SQLite headers. We only need
/// the headers, as the dylib already includes the actual code we use.

typedef struct sqlite3_tokenizer_module sqlite3_tokenizer_module;
typedef struct sqlite3_tokenizer sqlite3_tokenizer;
typedef struct sqlite3_tokenizer_cursor sqlite3_tokenizer_cursor;

struct sqlite3_tokenizer_module {
    
    /*
     ** Structure version. Should always be set to 0 or 1.
     */
    int iVersion;
    
    /*
     ** Create a new tokenizer. The values in the argv[] array are the
     ** arguments passed to the "tokenizer" clause of the CREATE VIRTUAL
     ** TABLE statement that created the fts3 table. For example, if
     ** the following SQL is executed:
     **
     **   CREATE .. USING fts3( ... , tokenizer <tokenizer-name> arg1 arg2)
     **
     ** then argc is set to 2, and the argv[] array contains pointers
     ** to the strings "arg1" and "arg2".
     **
     ** This method should return either SQLITE_OK (0), or an SQLite error
     ** code. If SQLITE_OK is returned, then *ppTokenizer should be set
     ** to point at the newly created tokenizer structure. The generic
     ** sqlite3_tokenizer.pModule variable should not be initialized by
     ** this callback. The caller will do so.
     */
    int (*xCreate)(
                   int argc,                           /* Size of argv array */
                   const char *const*argv,             /* Tokenizer argument strings */
                   sqlite3_tokenizer **ppTokenizer     /* OUT: Created tokenizer */
                   );
    
    /*
     ** Destroy an existing tokenizer. The fts3 module calls this method
     ** exactly once for each successful call to xCreate().
     */
    int (*xDestroy)(sqlite3_tokenizer *pTokenizer);
    
    /*
     ** Create a tokenizer cursor to tokenize an input buffer. The caller
     ** is responsible for ensuring that the input buffer remains valid
     ** until the cursor is closed (using the xClose() method).
     */
    int (*xOpen)(
                 sqlite3_tokenizer *pTokenizer,       /* Tokenizer object */
                 const char *pInput, int nBytes,      /* Input buffer */
                 sqlite3_tokenizer_cursor **ppCursor  /* OUT: Created tokenizer cursor */
                 );
    
    /*
     ** Destroy an existing tokenizer cursor. The fts3 module calls this
     ** method exactly once for each successful call to xOpen().
     */
    int (*xClose)(sqlite3_tokenizer_cursor *pCursor);
    
    /*
     ** Retrieve the next token from the tokenizer cursor pCursor. This
     ** method should either return SQLITE_OK and set the values of the
     ** "OUT" variables identified below, or SQLITE_DONE to indicate that
     ** the end of the buffer has been reached, or an SQLite error code.
     **
     ** *ppToken should be set to point at a buffer containing the
     ** normalized version of the token (i.e. after any case-folding and/or
     ** stemming has been performed). *pnBytes should be set to the length
     ** of this buffer in bytes. The input text that generated the token is
     ** identified by the byte offsets returned in *piStartOffset and
     ** *piEndOffset. *piStartOffset should be set to the index of the first
     ** byte of the token in the input buffer. *piEndOffset should be set
     ** to the index of the first byte just past the end of the token in
     ** the input buffer.
     **
     ** The buffer *ppToken is set to point at is managed by the tokenizer
     ** implementation. It is only required to be valid until the next call
     ** to xNext() or xClose().
     */
    /* TODO(shess) current implementation requires pInput to be
     ** nul-terminated.  This should either be fixed, or pInput/nBytes
     ** should be converted to zInput.
     */
    int (*xNext)(
                 sqlite3_tokenizer_cursor *pCursor,   /* Tokenizer cursor */
                 const char **ppToken, int *pnBytes,  /* OUT: Normalized text for token */
                 int *piStartOffset,  /* OUT: Byte offset of token in input buffer */
                 int *piEndOffset,    /* OUT: Byte offset of end of token in input buffer */
                 int *piPosition      /* OUT: Number of tokens returned before this one */
                 );
    
    /***********************************************************************
     ** Methods below this point are only available if iVersion>=1.
     */
    
    /*
     ** Configure the language id of a tokenizer cursor.
     */
    int (*xLanguageid)(sqlite3_tokenizer_cursor *pCsr, int iLangid);
};

struct sqlite3_tokenizer {
    const sqlite3_tokenizer_module *pModule;  /* The module for this tokenizer */
    /* Tokenizer implementations will typically add additional fields */
};

struct sqlite3_tokenizer_cursor {
    sqlite3_tokenizer *pTokenizer;       /* Tokenizer for this cursor. */
    /* Tokenizer implementations will typically add additional fields */
};
