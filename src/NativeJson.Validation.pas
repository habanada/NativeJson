{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Validation;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  Rtti,
  TypInfo,
  Math,
  uregexpr,
  Generics.Collections,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  System.Math,
  System.RegularExpressions,
  System.Generics.Collections,
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.Attributes,
  NativeJson.Schema.Attributes,
  NativeJson.Rtti.Cache,
  NativeJson.NamingStrategy,
  NativeJson.Fluent;

type
  ValidationStrings = class sealed
  public const
    Minimum = 'Value %s is less than the allowed minimum of %s';
    Maximum = 'Value %s is greater than the allowed maximum of %s';
    ExclusiveMinimum = 'Value %s must be greater than %s';
    ExclusiveMaximum = 'Value %s must be less than %s';
    MultipleOf = 'Value %s is not a multiple of %s';
    Pattern = 'Value "%s" does not match the required pattern "%s"';
    PatternInvalid = 'The pattern "%s" is not a valid regular expression: %s';
    MinLength = 'Text is %d characters long, the minimum is %d';
    MaxLength = 'Text is %d characters long, the maximum is %d';
    MinItems = 'The collection holds %d items, the minimum is %d';
    MaxItems = 'The collection holds %d items, the maximum is %d';
    UniqueItems = 'The collection contains a duplicate item at position %d';
    DepthExceeded = 'Maximum nesting depth of %d was exceeded';
  end;

  TJsonValidationError = class
  private
    FPath: string;
    FMemberName: string;
    FRule: string;
    FMessage: string;
  public
    constructor Create(const APath, AMemberName, ARule, AMessage: string);
    function ToString: TJsonToStringResult; override;
    property Path: string read FPath;
    property MemberName: string read FMemberName;
    property Rule: string read FRule;
    property Message: string read FMessage;
  end;

  TJsonValidationResult = class
  private
    FErrors: TObjectList<TJsonValidationError>;
    function GetError(Index: Integer): TJsonValidationError;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const APath, AMemberName, ARule, AMessage: string);
    function IsValid: Boolean;
    function ToString: TJsonToStringResult; override;
    property Errors[Index: Integer]: TJsonValidationError read GetError; default;
    property Count: Integer read GetCount;
  end;

  TJsonValidator = class
  private
    FContext: TRttiContext;
    FFluent: TJsonFluentContext;
    FNamingStrategy: TJsonNamingStrategyClass;
    FMemberSelection: TJsonMemberTypes;
    FMaxDepth: Integer;
    FVisited: TList<Pointer>;
    FResult: TJsonValidationResult;
    procedure VisitValue(const Value: TValue; const MemberPath: string; Depth: Integer);
    procedure VisitObject(InstanceObj: TObject; const MemberPath: string; Depth: Integer);
    procedure VisitRecord(const Value: TValue; RType: TRttiType; const MemberPath: string; Depth: Integer);
    procedure VisitMembers(const Value: TValue; RType: TRttiType; const MemberPath: string; Depth: Integer);
    procedure VisitArray(const Value: TValue; const MemberPath: string; Depth: Integer);
    function VisitList(InstanceObj: TObject; const MemberPath: string; Depth: Integer): Boolean;
    procedure CheckRules(const Value: TValue; Info: TJsonMemberInfo; const MemberPath: string);
  public
    constructor Create(Fluent: TJsonFluentContext = nil);
    destructor Destroy; override;
    function Validate(const Value: TValue): TJsonValidationResult;
    property NamingStrategy: TJsonNamingStrategyClass read FNamingStrategy write FNamingStrategy;
    property MemberSelection: TJsonMemberTypes read FMemberSelection write FMemberSelection;
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
  end;

function CountCodePoints(const S: string): Integer;
function NumberToText(const InputValue: Double): string;
function PathPart(const Name: string): string;

implementation

function PatternMatches(const Text, APattern: string): Boolean;
{$IFDEF FPC}
var
  Expr: TRegExpr;
{$ENDIF}
begin
  {$IFDEF FPC}
  Expr := TRegExpr.Create(APattern);
  try
    Expr.ModifierS := False;
    Result := Expr.Exec(Text);
  finally
    Expr.Free;
  end;
  {$ELSE}
  Result := TRegEx.IsMatch(Text, APattern);
  {$ENDIF}
end;

// ---------------------------------------------------------------------------

function CountCodePoints(const S: string): Integer;
var
  I, Len: Integer;
begin
  // According to the specification minLength and maxLength count code points.
  // Length() counts UTF-16 units - an emoji would be two characters.
  Result := 0;
  I := 1;
  Len := Length(S);
  while I <= Len do
  begin
    if (S[I] >= #$D800) and (S[I] <= #$DBFF) and (I < Len) and
       (S[I + 1] >= #$DC00) and (S[I + 1] <= #$DFFF) then
      Inc(I, 2)
    else
      Inc(I);
    Inc(Result);
  end;
end;

function NumberToText(const InputValue: Double): string;
begin
  Result := FloatToStr(InputValue, TFormatSettings.Invariant);
end;

function PathPart(const Name: string): string;
begin
  // JSON Pointer per RFC 6901: ~ becomes ~0, / becomes ~1. The order
  // matters, otherwise a generated ~1 turns into ~01 again.
  Result := StringReplace(Name, '~', '~0', [rfReplaceAll]);
  Result := StringReplace(Result, '/', '~1', [rfReplaceAll]);
end;

{ TJsonValidationError }

constructor TJsonValidationError.Create(const APath, AMemberName, ARule, AMessage: string);
begin
  inherited Create;
  FPath := APath;
  FMemberName := AMemberName;
  FRule := ARule;
  FMessage := AMessage;
end;

function TJsonValidationError.ToString: TJsonToStringResult;
begin
  if FPath <> '' then Result := FPath + ': ' + FMessage else Result := FMessage;
end;

{ TJsonValidationResult }

constructor TJsonValidationResult.Create;
begin
  inherited Create;
  FErrors := TObjectList<TJsonValidationError>.Create(True);
end;

destructor TJsonValidationResult.Destroy;
begin
  FErrors.Free;
  inherited;
end;

procedure TJsonValidationResult.Add(const APath, AMemberName, ARule, AMessage: string);
begin
  FErrors.Add(TJsonValidationError.Create(APath, AMemberName, ARule, AMessage));
end;

function TJsonValidationResult.GetError(Index: Integer): TJsonValidationError;
begin
  Result := FErrors[Index];
end;

function TJsonValidationResult.GetCount: Integer;
begin
  Result := FErrors.Count;
end;

function TJsonValidationResult.IsValid: Boolean;
begin
  Result := FErrors.Count = 0;
end;

function TJsonValidationResult.ToString: TJsonToStringResult;
var
  Lines: TJsonStringBuilder;
  ErrorMessage: TJsonValidationError;
begin
  Lines := TJsonStringBuilder.Create;
  try
    for ErrorMessage in FErrors do
    begin
      if Lines.Length > 0 then Lines.AppendLine;
      Lines.Append(ErrorMessage.ToString);
    end;
    Result := Lines.ToString;
  finally
    Lines.Free;
  end;
end;

{ TJsonValidator }

constructor TJsonValidator.Create(Fluent: TJsonFluentContext);
begin
  inherited Create;
  FContext := TRttiContext.Create;
  FFluent := Fluent;
  FNamingStrategy := nil;
  FMemberSelection := [];
  FMaxDepth := 64;
  FVisited := TList<Pointer>.Create;
end;

destructor TJsonValidator.Destroy;
begin
  FVisited.Free;
  FContext.Free;
  inherited;
end;

function TJsonValidator.Validate(const Value: TValue): TJsonValidationResult;
begin
  Result := TJsonValidationResult.Create;
  FResult := Result;
  FVisited.Clear;
  try
    VisitValue(Value, '', 0);
  except
    Result.Free;
    FResult := nil;
    raise;
  end;
  FResult := nil;
end;

procedure TJsonValidator.VisitValue(const Value: TValue; const MemberPath: string; Depth: Integer);
var
  RType: TRttiType;
begin
  if Value.TypeInfo = nil then Exit;
  if Depth > FMaxDepth then
  begin
    FResult.Add(MemberPath, '', 'maxDepth', Format(ValidationStrings.DepthExceeded, [FMaxDepth]));
    Exit;
  end;

  case JsonTypeKind(Value) of
    tkClass:
      if Value.AsObject <> nil then VisitObject(Value.AsObject, MemberPath, Depth);
    tkRecord:
      begin
        RType := FContext.GetType(Value.TypeInfo);
        if RType <> nil then VisitRecord(Value, RType, MemberPath, Depth);
      end;
    tkArray, tkDynArray:
      VisitArray(Value, MemberPath, Depth);
  end;
end;

procedure TJsonValidator.VisitObject(InstanceObj: TObject; const MemberPath: string; Depth: Integer);
var
  RType: TRttiType;
begin
  // Without this guard an object cycle - exactly the one that
  // PreserveReferences resolves during serialization - loops forever.
  if FVisited.IndexOf(Pointer(InstanceObj)) >= 0 then Exit;
  FVisited.Add(Pointer(InstanceObj));
  try
    if VisitList(InstanceObj, MemberPath, Depth) then Exit;
    RType := FContext.GetType(InstanceObj.ClassType);
    if RType <> nil then VisitMembers(TValue.From<TObject>(InstanceObj), RType, MemberPath, Depth);
  finally
    FVisited.Remove(Pointer(InstanceObj));
  end;
end;

procedure TJsonValidator.VisitRecord(const Value: TValue; RType: TRttiType; const MemberPath: string; Depth: Integer);
begin
  VisitMembers(Value, RType, MemberPath, Depth);
end;

procedure TJsonValidator.VisitMembers(const Value: TValue; RType: TRttiType; const MemberPath: string; Depth: Integer);
var
  TypeInfo: TJsonTypeInfo;
  Info: TJsonMemberInfo;
  InputValue: TValue;
  SubPath: string;
begin
  // The same cache as for serialization: the validation sees exactly
  // the members that also end up in the JSON - including [JsonIgnore] and
  // all fluent renames.
  // The same naming strategy as for serialization, otherwise the path
  // in the error points to a key the partner has never seen.
  TypeInfo := TJsonRttiCache.Get.GetTypeInfo(RType.Handle, FNamingStrategy, FFluent, FMemberSelection);
  if TypeInfo = nil then Exit;

  for Info in TypeInfo.Members do
  begin
    if not Info.IsReadable then Continue;
    InputValue := TValue.Empty;
    try
      // Via Info.GetValue, not directly via RTTI: otherwise the validation
      // would see a different value than the serializer for a [JsonGetter]
      // redirection.
      if JsonTypeKind(Value) = tkClass then
        InputValue := Info.GetValue(Value.AsObject)
      else
        InputValue := Info.GetValue(Value.GetReferenceToRawData);
    except
      // A getter that raises is not a validation result. Continue.
      Continue;
    end;

    SubPath := MemberPath + '/' + PathPart(Info.JsonName);
    CheckRules(InputValue, Info, SubPath);
    VisitValue(InputValue, SubPath, Depth + 1);
  end;
end;

procedure TJsonValidator.VisitArray(const Value: TValue; const MemberPath: string; Depth: Integer);
var
  I: Integer;
begin
  for I := 0 to Value.GetArrayLength - 1 do
    VisitValue(Value.GetArrayElement(I), MemberPath + '/' + IntToStr(I), Depth + 1);
end;

function TJsonValidator.VisitList(InstanceObj: TObject; const MemberPath: string; Depth: Integer): Boolean;
var
  RType: TRttiType;
  CountProp: TRttiProperty;
  Indexed: TRttiIndexedProperty;
  I, NumItems: Integer;
begin
  // TObjectList<T>, TList<T>, TCollection: everything that has Count and an
  // indexed Items is walked as a collection.
  Result := False;
  RType := FContext.GetType(InstanceObj.ClassType);
  if RType = nil then Exit;

  CountProp := RType.GetProperty('Count');
  if (CountProp = nil) or (CountProp.PropertyType = nil) or
     not (JsonTypeKind(CountProp.PropertyType) in [tkInteger, tkInt64]) then Exit;

  Indexed := RType.GetIndexedProperty('Items');
  if Indexed = nil then Exit;

  NumItems := CountProp.GetValue(InstanceObj).AsInteger;
  for I := 0 to NumItems - 1 do
    VisitValue(Indexed.GetValue(InstanceObj, [I]), MemberPath + '/' + IntToStr(I), Depth + 1);
  Result := True;
end;

procedure TJsonValidator.CheckRules(const Value: TValue; Info: TJsonMemberInfo; const MemberPath: string);
var
  RuleAttr: TJsonSchemaAttribute;
  Number, Divisor, Quotient: Double;
  IsNumber: Boolean;
  Text: string;
  Len, NumItems, I, J: Integer;
  Elements: TArray<string>;

  procedure Report(const RuleName, MessageText: string);
  begin
    FResult.Add(MemberPath, Info.JsonName, RuleName, MessageText);
  end;

  function ListLength(out ItemCount: Integer): Boolean;
  var
    RType: TRttiType;
    CountProp: TRttiProperty;
  begin
    ItemCount := 0;
    Result := False;
    if JsonTypeKind(Value) in [tkArray, tkDynArray] then
    begin
      ItemCount := Value.GetArrayLength;
      Exit(True);
    end;
    if JsonTypeKind(Value) <> tkClass then Exit;
    // A list that was never created has zero elements - that is a statement,
    // not a missing value. Otherwise the most common case slips through.
    if Value.AsObject = nil then Exit(True);
    RType := FContext.GetType(Value.AsObject.ClassType);
    if RType = nil then Exit;
    CountProp := RType.GetProperty('Count');
    if (CountProp = nil) or (CountProp.PropertyType = nil) or
       not (JsonTypeKind(CountProp.PropertyType) in [tkInteger, tkInt64]) then Exit;
    ItemCount := CountProp.GetValue(Value.AsObject).AsInteger;
    Result := True;
  end;

  function CollectElements(out Values: TArray<string>): Boolean;
  var
    K: Integer;
  begin
    Values := nil;
    Result := False;
    if not (JsonTypeKind(Value) in [tkArray, tkDynArray]) then Exit;
    SetLength(Values, Value.GetArrayLength);
    for K := 0 to High(Values) do
      Values[K] := Value.GetArrayElement(K).ToString;
    Result := True;
  end;

begin
  if Length(Info.Validations) = 0 then Exit;
  // Do NOT check IsEmpty: an unassigned dynamic array
  // reports True there, and that is exactly when minItems must apply. Only a
  // value without any type is really nothing.
  if Value.TypeInfo = nil then Exit;

  IsNumber := JsonTypeKind(Value) in [tkInteger, tkInt64, tkFloat];
  Number := 0;
  if IsNumber then
  begin
    // Currency exactly: the detour via Extended would give the wrong
    // result when comparing at the boundary.
    if Value.TypeInfo = System.TypeInfo(Currency) then
      Number := Value.AsType<Currency>
    else if JsonTypeKind(Value) = tkFloat then
      Number := Value.AsExtended
    else
      Number := Value.AsInt64;
  end;

  Text := '';
  if JsonTypeKind(Value) in [tkString, tkLString, tkWString, tkUString, tkChar, tkWChar] then
    Text := JsonValueAsString(Value);

  for RuleAttr in Info.Validations do
  begin
    if (RuleAttr is JsonRangeAttribute) and IsNumber then
    begin
      if JsonRangeAttribute(RuleAttr).HasMin and (Number < JsonRangeAttribute(RuleAttr).Min) then
        Report('minimum', Format(ValidationStrings.Minimum,
          [NumberToText(Number), NumberToText(JsonRangeAttribute(RuleAttr).Min)]));
      if JsonRangeAttribute(RuleAttr).HasMax and (Number > JsonRangeAttribute(RuleAttr).Max) then
        Report('maximum', Format(ValidationStrings.Maximum,
          [NumberToText(Number), NumberToText(JsonRangeAttribute(RuleAttr).Max)]));
    end
    else if (RuleAttr is JsonExclusiveRangeAttribute) and IsNumber then
    begin
      if JsonExclusiveRangeAttribute(RuleAttr).HasMin and (Number <= JsonExclusiveRangeAttribute(RuleAttr).Min) then
        Report('exclusiveMinimum', Format(ValidationStrings.ExclusiveMinimum,
          [NumberToText(Number), NumberToText(JsonExclusiveRangeAttribute(RuleAttr).Min)]));
      if JsonExclusiveRangeAttribute(RuleAttr).HasMax and (Number >= JsonExclusiveRangeAttribute(RuleAttr).Max) then
        Report('exclusiveMaximum', Format(ValidationStrings.ExclusiveMaximum,
          [NumberToText(Number), NumberToText(JsonExclusiveRangeAttribute(RuleAttr).Max)]));
    end
    else if (RuleAttr is JsonMultipleOfAttribute) and IsNumber then
    begin
      Divisor := JsonMultipleOfAttribute(RuleAttr).Value;
      if Divisor <> 0 then
      begin
        Quotient := Number / Divisor;
        // Floating point: 0.3 / 0.1 is not exactly 3. Hence compare
        // with a tolerance against the nearest whole number.
        if Abs(Quotient - Round(Quotient)) > 1E-9 then
          Report('multipleOf', Format(ValidationStrings.MultipleOf,
            [NumberToText(Number), NumberToText(Divisor)]));
      end;
    end
    else if (RuleAttr is JsonPatternAttribute) and (Text <> '') then
    begin
      try
        // Note: according to the specification pattern is NOT anchored.
        // "abc" satisfies "b" - whoever means the whole value writes ^...$.
        if not PatternMatches(Text, JsonPatternAttribute(RuleAttr).Pattern) then
          Report('pattern', Format(ValidationStrings.Pattern,
            [Text, JsonPatternAttribute(RuleAttr).Pattern]));
      except
        on E: Exception do
          Report('pattern', Format(ValidationStrings.PatternInvalid,
            [JsonPatternAttribute(RuleAttr).Pattern, E.Message]));
      end;
    end
    else if (RuleAttr is JsonMinLengthAttribute) and (JsonTypeKind(Value) in [tkString, tkLString, tkWString, tkUString]) then
    begin
      Len := CountCodePoints(Text);
      if Len < JsonMinLengthAttribute(RuleAttr).Length then
        Report('minLength', Format(ValidationStrings.MinLength,
          [Len, JsonMinLengthAttribute(RuleAttr).Length]));
    end
    else if (RuleAttr is JsonMaxLengthAttribute) and (JsonTypeKind(Value) in [tkString, tkLString, tkWString, tkUString]) then
    begin
      Len := CountCodePoints(Text);
      if Len > JsonMaxLengthAttribute(RuleAttr).Length then
        Report('maxLength', Format(ValidationStrings.MaxLength,
          [Len, JsonMaxLengthAttribute(RuleAttr).Length]));
    end
    else if RuleAttr is JsonArrayLengthAttribute then
    begin
      if ListLength(NumItems) then
      begin
        if JsonArrayLengthAttribute(RuleAttr).HasMin and (NumItems < JsonArrayLengthAttribute(RuleAttr).Min) then
          Report('minItems', Format(ValidationStrings.MinItems,
            [NumItems, JsonArrayLengthAttribute(RuleAttr).Min]));
        if JsonArrayLengthAttribute(RuleAttr).HasMax and (NumItems > JsonArrayLengthAttribute(RuleAttr).Max) then
          Report('maxItems', Format(ValidationStrings.MaxItems,
            [NumItems, JsonArrayLengthAttribute(RuleAttr).Max]));
      end;
    end
    else if RuleAttr is JsonUniqueItemsAttribute then
    begin
      if CollectElements(Elements) then
        for I := 1 to High(Elements) do
          for J := 0 to I - 1 do
            if Elements[I] = Elements[J] then
            begin
              Report('uniqueItems', Format(ValidationStrings.UniqueItems, [I]));
              Break;
            end;
    end;
  end;
end;

end.
