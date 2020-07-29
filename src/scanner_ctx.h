#ifndef CP_SCANNER_CTX_H
#define CP_SCANNER_CTX_H

#include "parser.h"

class StringLiteral
{
public:
    void Append(const char* str, const std::string::size_type len)
    {
        literal.append(str, len);
    }

    void AppendId(const char* str, const std::string::size_type len)
    {
        Append(str, len);
    }

    void AppendNonId(const char* str, const std::string::size_type len)
    {
        Append(str, len);
        isId = false;
    }

    void RemoveLast(const std::size_t n)
    {
        literal.erase(literal.size() - n);
    }

    // removes last CR if any, returns true if CR was there
    bool RemoveLastCr()
    {
        if(!literal.empty() && (literal.back() == '\r'))
        {
            literal.pop_back();
            return true;
        }
        return false;
    }

    void Clear() noexcept
    {
        literal.clear();
        isId = true;
    }

    bool IsEmpty() const noexcept
    {
        return literal.empty();
    }

    bool IsId() const noexcept
    {
        return isId;
    }

    std::string Release()
    {
        auto current = std::move(literal);
        Clear();
        return current;
    }

private:
    std::string literal;
    bool isId{true};
};

struct ScannerCtx
{
    void SetInputFile(const std::string path)
    {
        filepath = path;
        location.initialize(&filepath);
    }

    bool isBracketArg{};
    std::size_t bracketsLength{};
    StringLiteral stringLiteral;
    yy::parser::symbol_type nextToken{};
    yy::parser::location_type location{};
    std::string filepath;
};

#endif // CP_SCANNER_CTX_H