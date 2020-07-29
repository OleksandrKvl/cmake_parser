#include <unordered_map>
#include <functional>

#include "cmake_parser.h"

struct Config
{
    CMakeParser::DebugMode debugMode{CMakeParser::DebugMode::Disabled};
    CMakeParser::EvaluationMode evalMode{
        CMakeParser::EvaluationMode::Immediate};
    CMakeParser::InputMode inputMode{CMakeParser::InputMode::Interactive};
    std::string input;
};

void PrintHelp()
{
    std::cout << "Options:\n\n"
              << "-h, --help \t print this help\n\n"
              << "debug mode:\n"
              << "\t -dd \t [default] disable debug\n"
              << "\t -dp \t debug parser\n"
              << "\t -ds \t debug scanner\n"
              << "\t -df \t debug parser and scanner\n\n"
              << "evaluation mode:\n"
              << "\t -ei \t [default] immediate evaluation during parsing\n"
              << "\t -ep \t evaluation after all input is parsed\n"
              << "\t -ed \t disable evaluation, only parse\n\n"
              << "input mode:\n"
              << "\t [-ii] \t\t [default] interactive, input from terminal\n"
              << "\t -if file \t input from file\n"
              << "\t -is string \t input from next argument\n";
}

Config ParseOptions(int argc, char** argv)
{
    using namespace std::literals;
    Config config;

    for(int i = 1; i != argc; i++)
    {
        if(("-h"sv == argv[i]) || ("--help"sv == argv[i]))
        {
            PrintHelp();
            std::exit(0);
        }
        else if("-dp"sv == argv[i])
        {
            config.debugMode = CMakeParser::DebugMode::Parser;
        }
        else if("-ds"sv == argv[i])
        {
            config.debugMode = CMakeParser::DebugMode::Scanner;
        }
        else if("-df"sv == argv[i])
        {
            config.debugMode = CMakeParser::DebugMode::Full;
        }
        else if("-dd"sv == argv[i])
        {
            config.debugMode = CMakeParser::DebugMode::Disabled;
        }
        else if("-ed"sv == argv[i])
        {
            config.evalMode = CMakeParser::EvaluationMode::Disabled;
        }
        else if("-ei"sv == argv[i])
        {
            config.evalMode = CMakeParser::EvaluationMode::Immediate;
        }
        else if("-ep"sv == argv[i])
        {
            config.evalMode = CMakeParser::EvaluationMode::PostParse;
        }
        else if("-if"sv == argv[i])
        {
            if(argc - i < 2)
            {
                throw std::runtime_error{"File path is required"};
            }
            config.inputMode = CMakeParser::InputMode::File;
            config.input = argv[i + 1];
            i++;
        }
        else if("-is"sv == argv[i])
        {
            if(argc - i < 2)
            {
                throw std::runtime_error{"String input is required"};
            }
            config.inputMode = CMakeParser::InputMode::String;
            config.input = argv[i + 1];
            i++;
        }
        else if("-ii"sv == argv[i])
        {
            config.inputMode = CMakeParser::InputMode::Interactive;
        }
        else
        {
            throw std::runtime_error{"Unknown argument"};
        }
    }

    return config;
}

int main(int argc, char** argv)
{
    const auto config = ParseOptions(argc, argv);
    CMakeParser parser;

    parser.SetDebugMode(config.debugMode);
    parser.SetEvaluationMode(config.evalMode);
    parser.SetInput(config.inputMode, config.input);

    return parser.Parse();
}