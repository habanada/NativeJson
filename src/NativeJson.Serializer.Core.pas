{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Serializer.Core;

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
  Variants,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  System.DateUtils,
  System.Variants,
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.Serializer.Writer,
  NativeJson.Serializer.Converter,
  NativeJson.Rtti.Cache,
  NativeJson.Attributes,
  NativeJson.NamingStrategy,
  NativeJson.Settings,
  NativeJson.Fluent;

type
  EJsonSerializationError = class(Exception);

  TJsonSerializer = class
  private
    FConverters: TObjectList<TJsonConverter>;
    FFormatting: TJsonFormatting;
    FEnumHandling: TJsonEnumHandling;
    FPreserveReferences: TJsonPreserveReferences;
    FTypeNameHandling: TJsonTypeNameHandling;
    FDateFormat: string;
    FRttiCache: TJsonRttiCache;
    FGlobalNullHandling: TJsonNullValueHandling;
    FGlobalDefaultHandling: TJsonDefaultValueHandling;
    FRecursionStack: TList<Pointer>;
    FReferenceMap: TDictionary<Pointer, string>;
    FNextRefId: Integer;
    FWrapBytes: Boolean;
    FNamingStrategy: TJsonNamingStrategyClass;
    FFluentContext: TJsonFluentContext;
    FMemberSelection: TJsonMemberTypes;
    FKeySerializers: TDictionary<PTypeInfo, TKeySerializerProc>;
    FValueTransformers: TDictionary<PTypeInfo, TValueTransformerProc>;
    function FindConverter(TypeInfo: PTypeInfo): TJsonConverter;
    function IsDefaultValue(const Value: TValue): Boolean;
    function ValuesEqual(const Left, Right: TValue): Boolean;
    function GetInstancePointer(const Value: TValue): Pointer;
    function GetRuntimeTypeInfo(const Value: TValue): PTypeInfo;
    function GetQualifiedTypeName(AClass: TClass): string;
    function GetMapKey(const Key: TValue): string;
    procedure WriteObject(Writer: TJsonWriter; const Value: TValue; DeclaredType: PTypeInfo = nil);
    procedure WriteMembers(Writer: TJsonWriter; const Value: TValue; TypeData: TJsonTypeInfo);
    procedure WriteSet(Writer: TJsonWriter; const Value: TValue);
    procedure WriteArray(Writer: TJsonWriter; const Value: TValue);
    procedure InvokeBeforeSerialize(const Value: TValue; TypeData: TJsonTypeInfo);
    procedure InvokeAfterSerialize(const Value: TValue; TypeData: TJsonTypeInfo);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Serialize(Writer: TJsonWriter; const Value: TValue); overload;
    procedure Serialize(Stream: TStream; const Value: TValue); overload;
    function SerializeToString(const Value: TValue): string; overload;
    procedure SerializeValue(Writer: TJsonWriter; const Value: TValue; MemberInfo: TJsonMemberInfo = nil; DeclaredType: PTypeInfo = nil);
    property Converters: TObjectList<TJsonConverter> read FConverters;
    property Formatting: TJsonFormatting read FFormatting write FFormatting;
    property WrapBytes: Boolean read FWrapBytes write FWrapBytes;
    property EnumHandling: TJsonEnumHandling read FEnumHandling write FEnumHandling;
    property TypeNameHandling: TJsonTypeNameHandling read FTypeNameHandling write FTypeNameHandling;
    property DateFormat: string read FDateFormat write FDateFormat;
    property PreserveReferences: TJsonPreserveReferences read FPreserveReferences write FPreserveReferences;
    property NullValueHandling: TJsonNullValueHandling read FGlobalNullHandling write FGlobalNullHandling;
    property DefaultValueHandling: TJsonDefaultValueHandling read FGlobalDefaultHandling write FGlobalDefaultHandling;
    property NamingStrategy: TJsonNamingStrategyClass read FNamingStrategy write FNamingStrategy;
    property FluentContext: TJsonFluentContext read FFluentContext write FFluentContext;
    property MemberSelection: TJsonMemberTypes read FMemberSelection write FMemberSelection;
    property KeySerializers: TDictionary<PTypeInfo, TKeySerializerProc> write FKeySerializers;
    property ValueTransformers: TDictionary<PTypeInfo, TValueTransformerProc> write FValueTransformers;
  end;

implementation

uses
  NativeJson.Converters.Standard,
  NativeJson.Dynamic;

constructor TJsonSerializer.Create;
begin
  inherited Create;
  FConverters := TObjectList<TJsonConverter>.Create(True);
  RegisterDefaultConverters(FConverters);
  FFormatting := TJsonFormatting.None;
  FEnumHandling := TJsonEnumHandling.ByName;
  FPreserveReferences := TJsonPreserveReferences.None;
  FTypeNameHandling := TJsonTypeNameHandling.None;
  FDateFormat := '';
  FGlobalNullHandling := TJsonNullValueHandling.Include;
  FGlobalDefaultHandling := TJsonDefaultValueHandling.Include;
  FNamingStrategy := TDefaultNamingStrategy;
  FMemberSelection := [];
  FRttiCache := TJsonRttiCache.Get;
  FRecursionStack := TList<Pointer>.Create;
  FReferenceMap := TDictionary<Pointer, string>.Create;
  FNextRefId := 1;
end;

destructor TJsonSerializer.Destroy;
begin
  FReferenceMap.Free;
  FRecursionStack.Free;
  FConverters.Free;
  inherited;
end;

function ObjectBehindInterface(const Value: TValue): TObject;
var
  Intf: IInterface;
begin
  Result := nil;
  if Value.Kind <> tkInterface then Exit;
  Intf := Value.AsInterface;
  if Intf = nil then Exit;
  try
    // Only applies to implementations derived from TObject. An
    // interface from a DLL or from COM has no Delphi object.
    Result := Intf as TObject;
  except
    Result := nil;
  end;
end;

function TJsonSerializer.FindConverter(TypeInfo: PTypeInfo): TJsonConverter;
var
  I: Integer;
begin
  if TypeInfo = nil then Exit(nil);
  for I := FConverters.Count - 1 downto 0 do
    if FConverters[I].CanConvert(TypeInfo) then Exit(FConverters[I]);
  Result := nil;
end;

function TJsonSerializer.IsDefaultValue(const Value: TValue): Boolean;
begin
  if Value.IsEmpty then Exit(True);
  case JsonTypeKind(Value) of
    tkInteger, tkInt64, tkEnumeration, tkSet: Result := Value.AsOrdinal = 0;
    tkFloat: Result := Value.AsExtended = 0;
    tkString, tkLString, tkWString, tkUString: Result := JsonValueAsString(Value) = '';
    tkChar, tkWChar: Result := Value.AsOrdinal = 0;
    tkClass: Result := Value.AsObject = nil;
    tkInterface: Result := Value.AsInterface = nil;
    tkPointer: Result := PPointer(Value.GetReferenceToRawData)^ = nil;
    tkClassRef: Result := Value.AsClass = nil;
    tkVariant: Result := VarIsEmpty(Value.AsVariant) or VarIsNull(Value.AsVariant);
  else
    Result := False;
  end;
end;

function TJsonSerializer.ValuesEqual(const Left, Right: TValue): Boolean;
begin
  if Left.IsEmpty or Right.IsEmpty then Exit(Left.IsEmpty and Right.IsEmpty);
  if Left.Kind <> Right.Kind then Exit(False);
  case JsonTypeKind(Left) of
    tkInteger, tkInt64, tkEnumeration, tkSet, tkChar, tkWChar: Result := Left.AsOrdinal = Right.AsOrdinal;
    tkFloat: Result := Left.AsExtended = Right.AsExtended;
    tkString, tkLString, tkWString, tkUString: Result := JsonValueAsString(Left) = JsonValueAsString(Right);
    tkClass: Result := Left.AsObject = Right.AsObject;
    tkPointer: Result := PPointer(Left.GetReferenceToRawData)^ = PPointer(Right.GetReferenceToRawData)^;
    tkClassRef: Result := Left.AsClass = Right.AsClass;
  else
    Result := Left.ToString = Right.ToString;
  end;
end;

function TJsonSerializer.GetInstancePointer(const Value: TValue): Pointer;
begin
  if Value.Kind = tkClass then Result := Value.AsObject
  else Result := Value.GetReferenceToRawData;
end;

function TJsonSerializer.GetRuntimeTypeInfo(const Value: TValue): PTypeInfo;
begin
  Result := Value.TypeInfo;
  if (Value.Kind = tkClass) and (Value.AsObject <> nil) then Result := Value.AsObject.ClassInfo;
end;

function TJsonSerializer.GetQualifiedTypeName(AClass: TClass): string;
begin
  // TRttiType.QualifiedName raises ENonPublicType as soon as the type is not in the
  // interface section of a unit - e.g. when it is declared directly in the .dpr.
  // UnitName + ClassName returns the same string without this hurdle.
  if AClass = nil then Exit('');
  Result := AClass.UnitName + '.' + AClass.ClassName;
end;

function TJsonSerializer.GetMapKey(const Key: TValue): string;
var
  Proc: TKeySerializerProc;
begin
  if not Key.IsEmpty and (FKeySerializers <> nil) and FKeySerializers.TryGetValue(Key.TypeInfo, Proc) then Exit(Proc(Key));
  if Key.IsEmpty then Exit('');
  if JsonTypeKind(Key) in [tkString, tkLString, tkWString, tkUString, tkChar, tkWChar] then Exit(JsonValueAsString(Key));
  if JsonTypeKind(Key) = tkEnumeration then Exit(GetEnumName(Key.TypeInfo, Key.AsOrdinal));
  Result := Key.ToString;
end;

procedure TJsonSerializer.Serialize(Writer: TJsonWriter; const Value: TValue);
begin
  if Writer = nil then raise EArgumentNilException.Create('Writer');
  Writer.Formatting := FFormatting;
  Writer.EnumHandling := FEnumHandling;
  Writer.PreserveReferences := FPreserveReferences;
  Writer.TypeNameHandling := FTypeNameHandling;
  Writer.WrapBytes := FWrapBytes;
  FRecursionStack.Clear;
  FReferenceMap.Clear;
  FNextRefId := 1;
  SerializeValue(Writer, Value);
end;

procedure TJsonSerializer.Serialize(Stream: TStream; const Value: TValue);
var
  Writer: TJsonWriter;
begin
  Writer := TJsonWriter.Create(Stream);
  try
    Serialize(Writer, Value);
  finally
    Writer.Free;
  end;
end;

function TJsonSerializer.SerializeToString(const Value: TValue): string;
var
  Writer: TJsonWriter;
begin
  Writer := TJsonWriter.Create;
  try
    Serialize(Writer, Value);
    Result := Writer.ToJson;
  finally
    Writer.Free;
  end;
end;

procedure TJsonSerializer.InvokeBeforeSerialize(const Value: TValue; TypeData: TJsonTypeInfo);
var
  Obj: TObject;
begin
  if Value.Kind <> tkClass then Exit;
  Obj := Value.AsObject;
  if Obj = nil then Exit;
  if TypeData.OnSerializing <> nil then TypeData.OnSerializing.Invoke(Obj, []);
  if Assigned(TypeData.FluentOnSerializing) then TypeData.FluentOnSerializing(Obj);
end;

procedure TJsonSerializer.InvokeAfterSerialize(const Value: TValue; TypeData: TJsonTypeInfo);
var
  Obj: TObject;
begin
  if Value.Kind <> tkClass then Exit;
  Obj := Value.AsObject;
  if Obj = nil then Exit;
  if TypeData.OnSerialized <> nil then TypeData.OnSerialized.Invoke(Obj, []);
  if Assigned(TypeData.FluentOnSerialized) then TypeData.FluentOnSerialized(Obj);
end;

procedure TJsonSerializer.WriteMembers(Writer: TJsonWriter; const Value: TValue; TypeData: TJsonTypeInfo);
var
  Member: TJsonMemberInfo;
  MemberValue: TValue;
  InstancePtr: Pointer;
  ShouldWrite: Boolean;
  Proc: TValueTransformerProc;
  ChildType: TJsonTypeInfo;
  MemberType: PTypeInfo;
begin
  InstancePtr := GetInstancePointer(Value);
  for Member in TypeData.Members do
  begin
    if not Member.IsReadable then Continue;
    ShouldWrite := True;
    if Member.ShouldSerializeMethod <> nil then ShouldWrite := Member.ShouldSerializeMethod.Invoke(Value, []).AsBoolean;
    if ShouldWrite and Assigned(Member.ShouldSerializeDelegate) and (Value.Kind = tkClass) then ShouldWrite := Member.ShouldSerializeDelegate(Value.AsObject);
    if not ShouldWrite then Continue;
    MemberValue := Member.GetValue(InstancePtr);
    if Assigned(Member.ValueTransformer) then MemberValue := Member.ValueTransformer(MemberValue);
    if not MemberValue.IsEmpty and (FValueTransformers <> nil) and FValueTransformers.TryGetValue(MemberValue.TypeInfo, Proc) then Proc(Member.JsonName, MemberValue);
    if (Member.NullHandling = TJsonNullValueHandling.Ignore) or (FGlobalNullHandling = TJsonNullValueHandling.Ignore) then
      if MemberValue.IsEmpty or ((MemberValue.Kind = tkClass) and (MemberValue.AsObject = nil)) then Continue;
    if Member.HasDefaultValue and ValuesEqual(MemberValue, Member.DefaultValue) and (Member.DefaultHandling = TJsonDefaultValueHandling.Ignore) then Continue;
    if ((Member.DefaultHandling = TJsonDefaultValueHandling.Ignore) or (FGlobalDefaultHandling = TJsonDefaultValueHandling.Ignore)) and not Member.HasDefaultValue and IsDefaultValue(MemberValue) then Continue;
    case Member.Include of
      TJsonInclude.NonNull: if MemberValue.IsEmpty or ((MemberValue.Kind = tkClass) and (MemberValue.AsObject = nil)) then Continue;
      TJsonInclude.NonDefault: if IsDefaultValue(MemberValue) then Continue;
      TJsonInclude.NonEmpty: if IsDefaultValue(MemberValue) then Continue;
    end;
    if Member.IsUnwrapped and not MemberValue.IsEmpty and (MemberValue.Kind in [tkClass, tkRecord]) then
    begin
      if (MemberValue.Kind = tkClass) and (MemberValue.AsObject = nil) then Continue;
      ChildType := FRttiCache.GetTypeInfo(GetRuntimeTypeInfo(MemberValue), FNamingStrategy, FFluentContext, FMemberSelection);
      WriteMembers(Writer, MemberValue, ChildType);
      Continue;
    end;
    Writer.WritePropertyName(Member.JsonName);
    if Member.IsRaw then
    begin
      if MemberValue.IsEmpty then Writer.WriteNull else Writer.WriteRaw(JsonValueAsString(MemberValue));
      Continue;
    end;
    // With TypeNameHandling.Auto the declared type of the member decides
    // whether $type is written.
    if Member.ValueType <> nil then MemberType := Member.ValueType.Handle else MemberType := nil;
    SerializeValue(Writer, MemberValue, Member, MemberType);
  end;
end;

procedure TJsonSerializer.WriteObject(Writer: TJsonWriter; const Value: TValue; DeclaredType: PTypeInfo);
var
  DeclaredTypeInfo, RuntimeTypeInfo: PTypeInfo;
  TypeData: TJsonTypeInfo;
  ObjectPtr: Pointer;
  RefId: string;
  WriteType: Boolean;
  DiscriminatorValue, KeyText: string;
  Config: TJsonTypeConfig;
  RegisteredClass: TClass;
begin
  // For classes the TValue carries the runtime class. For TypeNameHandling.Auto
  // we need the type declared at this position, which only the caller knows.
  if DeclaredType <> nil then DeclaredTypeInfo := DeclaredType else DeclaredTypeInfo := Value.TypeInfo;
  RuntimeTypeInfo := GetRuntimeTypeInfo(Value);
  TypeData := FRttiCache.GetTypeInfo(RuntimeTypeInfo, FNamingStrategy, FFluentContext, FMemberSelection);
  ObjectPtr := nil;
  if Value.Kind = tkClass then ObjectPtr := Value.AsObject;
  if ObjectPtr <> nil then
  begin
    if FPreserveReferences = TJsonPreserveReferences.Objects then
    begin
      if FReferenceMap.TryGetValue(ObjectPtr, RefId) then
      begin
        Writer.WriteStartObject;
        Writer.WritePropertyName('$ref');
        Writer.WriteValue(RefId);
        Writer.WriteEndObject;
        Exit;
      end;
      RefId := IntToStr(FNextRefId);
      Inc(FNextRefId);
      FReferenceMap.Add(ObjectPtr, RefId);
    end
    else
    begin
      if FRecursionStack.Contains(ObjectPtr) then raise EJsonSerializationError.CreateFmt('Reference cycle detected in %s. Enable PreserveReferences.Objects.', [RuntimeTypeInfo.Name]);
      FRecursionStack.Add(ObjectPtr);
    end;
  end;
  try
    InvokeBeforeSerialize(Value, TypeData);
    Writer.WriteStartObject;
    if (ObjectPtr <> nil) and (FPreserveReferences = TJsonPreserveReferences.Objects) then
    begin
      Writer.WritePropertyName('$id');
      Writer.WriteValue(RefId);
    end;
    WriteType := FTypeNameHandling = TJsonTypeNameHandling.Objects;
    if FTypeNameHandling = TJsonTypeNameHandling.Auto then WriteType := (DeclaredTypeInfo <> RuntimeTypeInfo);
    if WriteType and (Value.Kind = tkClass) and (Value.AsObject <> nil) then
    begin
      // If a dedicated discriminator field is configured for this type,
      // THAT is written instead of $type with the Delphi class name.
      // Without configuration both loops stay empty and it takes
      // the old route unchanged.
      DiscriminatorValue := '';
      KeyText := '';
      if FFluentContext <> nil then
      begin
        RegisteredClass := Value.AsObject.ClassType;
        while (RegisteredClass <> nil) and (DiscriminatorValue = '') do
        begin
          if RegisteredClass.ClassInfo <> nil then
          begin
            Config := FFluentContext.GetConfig(RegisteredClass.ClassInfo);
            if (Config <> nil) and (Config.InternalDiscriminator <> '') then
            begin
              DiscriminatorValue := Config.InternalDiscriminator;
              Config.FindSubTypeKey(Value.AsObject.ClassType, KeyText);
            end;
          end;
          RegisteredClass := RegisteredClass.ClassParent;
        end;
      end;
      if (DiscriminatorValue <> '') and (KeyText <> '') then
      begin
        Writer.WritePropertyName(DiscriminatorValue);
        Writer.WriteValue(KeyText);
      end
      else
      begin
        // Also when a discriminator field is configured but this
        // class was not registered: then rather $type than
        // nothing - otherwise the output silently becomes unreadable.
        Writer.WritePropertyName('$type');
        Writer.WriteValue(GetQualifiedTypeName(Value.AsObject.ClassType));
      end;
    end;
    WriteMembers(Writer, Value, TypeData);
    Writer.WriteEndObject;
    InvokeAfterSerialize(Value, TypeData);
  finally
    if (ObjectPtr <> nil) and (FPreserveReferences <> TJsonPreserveReferences.Objects) then FRecursionStack.Remove(ObjectPtr);
  end;
end;

procedure TJsonSerializer.WriteSet(Writer: TJsonWriter; const Value: TValue);
var
  Element: PTypeInfo;
  Ordinal: Integer;
begin
  Element := JsonSetElementType(Value.TypeInfo);
  Writer.WriteStartArray;
  for Ordinal in JsonSetOrdinals(Value) do
    if (FEnumHandling = TJsonEnumHandling.ByInteger) or (Element = nil) or (Element^.Kind <> tkEnumeration) then Writer.WriteValue(Ordinal)
    else Writer.WriteValue(GetEnumName(Element, Ordinal));
  Writer.WriteEndArray;
end;

procedure TJsonSerializer.WriteArray(Writer: TJsonWriter; const Value: TValue);
var
  I: Integer;
  Ctx: TRttiContext;
  RType: TRttiType;
  ElementType: PTypeInfo;
begin
  ElementType := nil;
  Ctx := TRttiContext.Create;
  try
    RType := Ctx.GetType(Value.TypeInfo);
    if (RType is TRttiArrayType) and (TRttiArrayType(RType).ElementType <> nil) then
      ElementType := TRttiArrayType(RType).ElementType.Handle
    else if (RType is TRttiDynamicArrayType) and (TRttiDynamicArrayType(RType).ElementType <> nil) then
      ElementType := TRttiDynamicArrayType(RType).ElementType.Handle;
  finally
    Ctx.Free;
  end;
  Writer.WriteStartArray;
  for I := 0 to Value.GetArrayLength - 1 do SerializeValue(Writer, Value.GetArrayElement(I), nil, ElementType);
  Writer.WriteEndArray;
end;

procedure TJsonSerializer.SerializeValue(Writer: TJsonWriter; const Value: TValue; MemberInfo: TJsonMemberInfo; DeclaredType: PTypeInfo);
var
  LObject: TObject;
  Converter: TJsonConverter;
  ConverterClass: TClass;
  RType: TRttiType;
  Ctx: TRttiContext;
  Map: IDynamicMapIterable;
  Iterable: IDynamicIterable;
  Key, Item: TValue;
  LFormat: string;
  V: Variant;
begin
  if Value.IsEmpty then
  begin
    Writer.WriteNull;
    Exit;
  end;
  if (MemberInfo <> nil) and (MemberInfo.ConverterClass <> nil) then
  begin
    ConverterClass := MemberInfo.ConverterClass;
    if ConverterClass.InheritsFrom(TJsonConverter) then
    begin
      Converter := TJsonConverterClass(ConverterClass).Create;
      try
        if Converter.CanWrite then
        begin
          Converter.WriteJson(Writer, Value, Self);
          Exit;
        end;
      finally
        Converter.Free;
      end;
    end;
  end;
  Converter := FindConverter(Value.TypeInfo);
  if (Converter <> nil) and Converter.CanWrite then
  begin
    Converter.WriteJson(Writer, Value, Self);
    Exit;
  end;
  case JsonTypeKind(Value) of
    tkInteger: Writer.WriteValue(Value.AsInteger);
    tkInt64:
      // Unsigned 64-bit types have the same bits as Int64, but a
      // different meaning. Via AsInt64 High(UInt64) becomes -1.
      if GetTypeData(Value.TypeInfo)^.MinInt64Value < 0 then
        Writer.WriteValue(Value.AsInt64)
      else
        Writer.WriteRaw(UIntToStr(Value.AsUInt64));
    tkString, tkLString, tkWString, tkUString, tkChar, tkWChar: Writer.WriteValue(JsonValueAsString(Value));
    tkFloat:
      if (Value.TypeInfo = System.TypeInfo(TDateTime)) or (Value.TypeInfo = System.TypeInfo(TDate)) or (Value.TypeInfo = System.TypeInfo(TTime)) then
      begin
        LFormat := FDateFormat;
        if (MemberInfo <> nil) and (MemberInfo.FormatString <> '') then LFormat := MemberInfo.FormatString;
        if LFormat <> '' then Writer.WriteValue(FormatDateTime(LFormat, Value.AsExtended, TFormatSettings.Invariant)) else Writer.WriteValue(DateToISO8601(Value.AsExtended, False));
      end
      else if Value.TypeInfo = System.TypeInfo(Currency) then
        Writer.WriteRaw(CurrencyToJson(Value.AsType<Currency>))
      else if GetTypeData(Value.TypeInfo)^.FloatType = ftSingle then
        // Written via Extended a Single shows digits it never
        // had: 0.1 becomes 0.100000001490116.
        Writer.WriteRaw(SingleToJson(Value.AsType<Single>))
      else Writer.WriteValue(Value.AsExtended);
    tkEnumeration:
      if Value.TypeInfo = System.TypeInfo(Boolean) then Writer.WriteValue(Value.AsBoolean)
      else if FEnumHandling = TJsonEnumHandling.ByInteger then Writer.WriteValue(Value.AsOrdinal)
      else Writer.WriteValue(GetEnumName(Value.TypeInfo, Value.AsOrdinal));
    tkSet: WriteSet(Writer, Value);
    tkArray, tkDynArray: WriteArray(Writer, Value);
    tkRecord: WriteObject(Writer, Value);
    tkClass:
      begin
        if Value.AsObject = nil then
        begin
          Writer.WriteNull;
          Exit;
        end;
        Ctx := TRttiContext.Create;
        try
          RType := Ctx.GetType(Value.AsObject.ClassInfo);
          if TDynamicTypeHelper.TryGetMap(RType, Value, Map) then
          begin
            Writer.WriteStartObject;
            while Map.MoveNext do
            begin
              Key := Map.GetCurrentKey;
              Writer.WritePropertyName(GetMapKey(Key));
              SerializeValue(Writer, Map.GetCurrentValue, nil, Map.GetValueType);
            end;
            Writer.WriteEndObject;
          end
          else if TDynamicTypeHelper.TryGetIterable(RType, Value, Iterable) then
          begin
            Writer.WriteStartArray;
            while Iterable.MoveNext do
            begin
              Item := Iterable.GetCurrent;
              SerializeValue(Writer, Item, nil, Iterable.GetElementType);
            end;
            Writer.WriteEndArray;
          end
          else WriteObject(Writer, Value, DeclaredType);
        finally
          Ctx.Free;
        end;
      end;
    tkVariant:
      begin
        V := Value.AsVariant;
        if VarIsNull(V) or VarIsEmpty(V) then Writer.WriteNull
        else if VarIsType(V, varBoolean) then Writer.WriteValue(Boolean(V))
        else if VarIsOrdinal(V) then Writer.WriteValue(Int64(V))
        else if VarIsFloat(V) then Writer.WriteValue(Double(V))
        else Writer.WriteValue(VarToStr(V));
      end;
    tkInterface:
      begin
        // Describe the object behind the interface, not the interface.
        // Value.ToString would otherwise yield "(interface @ 02D24A10)".
        LObject := ObjectBehindInterface(Value);
        if LObject = nil then Writer.WriteNull else WriteObject(Writer, TValue.From<TObject>(LObject));
      end;
    tkPointer, tkClassRef: if IsDefaultValue(Value) then Writer.WriteNull else Writer.WriteValue(Value.ToString);
  else
    Writer.WriteValue(Value.ToString);
  end;
end;

end.
