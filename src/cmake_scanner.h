#ifndef CP_CMAKE_SCANNER_H
#define CP_CMAKE_SCANNER_H

#include <stdexcept>

#include "scanner_ctx.h"
#include "scanner.h"

class CMakeScanner
{
public:
    CMakeScanner()
    {
        if(yylex_init(&yyscanner))
        {
            throw std::runtime_error{"yylex_init() error"};
        }

        if(yylex_init_extra(&scannerCtx, &yyscanner))
        {
            throw std::runtime_error{"yylex_init_extra() error"};
        }
    }

    ~CMakeScanner()
    {
        yylex_destroy(yyscanner);

        if(file)
        {
            fclose(file);
        }

        if(stringBuf)
        {
            yy_delete_buffer(stringBuf, yyscanner);
        }
    }

    void SetDebug(const bool enable)
    {
        yyset_debug(enable, yyscanner);
    }

    void SetInputFile(const std::string& path)
    {
        file = fopen(path.c_str(), "rb");
        if(!file)
        {
            std::string error{"Cannot open file "};
            error += path;
            throw std::runtime_error{error};
        }
        scannerCtx.SetInputFile(path);
        yyset_in(file, yyscanner);
    }

    void SetInputString(const std::string& str)
    {
        stringBuf = yy_scan_bytes(str.c_str(), str.size(), yyscanner);
    }

    yyscan_t Raw() noexcept
    {
        return yyscanner;
    }

private:
    yyscan_t yyscanner{};
    ScannerCtx scannerCtx;
    FILE* file{};
    YY_BUFFER_STATE stringBuf{};
};

#endif // CP_CMAKE_SCANNER_H