/* generate c++ parser, c++ parser is always pure */
%skeleton "lalr1.cc"
%require "3.6.1"
%language "c++"

/* Use built-in variant type to allow use of non-POD types for symbols */
%define api.value.type variant

/* Generate make_TOKEN_NAME functions */
%define api.token.constructor

/* Generate the parser description file */
%verbose
/* Enable run-time traces (yydebug) */
%define parse.trace
/* Enable built-in assertions */
%define parse.assert

/* Detailed error info */
%define parse.error verbose
%define parse.lac full

/* We don't use character literals as tokens */
%define api.token.raw

/* Generate locations.h */
%locations
%define api.location.file "location.h"

/* Types required for tokens, also available to others, 
    location: at the top of parser_header.h
*/
%code requires
{
    #include <string>
    #include "parser_ctx_fwd.h"
    
    enum class ReferenceType
    {
        Normal,
        Cache,
        Env
    };
    
    using yyscan_t = void*;
}

/* Things that are provided to others, location: at the bottom of 
    parser_header.h
*/
%code provides
{
    #define YY_DECL yy::parser::symbol_type yylex(yyscan_t yyscanner)
}

%lex-param {yyscan_t yyscanner}
%parse-param {yyscan_t yyscanner}
%parse-param {ParserCtx& ctx}

/* Placed at the very beginning of the .cpp file, even before 
    #include "parser_header.h"
*/
%code top {}

/* Things that are used in actions, location: at the top of .cpp, after 
    #include "parser_header.h"
*/
%code
{
    #include <iostream>
    #include <memory>
    #include <vector>

    #include "scanner_ctx_fwd.h"

    YY_DECL;
    #define YY_HEADER_EXPORT_START_CONDITIONS
    #include "scanner.h"

    #include "parser_ctx.h"
    using namespace rpn;

    extern void PushState(const int new_state, yyscan_t yyscanner);
    extern void PopState(yyscan_t yyscanner);
}

/* 
Implementation of non-strict CMake arguments separation has 3 sr-conflicts which
are resolved correctly.
*/
/* %expect 3 */

/* Expect 0 conflicts in strict implementation */
%expect 0

/* declare tokens */
%token UTF8_BOM                         "UTF-8 BOM"
%token BAD_BOM                          "non UTF-8 BOM"
%token EOL                              "end of line"
%token SPACES                            "space(s)"
%token<std::string> IDENTIFIER          "command name"
%token OPEN_PAREN                       "open paren"
%token CLOSE_PAREN                      "close paren"
%token LINE_COMMENT                     "line comment"
%token<std::string> BRACKET_ARGUMENT    "bracket argument"
%token BRACKET_COMMENT                  "bracket comment"
%token DOUBLE_QUOTE                     "double quote"
%token<ReferenceType> REF_OPEN          "reference opening"
%token REF_CLOSE                        "reference closing"
%token<std::string> REF_VAR_NAME        "variable name"
%token<std::string> QUOTED_STR          "quoted argument chars"
%token<std::string> UNQUOTED_STR        "unquoted argument chars"

%nterm<std::size_t> arguments
%nterm<std::size_t> argument_list
%nterm<std::size_t> quoted_argument
%nterm<std::size_t> quoted_element_list
%nterm<std::size_t> unquoted_argument
%nterm<std::size_t> var_reference_list
%nterm<std::size_t> reference
%nterm<std::size_t> parenthesized_arguments

%%

file
    : {
        PushState(BOM, yyscanner);
    } bom file_element_list {
        PopState(yyscanner);
    }
    ;

bom
    : %empty
    | UTF8_BOM
    | BAD_BOM {
        error(@1, "only UTF-8 BOM is supported");
        YYERROR;
    }
    ;

file_element_list
    : %empty
    | file_element_list file_element
    ;

file_element
    : space_list command_invocation space_list file_line_ending {
        if(ctx.immediateEval)
        {
            ctx.rpnExpr.Evaluate();
            std::cout << '\n';
        }
        else
        {
            ctx.rpnExprList.push_back(std::move(ctx.rpnExpr));
        }
        ctx.rpnExpr.Clear();
    }
    | space_list file_line_ending
    ;

file_line_ending
    : line_ending
    | bracket_comments space_list line_ending
    ;

bracket_comments
    : BRACKET_COMMENT
    | bracket_comments space_list BRACKET_COMMENT
    ;

command_invocation
    : IDENTIFIER {
        ctx.rpnExpr.Push<StringExpression>(std::move($1));
    } space_list OPEN_PAREN {
        PushState(ARGUMENTS, yyscanner);
    }
    arguments
    CLOSE_PAREN {
        ctx.rpnExpr.Push<CommandCallExpression>($arguments + 1);

        PopState(yyscanner);
    }
    ;

/* 
Strict version, separation is required between all arguments.
Corresponds to BNF specification.
*/
arguments
    : zero_or_more_separation {
        $$ = 0;
    }
    | zero_or_more_separation argument_list zero_or_more_separation {
        $$ = $2;
    }
    ;

/* For some unknown reason bracket comments are allowed inside arguments */
argument_list
    : argument {
        $$ = 1;
    }
    | parenthesized_arguments {
        $$ = $1;
    }
    | BRACKET_COMMENT {
        $$ = 0;
    }
    | argument_list one_or_more_separation argument {
        $$ = $1 + 1;
    }
    | argument_list zero_or_more_separation BRACKET_COMMENT {
        $$ = $1;
    }
    | argument_list zero_or_more_separation parenthesized_arguments {
        $$ = $1 + $3;
    }
    ;

parenthesized_arguments
    : OPEN_PAREN {
        ctx.rpnExpr.Push<StringExpression>("(");
        ctx.rpnExpr.Push<UnquotedArgExpression>(1);
    } arguments CLOSE_PAREN {
        $$ = $arguments + 1 + 1;
        ctx.rpnExpr.Push<StringExpression>(")");
        ctx.rpnExpr.Push<UnquotedArgExpression>(1);
    }
    ;

one_or_more_separation
    : separation
    | one_or_more_separation separation
    ;

zero_or_more_separation
    : %empty
    | one_or_more_separation
    ;

argument
    : BRACKET_ARGUMENT {
        ctx.rpnExpr.Push<StringExpression>(std::move($1));
        ctx.rpnExpr.Push<BracketArgExpression>();
    }
    | quoted_argument {
        ctx.rpnExpr.Push<QuotedArgExpression>($1);
    }
    | unquoted_argument {
        ctx.rpnExpr.Push<UnquotedArgExpression>($1);
    }
    ;

/*
Non-strict arguments separation that produces warning instead of errors.
Corresponds to current CMake implementation. Non-first bracket argument 
should always have separation before(and after if there're more arguments).
Warning is reported for quoted+unquoted, close_paren+unquoted, 
close_paren+quoted. It also allows bracket comments in arguments.
*/
/* arguments
    : %empty {
        $$ = 0;
        ctx.lastArgToken = ParserCtx::ArgToken::Separation;
    }
    | arguments argument {
        $$ = $1 + 1;
    }
    | arguments BRACKET_COMMENT {
        $$ = $arguments;
        ctx.lastArgToken = ParserCtx::ArgToken::BracketArg;
    }
    | arguments separation {
        ctx.lastArgToken = ParserCtx::ArgToken::Separation;
    }
    | arguments[old_args] OPEN_PAREN {
        ctx.rpnExpr.Push<StringExpression>("(");
        ctx.rpnExpr.Push<UnquotedArgExpression>(1);
    } arguments[new_args] CLOSE_PAREN {
        $$ = $old_args + $new_args + 1 + 1;
        ctx.rpnExpr.Push<StringExpression>(")");
        ctx.rpnExpr.Push<UnquotedArgExpression>(1);
        ctx.lastArgToken = ParserCtx::ArgToken::UnquotedArg;
    }
    ;

argument
    : BRACKET_ARGUMENT  {
        if(ctx.lastArgToken != ParserCtx::ArgToken::Separation)
        {
            error(@1, "Error: separation is needed between arguments");
            YYERROR;
        }
        ctx.lastArgToken = ParserCtx::ArgToken::BracketArg;
        ctx.rpnExpr.Push<StringExpression>(std::move($1));
        ctx.rpnExpr.Push<BracketArgExpression>();
    }
    | quoted_argument {
        if(ctx.lastArgToken == ParserCtx::ArgToken::BracketArg)
        {
            error(@1, "Error: separation is needed between arguments");
            YYERROR;
        }
        else if(ctx.lastArgToken != ParserCtx::ArgToken::Separation)
        {
            error(@1, "Warning: separation is needed between arguments");
        }
        ctx.lastArgToken = ParserCtx::ArgToken::QuotedArg;

        ctx.rpnExpr.Push<QuotedArgExpression>($1);
    }
    | unquoted_argument {
        if(ctx.lastArgToken == ParserCtx::ArgToken::BracketArg)
        {
            error(@1, "Error: separation is needed between arguments");
            YYERROR;
        }
        else if(ctx.lastArgToken != ParserCtx::ArgToken::Separation)
        {
            error(@1, "Warning: separation is needed between arguments");
        }
        ctx.lastArgToken = ParserCtx::ArgToken::UnquotedArg;

        ctx.rpnExpr.Push<UnquotedArgExpression>($1);
    }
    ; */

quoted_argument
    : DOUBLE_QUOTE DOUBLE_QUOTE {
        $$ = 1;
        ctx.rpnExpr.Push<StringExpression>("");
    }
    | DOUBLE_QUOTE quoted_element_list DOUBLE_QUOTE {
        $$ = $2;
    }
    ;

quoted_element_list
    : quoted_element {
        $$ = 1;
    }
    | quoted_element_list quoted_element {
        $$ = $1 + 1;
    }
    ;
    
quoted_element
    : QUOTED_STR {
        ctx.rpnExpr.Push<StringExpression>(std::move($1));
    }
    | reference
    ;

unquoted_argument
    : unquoted_element {
        $$ = 1;
    }
    | unquoted_argument unquoted_element {
        $$ = $1 + 1;
    }
    | unquoted_argument quoted_argument {
        $$ = $1 + 1;
    }
    ;

unquoted_element
    : UNQUOTED_STR {
        ctx.rpnExpr.Push<StringExpression>(std::move($1));
    }
    | reference
    ;

/*
Possible solution to avoid SR-conflicts requires additional UNQUOTED_START 
UNQUOTED_END tokens.
*/
/* unquoted_argument
    : UNQUOTED_START unquoted_element_list UNQUOTED_END
    ;

unquoted_element_list
    : UNQUOTED_STR
    | reference
    | unquoted_argument UNQUOTED_STR
    | unquoted_argument reference
    | unquoted_argument quoted_argument
    ; */

reference
    : REF_OPEN REF_CLOSE {
        $$ = 1;
        // empty reference always evaluates to empty string
        ctx.rpnExpr.Push<StringExpression>("");
    }
    | REF_OPEN var_reference_list REF_CLOSE {
        $$ = $2;
        switch($1)
        {
        case ReferenceType::Normal:
            ctx.rpnExpr.Push<NormalVarRefExpression>($$);
            break;
        case ReferenceType::Cache:
            ctx.rpnExpr.Push<CacheVarRefExpression>($$);
            break;
        case ReferenceType::Env:
            ctx.rpnExpr.Push<EnvVarRefExpression>($$);
            break;
        }
    }
    | REF_OPEN command_invocation REF_CLOSE {
        if($1 != ReferenceType::Normal)
        {
            error(@1,
                "Only normal reference opening(${...}) "
                "is allowed for command reference");
            YYERROR;
        }
        $$ = 1;
        ctx.rpnExpr.Push<FunctionRefExpression>();
    }
    ;

var_reference_list
    : var_reference_element {
        $$ = 1;
    }
    | var_reference_list var_reference_element {
        $$ = $1 + 1;
    }
    ;

var_reference_element
    : REF_VAR_NAME {
        ctx.rpnExpr.Push<StringExpression>(std::move($1));
    }
    | reference
    ;

separation
    : SPACES
    | line_ending
    ;

line_ending
    : EOL
    | LINE_COMMENT  /* LINE_COMMENT contains EOL */
    ;

space_list
    : %empty
    | SPACES
    ;

%%

namespace yy
{
    void parser::error (const location_type& location, const std::string& msg)
    {
        std::cerr << location << " : " << msg << '\n';
    }
}