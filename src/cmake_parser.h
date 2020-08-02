#ifndef CP_CMAKE_PARSER_H
#define CP_CMAKE_PARSER_H

#include "cmake_scanner.h"
#include "parser_ctx.h"
#include "parser.h"

class CMakeParser
{
public:
    CMakeParser() : parser{scanner.Raw(), parserCtx}
    {
    }

    int Parse()
    {
        const auto parseErr = parser.parse();
        if(!parseErr && (evalMode == EvaluationMode::PostParse))
        {
            Evaluate();
        }
        return parseErr;
    }

    void Evaluate() const
    {
        for(const auto& expr : parserCtx.rpnExprList)
        {
            expr.Evaluate();
            std::cout << '\n';
        }
    }

    enum class InputMode
    {
        Interactive,
        File,
        String
    };

    void SetInput(const InputMode mode, const std::string& input)
    {
        if(mode == InputMode::File)
        {
            scanner.SetInputFile(input);
        }
        else if(mode == InputMode::String)
        {
            scanner.SetInputString(input);
        }
    }

    enum class DebugMode
    {
        Disabled,
        Parser,
        Scanner,
        Full
    };

    void SetDebugMode(const DebugMode mode)
    {
        switch(mode)
        {
        case DebugMode::Disabled:
            parser.set_debug_level(0);
            scanner.SetDebug(false);
            break;
        case DebugMode::Parser:
            parser.set_debug_level(1);
            break;
        case DebugMode::Scanner:
            scanner.SetDebug(true);
            break;
        case DebugMode::Full:
            parser.set_debug_level(1);
            scanner.SetDebug(true);
            break;
        default:
            break;
        }
    }

    enum class EvaluationMode
    {
        Disabled,
        Immediate,
        PostParse
    };

    void SetEvaluationMode(const EvaluationMode mode) noexcept
    {
        evalMode = mode;
        parserCtx.immediateEval = (evalMode == EvaluationMode::Immediate);
    }

private:
    CMakeScanner scanner;
    ParserCtx parserCtx;
    yy::parser parser;
    EvaluationMode evalMode;
};

#endif // CP_CMAKE_PARSER_H