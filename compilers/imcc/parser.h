/*
 * Copyright (C) 2002-2009, Parrot Foundation.
 */

#ifndef PARROT_IMCC_PARSER_H_GUARD
#define PARROT_IMCC_PARSER_H_GUARD

typedef struct _IdList {
    char* id;
    struct _IdList*  next;
} IdList;

#include "imcparser.h"
#include "imcc/yyscanner.h"

#define KEY_BIT(argnum) (1 << (argnum))

typedef struct yyguts_t yyguts_t;

void set_filename(imc_info_t *imcc, char * const filename);

SymReg * macro(imc_info_t *imcc, char *name);

/*int yyparse(yyscan_t, imc_info_t *imcc);*/
int yylex(YYSTYPE *, yyscan_t, imc_info_t *imcc);
int yylex_destroy(yyscan_t);

int yylex_init(yyscan_t*);
int yylex_init_extra(imc_info_t *imcc, yyscan_t*);
int yyget_column(yyscan_t);
void yyset_column(int column_no , yyscan_t);
int yyerror(yyscan_t, imc_info_t*, const char *);


/* These are generated by flex. YY_EXTRA_TYPE is used also by flex, so
 * defining it is handy: we do not need typecasts. */
#define YY_EXTRA_TYPE imc_info_t*
YY_EXTRA_TYPE yyget_extra(yyscan_t yyscanner);
void yyset_extra(YY_EXTRA_TYPE user_defined, yyscan_t yyscanner);

extern void compile_file(imc_info_t *imcc, PIOHANDLE file, void *);
extern void compile_string(imc_info_t *imcc, const char *, void *);
extern INTVAL imcc_run_compilation(imc_info_t *imcc, void *);
extern INTVAL imcc_compile_buffer_safe(ARGMOD(imc_info_t *imcc),
        yyscan_t yyscanner, ARGIN(STRING *source), int is_file, int is_pasm);

int at_eof(yyscan_t yyscanner);
PIOHANDLE determine_input_file_type(imc_info_t * imcc, STRING *sourcefile);

#endif /* PARROT_IMCC_PARSER_H_GUARD */

/*
 * Local variables:
 *   c-file-style: "parrot"
 * End:
 * vim: expandtab shiftwidth=4 cinoptions='\:2=2' :
 */
