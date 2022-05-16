--!nonstrict
-- @TODO This script really needs splitting up into sub-modules

local EMPTY_STRING = ""
local INVALID_ARGUMENT = "Invalid argument #%d (%s expected, got %s)"

local function ExpectType(PassedArg: any, ExpectedType: string, ArgNumber: number)
    local GotType = typeof(PassedArg)
    assert(GotType == ExpectedType, INVALID_ARGUMENT:format(ArgNumber, ExpectedType, GotType))
end

local function CreateStandardInitial(ExpectedTypeName)
    return function(_, Item)
        local ItemType = typeof(Item)

        if (ItemType == ExpectedTypeName) then
            return true, EMPTY_STRING
        end

        return false, "Expected" .. ExpectedTypeName .. ", got " .. ItemType
    end
end

local function ConcatWithToString(Array: {any}, Separator: string): string
    local Result = EMPTY_STRING
    local Size = #Array

    for Index, Value in ipairs(Array) do
        Result ..= tostring(Value)

        if (Index < Size) then
            Result ..= Separator
        end
    end

    return Result
end

local STRUCTURE_TO_FLAT_STRING_MT = {
    __tostring = function(self)
        local Pairings = {}

        for Key, Value in pairs(self) do
            table.insert(Pairings, tostring(Key) .. " = " .. tostring(Value))
        end

        return "{" .. ConcatWithToString(Pairings, ", ") .. "}"
    end;
}

-- Standard re-usable functions throughout all type checkers
    local function IsAKeyIn<T>(self: T, ...)
        return self:_AddConstraint("IsAKeyIn", function(_, Key, Store)
            return Store[Key] ~= nil, "No key found in table: " .. tostring(Store)
        end, ...)
    end

    local function IsAValueIn<T>(self: T, ...)
        return self:_AddConstraint("IsAValueIn", function(_, TargetValue, Store)
            for _, Value in pairs(Store) do
                if (Value == TargetValue) then
                    return true, EMPTY_STRING
                end
            end

            return false, "No value found in table: " .. tostring(Store)
        end, ...)
    end

    local function Equals<T>(self: T, ...)
        return self:_AddConstraint("Equals", function(_, Value, ExpectedValue)
            return Value == ExpectedValue, "Value " .. tostring(Value) .. " does not equal " .. tostring(ExpectedValue)
        end, ...)
    end

    local function GreaterThan<T>(self: T, ...)
        return self:_AddConstraint("GreaterThan", function(_, Value, ExpectedValue)
            return Value > ExpectedValue, "Value " .. tostring(Value) .. " is not greater than " .. tostring(ExpectedValue)
        end, ...)
    end

    local function LessThan<T>(self: T, ...)
        return self:_AddConstraint("LessThan", function(_, Value, ExpectedValue)
            return Value < ExpectedValue, "Value " .. tostring(Value) .. " is not less than " .. tostring(ExpectedValue)
        end, ...)
    end





local TypeGuard = {}

type SelfReturn<T, P...> = ((T, P...) -> T)

type TypeCheckerObject<T> = {
    _Copy: SelfReturn<TypeCheckerObject<T>>;
    _AddConstraint: SelfReturn<TypeCheckerObject<T>, string, (any) -> (TypeCheckerObject<T>), ...any>;

    Or: SelfReturn<TypeCheckerObject<T>, TypeCheckerObject<any>>;
    And: SelfReturn<TypeCheckerObject<T>, TypeCheckerObject<any>>;
    Alias: SelfReturn<TypeCheckerObject<T>, string>;
    AddTag: SelfReturn<TypeCheckerObject<T>, string>;
    Optional: SelfReturn<TypeCheckerObject<T>>;

    WrapCheck: (TypeCheckerObject<T>) -> ((any) -> (boolean, string));
    WrapAssert: (TypeCheckerObject<T>) -> ((any) -> ());
    Check: (TypeCheckerObject<T>, any) -> (string, boolean);
    Assert: (TypeCheckerObject<T>, any) -> ();

    -- Standard constraints
    Equals: SelfReturn<TypeCheckerObject<T>, any>;
    equals: SelfReturn<TypeCheckerObject<T>, any>;

    IsAValueIn: SelfReturn<TypeCheckerObject<T>, any>;
    isAValueIn: SelfReturn<TypeCheckerObject<T>, any>;

    IsAKeyIn: SelfReturn<TypeCheckerObject<T>, any>;
    isAKeyIn: SelfReturn<TypeCheckerObject<T>, any>;

    GreaterThan: SelfReturn<TypeCheckerObject<T>, number>;
    greaterThan: SelfReturn<TypeCheckerObject<T>, number>;

    LessThan: SelfReturn<TypeCheckerObject<T>, number>;
    lessThan: SelfReturn<TypeCheckerObject<T>, number>;
}

function TypeGuard.Template(Name)
    ExpectType(Name, "string", 1)

    local TemplateClass = {}
    TemplateClass.__index = TemplateClass
    TemplateClass._IsTemplate = true
    TemplateClass._InitialConstraint = nil
    TemplateClass._Type = Name

    function TemplateClass.new(...)
        local self = {
            _Tags = {};
            _Disjunction = {};
            _Conjunction = {};
            _ActiveConstraints = {};
        }

        setmetatable(self, TemplateClass)

        if (TemplateClass._InitialConstraint and select("#", ...) > 0) then
            return self:_InitialConstraint(...)
        end

        return self
    end

    function TemplateClass:_Copy()
        local New = TemplateClass.new()

        -- Copy tags
        for Key, Value in pairs(self._Tags) do
            New._Tags[Key] = Value
        end

        -- Copy OR
        for Index, Disjunction in ipairs(self._Disjunction) do
            New._Disjunction[Index] = Disjunction
        end

        -- Copy AND
        for Index, Conjunction in ipairs(self._Conjunction) do
            New._Conjunction[Index] = Conjunction
        end

        -- Copy constraints
        for ConstraintName, Constraint in pairs(self._ActiveConstraints) do
            New._ActiveConstraints[ConstraintName] = Constraint
        end

        return New
    end

    -- TODO: only 1 constraint of each type
    function TemplateClass:_AddConstraint(ConstraintName, Constraint, ...)
        ExpectType(ConstraintName, "string", 1)
        ExpectType(Constraint, "function", 2)

        self = self:_Copy()

        local ActiveConstraints = self._ActiveConstraints
        assert(ActiveConstraints[ConstraintName] == nil, "Constraint already exists: " .. ConstraintName)
        ActiveConstraints[ConstraintName] = {Constraint, {...}}
        return self
    end

    function TemplateClass:Optional()
        return self:AddTag("Optional")
    end

    function TemplateClass:Or(OtherType)
        TypeGuard._AssertIsTypeBase(OtherType)

        self = self:_Copy()
        table.insert(self._Disjunction, OtherType)
        return self
    end

    function TemplateClass:And(OtherType)
        TypeGuard._AssertIsTypeBase(OtherType)

        self = self:_Copy()
        table.insert(self._Conjunction, OtherType)
        return self
    end

    function TemplateClass:Alias(AliasName)
        ExpectType(AliasName, "string", 1)

        self = self:_Copy()
        self._Alias = AliasName
        return self
    end

    function TemplateClass:AddTag(TagName)
        ExpectType(TagName, "string", 1)

        self = self:_Copy()
        self._Tags[TagName] = true
        return self
    end

    function TemplateClass:WrapCheck()
        return function(...)
            return self:Check(...)
        end
    end

    function TemplateClass:WrapAssert()
        return function(...)
            return self:Assert(...)
        end
    end

    function TemplateClass:Check(Value)
        -- Handle "type x or type y or type z ..."
        -- We do this before checking constraints to check if any of the other conditions succeed
        local Disjunctions = self._Disjunction
        local DidTryDisjunction = (Disjunctions[1] ~= nil)

        for _, AlternateType in ipairs(Disjunctions) do
            local Success, _ = AlternateType:Check(Value)

            if (Success) then
                return true, EMPTY_STRING
            end
        end

        -- Handle "type x and type y and type z ..." - this is only really useful for objects and arrays
        for _, Conjunction in ipairs(self._Conjunction) do
            local Success, Message = Conjunction:Check(Value)

            if (not Success) then
                return false, "[Conjunction " .. tostring(Conjunction) .. "] " .. Message
            end
        end

        -- Optional allows the value to be nil, in which case it won't be checked and we can resolve
        if (self._Tags.Optional and Value == nil) then
            return true, EMPTY_STRING
        end

        -- Handle initial type check
        local Success, Message = self:_Initial(Value)

        if (not Success) then
            if (DidTryDisjunction) then
                return false, "Disjunctions failed on " .. tostring(self)
            else
                return false, Message
            end
        end

        -- Handle active constraints
        for _, Constraint in pairs(self._ActiveConstraints) do
            local SubSuccess, SubMessage = Constraint[1](self, Value, unpack(Constraint[2]))

            if (not SubSuccess) then
                if (DidTryDisjunction) then
                    return false, "Disjunctions failed on " .. tostring(self)
                else
                    return false, SubMessage
                end
            end
        end

        return true, EMPTY_STRING
    end

    function TemplateClass:Assert(...)
        assert(self:Check(...))
    end

    function TemplateClass:__tostring()
        -- User can create a unique alias to help simplify "where did it fail?"
        if (self._Alias) then
            return self._Alias
        end

        local Fields = {}

        -- Constraints list (including arg, possibly other type defs)
        if (next(self._ActiveConstraints) ~= nil) then
            local InnerConstraints = {}

            for ConstraintName, Constraint in pairs(self._ActiveConstraints) do
                table.insert(InnerConstraints, ConstraintName .. "(" .. ConcatWithToString(Constraint[2], ", ") .. ")")
            end

            table.insert(Fields, "Constraints = {" .. ConcatWithToString(InnerConstraints, ", ") .. "}")
        end

        -- Alternatives field str
        if (#self._Disjunction > 0) then
            local Alternatives = {}

            for _, AlternateType in ipairs(self._Disjunction) do
                table.insert(Alternatives, tostring(AlternateType))
            end

            table.insert(Fields, "Or = {" .. ConcatWithToString(Alternatives, ", ") .. "}")
        end

        -- Union fields str
        if (#self._Conjunction > 0) then
            local Unions = {}

            for _, Union in ipairs(self._Conjunction) do
                table.insert(Unions, tostring(Union))
            end

            table.insert(Fields, "And = {" .. ConcatWithToString(Unions, ", ") .. "}")
        end

        -- Tags (e.g. Optional, Strict)
        if (next(self._Tags) ~= nil) then
            local Tags = {}

            for Tag in pairs(self._Tags) do
                table.insert(Tags, Tag)
            end

            table.insert(Fields, "Tags = {" .. ConcatWithToString(Tags, ", ") .. "}")
        end

        return self._Type .. "(" .. ConcatWithToString(Fields, ", ") .. ")"
    end

    TemplateClass.Equals = Equals
    TemplateClass.equals = Equals

    TemplateClass.IsAValueIn = IsAValueIn
    TemplateClass.isAValueIn = IsAValueIn

    TemplateClass.IsAKeyIn = IsAKeyIn
    TemplateClass.isAKeyIn = IsAKeyIn

    TemplateClass.GreaterThan = GreaterThan
    TemplateClass.greaterThan = GreaterThan

    TemplateClass.LessThan = LessThan
    TemplateClass.lessThan = LessThan

    return function(...)
        return TemplateClass.new(...)
    end, TemplateClass
end

--- Checks if an object contains the fields which define a type template from this module
function TypeGuard._AssertIsTypeBase(Subject)
    ExpectType(Subject, "table", 1)

    assert(Subject._Tags ~= nil, "Subject does not contain _Tags field")
    assert(Subject._ActiveConstraints ~= nil, "Subject does not contain _ActiveConstraints field")
    assert(Subject._Disjunction ~= nil, "Subject does not contain _Disjunction field")
    assert(Subject._Conjunction ~= nil, "Subject does not contain _Conjunction field")
end

--- Cheap & easy way to create a type without any constraints, and just an initial check corresponding to Roblox's typeof
function TypeGuard.FromTypeName(TypeName)
    ExpectType(TypeName, "string", 1)

    local CheckerFunction, CheckerClass = TypeGuard.Template(TypeName)
    CheckerClass._Initial = CreateStandardInitial(TypeName)
    return CheckerFunction
end
TypeGuard.fromTypeName = TypeGuard.FromTypeName




do
    type NumberTypeCheckerObject = {
        Integer: SelfReturn<NumberTypeCheckerObject>;
        integer: SelfReturn<NumberTypeCheckerObject>;

        Decimal: SelfReturn<NumberTypeCheckerObject>;
        decimal: SelfReturn<NumberTypeCheckerObject>;

        Min: SelfReturn<NumberTypeCheckerObject, number>;
        min: SelfReturn<NumberTypeCheckerObject, number>;

        Max: SelfReturn<NumberTypeCheckerObject, number>;
        max: SelfReturn<NumberTypeCheckerObject, number>;

        Range: SelfReturn<NumberTypeCheckerObject, number, number>;
        range: SelfReturn<NumberTypeCheckerObject, number, number>;

        Positive: SelfReturn<NumberTypeCheckerObject>;
        positive: SelfReturn<NumberTypeCheckerObject>;

        Negative: SelfReturn<NumberTypeCheckerObject>;
        negative: SelfReturn<NumberTypeCheckerObject>;
    } & TypeCheckerObject<NumberTypeCheckerObject>

    local Number: SelfReturn<NumberTypeCheckerObject>, NumberClass = TypeGuard.Template("Number")

    function NumberClass:_Initial(Item)
        return typeof(Item) == "number", "Expected number, got " .. typeof(Item)
    end

    function NumberClass:Integer(...)
        return self:_AddConstraint("Integer", function(_, Item)
            return math.floor(Item) == Item, "Expected integer form, got " .. tostring(Item)
        end, ...)
    end
    NumberClass.integer = NumberClass.Integer

    function NumberClass:Decimal(...)
        return self:_AddConstraint("Decimal", function(_, Item)
            return math.floor(Item) ~= Item, "Expected decimal form, got " .. tostring(Item)
        end, ...)
    end
    NumberClass.decimal = NumberClass.Decimal

    function NumberClass:Min(...)
        return self:_AddConstraint("Min", function(_, Item, Min)
            return Item >= Min, "Length must be at least " .. tostring(Min) .. ", got " .. tostring(Item)
        end, ...)
    end
    NumberClass.min = NumberClass.Min

    function NumberClass:Max(...)
        return self:_AddConstraint("Max", function(_, Item, Max)
            return Item <= Max, "Length must be at most " .. tostring(Max) .. ", got " .. tostring(Item)
        end, ...)
    end
    NumberClass.max = NumberClass.Max

    function NumberClass:Range(...)
        return self:_AddConstraint("Range", function(_, Item, Min, Max)
            return Item >= Min and Item <= Max, "Length must be between " .. tostring(Min) .. " and " .. tostring(Max) .. ", got " .. tostring(Item)
        end, ...)
    end
    NumberClass.range = NumberClass.Range

    function NumberClass:Positive(...)
        return self:_AddConstraint("Positive", function(_, Item)
            return Item >= 0, "Expected positive number, got " .. tostring(Item)
        end, ...)
    end
    NumberClass.positive = NumberClass.Positive

    function NumberClass:Negative(...)
        return self:_AddConstraint("Negative", function(_, Item)
            return Item < 0, "Expected negative number, got " .. tostring(Item)
        end, ...)
    end
    NumberClass.negative = NumberClass.Negative

    TypeGuard.Number = Number
    TypeGuard.number = Number
end




do
    type StringTypeCheckerObject = TypeCheckerObject<StringTypeCheckerObject> & {
        MinLength: SelfReturn<StringTypeCheckerObject, number>;
        minLength: SelfReturn<StringTypeCheckerObject, number>;

        MaxLength: SelfReturn<StringTypeCheckerObject, number>;
        maxLength: SelfReturn<StringTypeCheckerObject, number>;

        Pattern: SelfReturn<StringTypeCheckerObject, string>;
        pattern: SelfReturn<StringTypeCheckerObject, string>;
    }

    local String: SelfReturn<StringTypeCheckerObject>, StringClass = TypeGuard.Template("String")
    StringClass._Initial = CreateStandardInitial("string")

    function StringClass:MinLength(...)
        return self:_AddConstraint("MinLength", function(_, Item, MinLength)
            return #Item >= MinLength, "Length must be at least " .. MinLength .. ", got " .. #Item
        end, ...)
    end
    StringClass.minLength = StringClass.MinLength

    function StringClass:MaxLength(...)
        return self:_AddConstraint("MaxLength", function(_, Item, MaxLength)
            return #Item <= MaxLength, "Length must be at most " .. MaxLength .. ", got " .. #Item
        end, ...)
    end
    StringClass.maxLength = StringClass.MaxLength

    function StringClass:Pattern(...)
        return self:_AddConstraint("Pattern", function(_, Item, Pattern)
            return string.match(Item, Pattern) ~= nil, "String does not match pattern " .. tostring(Pattern)
        end, ...)
    end
    StringClass.pattern = StringClass.Pattern

    TypeGuard.String = String
    TypeGuard.string = String
end




do
    local PREFIX_ARRAY = "Index"
    local PREFIX_PARAM = "Param"
    local ERR_PREFIX = "[%s '%d'] "
    local ERR_UNEXPECTED_VALUE = ERR_PREFIX .. " Unexpected value (strict tag is present)"

    type ArrayTypeCheckerObject = TypeCheckerObject<ArrayTypeCheckerObject> & {
        OfLength: SelfReturn<ArrayTypeCheckerObject, number>;
        ofLength: SelfReturn<ArrayTypeCheckerObject, number>;

        MinLength: SelfReturn<ArrayTypeCheckerObject, number>;
        minLength: SelfReturn<ArrayTypeCheckerObject, number>;

        MaxLength: SelfReturn<ArrayTypeCheckerObject, number>;
        maxLength: SelfReturn<ArrayTypeCheckerObject, number>;

        Contains: SelfReturn<ArrayTypeCheckerObject, any>;
        contains: SelfReturn<ArrayTypeCheckerObject, any>;

        OfType: SelfReturn<ArrayTypeCheckerObject, TypeCheckerObject<any>>;
        ofType: SelfReturn<ArrayTypeCheckerObject, TypeCheckerObject<any>>;

        OfStructure: SelfReturn<ArrayTypeCheckerObject, {TypeCheckerObject<any>}>;
        ofStructure: SelfReturn<ArrayTypeCheckerObject, {TypeCheckerObject<any>}>;

        StructuralEquals: SelfReturn<ArrayTypeCheckerObject, {TypeCheckerObject<any>}>;
        structuralEquals: SelfReturn<ArrayTypeCheckerObject, {TypeCheckerObject<any>}>;

        Strict: SelfReturn<ArrayTypeCheckerObject>;
        strict: SelfReturn<ArrayTypeCheckerObject>;
    }

    local Array: SelfReturn<ArrayTypeCheckerObject>, ArrayClass = TypeGuard.Template("Array")

    function ArrayClass:_PrefixError(ErrorString: string, Index: number)
        return ErrorString:format((self._Tags.DenoteParams and PREFIX_PARAM or PREFIX_ARRAY), Index)
    end

    function ArrayClass:_Initial(TargetArray)
        if (typeof(TargetArray) ~= "table") then
            return false, "Expected table, got " .. typeof(TargetArray)
        end

        for Key in pairs(TargetArray) do
            local KeyType = typeof(Key)

            if (KeyType ~= "number") then
                return false, "Non-numetic key detected: " .. KeyType
            end
        end

        return true, EMPTY_STRING
    end

    function ArrayClass:OfLength(...)
        return self:_AddConstraint("Length", function(_, TargetArray, Length)
            return #TargetArray == Length, "Length must be " .. Length .. ", got " .. #TargetArray
        end, ...)
    end
    ArrayClass.ofLength = ArrayClass.OfLength

    function ArrayClass:MinLength(...)
        return self:_AddConstraint("MinLength", function(_, TargetArray, MinLength)
            return #TargetArray >= MinLength, "Length must be at least " .. MinLength .. ", got " .. #TargetArray
        end, ...)
    end
    ArrayClass.minLength = ArrayClass.MinLength

    function ArrayClass:MaxLength(...)
        return self:_AddConstraint("MaxLength", function(_, TargetArray, MaxLength)
            return #TargetArray <= MaxLength, "Length must be at most " .. MaxLength .. ", got " .. #TargetArray
        end, ...)
    end
    ArrayClass.maxLength = ArrayClass.MaxLength

    function ArrayClass:Contains(...)
        return self:_AddConstraint("Contains", function(_, TargetArray, Value, StartPoint)
            return table.find(TargetArray, Value, StartPoint) ~= nil, "Value not found in array: " .. tostring(Value)
        end, ...)
    end
    ArrayClass.contains = ArrayClass.Contains

    function ArrayClass:OfType(...)
        return self:_AddConstraint("OfType", function(SelfRef, TargetArray, SubType)
            for Index, Value in ipairs(TargetArray) do
                local Success, SubMessage = SubType:Check(Value)

                if (not Success) then
                    return false, ERR_PREFIX:format((SelfRef._Tags.DenoteParams and PREFIX_PARAM or PREFIX_ARRAY), tostring(Index)) .. SubMessage
                end
            end

            return true, EMPTY_STRING
        end, ...)
    end
    ArrayClass.ofType = ArrayClass.OfType

    function ArrayClass:OfStructure(ArrayToCheck, ...)
        -- Just in case the user does any weird mutation
        local SubTypesCopy = {}

        for Key, Value in ipairs(ArrayToCheck) do
            SubTypesCopy[Key] = Value
        end

        setmetatable(SubTypesCopy, STRUCTURE_TO_FLAT_STRING_MT)

        return self:_AddConstraint("OfStructure", function(SelfRef, TargetArray, SubTypesAtPositions)
            -- Check all fields which should be in the object exist (unless optional) and the type check for each passes
            for Index, Checker in ipairs(SubTypesAtPositions) do
                local Success, SubMessage = Checker:Check(TargetArray[Index])

                if (not Success) then
                    return false, self:_PrefixError(ERR_PREFIX, tostring(Index)) .. SubMessage
                end
            end

            -- Check there are no extra indexes which shouldn't be in the object
            if (SelfRef._Tags.Strict) then
                for Index in ipairs(TargetArray) do
                    local Checker = SubTypesAtPositions[Index]

                    if (not Checker) then
                        return false, self:_PrefixError(ERR_UNEXPECTED_VALUE, tostring(Index))
                    end
                end
            end

            return true, EMPTY_STRING
        end, SubTypesCopy, ...)
    end
    ArrayClass.ofStructure = ArrayClass.OfStructure

    function ArrayClass:StructuralEquals(Other)
        return self:OfStructure(Other):Strict()
    end
    ArrayClass.structuralEquals = ArrayClass.StructuralEquals

    function ArrayClass:Strict()
        return self:AddTag("Strict")
    end
    ArrayClass.strict = ArrayClass.Strict

    function ArrayClass:DenoteParams()
        return self:AddTag("DenoteParams")
    end
    ArrayClass.denoteParams = ArrayClass.DenoteParams

    ArrayClass._InitialConstraint = ArrayClass.OfType

    TypeGuard.Array = Array
end




do
    type ObjectTypeCheckerObject = TypeCheckerObject<ObjectTypeCheckerObject> & {
        OfStructure: SelfReturn<ObjectTypeCheckerObject, {[any]: TypeCheckerObject<any>}>;
        ofStructure: SelfReturn<ObjectTypeCheckerObject, {[any]: TypeCheckerObject<any>}>;

        StructuralEquals: SelfReturn<ObjectTypeCheckerObject, {[any]: TypeCheckerObject<any>}>;
        structuralEquals: SelfReturn<ObjectTypeCheckerObject, {[any]: TypeCheckerObject<any>}>;

        Strict: SelfReturn<ObjectTypeCheckerObject>;
        strict: SelfReturn<ObjectTypeCheckerObject>;

        OfValueType: SelfReturn<ObjectTypeCheckerObject, TypeCheckerObject<any>>;
        ofValueType: SelfReturn<ObjectTypeCheckerObject, TypeCheckerObject<any>>;

        OfKeyType: SelfReturn<ObjectTypeCheckerObject, TypeCheckerObject<any>>;
        ofKeyType: SelfReturn<ObjectTypeCheckerObject, TypeCheckerObject<any>>;
    }

    local Object: SelfReturn<ObjectTypeCheckerObject>, ObjectClass = TypeGuard.Template("Object")

    function ObjectClass:_Initial(TargetObject)
        if (typeof(TargetObject) ~= "table") then
            return false, "Expected table, got " .. typeof(TargetObject)
        end

        for Key in pairs(TargetObject) do
            if (typeof(Key) == "number") then
                return false, "Incorrect key type: number"
            end
        end

        return true, EMPTY_STRING
    end

    function ObjectClass:OfStructure(OriginalSubTypes)
        -- Just in case the user does any weird mutation
        local SubTypesCopy = {}

        for Key, Value in pairs(OriginalSubTypes) do
            SubTypesCopy[Key] = Value
        end

        setmetatable(SubTypesCopy, STRUCTURE_TO_FLAT_STRING_MT)

        return self:_AddConstraint("OfStructure", function(SelfRef, StructureCopy, SubTypes)
            -- Check all fields which should be in the object exist (unless optional) and the type check for each passes
            for Key, Checker in pairs(SubTypes) do
                local RespectiveValue = StructureCopy[Key]

                if (RespectiveValue == nil and not Checker._Tags.Optional) then
                    return false, "[Key '" .. tostring(Key) .. "'] is nil"
                end

                local Success, SubMessage = Checker:Check(RespectiveValue)

                if (not Success) then
                    return false, "[Key '" .. tostring(Key) .. "'] " .. SubMessage
                end
            end

            -- Check there are no extra fields which shouldn't be in the object
            if (SelfRef._Tags.Strict) then
                for Key in pairs(StructureCopy) do
                    local Checker = SubTypes[Key]

                    if (not Checker) then
                        return false, "[Key '" .. tostring(Key) .. "'] unexpected (strict)"
                    end
                end
            end

            return true, EMPTY_STRING
        end, SubTypesCopy)
    end
    ObjectClass.ofStructure = ObjectClass.OfStructure

    function ObjectClass:OfValueType(...)
        return self:_AddConstraint("OfValueType", function(_, TargetArray, SubType)
            for Index, Value in pairs(TargetArray) do
                local Success, SubMessage = SubType:Check(Value)

                if (not Success) then
                    return false, "[OfValueType: Key '" .. tostring(Index) .. "'] " .. SubMessage
                end
            end

            return true, EMPTY_STRING
        end, ...)
    end
    ObjectClass.ofValueType = ObjectClass.OfValueType

    function ObjectClass:OfKeyType(...)
        return self:_AddConstraint("OfKeyType", function(_, TargetArray, SubType)
            for Index, Value in pairs(TargetArray) do
                local Success, SubMessage = SubType:Check(Value)

                if (not Success) then
                    return false, "[OfKeyType: Key '" .. tostring(Index) .. "'] " .. SubMessage
                end
            end

            return true, EMPTY_STRING
        end, ...)
    end
    ObjectClass.ofKeyType = ObjectClass.OfKeyType

    function ObjectClass:Strict()
        return self:AddTag("Strict")
    end
    ObjectClass.strict = ObjectClass.Strict

    function ObjectClass:StructuralEquals(...)
        return self:OfStructure(...):Strict()
    end
    ObjectClass.structuralEquals = ObjectClass.StructuralEquals

    ObjectClass._InitialConstraint = ObjectClass.OfStructure

    TypeGuard.Object = Object
end




do
    type InstanceTypeCheckerObject = TypeCheckerObject<InstanceTypeCheckerObject> & {
        OfStructure: SelfReturn<InstanceTypeCheckerObject, {[any]: TypeCheckerObject<Instance>}>;
        ofStructure: SelfReturn<InstanceTypeCheckerObject, {[any]: TypeCheckerObject<Instance>}>;

        StructuralEquals: SelfReturn<InstanceTypeCheckerObject, {[any]: TypeCheckerObject<Instance>}>;
        structuralEquals: SelfReturn<InstanceTypeCheckerObject, {[any]: TypeCheckerObject<Instance>}>;

        IsA: SelfReturn<InstanceTypeCheckerObject, string>;
        isA: SelfReturn<InstanceTypeCheckerObject, string>;

        CheckProperty: SelfReturn<InstanceTypeCheckerObject, string, TypeCheckerObject<any>>;
        checkProperty: SelfReturn<InstanceTypeCheckerObject, string, TypeCheckerObject<any>>;

        Strict: SelfReturn<InstanceTypeCheckerObject>;
        strict: SelfReturn<InstanceTypeCheckerObject>;
    }

    local InstanceChecker: SelfReturn<InstanceTypeCheckerObject>, InstanceCheckerClass = TypeGuard.Template("Instance")
    InstanceCheckerClass._Initial = CreateStandardInitial("Instance")

    function InstanceCheckerClass:OfStructure(OriginalSubTypes)
        -- Just in case the user does any weird mutation
        local SubTypesCopy = {}

        for Key, Value in pairs(OriginalSubTypes) do
            SubTypesCopy[Key] = Value
        end

        setmetatable(SubTypesCopy, STRUCTURE_TO_FLAT_STRING_MT)

        return self:_AddConstraint("OfStructure", function(SelfRef, InstanceRoot, SubTypes)
            -- Check all fields which should be in the object exist (unless optional) and the type check for each passes
            for Key, Checker in pairs(SubTypes) do
                local Success, SubMessage = Checker:Check(InstanceRoot:FindFirstChild(Key))

                if (not Success) then
                    return false, "[Instance '" .. tostring(Key) .. "'] " .. SubMessage
                end
            end

            -- Check there are no extra fields which shouldn't be in the object
            if (SelfRef._Tags.Strict) then
                for _, Value in ipairs(InstanceRoot:GetChildren()) do
                    local Key = Value.Name
                    local Checker = SubTypes[Key]

                    if (not Checker) then
                        return false, "[Instance '" .. tostring(Key) .. "'] unexpected (strict)"
                    end
                end
            end

            return true, EMPTY_STRING
        end, SubTypesCopy)
    end
    InstanceCheckerClass.ofStructure = InstanceCheckerClass.OfStructure

    function InstanceCheckerClass:IsA(...)
        return self:_AddConstraint("IsA", function(_, InstanceRoot, InstanceIsA)
            if (not InstanceRoot:IsA(InstanceIsA)) then
                return false, "Expected " .. InstanceIsA .. ", got " .. InstanceRoot.ClassName
            end

            return true, EMPTY_STRING
        end, ...)
    end
    InstanceCheckerClass.isA = InstanceCheckerClass.IsA

    function InstanceCheckerClass:CheckProperty(...)
        return self:_AddConstraint("CheckProperty", function(_, InstanceRoot, PropertyName, Checker)
            return Checker:Check(InstanceRoot[PropertyName])
        end, ...)
    end
    InstanceCheckerClass.checkProperty = InstanceCheckerClass.CheckProperty

    function InstanceCheckerClass:Strict()
        return self:AddTag("Strict")
    end
    InstanceCheckerClass.strict = InstanceCheckerClass.Strict

    function InstanceCheckerClass:StructuralEquals(...)
        return self:OfStructure(...):Strict()
    end
    InstanceCheckerClass.structuralEquals = InstanceCheckerClass.StructuralEquals

    InstanceCheckerClass._InitialConstraint = InstanceCheckerClass.IsA

    TypeGuard.Instance = InstanceChecker
end




do
    type BooleanTypeCheckerObject = TypeCheckerObject<BooleanTypeCheckerObject> & {
        -- Fill any stuff here in future
    }

    local Boolean: SelfReturn<BooleanTypeCheckerObject>, BooleanClass = TypeGuard.Template("Boolean")
    BooleanClass._Initial = CreateStandardInitial("boolean")

    BooleanClass._InitialConstraint = BooleanClass.Equals

    TypeGuard.Boolean = Boolean
    TypeGuard.boolean = Boolean
end




do
    type EnumTypeCheckerObject = TypeCheckerObject<EnumTypeCheckerObject> & {
        IsA: SelfReturn<EnumTypeCheckerObject, Enum | EnumItem>;
        isA: SelfReturn<EnumTypeCheckerObject, Enum | EnumItem>;
    }

    local EnumChecker: SelfReturn<EnumTypeCheckerObject>, EnumCheckerClass = TypeGuard.Template("Enum")

    function EnumCheckerClass:_Initial(Value)
        local GotType = typeof(Value)

        if (GotType ~= "EnumItem" and GotType ~= "Enum") then
            return false, "Expected EnumItem or Enum, got " .. GotType
        end

        return true, EMPTY_STRING
    end

    function EnumCheckerClass:IsA(...)
        return self:_AddConstraint("IsA", function(_, Value, TargetEnum)
            local PassedType = typeof(Value)
            local TargetType = typeof(TargetEnum)

            -- Both are EnumItems
            if (PassedType == "EnumItem" and TargetType == "EnumItem") then
                return Value == TargetEnum, "Expected " .. tostring(TargetEnum) .. ", got " .. tostring(Value)
            elseif (PassedType == "EnumItem" and TargetType == "Enum") then
                return table.find(TargetEnum:GetEnumItems(), Value) ~= nil, "Expected a " .. tostring(TargetEnum) .. ", got " .. tostring(Value)
            end

            return false, "Invalid comparison: " .. PassedType .. " to " .. TargetType
        end, ...)
    end
    EnumCheckerClass.isA = EnumCheckerClass.IsA

    EnumCheckerClass._InitialConstraint = EnumCheckerClass.IsA

    TypeGuard.Enum = EnumChecker
end




do
    type NilTypeCheckerObject = TypeCheckerObject<NilTypeCheckerObject> & {}

    local NilChecker: SelfReturn<NilTypeCheckerObject>, NilCheckerClass = TypeGuard.Template("Nil")

    function NilCheckerClass:_Initial(Value)
        if (Value == nil) then
            return false, "Expected nil, got " .. typeof(Value)
        end

        return true, EMPTY_STRING
    end

    TypeGuard.Nil = NilChecker
end




TypeGuard.Axes = TypeGuard.FromTypeName("Axes")
TypeGuard.BrickColor = TypeGuard.FromTypeName("BrickColor")
TypeGuard.CatalogSearchParams = TypeGuard.FromTypeName("CatalogSearchParams")
TypeGuard.CFrame = TypeGuard.FromTypeName("CFrame")
TypeGuard.Color3 = TypeGuard.FromTypeName("Color3")
TypeGuard.ColorSequence = TypeGuard.FromTypeName("ColorSequence")
TypeGuard.ColorSequenceKeypoint = TypeGuard.FromTypeName("ColorSequenceKeypoint")
TypeGuard.DateTime = TypeGuard.FromTypeName("DateTime")
TypeGuard.DockWidgetPluginGuiInfo = TypeGuard.FromTypeName("DockWidgetPluginGuiInfo")
TypeGuard.Enums = TypeGuard.FromTypeName("Enums")
TypeGuard.Faces = TypeGuard.FromTypeName("Faces")
TypeGuard.FloatCurveKey = TypeGuard.FromTypeName("FloatCurveKey")
TypeGuard.NumberRange = TypeGuard.FromTypeName("NumberRange")
TypeGuard.NumberSequence = TypeGuard.FromTypeName("NumberSequence")
TypeGuard.NumberSequenceKeypoint = TypeGuard.FromTypeName("NumberSequenceKeypoint")
TypeGuard.OverlapParams = TypeGuard.FromTypeName("OverlapParams")
TypeGuard.PathWaypoint = TypeGuard.FromTypeName("PathWaypoint")
TypeGuard.PhysicalProperties = TypeGuard.FromTypeName("PhysicalProperties")
TypeGuard.Random = TypeGuard.FromTypeName("Random")
TypeGuard.Ray = TypeGuard.FromTypeName("Ray")
TypeGuard.RaycastParams = TypeGuard.FromTypeName("RaycastParams")
TypeGuard.RaycastResult = TypeGuard.FromTypeName("RaycastResult")
TypeGuard.RBXScriptConnection = TypeGuard.FromTypeName("RBXScriptConnection")
TypeGuard.RBXScriptSignal = TypeGuard.FromTypeName("RBXScriptSignal")
TypeGuard.Rect = TypeGuard.FromTypeName("Rect")
TypeGuard.Region3 = TypeGuard.FromTypeName("Region3")
TypeGuard.Region3int16 = TypeGuard.FromTypeName("Region3int16")
TypeGuard.TweenInfo = TypeGuard.FromTypeName("TweenInfo")
TypeGuard.UDim = TypeGuard.FromTypeName("UDim")
TypeGuard.UDim2 = TypeGuard.FromTypeName("UDim2")
TypeGuard.Vector2 = TypeGuard.FromTypeName("Vector2")
TypeGuard.Vector2int16 = TypeGuard.FromTypeName("Vector2int16")
TypeGuard.Vector3 = TypeGuard.FromTypeName("Vector3")
TypeGuard.Vector3int16 = TypeGuard.FromTypeName("Vector3int16")

--- Creates a function which checks params as if they were a strict Array checker
function TypeGuard.Params(...)
    local Params = {...}

    for _, ParamChecker in ipairs(Params) do
        TypeGuard._AssertIsTypeBase(ParamChecker)
    end

    local Checker = TypeGuard.Array():StructuralEquals(Params):DenoteParams()

    return function(...)
        Checker:Assert({...})
    end
end
TypeGuard.params = TypeGuard.Params

--- Creates a function which checks variadic params against a single given type checker
function TypeGuard.VariadicParams(CompareType)
    TypeGuard._AssertIsTypeBase(CompareType)

    local Checker = TypeGuard.Array():OfType(CompareType):DenoteParams()

    return function(...)
        Checker:Assert({...})
    end
end
TypeGuard.variadicParams = TypeGuard.VariadicParams

return TypeGuard