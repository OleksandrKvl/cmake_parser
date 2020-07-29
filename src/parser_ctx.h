#ifndef CP_PARSER_CTX_H
#define CP_PARSER_CTX_H

#include "rpn.h"

struct ParserCtx
{
    rpn::RPNExpression rpnExpr;
    std::vector<rpn::RPNExpression> rpnExprList;
    bool immediateEval{};

    // used for non-strict argument separation handling
    // enum class ArgToken
    // {
    //     Separation,
    //     BracketArg,
    //     QuotedArg,
    //     UnquotedArg
    // };

    // ArgToken lastArgToken{ArgToken::Separation};
};

#endif // CP_PARSER_CTX_H