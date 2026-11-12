{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Rtti.Cache;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  TypInfo,
  Rtti,
  Generics.Collections,
  Generics.Defaults,
  SyncObjs,
  {$ELSE}
  System.SysUtils,
  System.TypInfo,
  System.Rtti,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.SyncObjs,
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.Attributes,
  NativeJson.Schema.Attributes,
  NativeJson.NamingStrategy,
  NativeJson.Fluent;

type
  EJsonRttiError = class(Exception);

  CacheStrings = class sealed
  public const
    AccessorNotFound = '%s: member "%s" was not found on %s';
    AccessorNotReadable = '%s: member "%s" on %s cannot be read';
    AccessorNotWritable = '%s: member "%s" on %s cannot be written';
    AccessorTypeMismatch = '%s: member "%s" on %s is of type %s, expected %s';
    AccessorMethodSignature = '%s: method "%s" on %s has the wrong signature';
    AccessorMethodOnRecord = '%s: method "%s" cannot be used on the record %s';
  end;

  TJsonMemberInfo = class
  private
    FRttiMember: TRttiMember;
    FJsonName: string;
    FOrder: Integer;
    FRequired: Boolean;
    FNullHandling: TJsonNullValueHandling;
    FDefaultHandling: TJsonDefaultValueHandling;
    FIsReadable: Boolean;
    FIsWritable: Boolean;
    FShouldSerializeMethod: TRttiMethod;
    FInclude: TJsonInclude;
    FConverterClass: TClass;
    FFormatString: string;
    FIsRaw: Boolean;
    FIsUnwrapped: Boolean;
    FShouldSerializeDelegate: TSerializationPredicate;
    FValueTransformer: TValueTransformer;
    FHasDefaultValue: Boolean;
    FDefaultValue: TValue;
    FPosition: Integer;
    FValidations: TArray<TJsonSchemaAttribute>;
    FGetter: TRttiMember;
    FGetterMethod: TRttiMethod;
    FSetter: TRttiMember;
    FSetterMethod: TRttiMethod;
    FOwnerIsClass: Boolean;
    function GetValueType: TRttiType;
  public
    constructor Create(AMember: TRttiMember; const AName: string);
    function GetValue(Instance: Pointer): TValue;
    procedure SetValue(Instance: Pointer; const AValue: TValue);
    property Member: TRttiMember read FRttiMember;
    property ValueType: TRttiType read GetValueType;
    property JsonName: string read FJsonName;
    property Order: Integer read FOrder write FOrder;
    property Required: Boolean read FRequired write FRequired;
    property NullHandling: TJsonNullValueHandling read FNullHandling write FNullHandling;
    property DefaultHandling: TJsonDefaultValueHandling read FDefaultHandling write FDefaultHandling;
    property IsReadable: Boolean read FIsReadable;
    property IsWritable: Boolean read FIsWritable;
    property ShouldSerializeMethod: TRttiMethod read FShouldSerializeMethod write FShouldSerializeMethod;
    property Include: TJsonInclude read FInclude write FInclude;
    property ConverterClass: TClass read FConverterClass write FConverterClass;
    property FormatString: string read FFormatString write FFormatString;
    property IsRaw: Boolean read FIsRaw write FIsRaw;
    property IsUnwrapped: Boolean read FIsUnwrapped write FIsUnwrapped;
    property ShouldSerializeDelegate: TSerializationPredicate read FShouldSerializeDelegate write FShouldSerializeDelegate;
    property ValueTransformer: TValueTransformer read FValueTransformer write FValueTransformer;
    property HasDefaultValue: Boolean read FHasDefaultValue write FHasDefaultValue;
    property DefaultValue: TValue read FDefaultValue write FDefaultValue;
    /// <summary>
    ///   Discovery index from the RTTI analysis. Serves as the second
    ///   sort key: TList.Sort is a quicksort and therefore not
    ///   stable - without this key the order of members with equal rank
    ///   would be random and could change between two runs.
    /// </summary>
    property Position: Integer read FPosition write FPosition;
    property Validations: TArray<TJsonSchemaAttribute> read FValidations write FValidations;
    property Getter: TRttiMember read FGetter write FGetter;
    property GetterMethod: TRttiMethod read FGetterMethod write FGetterMethod;
    property Setter: TRttiMember read FSetter write FSetter;
    property SetterMethod: TRttiMethod read FSetterMethod write FSetterMethod;
    property OwnerIsClass: Boolean read FOwnerIsClass write FOwnerIsClass;
  end;

  TJsonTypeInfo = class
  private
    FRttiType: TRttiType;
    FMembers: TObjectList<TJsonMemberInfo>;
    FMemberMap: TDictionary<string, TJsonMemberInfo>;
    FJsonConstructor: TRttiMethod;
    FOnSerializing: TRttiMethod;
    FOnSerialized: TRttiMethod;
    FOnDeserializing: TRttiMethod;
    FOnDeserialized: TRttiMethod;
    FFluentOnSerializing: TSerializationCallback;
    FFluentOnSerialized: TSerializationCallback;
    FFluentOnDeserializing: TDeserializationCallback;
    FFluentOnDeserialized: TDeserializationCallback;
    FFactory: TObjectFactoryFunc;
  public
    constructor Create(AType: TRttiType);
    destructor Destroy; override;
    function TryGetMember(const Name: string; out Member: TJsonMemberInfo): Boolean;
    property RttiType: TRttiType read FRttiType;
    property Members: TObjectList<TJsonMemberInfo> read FMembers;
    property JsonConstructor: TRttiMethod read FJsonConstructor;
    property OnSerializing: TRttiMethod read FOnSerializing;
    property OnSerialized: TRttiMethod read FOnSerialized;
    property OnDeserializing: TRttiMethod read FOnDeserializing;
    property OnDeserialized: TRttiMethod read FOnDeserialized;
    property FluentOnSerializing: TSerializationCallback read FFluentOnSerializing write FFluentOnSerializing;
    property FluentOnSerialized: TSerializationCallback read FFluentOnSerialized write FFluentOnSerialized;
    property FluentOnDeserializing: TDeserializationCallback read FFluentOnDeserializing write FFluentOnDeserializing;
    property FluentOnDeserialized: TDeserializationCallback read FFluentOnDeserialized write FFluentOnDeserialized;
    property Factory: TObjectFactoryFunc read FFactory write FFactory;
  end;

  TCacheKey = record
    TypeInfo: PTypeInfo;
    Strategy: TJsonNamingStrategyClass;
    FluentContext: TJsonFluentContext;
    FluentRevision: UInt64;
    MemberSelection: TJsonMemberTypes;
  end;

  TJsonRttiCache = class
  private
    class var FInstance: TJsonRttiCache;
    class var FClassLock: TCriticalSection;
    FContext: TRttiContext;
    FCache: TObjectDictionary<TCacheKey, TJsonTypeInfo>;
    FLock: TLightweightMREW;
    function AnalyzeType(TypeInfo: PTypeInfo; Strategy: TJsonNamingStrategyClass; Fluent: TJsonFluentContext; MemberSelection: TJsonMemberTypes): TJsonTypeInfo;
    function GetCount: Integer;
    procedure RemoveContext(Fluent: TJsonFluentContext);
  public
    class constructor Create;
    class destructor Destroy;
    class function Get: TJsonRttiCache;

    /// <summary>
    ///   Discards all analysis results that belong to this fluent context.
    ///   Called by TJsonFluentContext.Destroy.
    ///
    ///   Without this the cache grows without bound: its key contains
    ///   the context plus revision number, and every new configuration
    ///   creates a new key. A program that creates many short-lived
    ///   TJsonSettings would use more and more memory without
    ///   a forgotten Free to be found anywhere.
    ///
    ///   Deliberately does NOT create a cache if none exists yet - during
    ///   shutdown this method can be called after the class
    ///   destructor.
    /// </summary>
    class procedure ForgetContext(Fluent: TJsonFluentContext); static;

    constructor Create;
    destructor Destroy; override;
    function GetTypeInfo(TypeInfo: PTypeInfo; Strategy: TJsonNamingStrategyClass = nil; Fluent: TJsonFluentContext = nil; MemberSelection: TJsonMemberTypes = []): TJsonTypeInfo;

    /// <summary>Number of stored analysis results - for diagnostics.</summary>
    property Count: Integer read GetCount;
  end;

implementation

constructor TJsonMemberInfo.Create(AMember: TRttiMember; const AName: string);
begin
  inherited Create;
  FRttiMember := AMember;
  FJsonName := AName;
  FOrder := 0;
  FRequired := False;
  FNullHandling := TJsonNullValueHandling.Include;
  FDefaultHandling := TJsonDefaultValueHandling.Include;
  FInclude := TJsonInclude.Always;
  FConverterClass := nil;
  FFormatString := '';
  FIsRaw := False;
  FIsUnwrapped := False;
  FShouldSerializeMethod := nil;
  FHasDefaultValue := False;
  if AMember is TRttiProperty then
  begin
    FIsReadable := TRttiProperty(AMember).IsReadable;
    FIsWritable := TRttiProperty(AMember).IsWritable;
  end
  else if AMember is TRttiField then
  begin
    FIsReadable := True;
    FIsWritable := True;
  end;
end;

function TJsonMemberInfo.GetValueType: TRttiType;
begin
  if FRttiMember is TRttiProperty then Exit(TRttiProperty(FRttiMember).PropertyType);
  if FRttiMember is TRttiField then Exit(TRttiField(FRttiMember).FieldType);
  Result := nil;
end;

function TJsonMemberInfo.GetValue(Instance: Pointer): TValue;
begin
  if not FIsReadable then Exit(TValue.Empty);
  // Redirection takes precedence: the JSON name and the type stay those of the
  // declared member, only the access point is different.
  if FGetterMethod <> nil then Exit(FGetterMethod.Invoke(TObject(Instance), []));
  if FGetter is TRttiProperty then Exit(JsonPropertyGetValue(TRttiProperty(FGetter), Instance));
  if FGetter is TRttiField then Exit(TRttiField(FGetter).GetValue(Instance));
  if FRttiMember is TRttiProperty then Exit(JsonPropertyGetValue(TRttiProperty(FRttiMember), Instance));
  if FRttiMember is TRttiField then Exit(TRttiField(FRttiMember).GetValue(Instance));
  Result := TValue.Empty;
end;

procedure TJsonMemberInfo.SetValue(Instance: Pointer; const AValue: TValue);
begin
  if not FIsWritable then Exit;
  if FSetterMethod <> nil then
  begin
    FSetterMethod.Invoke(TObject(Instance), [AValue]);
    Exit;
  end;
  if FSetter is TRttiProperty then
  begin
    JsonPropertySetValue(TRttiProperty(FSetter), Instance, AValue);
    Exit;
  end;
  if FSetter is TRttiField then
  begin
    TRttiField(FSetter).SetValue(Instance, AValue);
    Exit;
  end;
  if FRttiMember is TRttiProperty then JsonPropertySetValue(TRttiProperty(FRttiMember), Instance, AValue)
  else if FRttiMember is TRttiField then TRttiField(FRttiMember).SetValue(Instance, AValue);
end;

constructor TJsonTypeInfo.Create(AType: TRttiType);
begin
  inherited Create;
  FRttiType := AType;
  FMembers := TObjectList<TJsonMemberInfo>.Create(True);
  FMemberMap := TDictionary<string, TJsonMemberInfo>.Create(TJsonIStringComparer.Ordinal);
end;

destructor TJsonTypeInfo.Destroy;
begin
  FMemberMap.Free;
  FMembers.Free;
  inherited;
end;

function TJsonTypeInfo.TryGetMember(const Name: string; out Member: TJsonMemberInfo): Boolean;
begin
  Result := FMemberMap.TryGetValue(Name, Member);
end;

class constructor TJsonRttiCache.Create;
begin
  FClassLock := TCriticalSection.Create;
end;

class destructor TJsonRttiCache.Destroy;
begin
  FInstance.Free;
  FClassLock.Free;
end;

function TJsonRttiCache.GetCount: Integer;
begin
  FLock.BeginRead;
  try
    Result := FCache.Count;
  finally
    FLock.EndRead;
  end;
end;

procedure TJsonRttiCache.RemoveContext(Fluent: TJsonFluentContext);
var
  ToDelete: TArray<TCacheKey>;
  SubTypePair: TPair<TCacheKey, TJsonTypeInfo>;
  NumItems, I: Integer;
begin
  if Fluent = nil then Exit;
  FLock.BeginWrite;
  try
    // Collect first, then delete: a dictionary must not be changed
    // during enumeration.
    SetLength(ToDelete, FCache.Count);
    NumItems := 0;
    for SubTypePair in FCache do
      if SubTypePair.Key.FluentContext = Fluent then
      begin
        ToDelete[NumItems] := SubTypePair.Key;
        Inc(NumItems);
      end;
    // doOwnsValues: Remove also frees the TJsonTypeInfo
    for I := 0 to NumItems - 1 do
      FCache.Remove(ToDelete[I]);
  finally
    FLock.EndWrite;
  end;
end;

class procedure TJsonRttiCache.ForgetContext(Fluent: TJsonFluentContext);
begin
  // No Get: it would be wrong to create a cache during shutdown
  // only to clear it right away.
  if FInstance = nil then Exit;
  FInstance.RemoveContext(Fluent);
end;

class function TJsonRttiCache.Get: TJsonRttiCache;
begin
  if FInstance = nil then
  begin
    FClassLock.Acquire;
    try
      if FInstance = nil then FInstance := TJsonRttiCache.Create;
    finally
      FClassLock.Release;
    end;
  end;
  Result := FInstance;
end;

constructor TJsonRttiCache.Create;
begin
  inherited Create;
  FContext := TRttiContext.Create;
  FCache := TObjectDictionary<TCacheKey, TJsonTypeInfo>.Create([doOwnsValues]);
end;

destructor TJsonRttiCache.Destroy;
begin
  FCache.Free;
  FContext.Free;
  inherited;
end;

function TJsonRttiCache.GetTypeInfo(TypeInfo: PTypeInfo; Strategy: TJsonNamingStrategyClass; Fluent: TJsonFluentContext; MemberSelection: TJsonMemberTypes): TJsonTypeInfo;
var
  Key: TCacheKey;
begin
  if TypeInfo = nil then raise EArgumentNilException.Create('TypeInfo');
  if Strategy = nil then Strategy := TDefaultNamingStrategy;
  Key := Default(TCacheKey);
  Key.TypeInfo := TypeInfo;
  Key.Strategy := Strategy;
  Key.FluentContext := Fluent;
  if Fluent <> nil then Key.FluentRevision := Fluent.Revision else Key.FluentRevision := 0;
  Key.MemberSelection := MemberSelection;
  FLock.BeginRead;
  try
    if FCache.TryGetValue(Key, Result) then Exit;
  finally
    FLock.EndRead;
  end;
  FLock.BeginWrite;
  try
    if not FCache.TryGetValue(Key, Result) then
    begin
      Result := AnalyzeType(TypeInfo, Strategy, Fluent, MemberSelection);
      FCache.Add(Key, Result);
    end;
  finally
    FLock.EndWrite;
  end;
end;

function TJsonRttiCache.AnalyzeType(TypeInfo: PTypeInfo; Strategy: TJsonNamingStrategyClass; Fluent: TJsonFluentContext; MemberSelection: TJsonMemberTypes): TJsonTypeInfo;
var
  RType: TRttiType;
  Attr, MethodAttr: TCustomAttribute;
  ClassAttr: JsonObjectAttribute;
  VisAttr: JsonVisibilityAttribute;
  SelAttr: JsonMemberSelectionAttribute;
  FluentTypeConfig: TJsonTypeConfig;
  EffectiveStrategy: TJsonNamingStrategyClass;
  MemberSerialization: TJsonMemberSerialization;
  AllowedVisibility: TJsonVisibilitySet;
  AllowedMemberTypes: TJsonMemberTypes;
  Method: TRttiMethod;
  Field: TRttiField;
  Prop: TRttiProperty;

  function HasProperty(const Name: string): Boolean;
  var
    P: TRttiProperty;
  begin
    Result := False;
    for P in RType.GetProperties do
      if SameText(P.Name, Name) then Exit(True);
  end;

  function ResolveFluentMember(M: TRttiMember): TJsonMemberConfig;
  begin
    Result := nil;
    if FluentTypeConfig = nil then Exit;
    Result := FluentTypeConfig.FindMember(M.Name);
    if (Result = nil) and (M is TRttiProperty) then Result := FluentTypeConfig.FindMember('F' + M.Name);
  end;

  // Resolves the name from [JsonGetter] / [JsonSetter] on the owning type.
  // The result goes into MemberInfo; every violation is reported immediately,
  // so a typo does not slip through as "field missing in JSON".
  function DescribeType(T: TRttiType): string;
  begin
    // The message itself must not crash when exactly the missing
    // type information is the reason for the message.
    if T = nil then Result := '<unknown>' else Result := T.Name;
  end;

  procedure ResolveAccess(MemberInfo: TJsonMemberInfo; const AttributeName, TargetName: string;
    ForWriting: Boolean);
  var
    F: TRttiField;
    Prop: TRttiProperty;
    Meth, Candidate: TRttiMethod;
    Params: TArray<TRttiParameter>;
    Expected: TRttiType;
  begin
    Expected := MemberInfo.ValueType;

    F := RType.GetField(TargetName);
    if F <> nil then
    begin
      // Missing type info must not pass as a match.
      if (Expected = nil) or (F.FieldType = nil) or (F.FieldType.Handle <> Expected.Handle) then
        raise EJsonRttiError.CreateFmt(CacheStrings.AccessorTypeMismatch,
          [AttributeName, TargetName, RType.Name, DescribeType(F.FieldType), DescribeType(Expected)]);
      if ForWriting then MemberInfo.Setter := F else MemberInfo.Getter := F;
      Exit;
    end;

    Prop := RType.GetProperty(TargetName);
    if Prop <> nil then
    begin
      if (Expected = nil) or (Prop.PropertyType = nil) or (Prop.PropertyType.Handle <> Expected.Handle) then
        raise EJsonRttiError.CreateFmt(CacheStrings.AccessorTypeMismatch,
          [AttributeName, TargetName, RType.Name, DescribeType(Prop.PropertyType), DescribeType(Expected)]);
      if ForWriting and not Prop.IsWritable then
        raise EJsonRttiError.CreateFmt(CacheStrings.AccessorNotWritable, [AttributeName, TargetName, RType.Name]);
      if not ForWriting and not Prop.IsReadable then
        raise EJsonRttiError.CreateFmt(CacheStrings.AccessorNotReadable, [AttributeName, TargetName, RType.Name]);
      if ForWriting then MemberInfo.Setter := Prop else MemberInfo.Getter := Prop;
      Exit;
    end;

    // For overloads GetMethod returns the first match. What is needed
    // is the one with the matching signature.
    Meth := nil;
    for Candidate in RType.GetMethods do
    begin
      if not SameText(Candidate.Name, TargetName) then Continue;
      if Meth = nil then Meth := Candidate;
      Params := Candidate.GetParameters;
      if ForWriting then
      begin
        if (Length(Params) = 1) and (Params[0].ParamType <> nil) and
           (Expected <> nil) and (Params[0].ParamType.Handle = Expected.Handle) then
        begin
          Meth := Candidate;
          Break;
        end;
      end
      else
      begin
        if (Length(Params) = 0) and (Candidate.ReturnType <> nil) and
           (Expected <> nil) and (Candidate.ReturnType.Handle = Expected.Handle) then
        begin
          Meth := Candidate;
          Break;
        end;
      end;
    end;
    if Meth = nil then
      raise EJsonRttiError.CreateFmt(CacheStrings.AccessorNotFound, [AttributeName, TargetName, RType.Name]);

    // Calling a method through RTTI needs an object instance.
    // Records do not have one - only fields and properties are allowed there.
    if not (RType is TRttiInstanceType) then
      raise EJsonRttiError.CreateFmt(CacheStrings.AccessorMethodOnRecord, [AttributeName, TargetName, RType.Name]);

    Params := Meth.GetParameters;
    if ForWriting then
    begin
      if (Length(Params) <> 1) or (Params[0].Flags * [pfVar, pfOut] <> []) then
        raise EJsonRttiError.CreateFmt(CacheStrings.AccessorMethodSignature, [AttributeName, TargetName, RType.Name]);
      if (Expected = nil) or (Params[0].ParamType = nil) or (Params[0].ParamType.Handle <> Expected.Handle) then
        raise EJsonRttiError.CreateFmt(CacheStrings.AccessorTypeMismatch,
          [AttributeName, TargetName, RType.Name, DescribeType(Params[0].ParamType), DescribeType(Expected)]);
      MemberInfo.SetterMethod := Meth;
    end
    else
    begin
      if (Length(Params) <> 0) or (Meth.ReturnType = nil) then
        raise EJsonRttiError.CreateFmt(CacheStrings.AccessorMethodSignature, [AttributeName, TargetName, RType.Name]);
      if (Expected = nil) or (Meth.ReturnType.Handle <> Expected.Handle) then
        raise EJsonRttiError.CreateFmt(CacheStrings.AccessorTypeMismatch,
          [AttributeName, TargetName, RType.Name, DescribeType(Meth.ReturnType), DescribeType(Expected)]);
      MemberInfo.GetterMethod := Meth;
    end;
  end;

  function IsValidationRule(A: TCustomAttribute): Boolean;
  begin
    // Only the attributes that can really be checked at runtime.
    // JsonTitle, JsonDescription and the like only describe.
    Result := (A is JsonRangeAttribute) or (A is JsonExclusiveRangeAttribute) or
              (A is JsonMultipleOfAttribute) or (A is JsonPatternAttribute) or
              (A is JsonMinLengthAttribute) or (A is JsonMaxLengthAttribute) or
              (A is JsonArrayLengthAttribute) or (A is JsonUniqueItemsAttribute);
  end;

  procedure ProcessMember(M: TRttiMember; IsField: Boolean);
  var
    PropAttr: JsonPropertyAttribute;
    IgnoreAttr: JsonIgnoreAttribute;
    IncludeAttr: JsonIncludeAttribute;
    ConvAttr: JsonConverterAttribute;
    FormatAttr: JsonFormatAttribute;
    RawAttr: JsonRawAttribute;
    UnwrapAttr: JsonUnwrappedAttribute;
    ShouldAttr: JsonShouldSerializeAttribute;
    RequiredAttr: JsonRequiredAttribute;
    GetterAttr: JsonGetterAttribute;
    SetterAttr: JsonSetterAttribute;
    Rules: TArray<TJsonSchemaAttribute>;
    A: TCustomAttribute;
    FluentMember: TJsonMemberConfig;
    JsonName: string;
    MemberInfo: TJsonMemberInfo;
    ShouldMethod: TRttiMethod;
  begin
    // TInterfacedObject brings RefCount as a public property. That
    // is reference counting bookkeeping and does not belong in the JSON -
    // it only became visible once interfaces were serialized
    // through their object.
    if (M.Parent is TRttiInstanceType) and
       (TRttiInstanceType(M.Parent).MetaclassType = TInterfacedObject) then Exit;

    FluentMember := ResolveFluentMember(M);
    if IsField and (TJsonMemberType.mtProperties in AllowedMemberTypes) and (Length(M.Name) > 1) and (M.Name[1] = 'F') and HasProperty(Copy(M.Name, 2, MaxInt)) then Exit;
    PropAttr := nil;
    IgnoreAttr := nil;
    IncludeAttr := nil;
    ConvAttr := nil;
    FormatAttr := nil;
    RawAttr := nil;
    UnwrapAttr := nil;
    ShouldAttr := nil;
    RequiredAttr := nil;
    GetterAttr := nil;
    SetterAttr := nil;
    Rules := nil;
    if (FluentTypeConfig = nil) or not FluentTypeConfig.InternalIgnoreAttributes then
      for A in M.GetAttributes do
      begin
        if A is JsonPropertyAttribute then PropAttr := JsonPropertyAttribute(A)
        else if A is JsonIgnoreAttribute then IgnoreAttr := JsonIgnoreAttribute(A)
        else if A is JsonIncludeAttribute then IncludeAttr := JsonIncludeAttribute(A)
        else if A is JsonConverterAttribute then ConvAttr := JsonConverterAttribute(A)
        else if A is JsonFormatAttribute then FormatAttr := JsonFormatAttribute(A)
        else if A is JsonRawAttribute then RawAttr := JsonRawAttribute(A)
        else if A is JsonUnwrappedAttribute then UnwrapAttr := JsonUnwrappedAttribute(A)
        else if A is JsonShouldSerializeAttribute then ShouldAttr := JsonShouldSerializeAttribute(A)
        else if A is JsonGetterAttribute then GetterAttr := JsonGetterAttribute(A)
        else if A is JsonSetterAttribute then SetterAttr := JsonSetterAttribute(A)
        else if A is JsonRequiredAttribute then RequiredAttr := JsonRequiredAttribute(A)
        else if IsValidationRule(A) then
        begin
          SetLength(Rules, Length(Rules) + 1);
          Rules[High(Rules)] := TJsonSchemaAttribute(A);
        end;
      end;
    if FluentMember <> nil then
    begin
      if FluentMember.InternalIgnored then Exit;
    end
    else if IgnoreAttr <> nil then Exit;
    if (PropAttr = nil) and (FluentMember = nil) then
    begin
      if not (M.Visibility in AllowedVisibility) then Exit;
      if IsField and not (TJsonMemberType.mtFields in AllowedMemberTypes) then Exit;
      if not IsField and not (TJsonMemberType.mtProperties in AllowedMemberTypes) then Exit;
      if MemberSerialization = TJsonMemberSerialization.OptIn then Exit;
      if (MemberSerialization = TJsonMemberSerialization.Fields) and not IsField then Exit;
    end;
    if (FluentMember <> nil) and (FluentMember.InternalJsonName <> '') then JsonName := FluentMember.InternalJsonName
    else if (PropAttr <> nil) and (PropAttr.PropertyName <> '') then JsonName := PropAttr.PropertyName
    else JsonName := EffectiveStrategy.ResolvePropertyName(M.Name);
    MemberInfo := TJsonMemberInfo.Create(M, JsonName);
    if PropAttr <> nil then
    begin
      MemberInfo.Order := PropAttr.Order;
      MemberInfo.Required := PropAttr.Required;
      MemberInfo.NullHandling := PropAttr.NullValueHandling;
      MemberInfo.DefaultHandling := PropAttr.DefaultValueHandling;
    end;
    if RequiredAttr <> nil then MemberInfo.Required := True;
    if IncludeAttr <> nil then MemberInfo.Include := IncludeAttr.Value;
    if ConvAttr <> nil then MemberInfo.ConverterClass := ConvAttr.ConverterType;
    if FormatAttr <> nil then MemberInfo.FormatString := FormatAttr.FormatString;
    MemberInfo.IsRaw := RawAttr <> nil;
    MemberInfo.IsUnwrapped := UnwrapAttr <> nil;
    ShouldMethod := nil;
    if ShouldAttr <> nil then ShouldMethod := RType.GetMethod(ShouldAttr.MethodName)
    else ShouldMethod := RType.GetMethod('ShouldSerialize' + M.Name);
    if (ShouldMethod <> nil) and (ShouldMethod.ReturnType <> nil) and (JsonTypeKind(ShouldMethod.ReturnType) = tkEnumeration) and (ShouldMethod.ReturnType.Handle = System.TypeInfo(Boolean)) and (Length(ShouldMethod.GetParameters) = 0) then MemberInfo.ShouldSerializeMethod := ShouldMethod;
    if FluentMember <> nil then
    begin
      if FluentMember.InternalHasOrder then MemberInfo.Order := FluentMember.InternalOrder;
      if FluentMember.InternalHasRequired then MemberInfo.Required := FluentMember.InternalIsRequired;
      if FluentMember.InternalConverter <> nil then MemberInfo.ConverterClass := FluentMember.InternalConverter;
      if FluentMember.InternalHasNullHandling then MemberInfo.NullHandling := FluentMember.InternalNullHandling;
      if FluentMember.InternalHasDefaultHandling then MemberInfo.DefaultHandling := FluentMember.InternalDefaultHandling;
      if Assigned(FluentMember.InternalShouldSerialize) then MemberInfo.ShouldSerializeDelegate := FluentMember.InternalShouldSerialize;
      if Assigned(FluentMember.InternalTransformer) then MemberInfo.ValueTransformer := FluentMember.InternalTransformer;
      if FluentMember.InternalHasDefaultValue then
      begin
        MemberInfo.HasDefaultValue := True;
        MemberInfo.DefaultValue := FluentMember.InternalDefaultValue;
      end;
    end;
    MemberInfo.OwnerIsClass := RType is TRttiInstanceType;
    // Until it is handed to the owning list MemberInfo belongs here -
    // and ResolveAccess raises on every wrong target name.
    try
      if GetterAttr <> nil then
      begin
        ResolveAccess(MemberInfo, 'JsonGetter', GetterAttr.Name, False);
        MemberInfo.FIsReadable := True;
      end;
      if SetterAttr <> nil then
      begin
        ResolveAccess(MemberInfo, 'JsonSetter', SetterAttr.Name, True);
        MemberInfo.FIsWritable := True;
      end;
      MemberInfo.Validations := Rules;
      MemberInfo.Position := Result.Members.Count;
      Result.Members.Add(MemberInfo);
    except
      MemberInfo.Free;
      raise;
    end;
    Result.FMemberMap.AddOrSetValue(JsonName, MemberInfo);
  end;

begin
  RType := FContext.GetType(TypeInfo);
  if RType = nil then raise Exception.CreateFmt('RTTI type not found for %s', [TypeInfo.Name]);
  Result := TJsonTypeInfo.Create(RType);
  try
  FluentTypeConfig := nil;
  if Fluent <> nil then FluentTypeConfig := Fluent.GetConfig(TypeInfo);
  MemberSerialization := TJsonMemberSerialization.OptOut;
  EffectiveStrategy := Strategy;
  AllowedVisibility := [mvPublic, mvPublished];
  if RType.TypeKind = tkRecord then AllowedMemberTypes := [TJsonMemberType.mtFields] else AllowedMemberTypes := [TJsonMemberType.mtProperties];
  if MemberSelection <> [] then AllowedMemberTypes := MemberSelection;
  if FluentTypeConfig <> nil then
  begin
    MemberSerialization := FluentTypeConfig.InternalMemberSerialization;
    if FluentTypeConfig.InternalMemberSelection <> [] then AllowedMemberTypes := FluentTypeConfig.InternalMemberSelection;
    if FluentTypeConfig.InternalNamingStrategy <> nil then EffectiveStrategy := TJsonNamingStrategyClass(FluentTypeConfig.InternalNamingStrategy);
    Result.FluentOnSerializing := FluentTypeConfig.InternalOnSerializing;
    Result.FluentOnSerialized := FluentTypeConfig.InternalOnSerialized;
    Result.FluentOnDeserializing := FluentTypeConfig.InternalOnDeserializing;
    Result.FluentOnDeserialized := FluentTypeConfig.InternalOnDeserialized;
    Result.Factory := FluentTypeConfig.InternalFactory;
  end;
  if (FluentTypeConfig = nil) or not FluentTypeConfig.InternalIgnoreAttributes then
    for Attr in RType.GetAttributes do
      if Attr is JsonObjectAttribute then
      begin
        ClassAttr := JsonObjectAttribute(Attr);
        if FluentTypeConfig = nil then MemberSerialization := ClassAttr.MemberSerialization;
        if (FluentTypeConfig = nil) and (ClassAttr.NamingStrategyType <> nil) then EffectiveStrategy := TJsonNamingStrategyClass(ClassAttr.NamingStrategyType);
      end
      else if Attr is JsonVisibilityAttribute then
      begin
        VisAttr := JsonVisibilityAttribute(Attr);
        AllowedVisibility := VisAttr.Visibility;
      end
      else if Attr is JsonMemberSelectionAttribute then
      begin
        SelAttr := JsonMemberSelectionAttribute(Attr);
        if (FluentTypeConfig = nil) or (FluentTypeConfig.InternalMemberSelection = []) then AllowedMemberTypes := SelAttr.Selection;
      end;
  if MemberSerialization = TJsonMemberSerialization.Fields then AllowedMemberTypes := [TJsonMemberType.mtFields];
  if EffectiveStrategy = nil then EffectiveStrategy := TDefaultNamingStrategy;
  for Method in RType.GetMethods do
  begin
    if Method.IsConstructor and (Result.FJsonConstructor = nil) then
      for MethodAttr in Method.GetAttributes do
        if MethodAttr is JsonConstructorAttribute then
        begin
          Result.FJsonConstructor := Method;
          Break;
        end;
    if Length(Method.GetParameters) = 0 then
      for MethodAttr in Method.GetAttributes do
      begin
        if MethodAttr is OnSerializingAttribute then Result.FOnSerializing := Method
        else if MethodAttr is OnSerializedAttribute then Result.FOnSerialized := Method
        else if MethodAttr is OnDeserializingAttribute then Result.FOnDeserializing := Method
        else if MethodAttr is OnDeserializedAttribute then Result.FOnDeserialized := Method;
      end;
  end;
  for Field in RType.GetFields do ProcessMember(Field, True);
  for Prop in RType.GetProperties do ProcessMember(Prop, False);
  // Sort stably: for equal Order the discovery index decides.
  // TList.Sort is a quicksort and therefore not stable by itself.
  Result.Members.Sort(TComparer<TJsonMemberInfo>.Construct(
    function(const L, R: TJsonMemberInfo): Integer
    begin
      Result := L.Order - R.Order;
      if Result = 0 then Result := L.Position - R.Position;
    end));
  except
    // The cache only takes over the result after a successful analysis.
    // If it aborts - e.g. on a wrong [JsonSetter] target - the
    // half-finished object has to be freed here.
    Result.Free;
    raise;
  end;
end;

end.
