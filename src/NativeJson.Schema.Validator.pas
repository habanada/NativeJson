{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Schema.Validator;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Generics.Collections,
  System.RegularExpressions,
  {$ELSE}
  System.SysUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  {$ENDIF}
  NativeJson.Dom.Value,
  NativeJson.Schema.Validation,
  NativeJson.Schema.Registry,
  NativeJson.ExactNumber;

type
  TNativeJsonValue = NativeJson.Dom.Value.TJsonValue;
  TJsonSchemaFormatValidator = reference to function(const Value: string): Boolean;

  TJsonSchemaValidator = class
  private type
    TRefFrame = record
      Schema: TNativeJsonValue;
      Instance: TNativeJsonValue;
    end;

    TEvaluation = class
    private
      FProperties: TDictionary<string, Boolean>;
      FItems: TDictionary<Integer, Boolean>;
    public
      Valid: Boolean;
      AllProperties: Boolean;
      AllItems: Boolean;
      constructor Create;
      destructor Destroy; override;
      procedure AddProperty(const Name: string);
      procedure AddItem(Index: Integer);
      procedure Merge(Source: TEvaluation);
      function HasProperty(const Name: string): Boolean;
      function HasItem(Index: Integer): Boolean;
    end;
  private
    FOptions: TJsonSchemaValidationOptions;
    FRegistry: TJsonSchemaRegistry;
    FRefStack: TList<TRefFrame>;
    FDynamicScope: TList<string>;
    FFormats: TDictionary<string, TJsonSchemaFormatValidator>;
    FRegexCache: TDictionary<string, TRegEx>;
    procedure Initialize(Schema: TNativeJsonValue; Options: TJsonSchemaValidationOptions);
    procedure RegisterDefaultFormats;
    procedure CheckAllSchemas;
    procedure CheckSchema(Schema: TNativeJsonValue);
    function Evaluate(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>; Depth: Integer): TEvaluation;
    function EvaluateReference(Instance, Target: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>; Depth: Integer): TEvaluation;
    procedure EvaluateAssertions(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>);
    procedure EvaluateNumeric(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>);
    procedure EvaluateString(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>);
    function EvaluateLogic(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>; Depth: Integer): TEvaluation;
    function EvaluateObject(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>; Depth: Integer; BaseEvaluation: TEvaluation): TEvaluation;
    function EvaluateArray(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>; Depth: Integer; BaseEvaluation: TEvaluation): TEvaluation;
    procedure AddError(Errors: TList<TJsonSchemaValidationError>; Schema: TNativeJsonValue; const InstancePath, Keyword, Message: string);
    function ShouldStop(Errors: TList<TJsonSchemaValidationError>; Baseline: Integer): Boolean;
    function IsReferenceActive(Schema, Instance: TNativeJsonValue): Boolean;
    function JsonTypeName(Value: TNativeJsonValue): string;
    function MatchesType(Value: TNativeJsonValue; const TypeName: string): Boolean;
    function MatchesDeclaredType(Value: TNativeJsonValue; Schema: TNativeJsonValue): Boolean;
    function ValuesEqual(A, B: TNativeJsonValue): Boolean;
    function CodePointLength(const Value: string): Integer;
    function IsSchemaValue(Value: TNativeJsonValue): Boolean;
    function IsNonNegativeInteger(Value: TNativeJsonValue): Boolean;
    function IsPositiveNumber(Value: TNativeJsonValue): Boolean;
    function TryExactNumber(Value: TNativeJsonValue; out Number: TJsonExactNumber): Boolean;
    function CountBelowMinimum(Constraint: TNativeJsonValue; Count: Integer): Boolean;
    function CountAboveMaximum(Constraint: TNativeJsonValue; Count: Integer): Boolean;
    function ConstraintText(Constraint: TNativeJsonValue): string;
    function PatternMatches(const Value, Pattern: string): Boolean;
  public
    constructor Create(Schema: TNativeJsonValue; Options: TJsonSchemaValidationOptions = nil); overload;
    destructor Destroy; override;
    procedure RegisterSchema(const Uri: string; Schema: TNativeJsonValue); overload;
    procedure RegisterFormat(const Name: string; Validator: TJsonSchemaFormatValidator);
    function Validate(Instance: TNativeJsonValue): TJsonSchemaValidationResult; overload;
    property Options: TJsonSchemaValidationOptions read FOptions;
  end;

implementation

uses
  {$IFDEF FPC}
  DateUtils,
  {$ELSE}
  System.DateUtils,
  {$ENDIF}
  NativeJson.Comparer,
  NativeJson.Dom.Primitive,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.JsonObject;

function IsDateFormat(const Value: string): Boolean;
var
  Y, M, D: Integer;
  DT: TDateTime;
begin
  if not TRegEx.IsMatch(Value, '^\d{4}-\d{2}-\d{2}$') then Exit(False);
  Y := StrToIntDef(Copy(Value, 1, 4), -1);
  M := StrToIntDef(Copy(Value, 6, 2), -1);
  D := StrToIntDef(Copy(Value, 9, 2), -1);
  Result := TryEncodeDate(Y, M, D, DT);
end;

function IsTimeFormat(const Value: string): Boolean;
var
  Match: TMatch;
  H, M, S, OH, OM: Integer;
begin
  Match := TRegEx.Match(Value, '^(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:[Zz]|([+-])(\d{2}):(\d{2}))$');
  if not Match.Success then Exit(False);
  H := StrToIntDef(Match.Groups[1].Value, -1);
  M := StrToIntDef(Match.Groups[2].Value, -1);
  S := StrToIntDef(Match.Groups[3].Value, -1);
  if (H > 23) or (M > 59) or (S > 60) then Exit(False);
  if Match.Groups[4].Success then
  begin
    OH := StrToIntDef(Match.Groups[5].Value, -1);
    OM := StrToIntDef(Match.Groups[6].Value, -1);
    if (OH > 23) or (OM > 59) then Exit(False);
  end;
  Result := True;
end;

function IsDateTimeFormat(const Value: string): Boolean;
var
  P: Integer;
begin
  P := Pos('T', Value);
  if P = 0 then P := Pos('t', Value);
  Result := (P > 0) and IsDateFormat(Copy(Value, 1, P - 1)) and IsTimeFormat(Copy(Value, P + 1, MaxInt));
end;

constructor TJsonSchemaValidator.TEvaluation.Create;
begin
  inherited Create;
  FProperties := TDictionary<string, Boolean>.Create;
  FItems := TDictionary<Integer, Boolean>.Create;
  Valid := True;
  AllProperties := False;
  AllItems := False;
end;

destructor TJsonSchemaValidator.TEvaluation.Destroy;
begin
  FItems.Free;
  FProperties.Free;
  inherited;
end;

procedure TJsonSchemaValidator.TEvaluation.AddProperty(const Name: string);
begin
  FProperties.AddOrSetValue(Name, True);
end;

procedure TJsonSchemaValidator.TEvaluation.AddItem(Index: Integer);
begin
  FItems.AddOrSetValue(Index, True);
end;

procedure TJsonSchemaValidator.TEvaluation.Merge(Source: TEvaluation);
var
  Name: string;
  Index: Integer;
begin
  if Source = nil then Exit;
  if Source.AllProperties then AllProperties := True else for Name in Source.FProperties.Keys do AddProperty(Name);
  if Source.AllItems then AllItems := True else for Index in Source.FItems.Keys do AddItem(Index);
end;

function TJsonSchemaValidator.TEvaluation.HasProperty(const Name: string): Boolean;
begin
  Result := AllProperties or FProperties.ContainsKey(Name);
end;

function TJsonSchemaValidator.TEvaluation.HasItem(Index: Integer): Boolean;
begin
  Result := AllItems or FItems.ContainsKey(Index);
end;

constructor TJsonSchemaValidator.Create(Schema: TNativeJsonValue; Options: TJsonSchemaValidationOptions);
begin
  inherited Create;
  Initialize(Schema, Options);
end;

procedure TJsonSchemaValidator.Initialize(Schema: TNativeJsonValue; Options: TJsonSchemaValidationOptions);
begin
  if Schema = nil then raise EArgumentNilException.Create('Schema');
  if Options = nil then FOptions := TJsonSchemaValidationOptions.Create else FOptions := Options.Clone;
  if FOptions.MaxErrors < 0 then raise EArgumentOutOfRangeException.Create('MaxErrors');
  if FOptions.MaxDepth < 1 then raise EArgumentOutOfRangeException.Create('MaxDepth');
  FRefStack := TList<TRefFrame>.Create;
  FDynamicScope := TList<string>.Create;
  FFormats := TDictionary<string, TJsonSchemaFormatValidator>.Create;
  FRegexCache := TDictionary<string, TRegEx>.Create;
  FRegistry := TJsonSchemaRegistry.Create(Schema, FOptions);
  RegisterDefaultFormats;
  if FOptions.StrictSchema then CheckAllSchemas;
end;

destructor TJsonSchemaValidator.Destroy;
begin
  FRegistry.Free;
  FRegexCache.Free;
  FFormats.Free;
  FDynamicScope.Free;
  FRefStack.Free;
  FOptions.Free;
  inherited;
end;

procedure TJsonSchemaValidator.RegisterDefaultFormats;
begin
  RegisterFormat('date',
    function(const Value: string): Boolean
    begin
      Result := IsDateFormat(Value);
    end);
  RegisterFormat('time',
    function(const Value: string): Boolean
    begin
      Result := IsTimeFormat(Value);
    end);
  RegisterFormat('date-time',
    function(const Value: string): Boolean
    begin
      Result := IsDateTimeFormat(Value);
    end);
  RegisterFormat('uuid',
    function(const Value: string): Boolean
    begin
      Result := TRegEx.IsMatch(Value, '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$');
    end);
  RegisterFormat('ipv4',
    function(const Value: string): Boolean
    var
      Parts: TArray<string>;
      I, N: Integer;
    begin
      Parts := Value.Split(['.']);
      if Length(Parts) <> 4 then Exit(False);
      for I := 0 to 3 do
        if (Parts[I] = '') or ((Length(Parts[I]) > 1) and (Parts[I][1] = '0')) or not TryStrToInt(Parts[I], N) or (N < 0) or (N > 255) then Exit(False);
      Result := True;
    end);
  RegisterFormat('hostname',
    function(const Value: string): Boolean
    var
      Parts: TArray<string>;
      Part: string;
    begin
      if (Value = '') or (Length(Value) > 253) then Exit(False);
      Parts := Value.Split(['.']);
      for Part in Parts do
        if (Part = '') or (Length(Part) > 63) or not TRegEx.IsMatch(Part, '^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$') then Exit(False);
      Result := True;
    end);
  RegisterFormat('email',
    function(const Value: string): Boolean
    begin
      Result := TRegEx.IsMatch(Value, '^[^\s@]+@[^\s@]+$');
    end);
  RegisterFormat('regex',
    function(const Value: string): Boolean
    begin
      try
        // TRegEx.Create does not compile the pattern yet - only an
        // access does. Without an access every pattern counts as valid.
        TRegEx.IsMatch('', Value);
        Result := True;
      except
        Result := False;
      end;
    end);
end;

procedure TJsonSchemaValidator.RegisterFormat(const Name: string; Validator: TJsonSchemaFormatValidator);
begin
  if Name = '' then raise EArgumentException.Create('Name');
  if not Assigned(Validator) then raise EArgumentNilException.Create('Validator');
  FFormats.AddOrSetValue(LowerCase(Name), Validator);
end;

procedure TJsonSchemaValidator.RegisterSchema(const Uri: string; Schema: TNativeJsonValue);
begin
  FRegistry.RegisterSchema(Uri, Schema);
  try
    if FOptions.StrictSchema then CheckAllSchemas;
  except
    FRegistry.UnregisterSchema(Uri);
    raise;
  end;
end;

function TJsonSchemaValidator.IsSchemaValue(Value: TNativeJsonValue): Boolean;
begin
  Result := (Value is TJsonObject) or (Value is TJsonBoolean);
end;

function TJsonSchemaValidator.TryExactNumber(Value: TNativeJsonValue; out Number: TJsonExactNumber): Boolean;
begin
  Result := (Value is TJsonNumber) and TJsonExactNumber.TryParse(TJsonNumber(Value).AsRawText, Number);
end;

function TJsonSchemaValidator.IsNonNegativeInteger(Value: TNativeJsonValue): Boolean;
var
  N: TJsonExactNumber;
begin
  Result := TryExactNumber(Value, N) and N.IsInteger and not N.IsNegative;
end;

function TJsonSchemaValidator.IsPositiveNumber(Value: TNativeJsonValue): Boolean;
var
  N: TJsonExactNumber;
begin
  Result := TryExactNumber(Value, N) and N.IsPositive;
end;

function TJsonSchemaValidator.CountBelowMinimum(Constraint: TNativeJsonValue; Count: Integer): Boolean;
var
  N: TJsonExactNumber;
begin
  Result := TryExactNumber(Constraint, N) and (N.CompareToInt64(Count) > 0);
end;

function TJsonSchemaValidator.CountAboveMaximum(Constraint: TNativeJsonValue; Count: Integer): Boolean;
var
  N: TJsonExactNumber;
begin
  Result := TryExactNumber(Constraint, N) and (N.CompareToInt64(Count) < 0);
end;

function TJsonSchemaValidator.ConstraintText(Constraint: TNativeJsonValue): string;
var
  N: TJsonExactNumber;
begin
  if TryExactNumber(Constraint, N) then Result := N.ToCanonical else Result := '';
end;

procedure TJsonSchemaValidator.CheckAllSchemas;
var
  Schema: TNativeJsonValue;
begin
  for Schema in FRegistry.Schemas do CheckSchema(Schema);
end;

procedure TJsonSchemaValidator.CheckSchema(Schema: TNativeJsonValue);
const
  TypeNames: array[0..6] of string = ('null', 'boolean', 'object', 'array', 'number', 'integer', 'string');
var
  Obj, Map: TJsonObject;
  Arr: TJsonArray;
  V: TNativeJsonValue;
  Pair: TPair<string, TNativeJsonValue>;
  Path: string;
  I, J: Integer;
  Dialect: TJsonSchemaDialect;

  procedure Fail(const Keyword, Message: string);
  begin
    raise EJsonSchemaException.Create(Path + '/' + JsonPointerEscape(Keyword), Keyword, Message);
  end;

  function HasTypeName(const S: string): Boolean;
  var
    K: Integer;
  begin
    for K := Low(TypeNames) to High(TypeNames) do if S = TypeNames[K] then Exit(True);
    Result := False;
  end;

  procedure RequireSchema(const Keyword: string);
  begin
    if Obj.TryGetValue(Keyword, V) and not IsSchemaValue(V) then Fail(Keyword, Keyword + ' must be a boolean or object schema');
  end;

  procedure RequireSchemaArray(const Keyword: string);
  var
    I: Integer;
  begin
    if not Obj.TryGetValue(Keyword, V) then Exit;
    if not (V is TJsonArray) or (TJsonArray(V).Count = 0) then Fail(Keyword, Keyword + ' must be a non-empty array of schemas');
    Arr := TJsonArray(V);
    for I := 0 to Arr.Count - 1 do if not IsSchemaValue(Arr[I]) then Fail(Keyword, Keyword + ' contains a value that is not a schema');
  end;

  procedure RequireSchemaMap(const Keyword: string);
  var
    Pair: TPair<string, TNativeJsonValue>;
  begin
    if not Obj.TryGetValue(Keyword, V) then Exit;
    if not (V is TJsonObject) then Fail(Keyword, Keyword + ' must be an object of schemas');
    Map := TJsonObject(V);
    for Pair in Map do if not IsSchemaValue(Pair.Value) then Fail(Keyword, Keyword + ' contains a value that is not a schema');
  end;

  procedure RequireNonNegative(const Keyword: string);
  begin
    if Obj.TryGetValue(Keyword, V) and not IsNonNegativeInteger(V) then Fail(Keyword, Keyword + ' must be a non-negative integer');
  end;

  procedure RequireNumber(const Keyword: string);
  begin
    if Obj.TryGetValue(Keyword, V) and not (V is TJsonNumber) then Fail(Keyword, Keyword + ' must be a number');
  end;

  procedure RequireString(const Keyword: string);
  begin
    if Obj.TryGetValue(Keyword, V) and not (V is TJsonString) then Fail(Keyword, Keyword + ' must be a string');
  end;

  procedure RequireStringArray(const Keyword: string; Unique: Boolean);
  var
    I, J: Integer;
  begin
    if not Obj.TryGetValue(Keyword, V) then Exit;
    if not (V is TJsonArray) then Fail(Keyword, Keyword + ' must be an array of strings');
    Arr := TJsonArray(V);
    for I := 0 to Arr.Count - 1 do
    begin
      if not (Arr[I] is TJsonString) then Fail(Keyword, Keyword + ' must contain only strings');
      if Unique then for J := 0 to I - 1 do if Arr[J].AsString = Arr[I].AsString then Fail(Keyword, Keyword + ' contains duplicate strings');
    end;
  end;

  procedure RequireAnchor(const Keyword: string);
  begin
    if not Obj.TryGetValue(Keyword, V) then Exit;
    if not (V is TJsonString) then Fail(Keyword, Keyword + ' must be a string');
    if not TRegEx.IsMatch(V.AsString, '^[A-Za-z_][A-Za-z0-9._-]*$') then Fail(Keyword, 'Invalid anchor name');
  end;

begin
  if not IsSchemaValue(Schema) then raise EJsonSchemaException.Create('#', '', 'Schema must be an object or boolean');
  if not (Schema is TJsonObject) then Exit;
  Obj := TJsonObject(Schema);
  Path := FRegistry.Info(Schema).SchemaPath;
  Dialect := FRegistry.Info(Schema).Dialect;

  RequireString('$schema');
  RequireString('$id');
  RequireString('$ref');
  RequireString('$comment');
  if (Dialect <> TJsonSchemaDialect.Draft07) and Obj.TryGetValue('$id', V) and (V is TJsonString) and (JsonSchemaUriFragment(V.AsString) <> '') then Fail('$id', '$id must not contain a fragment in this dialect');
  if Dialect <> TJsonSchemaDialect.Draft07 then RequireAnchor('$anchor');
  if Dialect = TJsonSchemaDialect.Draft2020_12 then
  begin
    RequireAnchor('$dynamicAnchor');
    RequireString('$dynamicRef');
  end;
  if Dialect = TJsonSchemaDialect.Draft2019_09 then
  begin
    RequireString('$recursiveRef');
    if Obj.TryGetValue('$recursiveAnchor', V) and not (V is TJsonBoolean) then Fail('$recursiveAnchor', '$recursiveAnchor must be boolean');
  end;

  if Obj.TryGetValue('type', V) then
  begin
    if V is TJsonString then
    begin
      if not HasTypeName(V.AsString) then Fail('type', 'Unknown JSON Schema type: ' + V.AsString);
    end
    else if V is TJsonArray then
    begin
      Arr := TJsonArray(V);
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr[I] is TJsonString) or not HasTypeName(Arr[I].AsString) then Fail('type', 'type array contains an invalid type');
        for J := 0 to I - 1 do if Arr[J].AsString = Arr[I].AsString then Fail('type', 'type array contains a duplicate type');
      end;
    end
    else Fail('type', 'type must be a string or an array of strings');
  end;

  if Obj.TryGetValue('enum', V) and not (V is TJsonArray) then Fail('enum', 'enum must be an array');
  if Obj.TryGetValue('multipleOf', V) and not IsPositiveNumber(V) then Fail('multipleOf', 'multipleOf must be greater than zero');
  RequireNumber('minimum');
  RequireNumber('maximum');
  RequireNumber('exclusiveMinimum');
  RequireNumber('exclusiveMaximum');
  RequireNonNegative('minLength');
  RequireNonNegative('maxLength');
  RequireNonNegative('minItems');
  RequireNonNegative('maxItems');
  RequireNonNegative('minProperties');
  RequireNonNegative('maxProperties');
  if Dialect <> TJsonSchemaDialect.Draft07 then
  begin
    RequireNonNegative('minContains');
    RequireNonNegative('maxContains');
  end;
  if Obj.TryGetValue('uniqueItems', V) and not (V is TJsonBoolean) then Fail('uniqueItems', 'uniqueItems must be boolean');
  if Obj.TryGetValue('pattern', V) then
  begin
    if not (V is TJsonString) then Fail('pattern', 'pattern must be a string');
    try
      TRegEx.IsMatch('', V.AsString);
    except
      on E: Exception do Fail('pattern', 'Invalid regular expression: ' + E.Message);
    end;
  end;
  RequireString('format');
  RequireString('contentEncoding');
  RequireString('contentMediaType');
  RequireStringArray('required', True);

  RequireSchema('additionalProperties');
  RequireSchema('propertyNames');
  RequireSchema('contains');
  RequireSchema('not');
  RequireSchema('if');
  RequireSchema('then');
  RequireSchema('else');
  RequireSchemaArray('allOf');
  RequireSchemaArray('anyOf');
  RequireSchemaArray('oneOf');
  RequireSchemaMap('properties');

  if Obj.TryGetValue('patternProperties', V) then
  begin
    if not (V is TJsonObject) then Fail('patternProperties', 'patternProperties must be an object');
    for Pair in TJsonObject(V) do
    begin
      if not IsSchemaValue(Pair.Value) then Fail('patternProperties', 'patternProperties contains a value that is not a schema');
      try
        TRegEx.IsMatch('', Pair.Key);
      except
        on E: Exception do Fail('patternProperties', 'Invalid regular expression "' + Pair.Key + '": ' + E.Message);
      end;
    end;
  end;

  if Dialect = TJsonSchemaDialect.Draft07 then
  begin
    RequireSchemaMap('definitions');
    if Obj.TryGetValue('items', V) then
    begin
      if not IsSchemaValue(V) and not (V is TJsonArray) then Fail('items', 'items must be a schema or array of schemas');
      if V is TJsonArray then
      begin
        Arr := TJsonArray(V);
        for I := 0 to Arr.Count - 1 do if not IsSchemaValue(Arr[I]) then Fail('items', 'items contains a value that is not a schema');
      end;
    end;
    RequireSchema('additionalItems');
    if Obj.TryGetValue('dependencies', V) then
    begin
      if not (V is TJsonObject) then Fail('dependencies', 'dependencies must be an object');
      for Pair in TJsonObject(V) do
        if Pair.Value is TJsonArray then
        begin
          Arr := TJsonArray(Pair.Value);
          for I := 0 to Arr.Count - 1 do
          begin
            if not (Arr[I] is TJsonString) then Fail('dependencies', 'property dependency arrays must contain strings');
            for J := 0 to I - 1 do if Arr[J].AsString = Arr[I].AsString then Fail('dependencies', 'property dependency arrays contain duplicates');
          end;
        end
        else if not IsSchemaValue(Pair.Value) then Fail('dependencies', 'dependency value must be a schema or string array');
    end;
  end
  else
  begin
    RequireSchemaMap('$defs');
    RequireSchemaMap('definitions');
    RequireSchemaMap('dependentSchemas');
    if Obj.TryGetValue('dependentRequired', V) then
    begin
      if not (V is TJsonObject) then Fail('dependentRequired', 'dependentRequired must be an object');
      for Pair in TJsonObject(V) do
      begin
        if not (Pair.Value is TJsonArray) then Fail('dependentRequired', 'dependentRequired values must be arrays');
        Arr := TJsonArray(Pair.Value);
        for I := 0 to Arr.Count - 1 do
        begin
          if not (Arr[I] is TJsonString) then Fail('dependentRequired', 'dependentRequired arrays must contain strings');
          for J := 0 to I - 1 do if Arr[J].AsString = Arr[I].AsString then Fail('dependentRequired', 'dependentRequired arrays contain duplicates');
        end;
      end;
    end;
    RequireSchema('unevaluatedProperties');
    RequireSchema('unevaluatedItems');
    RequireSchema('contentSchema');
    if Dialect = TJsonSchemaDialect.Draft2020_12 then
    begin
      RequireSchema('items');
      if Obj.TryGetValue('prefixItems', V) then
      begin
        if not (V is TJsonArray) or (TJsonArray(V).Count = 0) then Fail('prefixItems', 'prefixItems must be a non-empty array of schemas');
        Arr := TJsonArray(V);
        for I := 0 to Arr.Count - 1 do if not IsSchemaValue(Arr[I]) then Fail('prefixItems', 'prefixItems contains a value that is not a schema');
      end;
    end
    else
    begin
      if Obj.TryGetValue('items', V) then
      begin
        if not IsSchemaValue(V) and not (V is TJsonArray) then Fail('items', 'items must be a schema or array of schemas');
        if V is TJsonArray then
        begin
          Arr := TJsonArray(V);
          for I := 0 to Arr.Count - 1 do if not IsSchemaValue(Arr[I]) then Fail('items', 'items contains a value that is not a schema');
        end;
      end;
      RequireSchema('additionalItems');
    end;
  end;
end;

function TJsonSchemaValidator.PatternMatches(const Value, Pattern: string): Boolean;
var
  R: TRegEx;
begin
  try
    if not FRegexCache.TryGetValue(Pattern, R) then
    begin
      R := TRegEx.Create(Pattern);
      FRegexCache.Add(Pattern, R);
    end;
    Result := R.IsMatch(Value);
  except
    // A pattern that cannot be compiled cannot match anything.
    // With StrictSchema it was already reported before.
    Result := False;
  end;
end;

function TJsonSchemaValidator.CodePointLength(const Value: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  I := 1;
  while I <= Length(Value) do
  begin
    Inc(Result);
    if (I < Length(Value)) and (Ord(Value[I]) >= $D800) and (Ord(Value[I]) <= $DBFF) and (Ord(Value[I + 1]) >= $DC00) and (Ord(Value[I + 1]) <= $DFFF) then Inc(I, 2) else Inc(I);
  end;
end;

function TJsonSchemaValidator.JsonTypeName(Value: TNativeJsonValue): string;
var
  N: TJsonExactNumber;
begin
  if (Value = nil) or (Value is TJsonNull) then Exit('null');
  if Value is TJsonBoolean then Exit('boolean');
  if Value is TJsonObject then Exit('object');
  if Value is TJsonArray then Exit('array');
  if Value is TJsonNumber then
  begin
    if TryExactNumber(Value, N) and N.IsInteger then Exit('integer');
    Exit('number');
  end;
  Result := 'string';
end;

function TJsonSchemaValidator.MatchesType(Value: TNativeJsonValue; const TypeName: string): Boolean;
begin
  if TypeName = 'number' then Exit(Value is TJsonNumber);
  if TypeName = 'integer' then Exit((Value is TJsonNumber) and (JsonTypeName(Value) = 'integer'));
  Result := JsonTypeName(Value) = TypeName;
end;

function TJsonSchemaValidator.MatchesDeclaredType(Value: TNativeJsonValue; Schema: TNativeJsonValue): Boolean;
var
  Obj: TJsonObject;
  V, Item: TNativeJsonValue;
begin
  if not (Schema is TJsonObject) then Exit(True);
  Obj := TJsonObject(Schema);
  if not Obj.TryGetValue('type', V) then Exit(True);
  if V is TJsonString then Exit(MatchesType(Value, V.AsString));
  if V is TJsonArray then
  begin
    for Item in TJsonArray(V) do if (Item is TJsonString) and MatchesType(Value, Item.AsString) then Exit(True);
    Exit(False);
  end;
  Result := True;
end;

function TJsonSchemaValidator.ValuesEqual(A, B: TNativeJsonValue): Boolean;
begin
  Result := TJsonComparer.DeepEquals(A, B);
end;

procedure TJsonSchemaValidator.AddError(Errors: TList<TJsonSchemaValidationError>; Schema: TNativeJsonValue; const InstancePath, Keyword, Message: string);
var
  Info: TJsonSchemaNodeInfo;
  SchemaPath: string;
begin
  if ShouldStop(Errors, 0) then Exit;
  Info := FRegistry.Info(Schema);
  SchemaPath := Info.SchemaPath;
  if Keyword <> '' then SchemaPath := SchemaPath + '/' + JsonPointerEscape(Keyword);
  Errors.Add(TJsonSchemaValidationError.Create(InstancePath, SchemaPath, Info.ResourceUri, Keyword, Message));
end;

function TJsonSchemaValidator.ShouldStop(Errors: TList<TJsonSchemaValidationError>; Baseline: Integer): Boolean;
begin
  Result := (FOptions.StopOnFirstError and (Errors.Count > Baseline)) or ((FOptions.MaxErrors > 0) and (Errors.Count >= FOptions.MaxErrors));
end;

function TJsonSchemaValidator.IsReferenceActive(Schema, Instance: TNativeJsonValue): Boolean;
var
  Frame: TRefFrame;
begin
  for Frame in FRefStack do if (Frame.Schema = Schema) and (Frame.Instance = Instance) then Exit(True);
  Result := False;
end;

procedure TJsonSchemaValidator.EvaluateAssertions(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>);
var
  Obj: TJsonObject;
  V, Item: TNativeJsonValue;
  Match: Boolean;
begin
  Obj := TJsonObject(Schema);
  if not MatchesDeclaredType(Instance, Schema) then AddError(Errors, Schema, InstancePath, 'type', JsonTypeName(Instance) + ' is not one of the declared types');
  if ShouldStop(Errors, 0) then Exit;
  if Obj.TryGetValue('enum', V) and (V is TJsonArray) then
  begin
    Match := False;
    for Item in TJsonArray(V) do
      if ValuesEqual(Instance, Item) then
      begin
        Match := True;
        Break;
      end;
    if not Match then AddError(Errors, Schema, InstancePath, 'enum', 'Value does not match any entry in enum');
  end;
  if ShouldStop(Errors, 0) then Exit;
  if Obj.TryGetValue('const', V) and not ValuesEqual(Instance, V) then AddError(Errors, Schema, InstancePath, 'const', 'Value does not match const');
end;

procedure TJsonSchemaValidator.EvaluateNumeric(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>);
var
  Obj: TJsonObject;
  V: TNativeJsonValue;
  N, B: TJsonExactNumber;
  C: Integer;
begin
  if not TryExactNumber(Instance, N) then Exit;
  Obj := TJsonObject(Schema);
  if Obj.TryGetValue('multipleOf', V) and TryExactNumber(V, B) and B.IsPositive and not N.IsMultipleOf(B) then AddError(Errors, Schema, InstancePath, 'multipleOf', N.ToCanonical + ' is not a multiple of ' + B.ToCanonical);
  if ShouldStop(Errors, 0) then Exit;
  if Obj.TryGetValue('minimum', V) and TryExactNumber(V, B) and (N.Compare(B) < 0) then AddError(Errors, Schema, InstancePath, 'minimum', N.ToCanonical + ' is less than ' + B.ToCanonical);
  if ShouldStop(Errors, 0) then Exit;
  if Obj.TryGetValue('maximum', V) and TryExactNumber(V, B) and (N.Compare(B) > 0) then AddError(Errors, Schema, InstancePath, 'maximum', N.ToCanonical + ' is greater than ' + B.ToCanonical);
  if ShouldStop(Errors, 0) then Exit;
  if Obj.TryGetValue('exclusiveMinimum', V) and TryExactNumber(V, B) then
  begin
    C := N.Compare(B);
    if C <= 0 then AddError(Errors, Schema, InstancePath, 'exclusiveMinimum', N.ToCanonical + ' is not greater than ' + B.ToCanonical);
  end;
  if ShouldStop(Errors, 0) then Exit;
  if Obj.TryGetValue('exclusiveMaximum', V) and TryExactNumber(V, B) then
  begin
    C := N.Compare(B);
    if C >= 0 then AddError(Errors, Schema, InstancePath, 'exclusiveMaximum', N.ToCanonical + ' is not less than ' + B.ToCanonical);
  end;
end;

procedure TJsonSchemaValidator.EvaluateString(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>);
var
  Obj: TJsonObject;
  V: TNativeJsonValue;
  S: string;
  L: Integer;
  FormatValidator: TJsonSchemaFormatValidator;
begin
  if not (Instance is TJsonString) then Exit;
  S := Instance.AsString;
  L := CodePointLength(S);
  Obj := TJsonObject(Schema);
  if Obj.TryGetValue('minLength', V) and CountBelowMinimum(V, L) then AddError(Errors, Schema, InstancePath, 'minLength', Format('String has %d code points, minimum is %s', [L, ConstraintText(V)]));
  if ShouldStop(Errors, 0) then Exit;
  if Obj.TryGetValue('maxLength', V) and CountAboveMaximum(V, L) then AddError(Errors, Schema, InstancePath, 'maxLength', Format('String has %d code points, maximum is %s', [L, ConstraintText(V)]));
  if ShouldStop(Errors, 0) then Exit;
  if Obj.TryGetValue('pattern', V) and (V is TJsonString) and not PatternMatches(S, V.AsString) then AddError(Errors, Schema, InstancePath, 'pattern', 'String does not match pattern "' + V.AsString + '"');
  if ShouldStop(Errors, 0) then Exit;
  if FOptions.AssertFormats and Obj.TryGetValue('format', V) and (V is TJsonString) and FFormats.TryGetValue(LowerCase(V.AsString), FormatValidator) and not FormatValidator(S) then AddError(Errors, Schema, InstancePath, 'format', 'String does not satisfy format "' + V.AsString + '"');
end;

function TJsonSchemaValidator.EvaluateReference(Instance, Target: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>; Depth: Integer): TEvaluation;
var
  Frame: TRefFrame;
begin
  if IsReferenceActive(Target, Instance) then Exit(TEvaluation.Create);
  Frame.Schema := Target;
  Frame.Instance := Instance;
  FRefStack.Add(Frame);
  try
    Result := Evaluate(Instance, Target, InstancePath, Errors, Depth + 1);
  finally
    FRefStack.Delete(FRefStack.Count - 1);
  end;
end;

function TJsonSchemaValidator.EvaluateLogic(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>; Depth: Integer): TEvaluation;
var
  Obj: TJsonObject;
  V, Branch: TNativeJsonValue;
  Arr: TJsonArray;
  TempErrors: TList<TJsonSchemaValidationError>;
  BranchEval, Combined: TEvaluation;
  I, MatchCount, Baseline: Integer;
  AllValid, Condition: Boolean;
begin
  Result := TEvaluation.Create;
  Obj := TJsonObject(Schema);
  Baseline := Errors.Count;

  if Obj.TryGetValue('allOf', V) and (V is TJsonArray) then
  begin
    Arr := TJsonArray(V);
    Combined := TEvaluation.Create;
    try
      AllValid := True;
      for I := 0 to Arr.Count - 1 do
      begin
        if not IsSchemaValue(Arr[I]) then Continue;
        BranchEval := Evaluate(Instance, Arr[I], InstancePath, Errors, Depth + 1);
        try
          if BranchEval.Valid then Combined.Merge(BranchEval) else AllValid := False;
        finally
          BranchEval.Free;
        end;
        if ShouldStop(Errors, Baseline) then Break;
      end;
      if AllValid then Result.Merge(Combined);
    finally
      Combined.Free;
    end;
  end;

  if Obj.TryGetValue('anyOf', V) and (V is TJsonArray) and not ShouldStop(Errors, Baseline) then
  begin
    Arr := TJsonArray(V);
    MatchCount := 0;
    Combined := TEvaluation.Create;
    try
      for I := 0 to Arr.Count - 1 do
      begin
        if not IsSchemaValue(Arr[I]) then Continue;
        TempErrors := TList<TJsonSchemaValidationError>.Create;
        try
          BranchEval := Evaluate(Instance, Arr[I], InstancePath, TempErrors, Depth + 1);
          try
            if BranchEval.Valid then
            begin
              Inc(MatchCount);
              Combined.Merge(BranchEval);
            end;
          finally
            BranchEval.Free;
          end;
        finally
          TempErrors.Free;
        end;
      end;
      if MatchCount = 0 then AddError(Errors, Schema, InstancePath, 'anyOf', 'Value does not match any anyOf branch') else Result.Merge(Combined);
    finally
      Combined.Free;
    end;
  end;

  if Obj.TryGetValue('oneOf', V) and (V is TJsonArray) and not ShouldStop(Errors, Baseline) then
  begin
    Arr := TJsonArray(V);
    MatchCount := 0;
    Combined := TEvaluation.Create;
    try
      for I := 0 to Arr.Count - 1 do
      begin
        if not IsSchemaValue(Arr[I]) then Continue;
        TempErrors := TList<TJsonSchemaValidationError>.Create;
        try
          BranchEval := Evaluate(Instance, Arr[I], InstancePath, TempErrors, Depth + 1);
          try
            if BranchEval.Valid then
            begin
              Inc(MatchCount);
              Combined.Merge(BranchEval);
            end;
          finally
            BranchEval.Free;
          end;
        finally
          TempErrors.Free;
        end;
      end;
      if MatchCount <> 1 then AddError(Errors, Schema, InstancePath, 'oneOf', Format('Value matches %d oneOf branches instead of exactly one', [MatchCount])) else Result.Merge(Combined);
    finally
      Combined.Free;
    end;
  end;

  if Obj.TryGetValue('not', V) and IsSchemaValue(V) and not ShouldStop(Errors, Baseline) then
  begin
    TempErrors := TList<TJsonSchemaValidationError>.Create;
    try
      BranchEval := Evaluate(Instance, V, InstancePath, TempErrors, Depth + 1);
      try
        if BranchEval.Valid then AddError(Errors, Schema, InstancePath, 'not', 'Value matches the forbidden not schema');
      finally
        BranchEval.Free;
      end;
    finally
      TempErrors.Free;
    end;
  end;

  if Obj.TryGetValue('if', V) and IsSchemaValue(V) and not ShouldStop(Errors, Baseline) then
  begin
    TempErrors := TList<TJsonSchemaValidationError>.Create;
    try
      BranchEval := Evaluate(Instance, V, InstancePath, TempErrors, Depth + 1);
      try
        Condition := BranchEval.Valid;
        if Condition then Result.Merge(BranchEval);
      finally
        BranchEval.Free;
      end;
    finally
      TempErrors.Free;
    end;
    Branch := nil;
    if Condition then Obj.TryGetValue('then', Branch) else Obj.TryGetValue('else', Branch);
    if IsSchemaValue(Branch) then
    begin
      BranchEval := Evaluate(Instance, Branch, InstancePath, Errors, Depth + 1);
      try
        if BranchEval.Valid then Result.Merge(BranchEval);
      finally
        BranchEval.Free;
      end;
    end;
  end;
  Result.Valid := Errors.Count = Baseline;
end;

function TJsonSchemaValidator.EvaluateObject(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>; Depth: Integer; BaseEvaluation: TEvaluation): TEvaluation;
var
  ObjSchema, ObjInstance, Map: TJsonObject;
  V, Child: TNativeJsonValue;
  Arr: TJsonArray;
  Pair, InstPair: TPair<string, TNativeJsonValue>;
  E, KeywordEval: TEvaluation;
  MatchedNames: TDictionary<string, Boolean>;
  I, Baseline: Integer;
  KeywordValid: Boolean;
  Name: string;
  Dialect: TJsonSchemaDialect;

  function ChildPath(const AName: string): string;
  begin
    Result := InstancePath + '/' + JsonPointerEscape(AName);
  end;

  procedure ApplyRequiredMap(Dependencies: TNativeJsonValue; const Keyword: string);
  var
    DP: TPair<string, TNativeJsonValue>;
    Names: TJsonArray;
    K: Integer;
  begin
    if not (Dependencies is TJsonObject) then Exit;
    for DP in TJsonObject(Dependencies) do
    begin
      if not ObjInstance.Contains(DP.Key) or not (DP.Value is TJsonArray) then Continue;
      Names := TJsonArray(DP.Value);
      for K := 0 to Names.Count - 1 do
        if (Names[K] is TJsonString) and not ObjInstance.Contains(Names[K].AsString) then AddError(Errors, Schema, InstancePath, Keyword, 'Property "' + DP.Key + '" requires "' + Names[K].AsString + '"');
      if ShouldStop(Errors, Baseline) then Exit;
    end;
  end;

  procedure ApplySchemaMap(Dependencies: TNativeJsonValue; const Keyword: string);
  var
    DP: TPair<string, TNativeJsonValue>;
  begin
    if not (Dependencies is TJsonObject) then Exit;
    for DP in TJsonObject(Dependencies) do
    begin
      if not ObjInstance.Contains(DP.Key) or not IsSchemaValue(DP.Value) then Continue;
      E := Evaluate(Instance, DP.Value, InstancePath, Errors, Depth + 1);
      try
        if E.Valid then Result.Merge(E);
      finally
        E.Free;
      end;
      if ShouldStop(Errors, Baseline) then Exit;
    end;
  end;

  procedure ApplyDraft07Dependencies(Dependencies: TNativeJsonValue);
  var
    DP: TPair<string, TNativeJsonValue>;
    Names: TJsonArray;
    K: Integer;
  begin
    if not (Dependencies is TJsonObject) then Exit;
    for DP in TJsonObject(Dependencies) do
    begin
      if not ObjInstance.Contains(DP.Key) then Continue;
      if DP.Value is TJsonArray then
      begin
        Names := TJsonArray(DP.Value);
        for K := 0 to Names.Count - 1 do
          if (Names[K] is TJsonString) and not ObjInstance.Contains(Names[K].AsString) then AddError(Errors, Schema, InstancePath, 'dependencies', 'Property "' + DP.Key + '" requires "' + Names[K].AsString + '"');
      end
      else if IsSchemaValue(DP.Value) then
      begin
        E := Evaluate(Instance, DP.Value, InstancePath, Errors, Depth + 1);
        try
          if E.Valid then Result.Merge(E);
        finally
          E.Free;
        end;
      end;
      if ShouldStop(Errors, Baseline) then Exit;
    end;
  end;

begin
  Result := TEvaluation.Create;
  Result.Merge(BaseEvaluation);
  ObjSchema := TJsonObject(Schema);
  ObjInstance := TJsonObject(Instance);
  Dialect := FRegistry.Info(Schema).Dialect;
  Baseline := Errors.Count;
  MatchedNames := TDictionary<string, Boolean>.Create;
  try
    if ObjSchema.TryGetValue('properties', V) and (V is TJsonObject) then
    begin
      KeywordEval := TEvaluation.Create;
      try
        KeywordValid := True;
        for Pair in TJsonObject(V) do
          if ObjInstance.TryGetValue(Pair.Key, Child) then
          begin
            MatchedNames.AddOrSetValue(Pair.Key, True);
            if not IsSchemaValue(Pair.Value) then Continue;
            E := Evaluate(Child, Pair.Value, ChildPath(Pair.Key), Errors, Depth + 1);
            try
              if E.Valid then KeywordEval.AddProperty(Pair.Key) else KeywordValid := False;
            finally
              E.Free;
            end;
            if ShouldStop(Errors, Baseline) then Break;
          end;
        if KeywordValid then Result.Merge(KeywordEval);
      finally
        KeywordEval.Free;
      end;
    end;

    if ObjSchema.TryGetValue('patternProperties', V) and (V is TJsonObject) and not ShouldStop(Errors, Baseline) then
    begin
      KeywordEval := TEvaluation.Create;
      try
        KeywordValid := True;
        Map := TJsonObject(V);
        for Pair in Map do
        begin
          if not IsSchemaValue(Pair.Value) then Continue;
          for InstPair in ObjInstance do
            if PatternMatches(InstPair.Key, Pair.Key) then
            begin
              MatchedNames.AddOrSetValue(InstPair.Key, True);
              E := Evaluate(InstPair.Value, Pair.Value, ChildPath(InstPair.Key), Errors, Depth + 1);
              try
                if E.Valid then KeywordEval.AddProperty(InstPair.Key) else KeywordValid := False;
              finally
                E.Free;
              end;
              if ShouldStop(Errors, Baseline) then Break;
            end;
          if ShouldStop(Errors, Baseline) then Break;
        end;
        if KeywordValid then Result.Merge(KeywordEval);
      finally
        KeywordEval.Free;
      end;
    end;

    if ObjSchema.TryGetValue('additionalProperties', V) and IsSchemaValue(V) and not ShouldStop(Errors, Baseline) then
    begin
      KeywordEval := TEvaluation.Create;
      try
        KeywordValid := True;
        for InstPair in ObjInstance do
          if not MatchedNames.ContainsKey(InstPair.Key) then
          begin
            E := Evaluate(InstPair.Value, V, ChildPath(InstPair.Key), Errors, Depth + 1);
            try
              if E.Valid then KeywordEval.AddProperty(InstPair.Key) else KeywordValid := False;
            finally
              E.Free;
            end;
            if ShouldStop(Errors, Baseline) then Break;
          end;
        if KeywordValid then Result.Merge(KeywordEval);
      finally
        KeywordEval.Free;
      end;
    end;

    if ObjSchema.TryGetValue('propertyNames', V) and IsSchemaValue(V) and not ShouldStop(Errors, Baseline) then
      for InstPair in ObjInstance do
      begin
        Child := TJsonString.Create(InstPair.Key);
        E := nil;
        try
          E := Evaluate(Child, V, ChildPath(InstPair.Key), Errors, Depth + 1);
        finally
          E.Free;
          Child.Free;
        end;
        if ShouldStop(Errors, Baseline) then Break;
      end;

    if ObjSchema.TryGetValue('required', V) and (V is TJsonArray) and not ShouldStop(Errors, Baseline) then
    begin
      Arr := TJsonArray(V);
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr[I] is TJsonString) then Continue;
        Name := Arr[I].AsString;
        if not ObjInstance.Contains(Name) then AddError(Errors, Schema, InstancePath, 'required', 'Missing required property "' + Name + '"');
        if ShouldStop(Errors, Baseline) then Break;
      end;
    end;

    if ObjSchema.TryGetValue('minProperties', V) and CountBelowMinimum(V, ObjInstance.Count) and not ShouldStop(Errors, Baseline) then AddError(Errors, Schema, InstancePath, 'minProperties', Format('Object has %d properties, minimum is %s', [ObjInstance.Count, ConstraintText(V)]));
    if ObjSchema.TryGetValue('maxProperties', V) and CountAboveMaximum(V, ObjInstance.Count) and not ShouldStop(Errors, Baseline) then AddError(Errors, Schema, InstancePath, 'maxProperties', Format('Object has %d properties, maximum is %s', [ObjInstance.Count, ConstraintText(V)]));

    if Dialect = TJsonSchemaDialect.Draft07 then
    begin
      if ObjSchema.TryGetValue('dependencies', V) and not ShouldStop(Errors, Baseline) then ApplyDraft07Dependencies(V);
    end
    else
    begin
      if ObjSchema.TryGetValue('dependentRequired', V) and not ShouldStop(Errors, Baseline) then ApplyRequiredMap(V, 'dependentRequired');
      if ObjSchema.TryGetValue('dependentSchemas', V) and not ShouldStop(Errors, Baseline) then ApplySchemaMap(V, 'dependentSchemas');
    end;

    if (Dialect <> TJsonSchemaDialect.Draft07) and ObjSchema.TryGetValue('unevaluatedProperties', V) and IsSchemaValue(V) and not ShouldStop(Errors, Baseline) and not Result.AllProperties then
    begin
      KeywordEval := TEvaluation.Create;
      try
        KeywordValid := True;
        for InstPair in ObjInstance do
          if not Result.HasProperty(InstPair.Key) then
          begin
            E := Evaluate(InstPair.Value, V, ChildPath(InstPair.Key), Errors, Depth + 1);
            try
              if E.Valid then KeywordEval.AddProperty(InstPair.Key) else KeywordValid := False;
            finally
              E.Free;
            end;
            if ShouldStop(Errors, Baseline) then Break;
          end;
        if KeywordValid then
        begin
          KeywordEval.AllProperties := True;
          Result.Merge(KeywordEval);
        end;
      finally
        KeywordEval.Free;
      end;
    end;

  finally
    MatchedNames.Free;
  end;
end;

function TJsonSchemaValidator.EvaluateArray(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>; Depth: Integer; BaseEvaluation: TEvaluation): TEvaluation;
var
  Obj: TJsonObject;
  Arr, Schemas: TJsonArray;
  V, ItemSchema, Additional: TNativeJsonValue;
  E, KeywordEval: TEvaluation;
  TempErrors: TList<TJsonSchemaValidationError>;
  I, J, StartIndex, ApplyCount, MatchCount, Baseline: Integer;
  KeywordValid, DuplicateFound: Boolean;
  Dialect: TJsonSchemaDialect;
begin
  Result := TEvaluation.Create;
  Result.Merge(BaseEvaluation);
  Obj := TJsonObject(Schema);
  Arr := TJsonArray(Instance);
  Dialect := FRegistry.Info(Schema).Dialect;
  Baseline := Errors.Count;
  StartIndex := 0;

  if (Dialect = TJsonSchemaDialect.Draft2020_12) and Obj.TryGetValue('prefixItems', V) and (V is TJsonArray) then
  begin
    Schemas := TJsonArray(V);
    KeywordEval := TEvaluation.Create;
    try
      KeywordValid := True;
      ApplyCount := Schemas.Count;
      if ApplyCount > Arr.Count then ApplyCount := Arr.Count;
      for I := 0 to ApplyCount - 1 do
      begin
        if not IsSchemaValue(Schemas[I]) then Continue;
        E := Evaluate(Arr[I], Schemas[I], InstancePath + '/' + IntToStr(I), Errors, Depth + 1);
        try
          if E.Valid then KeywordEval.AddItem(I) else KeywordValid := False;
        finally
          E.Free;
        end;
        if ShouldStop(Errors, Baseline) then Break;
      end;
      if KeywordValid then Result.Merge(KeywordEval);
    finally
      KeywordEval.Free;
    end;
    StartIndex := Schemas.Count;
  end;

  if Obj.TryGetValue('items', V) and not ShouldStop(Errors, Baseline) then
  begin
    if (Dialect <> TJsonSchemaDialect.Draft2020_12) and (V is TJsonArray) then
    begin
      Schemas := TJsonArray(V);
      KeywordEval := TEvaluation.Create;
      try
        KeywordValid := True;
        ApplyCount := Schemas.Count;
        if ApplyCount > Arr.Count then ApplyCount := Arr.Count;
        for I := 0 to ApplyCount - 1 do
        begin
          if not IsSchemaValue(Schemas[I]) then Continue;
          E := Evaluate(Arr[I], Schemas[I], InstancePath + '/' + IntToStr(I), Errors, Depth + 1);
          try
            if E.Valid then KeywordEval.AddItem(I) else KeywordValid := False;
          finally
            E.Free;
          end;
          if ShouldStop(Errors, Baseline) then Break;
        end;
        if KeywordValid then Result.Merge(KeywordEval);
      finally
        KeywordEval.Free;
      end;
      StartIndex := Schemas.Count;
      if Obj.TryGetValue('additionalItems', Additional) and IsSchemaValue(Additional) and not ShouldStop(Errors, Baseline) then
      begin
        KeywordEval := TEvaluation.Create;
        try
          KeywordValid := True;
          for I := StartIndex to Arr.Count - 1 do
          begin
            E := Evaluate(Arr[I], Additional, InstancePath + '/' + IntToStr(I), Errors, Depth + 1);
            try
              if E.Valid then KeywordEval.AddItem(I) else KeywordValid := False;
            finally
              E.Free;
            end;
            if ShouldStop(Errors, Baseline) then Break;
          end;
          if KeywordValid then Result.Merge(KeywordEval);
        finally
          KeywordEval.Free;
        end;
      end;
    end
    else if IsSchemaValue(V) then
    begin
      ItemSchema := V;
      KeywordEval := TEvaluation.Create;
      try
        KeywordValid := True;
        for I := StartIndex to Arr.Count - 1 do
        begin
          E := Evaluate(Arr[I], ItemSchema, InstancePath + '/' + IntToStr(I), Errors, Depth + 1);
          try
            if E.Valid then KeywordEval.AddItem(I) else KeywordValid := False;
          finally
            E.Free;
          end;
          if ShouldStop(Errors, Baseline) then Break;
        end;
        if KeywordValid then
        begin
          if StartIndex = 0 then KeywordEval.AllItems := True;
          Result.Merge(KeywordEval);
        end;
      finally
        KeywordEval.Free;
      end;
    end;
  end;

  if Obj.TryGetValue('contains', V) and IsSchemaValue(V) and not ShouldStop(Errors, Baseline) then
  begin
    KeywordEval := TEvaluation.Create;
    try
      MatchCount := 0;
      for I := 0 to Arr.Count - 1 do
      begin
        TempErrors := TList<TJsonSchemaValidationError>.Create;
        try
          E := Evaluate(Arr[I], V, InstancePath + '/' + IntToStr(I), TempErrors, Depth + 1);
          try
            if E.Valid then
            begin
              Inc(MatchCount);
              KeywordEval.AddItem(I);
            end;
          finally
            E.Free;
          end;
        finally
          TempErrors.Free;
        end;
      end;
      KeywordValid := True;
      if Dialect = TJsonSchemaDialect.Draft07 then
      begin
        if MatchCount < 1 then
        begin
          AddError(Errors, Schema, InstancePath, 'contains', 'Array does not contain a matching item');
          KeywordValid := False;
        end;
      end
      else
      begin
        if Obj.TryGetValue('minContains', Additional) then
        begin
          if CountBelowMinimum(Additional, MatchCount) then
          begin
            AddError(Errors, Schema, InstancePath, 'minContains', Format('Array has %d matching items, minimum is %s', [MatchCount, ConstraintText(Additional)]));
            KeywordValid := False;
          end;
        end
        else if MatchCount < 1 then
        begin
          AddError(Errors, Schema, InstancePath, 'contains', 'Array does not contain a matching item');
          KeywordValid := False;
        end;
        if Obj.TryGetValue('maxContains', Additional) and CountAboveMaximum(Additional, MatchCount) then
        begin
          AddError(Errors, Schema, InstancePath, 'maxContains', Format('Array has %d matching items, maximum is %s', [MatchCount, ConstraintText(Additional)]));
          KeywordValid := False;
        end;
      end;
      if KeywordValid and (Dialect = TJsonSchemaDialect.Draft2020_12) then Result.Merge(KeywordEval);
    finally
      KeywordEval.Free;
    end;
  end;

  if Obj.TryGetValue('minItems', V) and CountBelowMinimum(V, Arr.Count) and not ShouldStop(Errors, Baseline) then AddError(Errors, Schema, InstancePath, 'minItems', Format('Array has %d items, minimum is %s', [Arr.Count, ConstraintText(V)]));
  if Obj.TryGetValue('maxItems', V) and CountAboveMaximum(V, Arr.Count) and not ShouldStop(Errors, Baseline) then AddError(Errors, Schema, InstancePath, 'maxItems', Format('Array has %d items, maximum is %s', [Arr.Count, ConstraintText(V)]));

  if Obj.TryGetValue('uniqueItems', V) and (V is TJsonBoolean) and V.AsBoolean and not ShouldStop(Errors, Baseline) then
  begin
    DuplicateFound := False;
    for I := 0 to Arr.Count - 1 do
    begin
      for J := I + 1 to Arr.Count - 1 do
        if ValuesEqual(Arr[I], Arr[J]) then
        begin
          AddError(Errors, Schema, InstancePath, 'uniqueItems', Format('Items %d and %d are equal', [I, J]));
          DuplicateFound := True;
          Break;
        end;
      if DuplicateFound or ShouldStop(Errors, Baseline) then Break;
    end;
  end;

  if (Dialect <> TJsonSchemaDialect.Draft07) and Obj.TryGetValue('unevaluatedItems', V) and IsSchemaValue(V) and not ShouldStop(Errors, Baseline) and not Result.AllItems then
  begin
    KeywordEval := TEvaluation.Create;
    try
      KeywordValid := True;
      for I := 0 to Arr.Count - 1 do
        if not Result.HasItem(I) then
        begin
          E := Evaluate(Arr[I], V, InstancePath + '/' + IntToStr(I), Errors, Depth + 1);
          try
            if E.Valid then KeywordEval.AddItem(I) else KeywordValid := False;
          finally
            E.Free;
          end;
          if ShouldStop(Errors, Baseline) then Break;
        end;
      if KeywordValid then
      begin
        KeywordEval.AllItems := True;
        Result.Merge(KeywordEval);
      end;
    finally
      KeywordEval.Free;
    end;
  end;
end;

function TJsonSchemaValidator.Evaluate(Instance, Schema: TNativeJsonValue; const InstancePath: string; Errors: TList<TJsonSchemaValidationError>; Depth: Integer): TEvaluation;
var
  Obj: TJsonObject;
  V, Target: TNativeJsonValue;
  RefEval, LogicEval, ContainerEval: TEvaluation;
  Info: TJsonSchemaNodeInfo;
  TargetUri, Resource: string;
  Baseline, ScopeCount: Integer;
begin
  Result := TEvaluation.Create;
  Baseline := Errors.Count;
  if Depth > FOptions.MaxDepth then
  begin
    AddError(Errors, Schema, InstancePath, 'maxDepth', Format('Maximum validation depth of %d exceeded', [FOptions.MaxDepth]));
    Result.Valid := False;
    Exit;
  end;

  Info := FRegistry.Info(Schema);
  Resource := Info.ResourceUri;
  ScopeCount := FDynamicScope.Count;
  if (ScopeCount = 0) or (FDynamicScope[ScopeCount - 1] <> Resource) then FDynamicScope.Add(Resource);
  try
    if Schema is TJsonBoolean then
    begin
      if not Schema.AsBoolean then AddError(Errors, Schema, InstancePath, 'false', 'Boolean false schema rejects the value');
      Result.Valid := Errors.Count = Baseline;
      Exit;
    end;
    Obj := TJsonObject(Schema);

    if Obj.TryGetValue('$ref', V) and (V is TJsonString) then
    begin
      Target := FRegistry.Resolve(V.AsString, Schema, TargetUri);
      RefEval := EvaluateReference(Instance, Target, InstancePath, Errors, Depth);
      try
        if RefEval.Valid then Result.Merge(RefEval);
      finally
        RefEval.Free;
      end;
      if Info.Dialect = TJsonSchemaDialect.Draft07 then
      begin
        Result.Valid := Errors.Count = Baseline;
        Exit;
      end;
    end;

    if not ShouldStop(Errors, Baseline) and (Info.Dialect = TJsonSchemaDialect.Draft2020_12) and Obj.TryGetValue('$dynamicRef', V) and (V is TJsonString) then
    begin
      Target := FRegistry.ResolveDynamic(V.AsString, Schema, FDynamicScope, TargetUri);
      RefEval := EvaluateReference(Instance, Target, InstancePath, Errors, Depth);
      try
        if RefEval.Valid then Result.Merge(RefEval);
      finally
        RefEval.Free;
      end;
    end;

    if not ShouldStop(Errors, Baseline) and (Info.Dialect = TJsonSchemaDialect.Draft2019_09) and Obj.TryGetValue('$recursiveRef', V) and (V is TJsonString) then
    begin
      Target := FRegistry.ResolveRecursive(V.AsString, Schema, FDynamicScope, TargetUri);
      RefEval := EvaluateReference(Instance, Target, InstancePath, Errors, Depth);
      try
        if RefEval.Valid then Result.Merge(RefEval);
      finally
        RefEval.Free;
      end;
    end;

    if not ShouldStop(Errors, Baseline) then EvaluateAssertions(Instance, Schema, InstancePath, Errors);
    if not ShouldStop(Errors, Baseline) then EvaluateNumeric(Instance, Schema, InstancePath, Errors);
    if not ShouldStop(Errors, Baseline) then EvaluateString(Instance, Schema, InstancePath, Errors);

    if not ShouldStop(Errors, Baseline) then
    begin
      LogicEval := EvaluateLogic(Instance, Schema, InstancePath, Errors, Depth);
      try
        if LogicEval.Valid then Result.Merge(LogicEval);
      finally
        LogicEval.Free;
      end;
    end;

    if not ShouldStop(Errors, Baseline) and (Instance is TJsonObject) then
    begin
      ContainerEval := EvaluateObject(Instance, Schema, InstancePath, Errors, Depth, Result);
      Result.Free;
      Result := ContainerEval;
    end
    else if not ShouldStop(Errors, Baseline) and (Instance is TJsonArray) then
    begin
      ContainerEval := EvaluateArray(Instance, Schema, InstancePath, Errors, Depth, Result);
      Result.Free;
      Result := ContainerEval;
    end;
    Result.Valid := Errors.Count = Baseline;
  finally
    while FDynamicScope.Count > ScopeCount do FDynamicScope.Delete(FDynamicScope.Count - 1);
  end;
end;

function TJsonSchemaValidator.Validate(Instance: TNativeJsonValue): TJsonSchemaValidationResult;
var
  Errors: TList<TJsonSchemaValidationError>;
  Eval: TEvaluation;
begin
  if Instance = nil then raise EArgumentNilException.Create('Instance');
  FRefStack.Clear;
  FDynamicScope.Clear;
  Errors := TList<TJsonSchemaValidationError>.Create;
  try
    Eval := Evaluate(Instance, FRegistry.Root, '', Errors, 0);
    try
      Result.IsValid := Eval.Valid;
    finally
      Eval.Free;
    end;
    Result.Errors := Errors.ToArray;
  finally
    Errors.Free;
  end;
end;

end.
