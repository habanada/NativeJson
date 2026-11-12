{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Attributes;

interface

{$I NativeJson.inc}

{$SCOPEDENUMS ON}

uses
  {$IFDEF FPC}
  SysUtils,
  TypInfo,
  Rtti;
  {$ELSE}
  System.SysUtils,
  System.TypInfo;
  {$ENDIF}

type
  TJsonMemberSerialization = (OptOut, OptIn, Fields);
  TJsonNullValueHandling = (Include, Ignore);
  TJsonDefaultValueHandling = (Include, Ignore);
  TJsonMissingMemberHandling = (Ignore, Error);
  TJsonInclude = (Always, NonDefault, NonEmpty, NonNull);
  TJsonVisibilitySet = set of TMemberVisibility;
  TJsonMemberType = (mtFields, mtProperties);
  TJsonMemberTypes = set of TJsonMemberType;

  JsonAttribute = class(TCustomAttribute)
  public
    constructor Create;
  end;

  JsonObjectAttribute = class(JsonAttribute)
  private
    FMemberSerialization: TJsonMemberSerialization;
    FNamingStrategyType: TClass;
  public
    constructor Create(MemberSerialization: TJsonMemberSerialization = TJsonMemberSerialization.OptOut);
    property MemberSerialization: TJsonMemberSerialization read FMemberSerialization;
    property NamingStrategyType: TClass read FNamingStrategyType write FNamingStrategyType;
  end;

  JsonArrayAttribute = class(JsonAttribute)
  private
    FAllowNullItems: Boolean;
  public
    constructor Create(AllowNullItems: Boolean = True);
    property AllowNullItems: Boolean read FAllowNullItems;
  end;

  JsonVisibilityAttribute = class(JsonAttribute)
  private
    FVisibility: TJsonVisibilitySet;
  public
    constructor Create(const Visibility: TJsonVisibilitySet);
    property Visibility: TJsonVisibilitySet read FVisibility;
  end;

  JsonMemberSelectionAttribute = class(JsonAttribute)
  private
    FSelection: TJsonMemberTypes;
  public
    constructor Create(const Selection: TJsonMemberTypes);
    property Selection: TJsonMemberTypes read FSelection;
  end;

  JsonPropertyAttribute = class(JsonAttribute)
  private
    FName: string;
    FNullValueHandling: TJsonNullValueHandling;
    FDefaultValueHandling: TJsonDefaultValueHandling;
    FRequired: Boolean;
    FOrder: Integer;
  public
    constructor Create(const Name: string = '');
    property PropertyName: string read FName write FName;
    property NullValueHandling: TJsonNullValueHandling read FNullValueHandling write FNullValueHandling;
    property DefaultValueHandling: TJsonDefaultValueHandling read FDefaultValueHandling write FDefaultValueHandling;
    property Required: Boolean read FRequired write FRequired;
    property Order: Integer read FOrder write FOrder;
  end;

  /// <summary>
  ///   Reads the value of this member through a different access point:
  ///   a field, a property or a parameterless function of the same
  ///   type. The JSON name and the declared type stay unchanged.
  /// </summary>
  JsonGetterAttribute = class(JsonAttribute)
  private
    FName: string;
  public
    constructor Create(const Name: string);
    property Name: string read FName;
  end;

  /// <summary>
  ///   Writes the value of this member through a different access point.
  ///   This allows a property without a setter to be filled
  ///   when reading anyway - for example through its private field.
  /// </summary>
  JsonSetterAttribute = class(JsonAttribute)
  private
    FName: string;
  public
    constructor Create(const Name: string);
    property Name: string read FName;
  end;

  JsonIgnoreAttribute = class(JsonAttribute);
  JsonConstructorAttribute = class(JsonAttribute);

  JsonShouldSerializeAttribute = class(JsonAttribute)
  private
    FMethodName: string;
  public
    constructor Create(const MethodName: string);
    property MethodName: string read FMethodName;
  end;

  JsonIncludeAttribute = class(JsonAttribute)
  private
    FValue: TJsonInclude;
  public
    constructor Create(Value: TJsonInclude);
    property Value: TJsonInclude read FValue;
  end;

  JsonConverterAttribute = class(JsonAttribute)
  private
    FConverterType: TClass;
  public
    constructor Create(ConverterType: TClass);
    property ConverterType: TClass read FConverterType;
  end;

  JsonFormatAttribute = class(JsonAttribute)
  private
    FFormatString: string;
  public
    constructor Create(const FormatString: string);
    property FormatString: string read FFormatString;
  end;

  JsonRawAttribute = class(JsonAttribute);
  JsonUnwrappedAttribute = class(JsonAttribute);

  /// <summary>
  ///   Registers a subclass for polymorphic serialization.
  ///   As an attribute the class name MUST be given as a string:
  ///   [JsonKnownType('TCircle')]
  ///   Reason: at this point the subclasses are only forward declared,
  ///   so "class of TCircle" cannot be used as a TClass yet.
  ///   The string is resolved through RTTI on first access.
  /// </summary>
  JsonKnownTypeAttribute = class(JsonAttribute)
  private
    FSubClass: TClass;
    FTypeName: string;
  public
    constructor Create(const SubClassName: string); overload;
    constructor Create(SubClass: TClass); overload;
    /// <summary>
    ///   Resolves the class name through RTTI.
    ///   AUnitName is the unit name of the base class. It is needed
    ///   because TRttiContext.FindType only finds fully qualified names
    ///   ("Demo.Model.TOrderLine"), while the attribute only holds the short
    ///   name. Subclasses are practically always in the same unit
    ///   as the base class, so that is the safe first attempt.
    /// </summary>
    function ResolveClass(const AUnitName: string = ''): TClass;
    property SubClass: TClass read FSubClass;
    property TypeName: string read FTypeName;
  end;
  OnSerializingAttribute = class(JsonAttribute);
  OnSerializedAttribute = class(JsonAttribute);
  OnDeserializingAttribute = class(JsonAttribute);
  OnDeserializedAttribute = class(JsonAttribute);

/// <summary>
///   Keeps classes in the program that are otherwise only referenced
///   by name - for example in [JsonKnownType('TSubClass')].
///
///   Background: the Delphi linker removes classes that are not referenced
///   anywhere in the code, including their RTTI. A class name that only
///   appears as a string in an attribute does NOT count as a reference
///   for the linker. As a result TRttiContext.FindType does not find the class,
///   the schema gets an empty "oneOf" and deserialization
///   fails with "Unknown runtime type".
///
///   One call in the initialization section of the model unit is enough:
///     initialization
///       JsonKeepTypes([TOrderLine, TTextLine]);
/// </summary>
procedure JsonKeepTypes(const AClasses: array of TClass);
function JsonFindKeptClass(const ATypeName: string; const AUnitName: string = ''): TClass;

implementation

uses
  {$IFNDEF FPC}
  System.Rtti,
  {$ENDIF}
  NativeJson.Compat;

var
  // Real references to the metaclasses. The existence of this
  // field together with the assignment is proof enough for the linker that the
  // class is needed - so the class and its RTTI stay in the EXE.
  GKeptTypes: TArray<TClass>;

procedure JsonKeepTypes(const AClasses: array of TClass);
var
  I, Base: Integer;
begin
  Base := Length(GKeptTypes);
  SetLength(GKeptTypes, Base + Length(AClasses));
  for I := 0 to High(AClasses) do
    GKeptTypes[Base + I] := AClasses[I];
end;

function JsonFindKeptClass(const ATypeName: string; const AUnitName: string): TClass;
var
  RegisteredClass: TClass;
  ShortName: string;
begin
  Result := nil;
  if ATypeName = '' then Exit;
  ShortName := Copy(ATypeName, LastDelimiter('.', ATypeName) + 1, MaxInt);
  for RegisteredClass in GKeptTypes do
    if SameText(RegisteredClass.UnitName + '.' + RegisteredClass.ClassName, ATypeName) then Exit(RegisteredClass);
  if AUnitName <> '' then
    for RegisteredClass in GKeptTypes do
      if SameText(RegisteredClass.UnitName + '.' + RegisteredClass.ClassName, AUnitName + '.' + ShortName) then Exit(RegisteredClass);
  for RegisteredClass in GKeptTypes do
    if SameText(RegisteredClass.ClassName, ShortName) then Exit(RegisteredClass);
end;

constructor JsonAttribute.Create;
begin
  inherited Create;
end;

constructor JsonObjectAttribute.Create(MemberSerialization: TJsonMemberSerialization);
begin
  inherited Create;
  FMemberSerialization := MemberSerialization;
end;

constructor JsonArrayAttribute.Create(AllowNullItems: Boolean);
begin
  inherited Create;
  FAllowNullItems := AllowNullItems;
end;

constructor JsonVisibilityAttribute.Create(const Visibility: TJsonVisibilitySet);
begin
  inherited Create;
  FVisibility := Visibility;
end;

constructor JsonMemberSelectionAttribute.Create(const Selection: TJsonMemberTypes);
begin
  inherited Create;
  FSelection := Selection;
end;

constructor JsonPropertyAttribute.Create(const Name: string);
begin
  inherited Create;
  FName := Name;
  FNullValueHandling := TJsonNullValueHandling.Include;
  FDefaultValueHandling := TJsonDefaultValueHandling.Include;
end;

constructor JsonGetterAttribute.Create(const Name: string);
begin
  inherited Create;
  FName := Name;
end;

constructor JsonSetterAttribute.Create(const Name: string);
begin
  inherited Create;
  FName := Name;
end;

constructor JsonShouldSerializeAttribute.Create(const MethodName: string);
begin
  inherited Create;
  FMethodName := MethodName;
end;

constructor JsonIncludeAttribute.Create(Value: TJsonInclude);
begin
  inherited Create;
  FValue := Value;
end;

constructor JsonConverterAttribute.Create(ConverterType: TClass);
begin
  inherited Create;
  FConverterType := ConverterType;
end;

constructor JsonFormatAttribute.Create(const FormatString: string);
begin
  inherited Create;
  FFormatString := FormatString;
end;

constructor JsonKnownTypeAttribute.Create(const SubClassName: string);
begin
  inherited Create;
  FSubClass := nil;
  FTypeName := SubClassName;
end;

constructor JsonKnownTypeAttribute.Create(SubClass: TClass);
begin
  inherited Create;
  FSubClass := SubClass;
  if SubClass <> nil then FTypeName := SubClass.ClassName;
end;

function JsonKnownTypeAttribute.ResolveClass(const AUnitName: string): TClass;
var
  Ctx: TRttiContext;
  Found, Candidate: TRttiType;
  SimpleName: string;
  LastDot: Integer;
begin
  if FSubClass <> nil then Exit(FSubClass);
  if FTypeName = '' then Exit(nil);
  Ctx := TRttiContext.Create;
  try
    Found := nil;

    // 1. If the attribute already holds a qualified name, search with it directly.
    if Pos('.', FTypeName) > 0 then
      Found := JsonRttiFindType(Ctx, FTypeName);

    // 2. Short name plus the unit of the base class. This is the normal case and
    //    the only way TRttiContext.FindType answers reliably.
    if not (Found is TRttiInstanceType) and (AUnitName <> '') and (Pos('.', FTypeName) = 0) then
      Found := JsonRttiFindType(Ctx, AUnitName + '.' + FTypeName);

    // 3. Last resort: go through all known types. This also finds
    //    subclasses that live in a different unit than the base class.
    if not (Found is TRttiInstanceType) then
    begin
      Found := nil;
      SimpleName := FTypeName;
      LastDot := LastDelimiter('.', SimpleName);
      if LastDot > 0 then SimpleName := Copy(SimpleName, LastDot + 1, MaxInt);
      for Candidate in JsonRttiGetTypes(Ctx) do
        if (Candidate is TRttiInstanceType) and SameText(Candidate.Name, SimpleName) then
        begin
          Found := Candidate;
          Break;
        end;
    end;

    if Found is TRttiInstanceType then FSubClass := TRttiInstanceType(Found).MetaclassType;
    if FSubClass = nil then FSubClass := JsonFindKeptClass(FTypeName, AUnitName);
  finally
    Ctx.Free;
  end;
  Result := FSubClass;
end;

end.
