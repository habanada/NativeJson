{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Deserializer.Core;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  Rtti,
  TypInfo,
  Generics.Collections,
  DateUtils,
  Math,
  Variants,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  System.DateUtils,
  System.Math,
  System.Variants,
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.Core.Reader,
  NativeJson.Core.Tokens,
  NativeJson.Serializer.Converter,
  NativeJson.Rtti.Cache,
  NativeJson.Attributes,
  NativeJson.Dom.Value,
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.Primitive,
  NativeJson.Deserializer.Activator,
  NativeJson.Deserializer.Generics,
  NativeJson.NamingStrategy,
  NativeJson.Settings,
  NativeJson.Fluent;

type
  EJsonDeserializationError = class(Exception)
  public
    class function CreateWithPos(const Msg: string; Reader: TObject): EJsonDeserializationError; static;
  end;

  DeserializationStrings = class sealed
  public const
    RangeOut = 'The value %s is outside the range of type %s';
    NotAWholeNumber = 'The value %s is not a whole number and cannot be stored in %s';
    NumberExpected = 'A JSON number was expected, found %s';
    BooleanExpected = 'A JSON boolean was expected, found %s';
    EnumOutOfRange = 'The ordinal %d is outside the range of enum %s';
    DictionaryKey = 'Dictionary key type %s is not supported';
    InterfaceNoGuid = 'The interface %s has no GUID and cannot be created from JSON';
    InterfaceNoFactory = 'No instance and no factory for the interface %s. Register one with Settings.RegisterFactory<%s>';
    InterfaceNotSupported = 'The object created for %s does not implement that interface';
  end;

  TJsonDeserializer = class
  private
    FConverters: TObjectList<TJsonConverter>;
    FRttiCache: TJsonRttiCache;
    FDateFormat: string;
    FReferenceMap: TDictionary<string, TObject>;
    FMissingMemberHandling: TJsonMissingMemberHandling;
    FStrictTypes: Boolean;
    FJson5: Boolean;
    FNamingStrategy: TJsonNamingStrategyClass;
    FFluentContext: TJsonFluentContext;
    FMemberSelection: TJsonMemberTypes;
    FCollectionAdapters: TDictionary<PTypeInfo, TCollectionAddProc>;
    FFactories: TDictionary<PTypeInfo, TObjectFactoryProc>;
    FKeyDeserializers: TDictionary<PTypeInfo, TKeyDeserializerProc>;
    function FindConverter(TypeInfo: PTypeInfo): TJsonConverter;
    function FindLocalConverter(MemberInfo: TJsonMemberInfo): TJsonConverter;
    function ReadValue(Json: TJsonValue; TypeInfo: PTypeInfo; const ExistingValue: TValue; MemberInfo: TJsonMemberInfo = nil): TValue;
    function ReadObject(Json: TJsonObject; TypeInfo: PTypeInfo; const ExistingValue: TValue): TValue;
    function ReadRecord(Json: TJsonObject; TypeInfo: PTypeInfo): TValue;
    function ReadArray(Json: TJsonArray; TypeInfo: PTypeInfo): TValue;
    function ReadDynArray(Json: TJsonArray; TypeInfo: PTypeInfo): TValue;
    function ReadCollection(Json: TJsonArray; TypeInfo: PTypeInfo; RType: TRttiType; const ExistingValue: TValue): TValue;
    function ReadDictionary(Json: TJsonObject; TypeInfo: PTypeInfo; RType: TRttiType; const ExistingValue: TValue): TValue;
    function ConvertToTarget(Json: TJsonValue; TypeInfo: PTypeInfo): TValue;
    function ParseEnum(Json: TJsonValue; TypeInfo: PTypeInfo): TValue;
    function ReadSet(Json: TJsonValue; TypeInfo: PTypeInfo): TValue;
    procedure CheckNumber(Json: TJsonValue);
    function ReadIntegerValue(Json: TJsonValue; TypeInfo: PTypeInfo): TValue;
    function ReadFloatValue(Json: TJsonValue; TypeInfo: PTypeInfo): TValue;
    function ReadInterface(Json: TJsonValue; TypeInfo: PTypeInfo; const ExistingValue: TValue): TValue;
    function ConvertDictionaryKey(const Key: string; KeyType: TRttiType): TValue;
    function CreateClassInstance(TypeInfo: PTypeInfo; TypeData: TJsonTypeInfo; Json: TJsonObject): TValue;
    function ResolveRuntimeType(Json: TJsonObject; DeclaredTypeInfo: PTypeInfo): PTypeInfo;
    function DiscriminatorFieldOf(Instance: TObject): string;
    function FindConstructorValue(Json: TJsonObject; TypeData: TJsonTypeInfo; Param: TRttiParameter; out JsonValue: TJsonValue): Boolean;
    procedure InternalPopulate(Instance: TObject; Json: TJsonObject; TypeData: TJsonTypeInfo);
    procedure ClearContainer(RType: TRttiType; const Instance: TValue);
    procedure InvokeBeforeDeserialize(Instance: TObject; TypeData: TJsonTypeInfo);
    procedure InvokeAfterDeserialize(Instance: TObject; TypeData: TJsonTypeInfo);
  public
    constructor Create;
    destructor Destroy; override;
    function BuildDomFromCurrent(Reader: TJsonReader): TJsonValue;
    function Deserialize(const Json: string; TypeInfo: PTypeInfo): TValue; overload;
    function Deserialize(JsonValue: TJsonValue; TypeInfo: PTypeInfo): TValue; overload;
    procedure Populate(Instance: TObject; JsonValue: TJsonValue);
    property Converters: TObjectList<TJsonConverter> read FConverters;
    property DateFormat: string read FDateFormat write FDateFormat;
    property MissingMemberHandling: TJsonMissingMemberHandling read FMissingMemberHandling write FMissingMemberHandling;
    property StrictTypes: Boolean read FStrictTypes write FStrictTypes;
    property Json5: Boolean read FJson5 write FJson5;
    property NamingStrategy: TJsonNamingStrategyClass read FNamingStrategy write FNamingStrategy;
    property FluentContext: TJsonFluentContext read FFluentContext write FFluentContext;
    property MemberSelection: TJsonMemberTypes read FMemberSelection write FMemberSelection;
    property CollectionAdapters: TDictionary<PTypeInfo, TCollectionAddProc> write FCollectionAdapters;
    property Factories: TDictionary<PTypeInfo, TObjectFactoryProc> write FFactories;
    property KeyDeserializers: TDictionary<PTypeInfo, TKeyDeserializerProc> write FKeyDeserializers;
  end;

implementation

uses
  NativeJson.Converters.Standard;

class function EJsonDeserializationError.CreateWithPos(const Msg: string; Reader: TObject): EJsonDeserializationError;
var
  R: TJsonReader;
begin
  if Reader is TJsonReader then
  begin
    R := TJsonReader(Reader);
    Result := EJsonDeserializationError.CreateFmt('%s (Line %d, Pos %d)', [Msg, R.LineNumber, R.LinePosition]);
  end
  else Result := EJsonDeserializationError.Create(Msg);
end;

constructor TJsonDeserializer.Create;
begin
  inherited Create;
  FConverters := TObjectList<TJsonConverter>.Create(True);
  RegisterDefaultConverters(FConverters);
  FDateFormat := '';
  FMissingMemberHandling := TJsonMissingMemberHandling.Ignore;
  FStrictTypes := False;
  FJson5 := False;
  FNamingStrategy := TDefaultNamingStrategy;
  FMemberSelection := [];
  FRttiCache := TJsonRttiCache.Get;
  FReferenceMap := TDictionary<string, TObject>.Create;
end;

destructor TJsonDeserializer.Destroy;
begin
  FReferenceMap.Free;
  FConverters.Free;
  inherited;
end;

function TJsonDeserializer.BuildDomFromCurrent(Reader: TJsonReader): TJsonValue;
var
  Obj: TJsonObject;
  Arr: TJsonArray;
  Name: string;
begin
  case Reader.TokenType of
    TJsonToken.StartObject:
      begin
        Obj := TJsonObject.Create;
        try
          while Reader.Read do
          begin
            if Reader.TokenType = TJsonToken.EndObject then Exit(Obj);
            if Reader.TokenType <> TJsonToken.PropertyName then raise EJsonDeserializationError.CreateWithPos('Expected property name', Reader);
            Name := Reader.Value;
            if not Reader.Read then raise EJsonDeserializationError.CreateWithPos('Unexpected end while reading property value', Reader);
            Obj.AddPair(Name, BuildDomFromCurrent(Reader));
          end;
          raise EJsonDeserializationError.CreateWithPos('Unterminated object', Reader);
        except
          Obj.Free;
          raise;
        end;
      end;
    TJsonToken.StartArray:
      begin
        Arr := TJsonArray.Create;
        try
          while Reader.Read do
          begin
            if Reader.TokenType = TJsonToken.EndArray then Exit(Arr);
            Arr.Add(BuildDomFromCurrent(Reader));
          end;
          raise EJsonDeserializationError.CreateWithPos('Unterminated array', Reader);
        except
          Arr.Free;
          raise;
        end;
      end;
    TJsonToken.Str: Result := TJsonString.Create(Reader.Value);
    TJsonToken.Integer: Result := TJsonNumber.Create(Reader.RawValue, False);
    TJsonToken.Float: Result := TJsonNumber.Create(Reader.RawValue, True);
    TJsonToken.Boolean: Result := TJsonBoolean.Create(Reader.ValueAsBool);
    TJsonToken.Null, TJsonToken.Undefined: Result := TJsonNull.Create;
  else
    raise EJsonDeserializationError.CreateWithPos('Token cannot be converted to DOM', Reader);
  end;
end;

function TJsonDeserializer.FindConverter(TypeInfo: PTypeInfo): TJsonConverter;
var
  I: Integer;
begin
  if TypeInfo = nil then Exit(nil);
  for I := FConverters.Count - 1 downto 0 do
    if FConverters[I].CanConvert(TypeInfo) then Exit(FConverters[I]);
  Result := nil;
end;

function TJsonDeserializer.FindLocalConverter(MemberInfo: TJsonMemberInfo): TJsonConverter;
begin
  Result := nil;
  if (MemberInfo <> nil) and (MemberInfo.ConverterClass <> nil) and MemberInfo.ConverterClass.InheritsFrom(TJsonConverter) then Result := TJsonConverterClass(MemberInfo.ConverterClass).Create;
end;

function TJsonDeserializer.Deserialize(const Json: string; TypeInfo: PTypeInfo): TValue;
var
  Reader: TJsonReader;
  Dom: TJsonValue;
begin
  if TypeInfo = nil then raise EArgumentNilException.Create('TypeInfo');
  FReferenceMap.Clear;
  Reader := TJsonReader.Create(Json);
  Reader.Json5 := FJson5;
  try
    if not Reader.Read then raise EJsonDeserializationError.Create('JSON input is empty');
    Dom := BuildDomFromCurrent(Reader);
    try
      if Reader.Read then raise EJsonDeserializationError.CreateWithPos('Unexpected content after root JSON value', Reader);
      Result := ReadValue(Dom, TypeInfo, TValue.Empty);
    finally
      Dom.Free;
    end;
  finally
    Reader.Free;
  end;
end;

function TJsonDeserializer.Deserialize(JsonValue: TJsonValue; TypeInfo: PTypeInfo): TValue;
begin
  if TypeInfo = nil then raise EArgumentNilException.Create('TypeInfo');
  FReferenceMap.Clear;
  Result := ReadValue(JsonValue, TypeInfo, TValue.Empty);
end;

procedure TJsonDeserializer.Populate(Instance: TObject; JsonValue: TJsonValue);
var
  TypeData: TJsonTypeInfo;
begin
  if Instance = nil then raise EArgumentNilException.Create('Instance');
  if (JsonValue = nil) or (JsonValue.GetJsonType <> TJsonType.jtObject) then raise EJsonDeserializationError.Create('Populate requires a JSON object');
  FReferenceMap.Clear;
  TypeData := FRttiCache.GetTypeInfo(Instance.ClassInfo, FNamingStrategy, FFluentContext, FMemberSelection);
  InvokeBeforeDeserialize(Instance, TypeData);
  InternalPopulate(Instance, TJsonObject(JsonValue), TypeData);
  InvokeAfterDeserialize(Instance, TypeData);
end;

procedure TJsonDeserializer.ClearContainer(RType: TRttiType; const Instance: TValue);
var
  Method: TRttiMethod;
begin
  if Instance.IsEmpty then Exit;
  Method := RType.GetMethod('Clear');
  if (Method <> nil) and (Length(Method.GetParameters) = 0) then Method.Invoke(Instance, []);
end;

function TJsonDeserializer.ReadValue(Json: TJsonValue; TypeInfo: PTypeInfo; const ExistingValue: TValue; MemberInfo: TJsonMemberInfo): TValue;
var
  Converter, LocalConverter: TJsonConverter;
  Reader: TJsonReader;
  Ctx: TRttiContext;
  RType: TRttiType;
begin
  if TypeInfo = nil then Exit(TValue.Empty);
  if (Json = nil) or (Json.GetJsonType = TJsonType.jtNull) then
  begin
    if TypeInfo = System.TypeInfo(Variant) then Result := TValue.From<Variant>(Null) else TValue.Make(nil, TypeInfo, Result);
    Exit;
  end;
  if TypeInfo = System.TypeInfo(TJsonValue) then Exit(TValue.From<TJsonValue>(Json.Clone));
  if TypeInfo = System.TypeInfo(TJsonObject) then
  begin
    if Json is TJsonObject then Result := TValue.From<TJsonObject>(TJsonObject(Json.Clone)) else TValue.Make(nil, TypeInfo, Result);
    Exit;
  end;
  if TypeInfo = System.TypeInfo(TJsonArray) then
  begin
    if Json is TJsonArray then Result := TValue.From<TJsonArray>(TJsonArray(Json.Clone)) else TValue.Make(nil, TypeInfo, Result);
    Exit;
  end;
  LocalConverter := FindLocalConverter(MemberInfo);
  try
    Converter := LocalConverter;
    if Converter = nil then Converter := FindConverter(TypeInfo);
    if (Converter <> nil) and Converter.CanRead then
    begin
      Reader := TJsonReader.Create(Json.ToJson);
      try
        if not Reader.Read then raise EJsonDeserializationError.Create('Converter received empty JSON');
        Result := Converter.ReadJson(Reader, TypeInfo, ExistingValue, Self);
        Exit;
      finally
        Reader.Free;
      end;
    end;
  finally
    LocalConverter.Free;
  end;
  Ctx := TRttiContext.Create;
  try
    RType := Ctx.GetType(TypeInfo);
    if RType = nil then raise EJsonDeserializationError.CreateFmt('RTTI type not found for %s', [TypeInfo.Name]);
    case JsonTypeKind(RType) of
      tkClass:
        if (Json.GetJsonType = TJsonType.jtArray) and TJsonGenericsHelper.IsCollection(RType) then Result := ReadCollection(TJsonArray(Json), TypeInfo, RType, ExistingValue)
        else if (Json.GetJsonType = TJsonType.jtObject) and TJsonGenericsHelper.IsDictionary(RType) then Result := ReadDictionary(TJsonObject(Json), TypeInfo, RType, ExistingValue)
        else if Json.GetJsonType = TJsonType.jtObject then Result := ReadObject(TJsonObject(Json), TypeInfo, ExistingValue)
        else raise EJsonDeserializationError.CreateFmt('Expected object/array for %s', [RType.Name]);
      tkRecord:
        if Json.GetJsonType = TJsonType.jtObject then Result := ReadRecord(TJsonObject(Json), TypeInfo)
        else raise EJsonDeserializationError.CreateFmt('Expected object for record %s', [RType.Name]);
      tkArray:
        if Json.GetJsonType = TJsonType.jtArray then Result := ReadArray(TJsonArray(Json), TypeInfo)
        else raise EJsonDeserializationError.CreateFmt('Expected array for %s', [RType.Name]);
      tkDynArray:
        if Json.GetJsonType = TJsonType.jtArray then Result := ReadDynArray(TJsonArray(Json), TypeInfo)
        else raise EJsonDeserializationError.CreateFmt('Expected array for %s', [RType.Name]);
      tkEnumeration: Result := ParseEnum(Json, TypeInfo);
      tkInterface:
        if Json.GetJsonType = TJsonType.jtObject then Result := ReadInterface(Json, TypeInfo, ExistingValue)
        else raise EJsonDeserializationError.CreateFmt('Expected object for interface %s', [RType.Name]);
    else
      Result := ConvertToTarget(Json, TypeInfo);
    end;
  finally
    Ctx.Free;
  end;
end;

function TJsonDeserializer.ResolveRuntimeType(Json: TJsonObject; DeclaredTypeInfo: PTypeInfo): PTypeInfo;
var
  TypeValue: TJsonValue;
  Name: string;
  Ctx: TRttiContext;
  DeclaredType, RuntimeType: TRttiType;
  DeclaredClass, RuntimeClass: TClass;
  KeptClass: TClass;
  Config: TJsonTypeConfig;
  SubClass: TClass;
begin
  Result := DeclaredTypeInfo;

  // Fluent configuration first: if the declared type has its own
  // discriminator field, that applies instead of $type. Without configuration
  // the whole block falls through and everything stays as before.
  if FFluentContext <> nil then
  begin
    Config := FFluentContext.GetConfig(DeclaredTypeInfo);
    if (Config <> nil) and (Config.InternalDiscriminator <> '') then
    begin
      if not Json.TryGetValue(Config.InternalDiscriminator, TypeValue) then Exit;
      Name := TypeValue.AsString;
      if Name = '' then Exit;
      if not Config.FindSubType(Name, SubClass) then
        raise EJsonDeserializationError.CreateFmt(
          'No subtype registered for %s = "%s" on %s. Register one with Entity<%s>.SubType.',
          [Config.InternalDiscriminator, Name, string(DeclaredTypeInfo.Name), string(DeclaredTypeInfo.Name)]);
      Exit(SubClass.ClassInfo);
    end;
  end;

  if not Json.TryGetValue('$type', TypeValue) then Exit;
  Name := TypeValue.AsString;
  if Name = '' then Exit;
  Ctx := TRttiContext.Create;
  try
    DeclaredType := Ctx.GetType(DeclaredTypeInfo);
    RuntimeType := JsonRttiFindType(Ctx, Name);
    if not (RuntimeType is TRttiInstanceType) then
    begin
      KeptClass := JsonFindKeptClass(Name);
      if KeptClass <> nil then RuntimeType := Ctx.GetType(KeptClass);
    end;
    if not (RuntimeType is TRttiInstanceType) then
      raise EJsonDeserializationError.CreateFmt(
        'Unknown runtime type "%s". Classes for TypeNameHandling must be declared in the interface section of a unit; types declared in the program (.dpr) cannot be found through RTTI.', [Name]);
    if not (DeclaredType is TRttiInstanceType) then raise EJsonDeserializationError.CreateFmt('Runtime type metadata is invalid for %s', [DeclaredTypeInfo.Name]);
    DeclaredClass := TRttiInstanceType(DeclaredType).MetaclassType;
    RuntimeClass := TRttiInstanceType(RuntimeType).MetaclassType;
    if not RuntimeClass.InheritsFrom(DeclaredClass) then raise EJsonDeserializationError.CreateFmt('Runtime type %s is not assignable to %s', [RuntimeType.Name, DeclaredType.Name]);
    Result := RuntimeType.Handle;
  finally
    Ctx.Free;
  end;
end;

function TJsonDeserializer.FindConstructorValue(Json: TJsonObject; TypeData: TJsonTypeInfo; Param: TRttiParameter; out JsonValue: TJsonValue): Boolean;
var
  Candidate: string;
  Member: TJsonMemberInfo;
begin
  Candidate := Param.Name;
  Result := Json.TryGetValue(Candidate, JsonValue);
  if Result then Exit;
  if (Length(Candidate) > 1) and (UpCase(Candidate[1]) = 'A') then Candidate := Copy(Candidate, 2, MaxInt);
  Result := Json.TryGetValue(Candidate, JsonValue);
  if Result then Exit;
  for Member in TypeData.Members do
    if SameText(Member.Member.Name, Candidate) or SameText(Member.Member.Name, 'F' + Candidate) then
      if Json.TryGetValue(Member.JsonName, JsonValue) then Exit(True);
  JsonValue := nil;
end;

function TJsonDeserializer.CreateClassInstance(TypeInfo: PTypeInfo; TypeData: TJsonTypeInfo; Json: TJsonObject): TValue;
var
  FactoryProc: TObjectFactoryProc;
  Params: TArray<TRttiParameter>;
  Args: TArray<TValue>;
  JsonValue: TJsonValue;
  I: Integer;
begin
  if (FFactories <> nil) and FFactories.TryGetValue(TypeInfo, FactoryProc) then Exit(TValue.From<TObject>(FactoryProc(TypeData.RttiType)).Cast(TypeInfo));
  if Assigned(TypeData.Factory) then Exit(TValue.From<TObject>(TypeData.Factory()).Cast(TypeInfo));
  if TypeData.JsonConstructor <> nil then
  begin
    Params := TypeData.JsonConstructor.GetParameters;
    SetLength(Args, Length(Params));
    for I := 0 to High(Params) do
      if FindConstructorValue(Json, TypeData, Params[I], JsonValue) then Args[I] := ReadValue(JsonValue, Params[I].ParamType.Handle, TValue.Empty)
      else TValue.Make(nil, Params[I].ParamType.Handle, Args[I]);
    Exit(TypeData.JsonConstructor.Invoke(TRttiInstanceType(TypeData.RttiType).MetaclassType, Args));
  end;
  Result := TJsonActivator.CreateInstance(TypeInfo);
end;

procedure TJsonDeserializer.InvokeBeforeDeserialize(Instance: TObject; TypeData: TJsonTypeInfo);
begin
  if Instance = nil then Exit;
  if TypeData.OnDeserializing <> nil then TypeData.OnDeserializing.Invoke(Instance, []);
  if Assigned(TypeData.FluentOnDeserializing) then TypeData.FluentOnDeserializing(Instance);
end;

procedure TJsonDeserializer.InvokeAfterDeserialize(Instance: TObject; TypeData: TJsonTypeInfo);
begin
  if Instance = nil then Exit;
  if TypeData.OnDeserialized <> nil then TypeData.OnDeserialized.Invoke(Instance, []);
  if Assigned(TypeData.FluentOnDeserialized) then TypeData.FluentOnDeserialized(Instance);
end;

function TJsonDeserializer.ReadObject(Json: TJsonObject; TypeInfo: PTypeInfo; const ExistingValue: TValue): TValue;
var
  RefValue, IdValue, TypeValue: TJsonValue;
  RefId: string;
  ExistingObject: TObject;
  RuntimeTypeInfo: PTypeInfo;
  TypeData: TJsonTypeInfo;
  Instance: TValue;
  Obj: TObject;
  RuntimeClass: TClass;
  ReuseExisting: Boolean;
begin
  if Json.TryGetValue('$ref', RefValue) then
  begin
    RefId := RefValue.AsString;
    if not FReferenceMap.TryGetValue(RefId, ExistingObject) then raise EJsonDeserializationError.CreateFmt('Unresolved reference "%s"', [RefId]);
    TValue.Make(@ExistingObject, TypeInfo, Result);
    Exit;
  end;
  RuntimeTypeInfo := ResolveRuntimeType(Json, TypeInfo);
  ReuseExisting := not ExistingValue.IsEmpty and ExistingValue.IsObject and (ExistingValue.AsObject <> nil);
  if ReuseExisting and not Json.TryGetValue('$type', TypeValue) then RuntimeTypeInfo := ExistingValue.AsObject.ClassInfo;
  RuntimeClass := GetTypeData(RuntimeTypeInfo)^.ClassType;
  if ReuseExisting then ReuseExisting := ExistingValue.AsObject.InheritsFrom(RuntimeClass);
  TypeData := FRttiCache.GetTypeInfo(RuntimeTypeInfo, FNamingStrategy, FFluentContext, FMemberSelection);
  if ReuseExisting then Instance := ExistingValue else Instance := CreateClassInstance(RuntimeTypeInfo, TypeData, Json);
  if not Instance.IsObject or (Instance.AsObject = nil) then raise EJsonDeserializationError.CreateFmt('Could not create %s', [RuntimeTypeInfo.Name]);
  Obj := Instance.AsObject;
  if Json.TryGetValue('$id', IdValue) then FReferenceMap.AddOrSetValue(IdValue.AsString, Obj);
  try
    InvokeBeforeDeserialize(Obj, TypeData);
    InternalPopulate(Obj, Json, TypeData);
    InvokeAfterDeserialize(Obj, TypeData);
    Result := Instance;
  except
    if not ReuseExisting then Obj.Free;
    raise;
  end;
end;

function TJsonDeserializer.DiscriminatorFieldOf(Instance: TObject): string;
var
  RegisteredClass: TClass;
  Config: TJsonTypeConfig;
begin
  // The discriminator field is configured on the BASE CLASS, the
  // object here is the subclass. So walk up the chain until a
  // configuration with a discriminator is found.
  Result := '';
  if (FFluentContext = nil) or (Instance = nil) then Exit;
  RegisteredClass := Instance.ClassType;
  while RegisteredClass <> nil do
  begin
    if RegisteredClass.ClassInfo <> nil then
    begin
      Config := FFluentContext.GetConfig(RegisteredClass.ClassInfo);
      if (Config <> nil) and (Config.InternalDiscriminator <> '') then
        Exit(Config.InternalDiscriminator);
    end;
    RegisteredClass := RegisteredClass.ClassParent;
  end;
end;

procedure TJsonDeserializer.InternalPopulate(Instance: TObject; Json: TJsonObject; TypeData: TJsonTypeInfo);
var
  Pair: TPair<string, TJsonValue>;
  Member: TJsonMemberInfo;
  ExistingValue, TargetValue: TValue;
  TypeInfo: PTypeInfo;
  DiscriminatorValue: string;
begin
  // The discriminator field has already done its job - it picked the
  // class. As a member it usually does not exist at all, and
  // with MissingMemberHandling.Error it would otherwise break exactly the load
  // that it made possible in the first place.
  DiscriminatorValue := DiscriminatorFieldOf(Instance);
  for Pair in Json do
  begin
    if (Pair.Key = '$id') or (Pair.Key = '$ref') or (Pair.Key = '$type') then Continue;
    if (DiscriminatorValue <> '') and SameText(Pair.Key, DiscriminatorValue)
      and not TypeData.TryGetMember(Pair.Key, Member) then Continue;
    if not TypeData.TryGetMember(Pair.Key, Member) then
    begin
      if FMissingMemberHandling = TJsonMissingMemberHandling.Error then raise EJsonDeserializationError.CreateFmt('Unknown member "%s" on %s', [Pair.Key, TypeData.RttiType.Name]);
      Continue;
    end;
    if Member.ValueType = nil then Continue;
    if Member.Required and (Pair.Value.GetJsonType = TJsonType.jtNull) then raise EJsonDeserializationError.CreateFmt('Required member "%s" cannot be null', [Member.JsonName]);
    TypeInfo := Member.ValueType.Handle;
    ExistingValue := TValue.Empty;
    if Member.IsReadable then ExistingValue := Member.GetValue(Instance);
    if not Member.IsWritable then
    begin
      if not ExistingValue.IsEmpty and (ExistingValue.Kind = tkClass) and (ExistingValue.AsObject <> nil) then ReadValue(Pair.Value, TypeInfo, ExistingValue, Member);
      Continue;
    end;
    TargetValue := ReadValue(Pair.Value, TypeInfo, ExistingValue, Member);
    if not TargetValue.IsEmpty then Member.SetValue(Instance, TargetValue);
  end;
  for Member in TypeData.Members do
    if Member.Required and not Json.Contains(Member.JsonName) then raise EJsonDeserializationError.CreateFmt('Required member "%s" is missing', [Member.JsonName]);
end;

function TJsonDeserializer.ReadRecord(Json: TJsonObject; TypeInfo: PTypeInfo): TValue;
var
  TypeData: TJsonTypeInfo;
  Pair: TPair<string, TJsonValue>;
  Member: TJsonMemberInfo;
  V: TValue;
  Ptr: Pointer;
begin
  TValue.Make(nil, TypeInfo, Result);
  TypeData := FRttiCache.GetTypeInfo(TypeInfo, FNamingStrategy, FFluentContext, FMemberSelection);
  Ptr := Result.GetReferenceToRawData;
  for Pair in Json do
    if TypeData.TryGetMember(Pair.Key, Member) then
    begin
      if Member.Required and (Pair.Value.GetJsonType = TJsonType.jtNull) then raise EJsonDeserializationError.CreateFmt('Required member "%s" cannot be null', [Member.JsonName]);
      if Member.IsWritable and (Member.ValueType <> nil) then
      begin
        V := ReadValue(Pair.Value, Member.ValueType.Handle, TValue.Empty, Member);
        if not V.IsEmpty then Member.SetValue(Ptr, V);
      end;
    end
    else if FMissingMemberHandling = TJsonMissingMemberHandling.Error then raise EJsonDeserializationError.CreateFmt('Unknown member "%s" on %s', [Pair.Key, TypeData.RttiType.Name]);
  for Member in TypeData.Members do
    if Member.Required and not Json.Contains(Member.JsonName) then raise EJsonDeserializationError.CreateFmt('Required member "%s" is missing', [Member.JsonName]);
end;

function TJsonDeserializer.ReadArray(Json: TJsonArray; TypeInfo: PTypeInfo): TValue;
var
  Ctx: TRttiContext;
  RType: TRttiType;
  ElementType: TRttiType;
  I, Count: Integer;
begin
  TValue.Make(nil, TypeInfo, Result);
  Ctx := TRttiContext.Create;
  try
    RType := Ctx.GetType(TypeInfo);
    if not (RType is TRttiArrayType) then Exit;
    ElementType := TRttiArrayType(RType).ElementType;
    Count := Result.GetArrayLength;
    if Json.Count < Count then Count := Json.Count;
    for I := 0 to Count - 1 do Result.SetArrayElement(I, ReadValue(Json[I], ElementType.Handle, TValue.Empty));
  finally
    Ctx.Free;
  end;
end;

function TJsonDeserializer.ReadDynArray(Json: TJsonArray; TypeInfo: PTypeInfo): TValue;
var
  Ctx: TRttiContext;
  RType: TRttiType;
  ElementType: TRttiType;
  I: Integer;
  Len: NativeInt;
begin
  TValue.Make(nil, TypeInfo, Result);
  Ctx := TRttiContext.Create;
  try
    RType := Ctx.GetType(TypeInfo);
    if not (RType is TRttiDynamicArrayType) then Exit;
    ElementType := TRttiDynamicArrayType(RType).ElementType;
    Len := Json.Count;
    DynArraySetLength(PPointer(Result.GetReferenceToRawData)^, TypeInfo, 1, @Len);
    for I := 0 to Json.Count - 1 do Result.SetArrayElement(I, ReadValue(Json[I], ElementType.Handle, TValue.Empty));
  finally
    Ctx.Free;
  end;
end;

function TJsonDeserializer.ReadCollection(Json: TJsonArray; TypeInfo: PTypeInfo; RType: TRttiType; const ExistingValue: TValue): TValue;
var
  Instance, Item: TValue;
  ElementType: TRttiType;
  Adapter: TCollectionAddProc;
  I: Integer;
begin
  if not ExistingValue.IsEmpty and ExistingValue.IsObject and (ExistingValue.AsObject <> nil) then Instance := ExistingValue else Instance := TJsonActivator.CreateInstance(TypeInfo);
  ElementType := TJsonGenericsHelper.GetCollectionElementType(RType);
  ClearContainer(RType, Instance);
  for I := 0 to Json.Count - 1 do
  begin
    Item := ReadValue(Json[I], ElementType.Handle, TValue.Empty);
    if (FCollectionAdapters <> nil) and FCollectionAdapters.TryGetValue(TypeInfo, Adapter) then Adapter(Instance.AsObject, Item)
    else TJsonGenericsHelper.AddToCollection(RType, Instance, Item);
  end;
  Result := Instance;
end;

function TJsonDeserializer.ConvertDictionaryKey(const Key: string; KeyType: TRttiType): TValue;
var
  Proc: TKeyDeserializerProc;
  EnumValue: Integer;
begin
  if (FKeyDeserializers <> nil) and FKeyDeserializers.TryGetValue(KeyType.Handle, Proc) then Exit(Proc(Key));
  case JsonTypeKind(KeyType) of
    tkString, tkLString, tkWString, tkUString: Result := TValue.From<string>(Key).Cast(KeyType.Handle);
    tkChar, tkWChar: if Key <> '' then Result := TValue.FromOrdinal(KeyType.Handle, Ord(Key[1])) else Result := TValue.FromOrdinal(KeyType.Handle, 0);
    tkInteger, tkInt64: Result := TValue.FromOrdinal(KeyType.Handle, StrToInt64(Key));
    tkEnumeration:
      begin
        EnumValue := GetEnumValue(KeyType.Handle, Key);
        if EnumValue < 0 then EnumValue := StrToInt(Key);
        Result := TValue.FromOrdinal(KeyType.Handle, EnumValue);
      end;
  else
    raise EJsonDeserializationError.CreateFmt('Dictionary key type %s requires a key deserializer', [KeyType.Name]);
  end;
end;

function TJsonDeserializer.ReadDictionary(Json: TJsonObject; TypeInfo: PTypeInfo; RType: TRttiType; const ExistingValue: TValue): TValue;
var
  Instance, KeyValue, ItemValue: TValue;
  KeyType, ValueType: TRttiType;
  Pair: TPair<string, TJsonValue>;
begin
  if not ExistingValue.IsEmpty and ExistingValue.IsObject and (ExistingValue.AsObject <> nil) then Instance := ExistingValue else Instance := TJsonActivator.CreateInstance(TypeInfo);
  TJsonGenericsHelper.GetDictionaryKeyValueTypes(RType, KeyType, ValueType);
  ClearContainer(RType, Instance);
  for Pair in Json do
  begin
    if (Pair.Key = '$id') or (Pair.Key = '$ref') or (Pair.Key = '$type') then Continue;
    KeyValue := ConvertDictionaryKey(Pair.Key, KeyType);
    ItemValue := ReadValue(Pair.Value, ValueType.Handle, TValue.Empty);
    TJsonGenericsHelper.AddToDictionary(RType, Instance, KeyValue, ItemValue);
  end;
  Result := Instance;
end;

function DescribeValueKind(Json: TJsonValue): string;
begin
  case Json.GetJsonType of
    TJsonType.jtString: Result := 'a string';
    TJsonType.jtBoolean: Result := 'a boolean';
    TJsonType.jtObject: Result := 'an object';
    TJsonType.jtArray: Result := 'an array';
    TJsonType.jtNull: Result := 'null';
  else
    Result := 'a number';
  end;
end;

function EnumFromOrdinal(TypeInfo: PTypeInfo; Ordinal: Int64): TValue;
var
  TypeDataPtr: PTypeData;
begin
  // An ordinal value outside the enumeration would otherwise produce a value
  // that does not exist in the type - and that blows up on the next access.
  TypeDataPtr := GetTypeData(TypeInfo);
  if (Ordinal < TypeDataPtr^.MinValue) or (Ordinal > TypeDataPtr^.MaxValue) then
    raise EJsonDeserializationError.CreateFmt(DeserializationStrings.EnumOutOfRange,
      [Ordinal, string(TypeInfo^.Name)]);
  Result := TValue.FromOrdinal(TypeInfo, Ordinal);
end;

function TJsonDeserializer.ParseEnum(Json: TJsonValue; TypeInfo: PTypeInfo): TValue;
var
  N: Integer;
  S: string;
begin
  if TypeInfo = System.TypeInfo(Boolean) then
  begin
    if FStrictTypes and (Json.GetJsonType <> TJsonType.jtBoolean) then
      raise EJsonDeserializationError.CreateFmt(DeserializationStrings.BooleanExpected, [DescribeValueKind(Json)]);
    Exit(TValue.From<Boolean>(Json.AsBoolean));
  end;
  if Json.GetJsonType in [TJsonType.jtInteger, TJsonType.jtFloat] then Exit(EnumFromOrdinal(TypeInfo, Json.AsInteger));
  S := Json.AsString;
  if TryStrToInt(S, N) then Exit(EnumFromOrdinal(TypeInfo, N));
  N := GetEnumValue(TypeInfo, S);
  if N < 0 then raise EJsonDeserializationError.CreateFmt('Invalid enum value "%s" for %s', [S, TypeInfo.Name]);
  Result := EnumFromOrdinal(TypeInfo, N);
end;

function TJsonDeserializer.ReadSet(Json: TJsonValue; TypeInfo: PTypeInfo): TValue;
var
  Element: PTypeInfo;
  Ordinals: TArray<Integer>;
  Item: TJsonValue;
  Parts: TArray<string>;
  Text: string;
  N, I: Integer;

  procedure AddOrdinal(Value: Integer);
  begin
    SetLength(Ordinals, Length(Ordinals) + 1);
    Ordinals[High(Ordinals)] := Value;
  end;

  function NameToOrdinal(const Name: string): Integer;
  begin
    if TryStrToInt(Name, Result) then Exit;
    if (Element = nil) or (Element^.Kind <> tkEnumeration) then
      raise EJsonDeserializationError.CreateFmt('Invalid set element "%s" for %s', [Name, TypeInfo.Name]);
    Result := GetEnumValue(Element, Name);
    if Result < 0 then raise EJsonDeserializationError.CreateFmt('Invalid set element "%s" for %s', [Name, TypeInfo.Name]);
  end;

begin
  Element := JsonSetElementType(TypeInfo);
  Ordinals := nil;
  if Json is TJsonArray then
  begin
    for I := 0 to TJsonArray(Json).Count - 1 do
    begin
      Item := TJsonArray(Json).Items[I];
      if Item.GetJsonType in [TJsonType.jtInteger, TJsonType.jtFloat] then AddOrdinal(Item.AsInteger)
      else AddOrdinal(NameToOrdinal(Item.AsString));
    end;
  end
  else if Json.GetJsonType = TJsonType.jtString then
  begin
    Text := Trim(Json.AsString);
    if (Text <> '') and (Text[1] = '[') then Delete(Text, 1, 1);
    if (Text <> '') and (Text[Length(Text)] = ']') then Delete(Text, Length(Text), 1);
    if Trim(Text) <> '' then
    begin
      Parts := Text.Split([',']);
      for N := 0 to High(Parts) do AddOrdinal(NameToOrdinal(Trim(Parts[N])));
    end;
  end
  else raise EJsonDeserializationError.CreateFmt('Set %s expects a JSON array, got %s', [TypeInfo.Name, DescribeValueKind(Json)]);
  Result := JsonSetFromOrdinals(TypeInfo, Ordinals);
end;

procedure TJsonDeserializer.CheckNumber(Json: TJsonValue);
begin
  if not FStrictTypes then Exit;
  if not (Json.GetJsonType in [TJsonType.jtInteger, TJsonType.jtFloat]) then
    raise EJsonDeserializationError.CreateFmt(DeserializationStrings.NumberExpected, [DescribeValueKind(Json)]);
end;

function TJsonDeserializer.ReadIntegerValue(Json: TJsonValue; TypeInfo: PTypeInfo): TValue;
var
  Text: string;
  InputValue, Min, Max: Int64;
  UnsignedValue: UInt64;
  FloatValue: Double;
  IsNegative, FitsInInt64: Boolean;
  TypeDataPtr: PTypeData;

  // 1e2 is valid JSON and means 100, 100e-2 means 1, and 1.0 is a whole number
  // according to the specification. Going through Double does NOT work for this:
  // 9007199254740993 rounds to ...992 there and would be accepted silently
  // with the wrong value. That is why the number text itself is shifted.
  function FromNumberText(const Raw: string; out IntegerPart: Int64; out UnsignedValue: UInt64;
    out IsNegative, FitsInInt64: Boolean): Boolean;
  var
    Digits: string;
    I, DotPos, EPos, Exponent, DecimalShift, FractionDigits: Integer;
    Mantissa, Rest: string;
    UValue: UInt64;
    Limit: UInt64;
  begin
    Result := False;
    IntegerPart := 0;
    UnsignedValue := 0;
    IsNegative := False;
    FitsInInt64 := False;
    if Raw = '' then Exit;

    I := 1;
    if Raw[1] = '-' then
    begin
      IsNegative := True;
      Inc(I);
    end;
    Mantissa := Copy(Raw, I, MaxInt);
    if Mantissa = '' then Exit;

    Exponent := 0;
    EPos := Pos('e', LowerCase(Mantissa));
    if EPos > 0 then
    begin
      Rest := Copy(Mantissa, EPos + 1, MaxInt);
      Mantissa := Copy(Mantissa, 1, EPos - 1);
      if not TryStrToInt(Rest, Exponent) then Exit;
    end;

    DotPos := Pos('.', Mantissa);
    if DotPos > 0 then
    begin
      FractionDigits := Length(Mantissa) - DotPos;
      Digits := Copy(Mantissa, 1, DotPos - 1) + Copy(Mantissa, DotPos + 1, MaxInt);
    end
    else
    begin
      FractionDigits := 0;
      Digits := Mantissa;
    end;
    if Digits = '' then Exit;
    for I := 1 to Length(Digits) do
      if not CharInSet(Digits[I], ['0'..'9']) then Exit;

    // Shift the decimal point by the exponent.
    DecimalShift := FractionDigits - Exponent;
    if DecimalShift > 0 then
    begin
      // Whatever would remain after the decimal point must be zero - otherwise it is
      // not a whole number and is rejected, not truncated.
      if DecimalShift > Length(Digits) then
      begin
        for I := 1 to Length(Digits) do
          if Digits[I] <> '0' then Exit;
        Digits := '0';
      end
      else
      begin
        for I := Length(Digits) - DecimalShift + 1 to Length(Digits) do
          if Digits[I] <> '0' then Exit;
        Digits := Copy(Digits, 1, Length(Digits) - DecimalShift);
        if Digits = '' then Digits := '0';
      end;
    end
    else if DecimalShift < 0 then
    begin
      // Append zeros. More than 20 digits do not fit into any
      // 64-bit type anyway - the cutoff protects against huge helper strings.
      if -DecimalShift > 20 then Exit;
      Digits := Digits + StringOfChar('0', -DecimalShift);
    end;

    while (Length(Digits) > 1) and (Digits[1] = '0') do Delete(Digits, 1, 1);
    if Length(Digits) > 20 then Exit;

    UValue := 0;
    for I := 1 to Length(Digits) do
    begin
      if UValue > (High(UInt64) - UInt64(Ord(Digits[I]) - Ord('0'))) div 10 then Exit;
      UValue := UValue * 10 + UInt64(Ord(Digits[I]) - Ord('0'));
    end;

    UnsignedValue := UValue;
    if IsNegative then Limit := UInt64(High(Int64)) + 1 else Limit := UInt64(High(Int64));
    FitsInInt64 := UValue <= Limit;
    if FitsInInt64 then
    begin
      if IsNegative then
      begin
        if UValue = UInt64(High(Int64)) + 1 then IntegerPart := Low(Int64) else IntegerPart := -Int64(UValue);
      end
      else
        IntegerPart := Int64(UValue);
    end;
    Result := True;
  end;

  function FromFloatText(out Target: Int64): Boolean;
  var
    UnsignedValue: UInt64;
    IsNegative, Fits: Boolean;
  begin
    Result := FromNumberText(Text, Target, UnsignedValue, IsNegative, Fits) and Fits;
  end;

begin
  CheckNumber(Json);
  // The raw text is the only lossless source. Via AsInteger a
  // 20-digit number would already be rounded before it can be rejected.
  Text := Trim(Json.AsRawText);
  TypeDataPtr := GetTypeData(TypeInfo);

  if JsonTypeKind(TypeInfo) = tkInt64 then
  begin
    if TypeDataPtr^.MinInt64Value < 0 then
    begin
      if not TryStrToInt64(Text, InputValue) and not FromFloatText(InputValue) then
        raise EJsonDeserializationError.CreateFmt(DeserializationStrings.RangeOut, [Text, string(TypeInfo^.Name)]);
      Exit(TValue.From<Int64>(InputValue).Cast(TypeInfo));
    end;
    // Unsigned: same bits, different meaning. StrToInt64 would
    // read High(UInt64) as -1.
    if not TryStrToUInt64(Text, UnsignedValue) then
      // Directly via the number text, not via the Int64 route: otherwise
      // 1e19 would already stop before the check, although the value fits
      // into a UInt64.
      if not FromNumberText(Text, InputValue, UnsignedValue, IsNegative, FitsInInt64) or IsNegative then
        raise EJsonDeserializationError.CreateFmt(DeserializationStrings.RangeOut, [Text, string(TypeInfo^.Name)]);
    TValue.Make(@UnsignedValue, TypeInfo, Result);
    Exit;
  end;

  if not TryStrToInt64(Text, InputValue) and not FromFloatText(InputValue) then
  begin
    if TryStrToFloat(Text, FloatValue, TFormatSettings.Invariant) and (FloatValue <> Int(FloatValue)) then
      raise EJsonDeserializationError.CreateFmt(DeserializationStrings.NotAWholeNumber, [Text, string(TypeInfo^.Name)]);
    raise EJsonDeserializationError.CreateFmt(DeserializationStrings.RangeOut, [Text, string(TypeInfo^.Name)]);
  end;

  Min := TypeDataPtr^.MinValue;
  Max := TypeDataPtr^.MaxValue;
  // For Cardinal the maximum does not fit into the signed
  // MaxValue field and is stored there as -1. Hence the special case.
  if TypeDataPtr^.OrdType = otULong then
  begin
    Min := 0;
    Max := High(UInt32);
  end;
  if (InputValue < Min) or (InputValue > Max) then
    raise EJsonDeserializationError.CreateFmt(DeserializationStrings.RangeOut, [Text, string(TypeInfo^.Name)]);

  Result := TValue.FromOrdinal(TypeInfo, InputValue);
end;

function TJsonDeserializer.ReadFloatValue(Json: TJsonValue; TypeInfo: PTypeInfo): TValue;
var
  Limit, InputValue: Extended;
  Money: Currency;
  Text: string;
begin
  CheckNumber(Json);
  Text := Trim(Json.AsRawText);

  if GetTypeData(TypeInfo)^.FloatType = ftCurr then
  begin
    // Currency exactly: not via Double, and the range is checked
    // by the text parser itself.
    if not TryStrToCurr(Text, Money, TFormatSettings.Invariant) then
      raise EJsonDeserializationError.CreateFmt(DeserializationStrings.RangeOut, [Text, 'Currency']);
    Exit(TValue.From<Currency>(Money).Cast(TypeInfo));
  end;

  case GetTypeData(TypeInfo)^.FloatType of
    ftSingle: Limit := MaxSingle;
    ftDouble: Limit := MaxDouble;
    ftComp:   Limit := MaxComp;
  else
    Limit := MaxExtended;
  end;

  InputValue := Json.AsDouble;
  if not (FJson5 and (IsNan(InputValue) or IsInfinite(InputValue))) and ((InputValue < -Limit) or (InputValue > Limit)) then
    raise EJsonDeserializationError.CreateFmt(DeserializationStrings.RangeOut, [Text, string(TypeInfo^.Name)]);

  Result := TValue.From<Double>(InputValue).Cast(TypeInfo);
end;

function TJsonDeserializer.ReadInterface(Json: TJsonValue; TypeInfo: PTypeInfo; const ExistingValue: TValue): TValue;
var
  Existing: IInterface;
  InstanceObj: TObject;
  InterfaceGuid: TGUID;
  FactoryFunc: TObjectFactoryProc;
  Created: IInterface;
  Ctx: TRttiContext;
  RType: TRttiType;
begin
  InstanceObj := nil;

  // 1. If the interface already points to an instance, that instance is filled.
  if not ExistingValue.IsEmpty and (ExistingValue.Kind = tkInterface) then
  begin
    Existing := ExistingValue.AsInterface;
    if Existing <> nil then
      try
        InstanceObj := Existing as TObject;
      except
        InstanceObj := nil;
      end;
  end;

  if InstanceObj <> nil then
  begin
    InternalPopulate(InstanceObj, TJsonObject(Json),
      FRttiCache.GetTypeInfo(InstanceObj.ClassInfo, FNamingStrategy, FFluentContext, FMemberSelection));
    Exit(ExistingValue);
  end;

  // 2. Otherwise a factory must say which class is meant. Nobody can derive
  //    TDog from IAnimal alone.
  InterfaceGuid := GetTypeData(TypeInfo)^.Guid;
  if IsEqualGUID(InterfaceGuid, TGUID.Empty) then
    raise EJsonDeserializationError.CreateFmt(DeserializationStrings.InterfaceNoGuid, [string(TypeInfo^.Name)]);

  if (FFactories = nil) or not FFactories.TryGetValue(TypeInfo, FactoryFunc) then
    raise EJsonDeserializationError.CreateFmt(DeserializationStrings.InterfaceNoFactory,
      [string(TypeInfo^.Name), string(TypeInfo^.Name)]);

  Ctx := TRttiContext.Create;
  try
    RType := Ctx.GetType(TypeInfo);
    InstanceObj := FactoryFunc(RType);
  finally
    Ctx.Free;
  end;
  if InstanceObj = nil then
    raise EJsonDeserializationError.CreateFmt(DeserializationStrings.InterfaceNoFactory,
      [string(TypeInfo^.Name), string(TypeInfo^.Name)]);

  // Supports holds the reference. With a non-counting implementation
  // the object still belongs to the caller.
  if not Supports(InstanceObj, InterfaceGuid, Created) then
  begin
    InstanceObj.Free;
    raise EJsonDeserializationError.CreateFmt(DeserializationStrings.InterfaceNotSupported, [string(TypeInfo^.Name)]);
  end;

  InternalPopulate(InstanceObj, TJsonObject(Json),
    FRttiCache.GetTypeInfo(InstanceObj.ClassInfo, FNamingStrategy, FFluentContext, FMemberSelection));

  TValue.Make(@Created, TypeInfo, Result);
end;

function TJsonDeserializer.ConvertToTarget(Json: TJsonValue; TypeInfo: PTypeInfo): TValue;
var
  S: string;
  DT: TDateTime;
  FS: TFormatSettings;
  V: Variant;
begin
  case JsonTypeKind(TypeInfo) of
    tkInteger, tkInt64: Result := ReadIntegerValue(Json, TypeInfo);
    tkFloat:
      if (TypeInfo = System.TypeInfo(TDateTime)) or (TypeInfo = System.TypeInfo(TDate)) or (TypeInfo = System.TypeInfo(TTime)) then
      begin
        if Json.GetJsonType in [TJsonType.jtInteger, TJsonType.jtFloat] then DT := Json.AsDouble
        else
        begin
          S := Json.AsString;
          if FDateFormat <> '' then
          begin
            FS := TFormatSettings.Invariant;
            FS.ShortDateFormat := FDateFormat;
            if Pos('-', FDateFormat) > 0 then FS.DateSeparator := '-'
            else if Pos('/', FDateFormat) > 0 then FS.DateSeparator := '/'
            else if Pos('.', FDateFormat) > 0 then FS.DateSeparator := '.';
            if not TryStrToDateTime(S, DT, FS) and not TryStrToDate(S, DT, FS) then
              try DT := ISO8601ToDate(S, False) except raise EJsonDeserializationError.CreateFmt('Invalid date "%s"', [S]); end;
          end
          else
            try DT := ISO8601ToDate(S, False) except raise EJsonDeserializationError.CreateFmt('Invalid ISO date "%s"', [S]); end;
        end;
        Result := TValue.From<TDateTime>(DT).Cast(TypeInfo);
      end
      else
        // Currency, Single, Double, Extended, Comp: exact or with a
        // range check against the maximum of the target type.
        Result := ReadFloatValue(Json, TypeInfo);
    tkString, tkLString, tkWString, tkUString:
      begin
        S := Json.AsString;
        Result := TValue.From<string>(S).Cast(TypeInfo);
      end;
    tkChar, tkWChar:
      begin
        S := Json.AsString;
        if S <> '' then Result := TValue.FromOrdinal(TypeInfo, Ord(S[1])) else Result := TValue.FromOrdinal(TypeInfo, 0);
      end;
    tkSet: Result := ReadSet(Json, TypeInfo);
    tkVariant:
      begin
        case Json.GetJsonType of
          TJsonType.jtBoolean: V := Json.AsBoolean;
          TJsonType.jtInteger: V := Json.AsInteger;
          TJsonType.jtFloat: V := Json.AsDouble;
          TJsonType.jtString, TJsonType.jtDate: V := Json.AsString;
        else
          V := Json.ToJson;
        end;
        Result := TValue.From<Variant>(V);
      end;
  else
    raise EJsonDeserializationError.CreateFmt('Unsupported target type %s', [TypeInfo.Name]);
  end;
end;

end.
