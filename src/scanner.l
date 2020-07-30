/* Stop when reach the end of yyin */
%option noyywrap

/* No default action for unrecognized symbols */
%option nodefault

/* Allow to manage current state using yy_push/pop_state() */
%option stack

/* Enable flex warnings */
%option warn

/* Enable debug output when yy_flex_debug is 1 */
%option debug

/* Suppresses inclusion of the non-ANSI header file unistd.h */
%option nounistd

/* We don't need interactive mode and related code */
/*
%option never-interactive
%option batch
*/

/* We don't need these functions */
%option nounput noinput

/* Create pure scanner */
%option reentrant

/* The type of scanner's context(yyextra) */
%option extra-type="ScannerCtx*"

/* Generate lex.backup file */
/* %option backup */

%x BOM
%x FILE_LINE
%x ARGUMENTS
%x BRACKET_SCOPE
%x BRACKET_END
%x COMMENT
%x QUOTED_ARG
%x REFERENCE
%x UNQUOTED_ARG

%top{
#include <cstdint>
}

%{
#include <limits>
#include "parser.h"
#include "scanner_ctx.h"

int isatty(int fd);

void PushState(const int new_state, yyscan_t yyscanner);
void PopState(yyscan_t yyscanner);
int TopState(yyscan_t yyscanner);

std::size_t CalcBracketsLength(
    const char* str, const int size, const bool isBracketArg);

yy::parser::location_type ExtractNextTokenLocation(
    yy::parser::location_type& current, const int nextLength);

yy::parser::symbol_type GetPreRefToken(
    yyscan_t yyscanner,
    StringLiteral& stringLiteral,
    const yy::parser::location_type& location);

#define YY_USER_ACTION  location.columns(yyleng);
%}

%%
%{
    auto& location = yyextra->location;
    auto& nextToken = yyextra->nextToken;
    auto& stringLiteral = yyextra->stringLiteral;

    if(!nextToken.empty())
    {
        location = nextToken.location;
        // current yy::parser::symbol_type doesn't clear moved-from token,
        // thus, we need to do this manually
        auto token = std::move(nextToken);
		nextToken.clear();
        return token;
    }
    location.step();
%}

    /* UTF-8 BOM */
<BOM>\xEF\xBB\xBF {
    PushState(FILE_LINE, yyscanner);

    return yy::parser::make_UTF8_BOM(location);
}

    /* Detect UTF-16/32 BE/LE BOMs but don't support them */
<BOM>(\xFE\xFF)|(\xFF\xFE)|(\x00\x00\xFE\xFF)|(\xFF\xFE\x00\x00) {
    PushState(FILE_LINE, yyscanner);

    return yy::parser::make_BAD_BOM(location);
}

    /* No BOM or undetected BOM */
<BOM>.|\n {
    PushState(FILE_LINE, yyscanner);

    yyless(0);
    location.columns(-1);
}

<FILE_LINE>[A-Za-z_][A-Za-z0-9_]* {
    return yy::parser::make_IDENTIFIER(
        {yytext, static_cast<std::string::size_type>(yyleng)}, location);
}

<FILE_LINE,ARGUMENTS>\( {
    return yy::parser::make_OPEN_PAREN(location);
}

<FILE_LINE,ARGUMENTS,REFERENCE>\) {
    return yy::parser::make_CLOSE_PAREN(location);
}

    /* Bracket comment or argument start */
<FILE_LINE,ARGUMENTS>#?\[=*\[\r?\n? {
    yyextra->isBracketArg = (yytext[0] != '#');

    if(yyextra->isBracketArg)
    {
        stringLiteral.Clear();
    }

    yyextra->bracketsLength = CalcBracketsLength(
        yytext, yyleng, yyextra->isBracketArg);
    
    if(yytext[yyleng - 1] == '\n')
    {
        location.lines();
    }

    PushState(BRACKET_SCOPE, yyscanner);
}

    /* Possible end of bracket scope */
<BRACKET_SCOPE>\]=* {
    stringLiteral.Append(yytext, yyleng);
    if(yyleng == (yyextra->bracketsLength - 1))
    {
        PushState(BRACKET_END, yyscanner);
    }
}

    /* Handle body line-by-line to avoid memory problems with huge strings */
<BRACKET_SCOPE>[^\]\n]+\n? {
    const auto endsWithLf = (yytext[yyleng - 1] == '\n');
    
    if(endsWithLf)
    {
        location.lines();
    }
    
    if(yyextra->isBracketArg)
    {
        if(endsWithLf)
        {
            stringLiteral.RemoveLastCr();
        }
        stringLiteral.Append(yytext, yyleng);
    }
}

    /* Preceding ]=* was not part of closing brackets */
<BRACKET_END>[^\]]+ {
    if(yyextra->isBracketArg)
    {
        stringLiteral.Append(yytext, yyleng);
    }
    PopState(yyscanner);
}

<BRACKET_END>\] {
    // remove preceding ]=* symbols
    stringLiteral.RemoveLast(yyextra->bracketsLength - 1);
    
    // State stack at this point: [..., FILE_LINE or ARGUMENTS, BRACKET_SCOPE],
    // hence do PopState() twice
    PopState(yyscanner);
    PopState(yyscanner);

    if(yyextra->isBracketArg)
    {
        return yy::parser::make_BRACKET_ARGUMENT(
            stringLiteral.Release(), location);
    }
    return yy::parser::make_BRACKET_COMMENT(location);
}

<FILE_LINE,ARGUMENTS># {
    PushState(COMMENT, yyscanner);
}

    /* Use \n? to handle EOF */
<COMMENT>.*\n? {
    location.lines();

    PopState(yyscanner);

    return yy::parser::make_LINE_COMMENT(location);
}

    /* Start of quoted argument */
<ARGUMENTS>\" {
    stringLiteral.Clear();

    PushState(QUOTED_ARG, yyscanner);

    return yy::parser::make_DOUBLE_QUOTE(location);
}

    /* End of quoted argument */
<QUOTED_ARG>\" {
    // append quote if it was part of legacy unquoted argument
    if(TopState(yyscanner) == UNQUOTED_ARG)
    {
        stringLiteral.Append(yytext, 1);
    }
    
    PopState(yyscanner);

    if(!stringLiteral.IsEmpty())
    {
        auto doubleQuote = yy::parser::make_DOUBLE_QUOTE(
            ExtractNextTokenLocation(location, 1));
        nextToken.move(doubleQuote);

        return yy::parser::make_QUOTED_STR(stringLiteral.Release(), location);
    }
    return yy::parser::make_DOUBLE_QUOTE(location);
}

    /* Escapes */
<QUOTED_ARG,REFERENCE,UNQUOTED_ARG>\\t {
    static constexpr char tab[] = "\t";
    stringLiteral.AppendNonId(tab, sizeof(tab) - 1);
}

<QUOTED_ARG,REFERENCE,UNQUOTED_ARG>\\r {
    static constexpr char cr[] = "\r";
    stringLiteral.AppendNonId(cr, sizeof(cr) - 1);
}

<QUOTED_ARG,REFERENCE,UNQUOTED_ARG>\\n {
    static constexpr char lf[] = "\n";
    stringLiteral.AppendNonId(lf, sizeof(lf) - 1);
}

    /* Line continuation */
<QUOTED_ARG>\\\r?\n {
    location.lines();
}

    /* Escape any non-alphanumeric with \ */
<QUOTED_ARG,REFERENCE,UNQUOTED_ARG>\\[^A-Za-z0-9;] {
    stringLiteral.AppendNonId(&yytext[1], 1);
}

    /* \; encodes itself in quoted and unquoted arguments */
<QUOTED_ARG,UNQUOTED_ARG>\\; {
    stringLiteral.Append(yytext, 1 + 1);
}

    /* \; escapes ; inside reference */
<REFERENCE>\\; {
    stringLiteral.AppendNonId(&yytext[1], 1);
}

    /* Not reference */
<QUOTED_ARG,REFERENCE,UNQUOTED_ARG>\$ {
    stringLiteral.AppendNonId(yytext, 1);
}

    /* It should really be an error */
    /* <REFERENCE>\$ {
    return yy::parser::make_YYUNDEF(location);
} */

    /* Reference */
<QUOTED_ARG,REFERENCE,UNQUOTED_ARG>\$\{ {
    PushState(REFERENCE, yyscanner);

    if(!stringLiteral.IsEmpty())
    {
        auto refOpen = yy::parser::make_REF_OPEN(
            ReferenceType::Normal, ExtractNextTokenLocation(location, yyleng));
        nextToken.move(refOpen);

        return GetPreRefToken(yyscanner, stringLiteral, location);
    }

    return yy::parser::make_REF_OPEN(ReferenceType::Normal, location);
}

<QUOTED_ARG,REFERENCE,UNQUOTED_ARG>\$ENV\{ {
    PushState(REFERENCE, yyscanner);

    if(!stringLiteral.IsEmpty())
    {
        auto refOpen = yy::parser::make_REF_OPEN(
            ReferenceType::Env, ExtractNextTokenLocation(location, yyleng));
        nextToken.move(refOpen);

        return GetPreRefToken(yyscanner, stringLiteral, location);
    }

    return yy::parser::make_REF_OPEN(ReferenceType::Env, location);
}

<QUOTED_ARG,REFERENCE,UNQUOTED_ARG>\$CACHE\{ {
    PushState(REFERENCE, yyscanner);

    if(!stringLiteral.IsEmpty())
    {        
        auto refOpen = yy::parser::make_REF_OPEN(
            ReferenceType::Cache, ExtractNextTokenLocation(location, yyleng));
        nextToken.move(refOpen);

        return GetPreRefToken(yyscanner, stringLiteral, location);
    }
    
    return yy::parser::make_REF_OPEN(ReferenceType::Cache, location);
}

    /* Detect bad reference type, not strictly required but CMake has it */
<QUOTED_ARG,REFERENCE,UNQUOTED_ARG>\$[A-Za-z0-9_]+\{ {
    return yy::parser::make_YYUNDEF(location);
}

    /* Append any non-special symbols, handle line-by-line */
<QUOTED_ARG>[^\\\"$\n]+ {
    // stringLiteral.Append(yytext, yyleng);
    stringLiteral.Append(yytext, yyleng);
}

<QUOTED_ARG>\n {
    location.lines();

    stringLiteral.RemoveLastCr();
    stringLiteral.Append(yytext, 1);
}

    /* Detect IDENTIFIER of a command name */
<REFERENCE>[A-Za-z_][A-Za-z0-9_]* {
    stringLiteral.AppendId(yytext, yyleng);
}

    /* General symbols that are allowed in reference */
<REFERENCE>[A-Za-z0-9/_.+\-]+ {
    stringLiteral.AppendNonId(yytext, yyleng);
}

<REFERENCE>\( {
    if(!stringLiteral.IsEmpty() && stringLiteral.IsId())
    {
        auto openParen = yy::parser::make_OPEN_PAREN(
            ExtractNextTokenLocation(location, 1));
        nextToken.move(openParen);

        return yy::parser::make_IDENTIFIER(stringLiteral.Release(), location);
    }
    return yy::parser::make_OPEN_PAREN(location);
}

<REFERENCE>[ \t]+ {
    if(!stringLiteral.IsEmpty() && stringLiteral.IsId())
    {
        auto space = yy::parser::make_SPACES(
            ExtractNextTokenLocation(location, yyleng));
        nextToken.move(space);

        return yy::parser::make_IDENTIFIER(stringLiteral.Release(), location);
    }
    return yy::parser::make_SPACES(location);
}

<REFERENCE>\} {
    PopState(yyscanner);

    if(!stringLiteral.IsEmpty())
    {
        auto refClose = yy::parser::make_REF_CLOSE(
            ExtractNextTokenLocation(location, 1));
        nextToken.move(refClose);

        return yy::parser::make_REF_VAR_NAME(stringLiteral.Release(), location);
    }

    return yy::parser::make_REF_CLOSE(location);
}

    /* Unquoted argument */

    /* Start of unquoted argument */
<ARGUMENTS>[^ \t\n\(\)#\"] {
    PushState(UNQUOTED_ARG, yyscanner);
    
    stringLiteral.Clear();
    
    yyless(0);
    location.columns(-1);
}

    /* Start of legacy unquoted argument, e.g. f(a"b") */
<UNQUOTED_ARG>\" {
    if(!stringLiteral.IsEmpty())
    {
        PushState(QUOTED_ARG, yyscanner);

        auto doubleQuote = yy::parser::make_DOUBLE_QUOTE(
            ExtractNextTokenLocation(location, 1));
        nextToken.move(doubleQuote);

        // report current literal, append quote to the next one
        auto literal = stringLiteral.Release();
        stringLiteral.Append(yytext, 1);
        return yy::parser::make_UNQUOTED_STR(std::move(literal), location);
    }

    PushState(QUOTED_ARG, yyscanner);
    stringLiteral.Append(yytext, 1);
    return yy::parser::make_DOUBLE_QUOTE(location);
}

    /* 
        Unquoted string sequence, not including references and escapes,
        plus a legacy make-style references, e.g. $(var)
    */
<UNQUOTED_ARG>[^ \t\n\(\)#\"\\$]+|\$\([A-Za-z0-9_]*\) {
    stringLiteral.Append(yytext, yyleng);
}

    /* End of unquoted argument */
<UNQUOTED_ARG>[ \t\n\(\)#\"] {
    PopState(yyscanner);

    yyless(0);
    const auto lineEndingLength = stringLiteral.RemoveLastCr() ? (1 + 1) : 1;
    location.columns(-lineEndingLength);

    if(!stringLiteral.IsEmpty())
    {
        return yy::parser::make_UNQUOTED_STR(stringLiteral.Release(), location);
    }
}

<*>\r?\n {
    location.lines();
    return yy::parser::make_EOL(location);
}

    /* This should work for non-interactive mode */
    /* <*>(\r\n)+ {
    location.lines(yyleng/2);
    return yy::parser::make_EOL(location);
}

<*>\n+ {
    location.lines(yyleng);
    return yy::parser::make_EOL(location);
} */

<FILE_LINE,ARGUMENTS>[ \t]+ {
    return yy::parser::make_SPACES(location);
}

<*>. {
    return yy::parser::make_YYUNDEF(location);
}

    /*
    EOF is valid only in FILE_LINE and BOM state, generate final EOL because 
    rules in parser work with lines and always expect EOL.
    */
<FILE_LINE,BOM><<EOF>> {
    auto eof = yy::parser::make_YYEOF(location);
    nextToken.move(eof);

    return yy::parser::make_EOL(location);
}

    /* In all other states EOF is invalid */
<<EOF>> {
    return yy::parser::make_YYUNDEF(location);
}

%%

void PushState(const int new_state, yyscan_t yyscanner)
{
    yy_push_state(new_state, yyscanner);
}

void PopState(yyscan_t yyscanner)
{
    yy_pop_state(yyscanner);
}

int TopState(yyscan_t yyscanner)
{
    return yy_top_state(yyscanner);
}

std::size_t CalcBracketsLength(
    const char* str, const int size, const bool isBracketArg)
{
    std::size_t length = size;
    
    if(!isBracketArg)
    {
        length--;
    }

    if(str[size - 1] == '\n')
    {
        length--;
        if(str[size - 2] == '\r')
        {
            length--;
        }
    }

    return length;
}

// Returns location of nextLength-from-the-end characters and subtracts current 
//  location appropriately
yy::parser::location_type ExtractNextTokenLocation(
    yy::parser::location_type& current, const int nextLength)
{
    auto nextLocation{current};
    current.columns(-nextLength);
    nextLocation.begin = current.end;

    return nextLocation;
}

yy::parser::symbol_type GetPreRefToken(
    yyscan_t yyscanner,
    StringLiteral& stringLiteral,
    const yy::parser::location_type& location)
{
    if(TopState(yyscanner) == QUOTED_ARG)
    {
        return yy::parser::make_QUOTED_STR(stringLiteral.Release(), location);
    }
    else if(TopState(yyscanner) == UNQUOTED_ARG)
    {
        return yy::parser::make_UNQUOTED_STR(stringLiteral.Release(), location);
    }
    return yy::parser::make_REF_VAR_NAME(stringLiteral.Release(), location);
}

// simple implementation for current use case
int isatty(int fd)
{
    if(fd == fileno(stdin))
    {
        return 1;
    }
    return 0;
}