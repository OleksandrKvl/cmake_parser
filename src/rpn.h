#ifndef CP_RPN_H
#define CP_RPN_H

#include <memory>
#include <vector>
#include <iostream>
#include <algorithm>

namespace rpn
{
// #define CP_RPN_LOG_EXPR_CREATION 1

using results_type = std::vector<std::string>;
using results_iterator = results_type::iterator;

struct CommandContext
{
    std::string result;
};

struct EvaluationContext
{
    // stack of expression results
    results_type results;

    // stack of lengths of expression results
    std::vector<std::size_t> resultsCount;

    // some context for command execution
    CommandContext commandContext;
};

class IExpression
{
public:
    virtual ~IExpression() = default;
    virtual void Evaluate(EvaluationContext& context) const = 0;
};

class RPNExpression
{
public:
    using expression_ptr = std::unique_ptr<IExpression>;

    void Push(expression_ptr expr)
    {
        rpnExprList.push_back(std::move(expr));
    }

    template<typename ExprT, typename... ExprArgs>
    void Push(ExprArgs&&... args)
    {
        Push(std::make_unique<ExprT>(std::forward<ExprArgs>(args)...));
    }

    void Evaluate() const
    {
        EvaluationContext context;
        for(const auto& expr : rpnExprList)
        {
            expr->Evaluate(context);
        }
        std::cout << context.commandContext.result;
    }

    void Clear()
    {
        rpnExprList.clear();
    }

private:
    std::vector<expression_ptr> rpnExprList;
};

class StringExpression : public IExpression
{
public:
    explicit StringExpression(std::string str) : str{std::move(str)}
    {
#if CP_RPN_LOG_EXPR_CREATION
        std::cout << "StringExpression(" << this->str << ")\n";
#endif
    }

    void Evaluate(EvaluationContext& context) const final
    {
        context.results.push_back(str);
        context.resultsCount.push_back(1);
    }

private:
    const std::string str;
};

class BracketArgExpression : public IExpression
{
public:
#if CP_RPN_LOG_EXPR_CREATION
    BracketArgExpression()
    {
        std::cout << "BracketArgExpression()\n";
    }
#endif

    void Evaluate(EvaluationContext& context) const final
    {
        // do nothing because string should already be in the results
    }
};

class ConcatExpression : public IExpression
{
public:
    explicit ConcatExpression(const std::size_t arity) : arity{arity}
    {
    }

    void Evaluate(EvaluationContext& context) const override
    {
        if(arity == 1)
        {
            // there's nothing to concat
            return;
        }

        std::string result;

        std::for_each(
            std::cend(context.results) - arity,
            std::cend(context.results),
            [&result](const auto& str) {
                result += str;
            });

        context.results.erase(
            std::end(context.results) - arity, std::end(context.results));
        context.resultsCount.erase(
            std::end(context.resultsCount) - arity,
            std::end(context.resultsCount));

        context.results.push_back(std::move(result));
        context.resultsCount.push_back(1);
    }

private:
    const std::size_t arity{};
};

class QuotedArgExpression : public ConcatExpression
{
public:
    explicit QuotedArgExpression(const std::size_t arity)
        : ConcatExpression{arity}
    {
#if CP_RPN_LOG_EXPR_CREATION
        std::cout << "QuotedArgExpression(" << arity << ")\n";
#endif
    }
};

class UnquotedArgExpression : public ConcatExpression
{
public:
    explicit UnquotedArgExpression(const std::size_t arity)
        : ConcatExpression{arity}
    {
#if CP_RPN_LOG_EXPR_CREATION
        std::cout << "UnquotedArgExpression(" << arity << ")\n";
#endif
    }
};

template<typename T>
class VarRefExpression : public ConcatExpression
{
public:
    explicit VarRefExpression(const std::size_t arity) : ConcatExpression{arity}
    {
    }

    void Evaluate(EvaluationContext& context) const override
    {
        ConcatExpression::Evaluate(context);

        const auto& variableName = context.results.back();
        auto variableValue =
            static_cast<const T&>(*this).GetVariableValue(variableName);

        // since we know that we need to push/pop exactly one argument to/from
        // both stacks, we can just rewrite last element
        context.results.back() = std::move(variableValue);
        context.resultsCount.back() = 1;
    }
};

class NormalVarRefExpression : public VarRefExpression<NormalVarRefExpression>
{
public:
    explicit NormalVarRefExpression(const std::size_t arity)
        : VarRefExpression{arity}
    {
#if CP_RPN_LOG_EXPR_CREATION
        std::cout << "NormalVarRefExpression(" << arity << ")\n";
#endif
    }

    std::string GetVariableValue(const std::string& name) const
    {
        return {"[get_normal_var(" + name + ")]"};
    }
};

class CacheVarRefExpression : public VarRefExpression<NormalVarRefExpression>
{
public:
    explicit CacheVarRefExpression(const std::size_t arity)
        : VarRefExpression{arity}
    {
#if CP_RPN_LOG_EXPR_CREATION
        std::cout << "CacheVarRefExpression(" << arity << ")\n";
#endif
    }

    std::string GetVariableValue(const std::string& name) const
    {
        return {"[get_cache_var(" + name + ")]"};
    }
};

class EnvVarRefExpression : public VarRefExpression<NormalVarRefExpression>
{
public:
    explicit EnvVarRefExpression(const std::size_t arity)
        : VarRefExpression{arity}
    {
#if CP_RPN_LOG_EXPR_CREATION
        std::cout << "EnvVarRefExpression(" << arity << ")\n";
#endif
    }

    std::string GetVariableValue(const std::string& name) const
    {
        return {"[get_env_var(" + name + ")]"};
    }
};

class FunctionRefExpression : public IExpression
{
public:
#if CP_RPN_LOG_EXPR_CREATION
    FunctionRefExpression()
    {
        std::cout << "FunctionRefExpression()\n";
    }
#endif
    void Evaluate(EvaluationContext& context) const final
    {
        context.results.push_back(GetFunctionResult(context.commandContext));
        context.resultsCount.push_back(1);
    }

    std::string GetFunctionResult(const CommandContext& commandContext) const
    {
        return {"[result_of(" + commandContext.result + ")]"};
    }
};

class CommandCallExpression : public IExpression
{
public:
    explicit CommandCallExpression(const std::size_t arity) : arity{arity}
    {
#if CP_RPN_LOG_EXPR_CREATION
        std::cout << "CommandCallExpression(" << arity << ")\n";
#endif
    }

    void Evaluate(EvaluationContext& context) const final
    {
        const auto evaluatedArity = EvaluateArity(context.resultsCount);
        auto argsEnd = std::end(context.results);
        auto argsBegin = argsEnd - evaluatedArity;

        context.commandContext.result.clear();
        CallCommand(argsBegin, argsEnd, context.commandContext);

        context.results.erase(argsBegin, argsEnd);
    }

    std::size_t EvaluateArity(std::vector<std::size_t>& resultsCount) const
    {
        std::size_t evaluatedArity{};
        for(std::size_t i{}; i != arity; i++)
        {
            evaluatedArity += resultsCount.back();
            resultsCount.pop_back();
        }
        return evaluatedArity;
    }

    void CallCommand(
        results_iterator argsBegin,
        results_iterator argsEnd,
        CommandContext& commandContext) const
    {
        const auto& name = *argsBegin;
        std::advance(argsBegin, 1);

        const std::string delimiter{", "};
        std::string result{"[call("};
        result += name + delimiter;

        std::for_each(
            argsBegin, argsEnd, [&result, &delimiter](const auto& arg) {
                result += arg + delimiter;
            });
        result.resize(result.size() - delimiter.size());
        result += ")]";

        commandContext.result = std::move(result);
    }

private:
    const std::size_t arity{};
};
} // namespace rpn

#endif // CP_RPN_H