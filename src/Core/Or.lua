--!native
--!optimize 2

if (not script) then
    script = game:GetService("ReplicatedFirst").TypeGuard.Core.Or
end

local Template = require(script.Parent.Parent:WaitForChild("_Template"))
    type TypeCheckerConstructor<T, P...> = Template.TypeCheckerConstructor<T, P...>
    type SignatureTypeChecker = Template.SignatureTypeChecker
    type FunctionalArg<T> = Template.FunctionalArg<T>
    type TypeChecker<ExtensionClass, Primitive> = Template.TypeChecker<ExtensionClass, Primitive>
    type SelfReturn<T, P...> = Template.SelfReturn<T, P...>

local Util = require(script.Parent.Parent:WaitForChild("Util"))
    local ConcatWithToString = Util.ConcatWithToString
    local StructureStringMT = Util.StructureStringMT
    local AssertIsTypeBase = Util.AssertIsTypeBase
    local ExpectType = Util.ExpectType
    local Expect = Util.Expect

local Number = require(script.Parent.Number)

export type OrTypeChecker = TypeChecker<OrTypeChecker, any> & {
    IsAValueIn: ((self: OrTypeChecker, Values: FunctionalArg<{any}>) -> (OrTypeChecker));
    IsATypeIn: ((self: OrTypeChecker, Types: FunctionalArg<{SignatureTypeChecker}>) -> (OrTypeChecker));
    IsAKeyIn: ((self: OrTypeChecker, Map: FunctionalArg<{[any]: any}>) -> (OrTypeChecker));

    DefineGetType: ((self: OrTypeChecker, GetTypeIndexFromValue: (any) -> (SignatureTypeChecker?)) -> (OrTypeChecker));
    DefineDivide: ((self: OrTypeChecker, Divider: (() -> ())) -> (OrTypeChecker));
};

type OrConstructor = ((Types: FunctionalArg<SignatureTypeChecker>?, ...FunctionalArg<any>) -> (OrTypeChecker)) &
                     ((Values: FunctionalArg<{any}>, ...FunctionalArg<any>) -> (OrTypeChecker))
local Or: OrConstructor, OrClass = Template.Create("Or")

function OrClass:_Initial(Value)
    return true
end

function OrClass:DefineGetType(GetTypeIndexFromValue)
    ExpectType(GetTypeIndexFromValue, Expect.FUNCTION, 1)
    self = self:Copy()
    self._GetTypeIndexFromValue = GetTypeIndexFromValue
    self:_Changed()
    return self
end

function OrClass:DefineDivide(Divider)
    ExpectType(Divider, Expect.FUNCTION, 1)
    self = self:Copy()
    self._Divider = Divider
    self:_Changed()
    return self
end

local function _IsAValueIn(_self, TargetValue, Options)
    for _, Value in Options do
        if (Value == TargetValue) then
            return true
        end
    end

    return false, `Value {TargetValue} was not found in table {ConcatWithToString(Options, ", ")}`
end
function OrClass:IsAValueIn(Options)
    ExpectType(Options, Expect.TABLE_OR_FUNCTION, 1)
    return self:_AddConstraint(false, "IsAValueIn", _IsAValueIn, Options)
end

local function _IsAKeyIn(_self, Key, Options)
    if (Options[Key] == nil) then
        local Keys = {}

        for Key in Options do
            table.insert(Keys, Key)
        end

        return false, `Key {Key} was not found in set ({ConcatWithToString(Keys, ", ")})`
    end

    return true
end
function OrClass:IsAKeyIn(Options)
    ExpectType(Options, Expect.TABLE_OR_FUNCTION, 1)
    return self:_AddConstraint(false, "IsAKeyIn", _IsAKeyIn, Options)
end

local function _IsATypeIn(_self, Value, Options)
    for _, TypeChecker in Options do
        if (TypeChecker:_Check(Value)) then
            return true
        end
    end

    -- Failed -> compute most similar type and show problems with that specifically.
    local BestMatch
    local BestMatchScore = 0

    for _, TypeChecker in Options do
        local Similarity = TypeChecker.Similarity
        local Score = (Similarity and Similarity(TypeChecker, Value) or 0)

        if (Score > BestMatchScore) then
            BestMatch = TypeChecker
            BestMatchScore = Score
        end
    end

    -- No best match -> show all failed type checkers.
    if (BestMatchScore == 0) then
        return false, `Value '{Value}' has no best match on type set ({ConcatWithToString(Options, ", ")})`
    end

    -- This can help with object & array disjunctions, where we show the closest structural match.
    return false, `Value '{Value}' did not satisfy best match: {BestMatch}`
end
function OrClass:IsATypeIn(Options)
    ExpectType(Options, Expect.TABLE_OR_FUNCTION, 1)
    for _, Option in Options do
        AssertIsTypeBase(Option, 1)
    end

    local CompleteList = table.create(#Options)
    setmetatable(CompleteList, StructureStringMT)

    -- Flatten pure IsATypeIn disjunctions into single list.
    -- Can't really do this if it has other constraints as they would be erased.
    for _, Option in Options do
        if (Option.Type == "Or") then
            local IsATypeIn = Option:GetConstraint("IsATypeIn")
            if (IsATypeIn ~= nil and (#Option._ActiveConstraints == 1)) then
                for _, Checker in IsATypeIn[1] do
                    table.insert(CompleteList, Checker)
                end
                continue
            end
        end

        table.insert(CompleteList, Option)
    end

    -- Merge existing IsATypeIn constraints into one list.
    local IsATypeIn, Index = self:GetConstraint("IsATypeIn")
    if (IsATypeIn) then
        for _, Checker in IsATypeIn[1] do
            table.insert(CompleteList, Checker)
        end

        local Copy = self:Copy()
        local NewActiveConstraints = table.clone(Copy._ActiveConstraints)
        NewActiveConstraints[Index] = table.clone(NewActiveConstraints[Index])
        NewActiveConstraints[Index][2] = {CompleteList}
        Copy._ActiveConstraints = NewActiveConstraints
        return Copy
    end

    return self:_AddConstraint(false, "IsATypeIn", _IsATypeIn, CompleteList)
end

-- Disables leading serialization (record repeat number of that type before the sequence, instead of before each element).
function OrClass:NoLeads()
    self:_AddTag("NoLeads")
end

local function TestComparability(X, Y)
    return (X < Y) ~= nil
end
function OrClass:InitialConstraintsDirectVariadic(...)
    local First = select(1, ...)
    local Packed = {...}

    -- If it's a TypeChecker then we use a disjunction of types.
    if (type(First) == "table" and First._TC) then
        return self:IsATypeIn(Packed)
    end
    
    -- Otherwise we use a disjunction of values.
    -- Always more efficient to put it in a dict than using table.find with a list.
    -- But only possible to do efficiently during serialization with deterministically orderable values.
    if (pcall(TestComparability, First, (select(2, ...)))) then
        local AsKeys = {}
        for _, Value in Packed do
            AsKeys[Value] = true
        end
        return self:IsAKeyIn(AsKeys)
    end

    return self:IsAValueIn(Packed)
end

function OrClass:_UpdateSerialize()
    if (self:_HasFunctionalConstraints()) then
        self._Serialize = function(_, _, _)
            error("Functional constraints currently not supported")
        end
        self._Deserialize = function(_, _)
            error("Functional constraints currently not supported")
        end
        return
    end

    -- Serializes one of multiple values.
    local IsAValueIn = self:GetConstraint("IsAValueIn")
    if (IsAValueIn) then
        local Values = IsAValueIn[1]
        local NumberSerializer = Number(1, math.max(1, #Values)):Integer()
            local NumberDeserialize = NumberSerializer._Deserialize
            local NumberSerialize = NumberSerializer._Serialize

        self._Serialize = function(Buffer, Value, Cache)
            NumberSerialize(Buffer, table.find(Values, Value), Cache)
        end
        self._Deserialize = function(Buffer, Cache)
            return Values[NumberDeserialize(Buffer, Cache)]
        end

        return
    end

    -- Serializes one of multiple keys.
    local IsAKeyIn = self:GetConstraint("IsAKeyIn")
    if (IsAKeyIn) then
        local AsArray = {}

        -- Check for non-string keys, set serializer & deserializer to error if any are found.
        for Key in IsAKeyIn[1] do
            table.insert(AsArray, Key)

            if (type(Key) == "string") then
                continue
            end

            self._Serialize = function(_Buffer, _Value, _Cache)
                error("Cannot serialize with non-string key as Or")
            end
            self._Deserialize = function(_Buffer, _Cache)
                error("Cannot deserialize with non-string key as Or")
            end

            return
        end

        -- Sort string keys & use them as the array indexes.
        table.sort(AsArray)

        local NumberSerializer = Number(1, math.max(1, #AsArray)):Integer()
            local NumberDeserialize = NumberSerializer._Deserialize
            local NumberSerialize = NumberSerializer._Serialize

        self._Serialize = function(Buffer, Value, Cache)
            NumberSerialize(Buffer, table.find(AsArray, Value), Cache)
        end
        self._Deserialize = function(Buffer, Cache)
            return AsArray[NumberDeserialize(Buffer, Cache)]
        end

        return
    end

    -- Serializes one of multiple types.
    local IsATypeIn = self:GetConstraint("IsATypeIn")
    local GetTypeIndexFromValue = self._GetTypeIndexFromValue
    if (IsATypeIn or GetTypeIndexFromValue) then
        local Types = IsATypeIn[1]
        local NumberSerializer = Number(1, math.max(1, #Types)):Integer()
            local NumberDeserialize = NumberSerializer._Deserialize
            local NumberSerialize = NumberSerializer._Serialize

        local Divider = self._Divider
        if (GetTypeIndexFromValue) then
            self._Serialize = Divider and function(Buffer, Value, Cache)
                local Index = GetTypeIndexFromValue(Value)
                local Serializer = Types[Index]
                if (Serializer) then
                    NumberSerialize(Buffer, Index, Cache)
                    Serializer._Serialize(Buffer, Value, Cache)
                    if (Divider) then
                        Divider()
                    end
                    return
                end
                error(`Value {Value} did not satisfy any type definition`)
            end or function(Buffer, Value, Cache)
                local Index = GetTypeIndexFromValue(Value)
                local Serializer = Types[Index]
                if (Serializer) then
                    NumberSerialize(Buffer, Index, Cache)
                    Serializer._Serialize(Buffer, Value, Cache)
                    return
                end
                error(`Value {Value} did not satisfy any type definition`)
            end
        else
            self._Serialize = Divider and function(Buffer, Value, Cache)
                for Index, TypeChecker in Types do
                    if (TypeChecker:_Check(Value)) then
                        NumberSerialize(Buffer, Index, Cache)
                        TypeChecker._Serialize(Buffer, Value, Cache)
                        Divider()
                        return
                    end
                end
                error(`Value {Value} did not satisfy any type definition`)
            end or function(Buffer, Value, Cache)
                for Index, TypeChecker in Types do
                    if (TypeChecker:_Check(Value)) then
                        NumberSerialize(Buffer, Index, Cache)
                        TypeChecker._Serialize(Buffer, Value, Cache)
                        return
                    end
                end
                error(`Value {Value} did not satisfy any type definition`)
            end
        end
        self._Deserialize = function(Buffer, Cache)
            local Result = Types[NumberDeserialize(Buffer, Cache)]._Deserialize(Buffer, Cache)
            if (Divider) then
                Divider()
            end
            return Result
        end
        return
    end

    self._Serialize = function(_Buffer, _Value, _Cache)
        error("No constraints: cannot serialize")
    end
    self._Deserialize = function(_Buffer, _Cache)
        error("No constraints: cannot deserialize")
    end
end

--[[ local Test = Or(
    Or(
        Number(0, 1),
        Number(5, 6),
        Or(
            Number(100, 200),
            Number(300, 400),
            Or("X", "Y", "Z")
        )
    ),
    Number(9, 10)
)
print("////", Test._ActiveConstraints)
print(">>>", Test:Check(900)) ]]

return Or