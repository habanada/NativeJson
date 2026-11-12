{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Schema.Generator;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  Rtti,
  TypInfo,
  Generics.Collections,
  Math,
  DB,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  System.Math,
  Data.DB,
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.Dom.Value,
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.Primitive,
  NativeJson.Attributes,
  NativeJson.Schema.Attributes,
  NativeJson.Fluent,
  NativeJson.Rtti.Cache,
  NativeJson.Deserializer.Generics,
  NativeJson.NamingStrategy,
  NativeJson.Serializer.Writer;

type
  TJsonSchemaVersion = (
    Draft07,
    Draft2019_09,
    Draft2020_12
  );

  TSchemaLogEvent = reference to procedure(const Msg: string);
  TJsonSchemaTypeHandler = reference to function(TypeInfo: PTypeInfo): TJsonObject;
  TJsonSchemaMemberEvent = reference to procedure(Member: TJsonMemberInfo; Schema: TJsonObject);

  TJsonSchemaGenerator = class
  private
    // A single RTTI context for the whole lifetime of the generator.
    // A context that is not released keeps the RTTI pool open until program
    // end and shows up in ReportMemoryLeaksOnShutdown.
    FContext: TRttiContext;
    FVersion: TJsonSchemaVersion;
    FRttiCache: TJsonRttiCache;
    FFluent: TJsonFluentContext;
    FEnumHandling: TJsonEnumHandling;
    FMemberSelection: TJsonMemberTypes;
    FOnLog: TSchemaLogEvent;
    FBaseUri: string;
    
    FCustomHandlers: TDictionary<PTypeInfo, TJsonSchemaTypeHandler>;
    FOnBeforeMember: TJsonSchemaMemberEvent;
    FOnAfterMember: TJsonSchemaMemberEvent;

    FDefinitions: TJsonObject;
    FKnownTypes: TDictionary<PTypeInfo, string>;
    FPendingTypes: TQueue<PTypeInfo>;

    function GetSchemaUrl: string;
    function GetDefKeyword: string;
    function GetTypeName(TypeInfo: PTypeInfo): string;
    function MakeNullable(Schema: TJsonObject): TJsonObject;
    function MakeNumber(const Value: Double): TJsonNumber;
    procedure Log(const Msg: string);
    
    // --- Helper ---
    /// <summary>Returns or creates a reference to a definition ($ref).</summary>
    function GetDefinitionRef(TypeInfo: PTypeInfo): string;

    // --- Core Logic ---
    function GetTypeReferenceOrSchema(TypeInfo: PTypeInfo; ForceInline: Boolean = False): TJsonObject;
    function GenerateDefinition(TypeInfo: PTypeInfo): TJsonObject;
    function GeneratePolymorphicSchema(TypeInfo: PTypeInfo): TJsonObject;

    // --- Type Specific Generators ---
    procedure FillObjectType(Schema: TJsonObject; TypeInfo: PTypeInfo);
    procedure FillArrayType(Schema: TJsonObject; TypeInfo: PTypeInfo);
    procedure FillEnumType(Schema: TJsonObject; TypeInfo: PTypeInfo);
    procedure FillSetType(Schema: TJsonObject; TypeInfo: PTypeInfo);
    procedure FillDictionaryType(Schema: TJsonObject; KeyType, ValueType: TRttiType);
    
    function TryFillSpecialTypes(Schema: TJsonObject; TypeInfo: PTypeInfo): Boolean;

    // --- Attributes ---
    procedure ApplyClassAttributes(Schema: TJsonObject; TypeInfo: PTypeInfo);
    procedure ApplyMemberAttributes(Schema: TJsonObject; Member: TJsonMemberInfo);
    
    procedure ApplyNumericConstraints(Schema: TJsonObject; Member: TJsonMemberInfo);
    procedure ApplyStringConstraints(Schema: TJsonObject; Member: TJsonMemberInfo);
    procedure ApplyArrayConstraints(Schema: TJsonObject; Member: TJsonMemberInfo);
    procedure ApplyMetadata(Schema: TJsonObject; Member: TJsonMemberInfo);

  public
    constructor Create(FluentContext: TJsonFluentContext = nil);
    destructor Destroy; override;

    function Generate<T>: TJsonObject; overload;
    function Generate(TypeInfo: PTypeInfo): TJsonObject; overload;
    
    procedure RegisterTypeHandler<T>(Handler: TJsonSchemaTypeHandler);

    property Version: TJsonSchemaVersion read FVersion write FVersion;
    property EnumHandling: TJsonEnumHandling read FEnumHandling write FEnumHandling;
    property MemberSelection: TJsonMemberTypes read FMemberSelection write FMemberSelection;
    property BaseUri: string read FBaseUri write FBaseUri;
    
    property OnLog: TSchemaLogEvent read FOnLog write FOnLog;
    property OnBeforeMemberSchema: TJsonSchemaMemberEvent read FOnBeforeMember write FOnBeforeMember;
    property OnAfterMemberSchema: TJsonSchemaMemberEvent read FOnAfterMember write FOnAfterMember;
  end;

implementation

uses
  {$IFDEF FPC}
  Character;
  {$ELSE}
  System.Character;
  {$ENDIF}

{ TJsonSchemaGenerator }

constructor TJsonSchemaGenerator.Create(FluentContext: TJsonFluentContext);
begin
  inherited Create;
  FContext := TRttiContext.Create;
  FRttiCache := TJsonRttiCache.Get;
  FFluent := FluentContext;
  FVersion := TJsonSchemaVersion.Draft2020_12;
  FEnumHandling := TJsonEnumHandling.ByName;
  FMemberSelection := [];
  FKnownTypes := TDictionary<PTypeInfo, string>.Create;
  FPendingTypes := TQueue<PTypeInfo>.Create;
  FCustomHandlers := TDictionary<PTypeInfo, TJsonSchemaTypeHandler>.Create;
end;

destructor TJsonSchemaGenerator.Destroy;
begin
  // After a successful Generate FDefinitions is nil, because the
  // result has taken it over. Only an aborted run leaves
  // something here.
  FDefinitions.Free;
  FCustomHandlers.Free;
  FPendingTypes.Free;
  FKnownTypes.Free;
  FContext.Free;
  inherited;
end;

procedure TJsonSchemaGenerator.RegisterTypeHandler<T>(Handler: TJsonSchemaTypeHandler);
begin
  FCustomHandlers.AddOrSetValue(System.TypeInfo(T), Handler);
end;

procedure TJsonSchemaGenerator.Log(const Msg: string);
begin
  if Assigned(FOnLog) then FOnLog(Msg);
end;

function TJsonSchemaGenerator.GetSchemaUrl: string;
begin
  case FVersion of
    Draft07:      Result := 'http://json-schema.org/draft-07/schema#';
    Draft2019_09: Result := 'https://json-schema.org/draft/2019-09/schema';
    Draft2020_12: Result := 'https://json-schema.org/draft/2020-12/schema';
  end;
end;

function TJsonSchemaGenerator.GetDefKeyword: string;
begin
  if FVersion >= Draft2019_09 then Result := '$defs' else Result := 'definitions';
end;

function TJsonSchemaGenerator.GetTypeName(TypeInfo: PTypeInfo): string;
var
  S: string;
begin
  S := string(TypeInfo.Name);
  if (S.Length > 1) and (S.Chars[0] = 'T') and S.Chars[1].IsUpper then
    Result := S.Substring(1)
  else
    Result := S;
  Result := Result.Replace('<', '_').Replace('>', '').Replace(',', '_').Replace(' ', '').Replace('&', '');
end;

function TJsonSchemaGenerator.GetDefinitionRef(TypeInfo: PTypeInfo): string;
var
  TypeName: string;
begin
  // Check whether the type is already known
  if not FKnownTypes.TryGetValue(TypeInfo, TypeName) then
  begin
    TypeName := GetTypeName(TypeInfo);
    
    // Prevent name collisions
    while FDefinitions.Contains(TypeName) do
      TypeName := TypeName + '_' + IntToHex(Random(65535), 4);
      
    FKnownTypes.Add(TypeInfo, TypeName);
    FPendingTypes.Enqueue(TypeInfo);
  end;
  
  Result := '#/' + GetDefKeyword + '/' + TypeName;
end;

function TJsonSchemaGenerator.Generate<T>: TJsonObject;
begin
  Result := Generate(System.TypeInfo(T));
end;

function TJsonSchemaGenerator.Generate(TypeInfo: PTypeInfo): TJsonObject;
var
  NextType: PTypeInfo;
  TypeName: string;
  IdName, CurrentBaseUri: string;
  Primitive: TJsonObject;
  Pair: TPair<string, TJsonValue>;
begin
  if TypeInfo = nil then raise EArgumentNilException.Create('TypeInfo');
  Log('Starting schema generation for ' + string(TypeInfo.Name));
  FKnownTypes.Clear;
  FPendingTypes.Clear;
  // A leftover from an aborted earlier run belongs to nobody anymore.
  FreeAndNil(FDefinitions);
  FDefinitions := TJsonObject.Create;

  Result := TJsonObject.Create;
  try
  Result.AddPair('$schema', GetSchemaUrl);
  
  if FBaseUri <> '' then
  begin
    CurrentBaseUri := FBaseUri;
    IdName := GetTypeName(TypeInfo) + '.json';
    if not CurrentBaseUri.EndsWith('/') then CurrentBaseUri := CurrentBaseUri + '/';
    Result.AddPair('$id', CurrentBaseUri + IdName);
  end;
  
  case JsonTypeKind(TypeInfo) of
    tkClass, tkRecord, tkInterface: 
      FillObjectType(Result, TypeInfo);
    tkArray, tkDynArray: 
      FillArrayType(Result, TypeInfo);
    else 
      begin
        Primitive := GetTypeReferenceOrSchema(TypeInfo, True);
        if Primitive <> nil then
        begin
          for Pair in Primitive do
            Result.AddPair(Pair.Key, Pair.Value.Clone);
          Primitive.Free;
        end;
      end;
  end;
  
  ApplyClassAttributes(Result, TypeInfo);

  while FPendingTypes.Count > 0 do
  begin
    NextType := FPendingTypes.Dequeue;
    TypeName := FKnownTypes[NextType];
    if not FDefinitions.Contains(TypeName) then
    begin
      Log('Generating definition for ' + TypeName);
      FDefinitions.AddPair(TypeName, GenerateDefinition(NextType));
    end;
  end;

    // From here on FDefinitions belongs either to the result or to nobody.
    // The field must become empty in both cases, otherwise after leaving
    // it points to foreign or freed memory.
    if FDefinitions.Count > 0 then
    begin
      Result.AddPair(GetDefKeyword, FDefinitions);
      FDefinitions := nil;
    end
    else
      FreeAndNil(FDefinitions);
  except
    FreeAndNil(FDefinitions);
    Result.Free;
    raise;
  end;
end;

function TJsonSchemaGenerator.GetTypeReferenceOrSchema(TypeInfo: PTypeInfo; ForceInline: Boolean): TJsonObject;
var
  RType: TRttiType;
  Handler: TJsonSchemaTypeHandler;
  K, V: TRttiType;
begin
  // Check custom handlers (exact match)
  if FCustomHandlers.TryGetValue(TypeInfo, Handler) then
  begin
    Result := Handler(TypeInfo);
    Exit;
  end;

  case JsonTypeKind(TypeInfo) of
    tkInteger, tkInt64:
      begin
        Result := TJsonObject.Create;
        Result.AddPair('type', 'integer');
        Exit;
      end;
    tkFloat:
      begin
        Result := TJsonObject.Create;
        if (TypeInfo = System.TypeInfo(TDate)) or (TypeInfo = System.TypeInfo(TDateTime)) then
        begin
          Result.AddPair('type', 'string');
          Result.AddPair('format', 'date-time');
        end
        else
          Result.AddPair('type', 'number');
        Exit;
      end;
    tkString, tkUString, tkLString, tkWString, tkChar, tkWChar:
      begin
        Result := TJsonObject.Create;
        Result.AddPair('type', 'string');
        Exit;
      end;
    tkEnumeration:
      begin
        Result := TJsonObject.Create;
        if TypeInfo = System.TypeInfo(Boolean) then Result.AddPair('type', 'boolean') else FillEnumType(Result, TypeInfo);
        Exit;
      end;
    tkSet:
      begin
        Result := TJsonObject.Create;
        FillSetType(Result, TypeInfo);
        Exit;
      end;
    tkVariant:
      begin
        Result := TJsonObject.Create; 
        Exit;
      end;
  end;

  RType := FContext.GetType(TypeInfo);

  if TJsonGenericsHelper.IsCollection(RType) then
  begin
    Result := TJsonObject.Create;
    Result.AddPair('type', 'array');
    Result.AddPair('items', GetTypeReferenceOrSchema(TJsonGenericsHelper.GetCollectionElementType(RType).Handle));
    Exit;
  end;

  if TJsonGenericsHelper.IsDictionary(RType) then
  begin
    TJsonGenericsHelper.GetDictionaryKeyValueTypes(RType, K, V);
    Result := TJsonObject.Create;
    FillDictionaryType(Result, K, V);
    Exit;
  end;

  if (JsonTypeKind(TypeInfo) in [tkArray, tkDynArray]) and (not ForceInline) then
  begin
    Result := TJsonObject.Create;
    FillArrayType(Result, TypeInfo);
    Exit;
  end;

  if (JsonTypeKind(TypeInfo) in [tkClass, tkRecord, tkInterface]) and (not ForceInline) then
  begin
    Result := TJsonObject.Create;
    if TryFillSpecialTypes(Result, TypeInfo) then Exit; 
    Result.Free; 

    Result := TJsonObject.Create;
    Result.AddPair('$ref', GetDefinitionRef(TypeInfo));
    Exit;
  end;

  Result := GenerateDefinition(TypeInfo);
end;

function TJsonSchemaGenerator.GenerateDefinition(TypeInfo: PTypeInfo): TJsonObject;
var
  RType: TRttiType;
  Attr: TCustomAttribute;
  HasKnownTypes: Boolean;
begin
  Result := TJsonObject.Create;
  if TryFillSpecialTypes(Result, TypeInfo) then Exit;

  if JsonTypeKind(TypeInfo) = tkClass then
  begin
    RType := FContext.GetType(TypeInfo);
    HasKnownTypes := False;
    for Attr in RType.GetAttributes do
      if Attr is JsonKnownTypeAttribute then
      begin
        HasKnownTypes := True;
        Break;
      end;

    if HasKnownTypes then
    begin
      Result.Free;
      Result := GeneratePolymorphicSchema(TypeInfo);
      // Class-level attributes (Title, Description) apply to polymorphic types too
      ApplyClassAttributes(Result, TypeInfo);
      Exit;
    end;
  end;

  case JsonTypeKind(TypeInfo) of
    tkClass, tkRecord, tkInterface: FillObjectType(Result, TypeInfo);
    tkArray, tkDynArray: FillArrayType(Result, TypeInfo);
    else Result.AddPair('type', 'string');
  end;
  
  ApplyClassAttributes(Result, TypeInfo);
end;

procedure TJsonSchemaGenerator.FillObjectType(Schema: TJsonObject; TypeInfo: PTypeInfo);
var
  JsonTypeInfo: TJsonTypeInfo;
  PropsObj: TJsonObject;
  RequiredArr: TJsonArray;
  Member: TJsonMemberInfo;
  PropSchema: TJsonObject;
  MemberTypeInfo: PTypeInfo;
begin
  Schema.AddPair('type', 'object');
  JsonTypeInfo := FRttiCache.GetTypeInfo(TypeInfo, nil, FFluent, FMemberSelection);
  
  PropsObj := TJsonObject.Create;
  RequiredArr := TJsonArray.Create;
  
  for Member in JsonTypeInfo.Members do
  begin
    // Without RTTI type information there is nothing to describe. PropertyType/FieldType
    // can be nil, accessing .Handle would then be an access violation.
    if Member.ValueType = nil then
    begin
      Log('Member "' + Member.JsonName + '" skipped: no RTTI type information');
      Continue;
    end;
    MemberTypeInfo := Member.ValueType.Handle;

    PropSchema := GetTypeReferenceOrSchema(MemberTypeInfo);
    
    // Required fields are NOT made nullable: the deserializer raises
    // on a null value in a required field, so the schema must not
    // allow it either. Otherwise the description contradicts the
    // actual behavior.
    if (not Member.Required) and
       (Member.NullHandling = TJsonNullValueHandling.Include) and (Member.ValueType <> nil) and
       (JsonTypeKind(Member.ValueType) in [tkClass, tkInterface, tkDynArray, tkLString, tkWString, tkUString]) then
      PropSchema := MakeNullable(PropSchema);
    
    if Assigned(FOnBeforeMember) then FOnBeforeMember(Member, PropSchema);

    ApplyMetadata(PropSchema, Member);
    ApplyNumericConstraints(PropSchema, Member);
    ApplyStringConstraints(PropSchema, Member);
    ApplyArrayConstraints(PropSchema, Member);
    ApplyMemberAttributes(PropSchema, Member);
    
    if Assigned(FOnAfterMember) then FOnAfterMember(Member, PropSchema);
    
    if Member.HasDefaultValue then
    begin
       case JsonTypeKind(Member.DefaultValue) of
         tkInteger: PropSchema.AddPair('default', TJsonNumber.Create(Member.DefaultValue.AsInteger));
         tkFloat:   PropSchema.AddPair('default', MakeNumber(Member.DefaultValue.AsExtended));
         tkString, tkUString, tkWString: PropSchema.AddPair('default', JsonValueAsString(Member.DefaultValue));
         tkEnumeration: if Member.DefaultValue.TypeInfo = System.TypeInfo(Boolean) then PropSchema.AddPair('default', Member.DefaultValue.AsBoolean);
       end;
    end;

    if Member.Required then RequiredArr.Add(Member.JsonName);
    PropsObj.AddPair(Member.JsonName, PropSchema);
  end;
  
  Schema.AddPair('properties', PropsObj);
  if RequiredArr.Count > 0 then Schema.AddPair('required', RequiredArr) else RequiredArr.Free;
end;

function TJsonSchemaGenerator.GeneratePolymorphicSchema(TypeInfo: PTypeInfo): TJsonObject;
var
  RType: TRttiType;
  Attr: TCustomAttribute;
  OneOfArr: TJsonArray;
  SubClass: TClass;
  SubRef: string;
  DiscObj: TJsonObject;
  OwnerUnit: string;
  RefObj: TJsonObject;
begin
  Result := TJsonObject.Create;
  OneOfArr := TJsonArray.Create;
  Result.AddPair('oneOf', OneOfArr);

  RType := FContext.GetType(TypeInfo);

  // Unit of the base class as a search aid. The attribute only holds the short
  // name ('TOrderLine'), but FindType needs the full one
  // ('Demo.Model.TOrderLine').
  OwnerUnit := '';
  if RType is TRttiInstanceType then
    OwnerUnit := TRttiInstanceType(RType).MetaclassType.UnitName;

  for Attr in RType.GetAttributes do
  begin
    if Attr is JsonKnownTypeAttribute then
    begin
      SubClass := JsonKnownTypeAttribute(Attr).ResolveClass(OwnerUnit);
      if SubClass = nil then
      begin
        Log('Unknown type "' + JsonKnownTypeAttribute(Attr).TypeName + '" could not be resolved');
        Continue;
      end;
      SubRef := GetDefinitionRef(SubClass.ClassInfo);

      RefObj := TJsonObject.Create;
      RefObj.AddPair('$ref', SubRef);
      OneOfArr.Add(RefObj);
    end;
  end;
  
  DiscObj := TJsonObject.Create;
  DiscObj.AddPair('propertyName', '$type');
  Result.AddPair('discriminator', DiscObj);
  
  Log('Generated polymorphic schema for ' + string(TypeInfo.Name));
end;

procedure TJsonSchemaGenerator.FillArrayType(Schema: TJsonObject; TypeInfo: PTypeInfo);
var
  RType, ElementType: TRttiType;
begin
  Schema.AddPair('type', 'array');
  RType := FContext.GetType(TypeInfo);
  ElementType := nil;
  if RType is TRttiArrayType then ElementType := TRttiArrayType(RType).ElementType
  else if RType is TRttiDynamicArrayType then ElementType := TRttiDynamicArrayType(RType).ElementType;
  if ElementType <> nil then Schema.AddPair('items', GetTypeReferenceOrSchema(ElementType.Handle));
end;

procedure TJsonSchemaGenerator.FillEnumType(Schema: TJsonObject; TypeInfo: PTypeInfo);
var
  Data: PTypeData;
  I: Integer;
  EnumArr: TJsonArray;
begin
  if FEnumHandling = TJsonEnumHandling.ByInteger then
  begin
    Schema.AddPair('type', 'integer');
    Data := GetTypeData(TypeInfo);
    Schema.AddPair('minimum', TJsonNumber.Create(Data.MinValue));
    Schema.AddPair('maximum', TJsonNumber.Create(Data.MaxValue));
  end
  else
  begin
    Schema.AddPair('type', 'string');
    EnumArr := TJsonArray.Create;
    Data := GetTypeData(TypeInfo);
    for I := Data.MinValue to Data.MaxValue do
      EnumArr.Add(GetEnumName(TypeInfo, I));
    Schema.AddPair('enum', EnumArr);
  end;
end;

procedure TJsonSchemaGenerator.FillSetType(Schema: TJsonObject; TypeInfo: PTypeInfo);
var ItemsSchema: TJsonObject;
begin
  Schema.AddPair('type', 'array');
  Schema.AddPair('uniqueItems', True);
  ItemsSchema := TJsonObject.Create;
  FillEnumType(ItemsSchema, JsonSetElementType(TypeInfo));
  Schema.AddPair('items', ItemsSchema);
end;

procedure TJsonSchemaGenerator.FillDictionaryType(Schema: TJsonObject; KeyType, ValueType: TRttiType);
var
  PatternObj: TJsonObject;
begin
  Schema.AddPair('type', 'object');
  if KeyType.Handle = System.TypeInfo(TGUID) then
  begin
    PatternObj := TJsonObject.Create;
    PatternObj.AddPair('pattern', '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    Schema.AddPair('propertyNames', PatternObj);
  end;
  Schema.AddPair('additionalProperties', GetTypeReferenceOrSchema(ValueType.Handle));
end;

function TJsonSchemaGenerator.TryFillSpecialTypes(Schema: TJsonObject; TypeInfo: PTypeInfo): Boolean;
var
  RType: TRttiType;
  Items: TJsonObject;
begin
  Result := False;
  if JsonTypeKind(TypeInfo) <> tkClass then Exit;
  
  RType := FContext.GetType(TypeInfo);
  if not (RType is TRttiInstanceType) then Exit;
  
  if TRttiInstanceType(RType).MetaclassType.InheritsFrom(TStream) then
  begin
    Schema.AddPair('type', 'string');
    Schema.AddPair('contentEncoding', 'base64');
    Schema.AddPair('format', 'byte');
    Result := True;
    Exit;
  end;
  
  if TRttiInstanceType(RType).MetaclassType.InheritsFrom(TDataSet) then
  begin
    Schema.AddPair('type', 'array');
    Items := TJsonObject.Create;
    Items.AddPair('type', 'object');
    Items.AddPair('additionalProperties', True);
    Schema.AddPair('items', Items);
    Result := True;
    Exit;
  end;
  
  if TRttiInstanceType(RType).MetaclassType.InheritsFrom(TJsonValue) then
  begin
    Result := True; 
    Exit;
  end;
end;

function TJsonSchemaGenerator.MakeNumber(const Value: Double): TJsonNumber;
begin
  // FloatToStr returns the shortest lossless representation: 9999.99 instead of
  // 9999.9899999999998, and 100 instead of 100.0 for whole values.
  Result := TJsonNumber.Create(FloatToStr(Value, TFormatSettings.Invariant), True);
end;

function TJsonSchemaGenerator.MakeNullable(Schema: TJsonObject): TJsonObject;
var PropType: TJsonValue; NewType: TJsonArray; ExistingType: string;
begin
  // TryGetValue instead of GetValue: the own DOM raises an exception on a missing
  // key instead of returning nil.
  if Schema.TryGetValue('type', PropType) and (PropType is TJsonString) then
  begin
    ExistingType := PropType.AsString;
    if ExistingType <> 'null' then
    begin
      NewType := TJsonArray.Create;
      try
        NewType.Add(ExistingType);
        NewType.Add('null');
      except
        NewType.Free;
        raise;
      end;
      Schema.Remove('type');
      Schema.AddPair('type', NewType);
    end;
  end;
  Result := Schema;
end;

procedure TJsonSchemaGenerator.ApplyClassAttributes(Schema: TJsonObject; TypeInfo: PTypeInfo);
var
  RType: TRttiType;
  Attr: TCustomAttribute;
begin
  if JsonTypeKind(TypeInfo) <> tkClass then Exit;
  RType := FContext.GetType(TypeInfo);
  for Attr in RType.GetAttributes do
  begin
    if Attr is JsonTitleAttribute then Schema.AddPair('title', JsonTitleAttribute(Attr).Title)
    else if Attr is JsonDescriptionAttribute then Schema.AddPair('description', JsonDescriptionAttribute(Attr).Text)
    else if Attr is JsonDeprecatedAttribute then
    begin
      Schema.AddPair('deprecated', True);
      if JsonDeprecatedAttribute(Attr).Reason <> '' then Schema.AddPair('$comment', JsonDeprecatedAttribute(Attr).Reason);
    end
    else if Attr is JsonSchemaExtensionAttribute then
      Schema.AddPair(JsonSchemaExtensionAttribute(Attr).Key, JsonSchemaExtensionAttribute(Attr).Value);
  end;
end;

procedure TJsonSchemaGenerator.ApplyMetadata(Schema: TJsonObject; Member: TJsonMemberInfo);
var Attr: TCustomAttribute; Examples: TJsonArray;
begin
  Examples := nil;
  for Attr in Member.Member.GetAttributes do
  begin
    if Attr is JsonDescriptionAttribute then Schema.AddPair('description', JsonDescriptionAttribute(Attr).Text)
    else if Attr is JsonSchemaFormatAttribute then Schema.AddPair('format', JsonSchemaFormatAttribute(Attr).FormatName)
    else if Attr is JsonReadOnlyAttribute then Schema.AddPair('readOnly', True)
    else if Attr is JsonWriteOnlyAttribute then Schema.AddPair('writeOnly', True)
    else if Attr is JsonDeprecatedAttribute then
    begin
      Schema.AddPair('deprecated', True);
      if JsonDeprecatedAttribute(Attr).Reason <> '' then Schema.AddPair('$comment', JsonDeprecatedAttribute(Attr).Reason);
    end
    else if Attr is JsonExampleAttribute then
    begin
      if Examples = nil then begin Examples := TJsonArray.Create; Schema.AddPair('examples', Examples); end;
      Examples.Add(JsonExampleAttribute(Attr).Value);
    end;
  end;
end;

procedure TJsonSchemaGenerator.ApplyNumericConstraints(Schema: TJsonObject; Member: TJsonMemberInfo);
var Attr: TCustomAttribute;
begin
  if (Member.ValueType = nil) or not (JsonTypeKind(Member.ValueType) in [tkInteger, tkInt64, tkFloat]) then Exit;
  for Attr in Member.Member.GetAttributes do
  begin
    if Attr is JsonRangeAttribute then
    begin
      if JsonRangeAttribute(Attr).HasMin then Schema.AddPair('minimum', MakeNumber(JsonRangeAttribute(Attr).Min));
      if JsonRangeAttribute(Attr).HasMax then Schema.AddPair('maximum', MakeNumber(JsonRangeAttribute(Attr).Max));
    end
    else if Attr is JsonExclusiveRangeAttribute then
    begin
      if JsonExclusiveRangeAttribute(Attr).HasMin then Schema.AddPair('exclusiveMinimum', MakeNumber(JsonExclusiveRangeAttribute(Attr).Min));
      if JsonExclusiveRangeAttribute(Attr).HasMax then Schema.AddPair('exclusiveMaximum', MakeNumber(JsonExclusiveRangeAttribute(Attr).Max));
    end
    else if Attr is JsonMultipleOfAttribute then
      Schema.AddPair('multipleOf', MakeNumber(JsonMultipleOfAttribute(Attr).Value));
  end;
end;

procedure TJsonSchemaGenerator.ApplyStringConstraints(Schema: TJsonObject; Member: TJsonMemberInfo);
var Attr: TCustomAttribute;
begin
  if (Member.ValueType = nil) or not (JsonTypeKind(Member.ValueType) in [tkString, tkUString, tkWString, tkLString, tkChar, tkWChar]) then Exit;
  for Attr in Member.Member.GetAttributes do
  begin
    if Attr is JsonPatternAttribute then Schema.AddPair('pattern', JsonPatternAttribute(Attr).Pattern)
    else if Attr is JsonMinLengthAttribute then Schema.AddPair('minLength', TJsonNumber.Create(JsonMinLengthAttribute(Attr).Length))
    else if Attr is JsonMaxLengthAttribute then Schema.AddPair('maxLength', TJsonNumber.Create(JsonMaxLengthAttribute(Attr).Length));
  end;
end;

procedure TJsonSchemaGenerator.ApplyArrayConstraints(Schema: TJsonObject; Member: TJsonMemberInfo);
var Attr: TCustomAttribute; Val: TJsonValue;
begin
  // Without the type test minItems and maxItems would also be attached to a
  // non-array. TryGetValue, because GetValue raises here.
  if not Schema.TryGetValue('type', Val) then Exit;
  if not ((Val is TJsonString) and (Val.AsString = 'array')) then Exit;

  for Attr in Member.Member.GetAttributes do
  begin
    if Attr is JsonArrayLengthAttribute then
    begin
      if JsonArrayLengthAttribute(Attr).HasMin then Schema.AddPair('minItems', JsonArrayLengthAttribute(Attr).Min);
      if JsonArrayLengthAttribute(Attr).HasMax then Schema.AddPair('maxItems', JsonArrayLengthAttribute(Attr).Max);
    end
    else if Attr is JsonUniqueItemsAttribute then
      Schema.AddPair('uniqueItems', True);
  end;
end;

procedure TJsonSchemaGenerator.ApplyMemberAttributes(Schema: TJsonObject; Member: TJsonMemberInfo);
var Attr: TCustomAttribute;
begin
  for Attr in Member.Member.GetAttributes do
    if Attr is JsonSchemaExtensionAttribute then
      Schema.AddPair(JsonSchemaExtensionAttribute(Attr).Key, JsonSchemaExtensionAttribute(Attr).Value);
end;

end.