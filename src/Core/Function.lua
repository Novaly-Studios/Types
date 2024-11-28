--!native
--!optimize 2

if (not script) then
    script = game:GetService("ReplicatedFirst").TypeGuard.Core.Function
end

local Template = require(script.Parent.Parent._Template)
    type TypeCheckerConstructor<T, P...> = Template.TypeCheckerConstructor<T, P...>
    type FunctionalArg<T> = Template.FunctionalArg<T>
    type TypeChecker<ExtensionClass, Primitive> = Template.TypeChecker<ExtensionClass, Primitive>
    type SelfReturn<T, P...> = Template.SelfReturn<T, P...>

local Number = require(script.Parent.Number)
    type NumberTypeChecker = Number.NumberTypeChecker

local Util = require(script.Parent.Parent.Util)
    local CreateStandardInitial = Util.CreateStandardInitial
    local AssertIsTypeBase = Util.AssertIsTypeBase

type FunctionTypeChecker = TypeChecker<FunctionTypeChecker, ((...any) -> (...any))> & {
    CheckParamCount: ((self: FunctionTypeChecker, Checker: FunctionalArg<NumberTypeChecker>) -> (FunctionTypeChecker));
};

local FunctionChecker: (() -> (FunctionTypeChecker)), FunctionCheckerClass = Template.Create("Function")
FunctionCheckerClass._Initial = CreateStandardInitial("function")
FunctionCheckerClass._TypeOf = {"function"}

function FunctionCheckerClass:CheckParamCount(Checker)
    AssertIsTypeBase(Checker, 1)

    return self:_AddConstraint(true, "CheckParamCount", function(_, Function, Checker)
        local ParamCount, Variadic = debug.info(Function, "n")
        ParamCount = Variadic and math.huge or ParamCount
        local Success = Checker:_Check(ParamCount)

        if (Success) then
            return true
        end

        return false, `Expected function to have {Checker} parameters, got {ParamCount}`
    end, Checker)
end

return FunctionChecker