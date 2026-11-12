{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Converters.Standard;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  TypInfo,
  Rtti,
  Generics.Collections,
  SyncObjs,
  System.NetEncoding,
  DateUtils,
  System.TimeSpan,
  Types,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  System.Rtti,
  System.Generics.Collections,
  System.SyncObjs,
  System.NetEncoding,
  System.DateUtils,
  System.TimeSpan, // for TTimeSpan
  System.Types,    // for TPoint, TRect, TSize
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.Serializer.Converter,
  NativeJson.Serializer.Writer,
  NativeJson.Core.Reader,
  NativeJson.Core.Tokens;

type
  // ===========================================================================
  // SYSTEM TYPES
  // ===========================================================================

  /// <summary>
  ///   Serializes TGUID as a canonical string: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
  /// </summary>
  TGuidConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TStringBuilder as a plain string.
  /// </summary>
  TStringBuilderConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TValue (unwraps the content transparently).
  /// </summary>
  TValueConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  // ===========================================================================
  // TIME & DATE
  // ===========================================================================

  /// <summary>
  ///   Serializes TTimeSpan as a string (c format) or ticks.
  /// </summary>
  TTimeSpanConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TDateTime as a Unix timestamp (seconds).
  /// </summary>
  TUnixDateTimeConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TDateTime as a Java timestamp (milliseconds).
  /// </summary>
  TMillisecondEpochConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  // ===========================================================================
  // COLLECTIONS & STREAMS
  // ===========================================================================

  /// <summary>
  ///   Serializes TBytes (and any other dynamic byte array) as a
  ///   Base64 string instead of a list of numbers.
  ///
  ///   Without this converter every byte is written as a separate number:
  ///   one megabyte of payload becomes about four megabytes of text, and with
  ///   large amounts of data the string buffer runs into the 2^31 limit.
  ///   Base64 needs only about a third more than the raw data.
  ///
  ///   When reading, the old list of numbers is still accepted,
  ///   so existing files do not become unreadable.
  /// </summary>
  TBytesConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TStream as a Base64 string.
  /// </summary>
  TStreamConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TStrings/TStringList as a JSON array of strings ["A", "B"].
  /// </summary>
  TStringsConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TCollection as a JSON array of objects.
  /// </summary>
  TCollectionConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  // ===========================================================================
  // GEOMETRY (System.Types) - platform independent
  // ===========================================================================

  /// <summary>
  ///   Serializes TPoint and TPointF as {"x": 1, "y": 2}.
  /// </summary>
  TPointConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TRect and TRectF as {"left":.., "top":.., "right":.., "bottom":..}.
  /// </summary>
  TRectConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TSize and TSizeF as {"width":.., "height":..}.
  /// </summary>
  TSizeConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Every class with LoadFromStream and SaveToStream is treated as Base64
  ///   - regardless of whether it descends from TStream.
  /// </summary>
  TStreamableConverter = class(TJsonConverter)
  private
    class var FCache: TDictionary<PTypeInfo, Boolean>;
    class var FLock: TCriticalSection;
    class function HasStreamMethods(TypeInfo: PTypeInfo): Boolean; static;
    class function FindMethod(RType: TRttiType; const Name: string): TRttiMethod; static;
  public
    class constructor Create;
    class destructor Destroy;
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

procedure RegisterDefaultConverters(AList: TObjectList<TJsonConverter>);

implementation

// Resolve circular references
uses
  NativeJson.Serializer.Core,
  NativeJson.Deserializer.Core,
  NativeJson.Deserializer.Activator,
  NativeJson.Dom.Value;

procedure RegisterDefaultConverters(AList: TObjectList<TJsonConverter>);
begin
  // System
  AList.Add(TGUIDConverter.Create);
  AList.Add(TStringBuilderConverter.Create);
  AList.Add(TValueConverter.Create);
  
  // Time
  AList.Add(TTimeSpanConverter.Create);
  
  // Binary data
  AList.Add(TBytesConverter.Create);

  // Classes
  // The general route first, then the special one: FindConverter walks the
  // list from the end, so the TStreamConverter registered later
  // wins for real TStream descendants.
  AList.Add(TStreamableConverter.Create);
  AList.Add(TStreamConverter.Create);
  AList.Add(TStringsConverter.Create);
  AList.Add(TCollectionConverter.Create);
  
  // Geometry
  AList.Add(TPointConverter.Create);
  AList.Add(TRectConverter.Create);
  AList.Add(TSizeConverter.Create);
end;

{ TStreamableConverter }

class constructor TStreamableConverter.Create;
begin
  FCache := TDictionary<PTypeInfo, Boolean>.Create;
  FLock := TCriticalSection.Create;
end;

class destructor TStreamableConverter.Destroy;
begin
  FCache.Free;
  FLock.Free;
end;

class function TStreamableConverter.FindMethod(RType: TRttiType; const Name: string): TRttiMethod;
var
  M: TRttiMethod;
  P: TArray<TRttiParameter>;
begin
  Result := nil;
  for M in RType.GetMethods do
  begin
    if not SameText(M.Name, Name) then Continue;
    P := M.GetParameters;
    if Length(P) <> 1 then Continue;
    if (P[0].ParamType = nil) or (P[0].ParamType.TypeKind <> tkClass) then Continue;
    if not TRttiInstanceType(P[0].ParamType).MetaclassType.InheritsFrom(TStream) then Continue;
    Exit(M);
  end;
end;

class function TStreamableConverter.HasStreamMethods(TypeInfo: PTypeInfo): Boolean;
var
  Ctx: TRttiContext;
  RType: TRttiType;
begin
  // Cached, because CanConvert runs for EVERY value and a
  // method lookup through RTTI would be far too expensive there.
  FLock.Enter;
  try
    if FCache.TryGetValue(TypeInfo, Result) then Exit;
  finally
    FLock.Leave;
  end;

  Result := False;
  Ctx := TRttiContext.Create;
  try
    RType := Ctx.GetType(TypeInfo);
    if (RType is TRttiInstanceType) and
       not TRttiInstanceType(RType).MetaclassType.InheritsFrom(TStream) then
      Result := (FindMethod(RType, 'SaveToStream') <> nil) and
                (FindMethod(RType, 'LoadFromStream') <> nil);
  finally
    Ctx.Free;
  end;

  FLock.Enter;
  try
    FCache.AddOrSetValue(TypeInfo, Result);
  finally
    FLock.Leave;
  end;
end;

function TStreamableConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := (TypeInfo <> nil) and (TypeInfo.Kind = tkClass) and HasStreamMethods(TypeInfo);
end;

procedure TStreamableConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  Obj: TObject;
  Buffer: TMemoryStream;
  RawBytes: TBytes;
  Ctx: TRttiContext;
  Method: TRttiMethod;
begin
  Obj := nil;
  if Value.IsObject then Obj := Value.AsObject;
  if Obj = nil then
  begin
    Writer.WriteNull;
    Exit;
  end;
  Ctx := TRttiContext.Create;
  Buffer := TMemoryStream.Create;
  try
    Method := FindMethod(Ctx.GetType(Obj.ClassType), 'SaveToStream');
    if Method = nil then raise EJsonConverterError.CreateFmt('SaveToStream not found on %s', [Obj.ClassName]);
    Method.Invoke(Obj, [Buffer]);
    SetLength(RawBytes, Buffer.Size);
    if Buffer.Size > 0 then
    begin
      Buffer.Position := 0;
      Buffer.ReadBuffer(RawBytes[0], Buffer.Size);
    end;
    Writer.WriteValue(TNetEncoding.Base64String.EncodeBytesToString(RawBytes));
  finally
    Buffer.Free;
    Ctx.Free;
  end;
end;

function TStreamableConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  Obj: TObject;
  Buffer: TMemoryStream;
  RawBytes: TBytes;
  Ctx: TRttiContext;
  Method: TRttiMethod;
  CreatedValue: TValue;
begin
  if Reader.TokenType = TJsonToken.Null then
  begin
    TValue.Make(nil, ObjectType, Result);
    Exit;
  end;

  if not ExistingValue.IsEmpty and ExistingValue.IsObject and (ExistingValue.AsObject <> nil) then
  begin
    Result := ExistingValue;
    Obj := ExistingValue.AsObject;
  end
  else
  begin
    CreatedValue := TJsonActivator.CreateInstance(ObjectType);
    if not CreatedValue.IsObject or (CreatedValue.AsObject = nil) then
      raise EJsonConverterError.CreateFmt('Cannot create %s', [ObjectType.Name]);
    Result := CreatedValue;
    Obj := CreatedValue.AsObject;
  end;

  RawBytes := TNetEncoding.Base64String.DecodeStringToBytes(Reader.Value);
  Ctx := TRttiContext.Create;
  Buffer := TMemoryStream.Create;
  try
    if Length(RawBytes) > 0 then Buffer.WriteBuffer(RawBytes[0], Length(RawBytes));
    Buffer.Position := 0;
    Method := FindMethod(Ctx.GetType(Obj.ClassType), 'LoadFromStream');
    if Method = nil then raise EJsonConverterError.CreateFmt('LoadFromStream not found on %s', [Obj.ClassName]);
    Method.Invoke(Obj, [Buffer]);
  finally
    Buffer.Free;
    Ctx.Free;
  end;
end;

{ TGUIDConverter }

function TGUIDConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TGUID);
end;

procedure TGUIDConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
begin
  Writer.WriteValue(Value.AsType<TGUID>.ToString.Trim(['{', '}']));
end;

function TGUIDConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
begin
  if Reader.TokenType = TJsonToken.Str then
    Result := TValue.From<TGUID>(TGUID.Create('{' + Reader.Value + '}'))
  else if Reader.TokenType = TJsonToken.Null then
    Result := TValue.From<TGUID>(Default(TGUID))
  else
    Result := TValue.Empty;
end;

{ TBytesConverter }

function TBytesConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  // Deliberately WITHOUT TRttiContext: FindConverter walks this list for every
  // single value. A context per call would be the most expensive
  // mistake in the whole write path. The element type information is
  // directly in the type data.
  Result := False;
  if (TypeInfo = nil) or (TypeInfo.Kind <> tkDynArray) then Exit;
  Result := JsonDynArrayElementType(TypeInfo) = System.TypeInfo(Byte);
end;

procedure TBytesConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  Bytes: TBytes;
  I, Len: Integer;
begin
  if Value.IsEmpty then
  begin
    Writer.WriteNull;
    Exit;
  end;

  if Value.TypeInfo = System.TypeInfo(TBytes) then
    Bytes := Value.AsType<TBytes>
  else
  begin
    // Other byte array type: copy element by element, because AsType<TBytes>
    // does not work here.
    Len := Value.GetArrayLength;
    SetLength(Bytes, Len);
    for I := 0 to Len - 1 do
      Bytes[I] := Byte(Value.GetArrayElement(I).AsOrdinal);
  end;

  // Base64String instead of Base64: the MIME variant wraps every 76 characters,
  // and every line break ends up as \r\n in the JSON - that inflates the
  // output by about seven percent without benefiting anyone.
  if Writer.WrapBytes then
  begin
    Writer.WriteStartObject;
    Writer.WritePropertyName('@bytes');
    Writer.WriteValue(TNetEncoding.Base64String.EncodeBytesToString(Bytes));
    Writer.WriteEndObject;
    Exit;
  end;
  Writer.WriteValue(TNetEncoding.Base64String.EncodeBytesToString(Bytes));
end;

function DecodeWrappedBase64(const Text: string): TBytes;
var
  Normalized: string;
begin
  Normalized := StringReplace(StringReplace(Text, '-', '+', [rfReplaceAll]), '_', '/', [rfReplaceAll]);
  while Length(Normalized) mod 4 <> 0 do Normalized := Normalized + '=';
  try
    Result := TNetEncoding.Base64String.DecodeStringToBytes(Normalized);
  except
    on E: Exception do
      raise EJsonConverterError.CreateFmt('Invalid Base64 data: %s', [E.Message]);
  end;
end;

function TBytesConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  Bytes: TBytes;
  Buffer: TList<Byte>;
  Len: NativeInt;
  I: Integer;
  MemberName, Encoded: string;
begin
  TValue.Make(nil, ObjectType, Result);

  if Reader.TokenType = TJsonToken.Null then Exit;

  if Reader.TokenType = TJsonToken.Str then
  begin
    try
      // Base64String also reads wrapped data correctly
      Bytes := TNetEncoding.Base64String.DecodeStringToBytes(Reader.Value);
    except
      on E: Exception do
        raise EJsonConverterError.CreateFmt('Invalid Base64 data: %s', [E.Message]);
    end;
  end
  else if Reader.TokenType = TJsonToken.StartObject then
  begin
    Encoded := '';
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndObject then Break;
      if Reader.TokenType <> TJsonToken.PropertyName then Continue;
      MemberName := Reader.Value;
      if not Reader.Read then raise EJsonConverterError.Create('Unexpected end of a byte array wrapper');
      if (MemberName = '@bytes') and (Reader.TokenType = TJsonToken.Str) then Encoded := Reader.Value
      else raise EJsonConverterError.Create('Unexpected member in a byte array wrapper');
    end;
    Bytes := DecodeWrappedBase64(Encoded);
  end
  else if Reader.TokenType = TJsonToken.StartArray then
  begin
    // Old format: list of single numbers
    Buffer := TList<Byte>.Create;
    try
      while Reader.Read do
      begin
        if Reader.TokenType = TJsonToken.EndArray then Break;
        if Reader.TokenType in [TJsonToken.Integer, TJsonToken.Float] then
          Buffer.Add(Byte(Reader.ValueAsInt))
        else if Reader.TokenType = TJsonToken.Null then
          Buffer.Add(0)
        else
          raise EJsonConverterError.Create('Unexpected value in byte array');
      end;
      Bytes := Buffer.ToArray;
    finally
      Buffer.Free;
    end;
  end
  else
    raise EJsonConverterError.Create('Expected a Base64 string, a number array or a byte array wrapper');

  // Fast path for the usual TBytes
  if ObjectType = System.TypeInfo(TBytes) then
  begin
    Result := TValue.From<TBytes>(Bytes);
    Exit;
  end;

  // Other byte array type: set the length and fill element by element
  Len := Length(Bytes);
  DynArraySetLength(PPointer(Result.GetReferenceToRawData)^, ObjectType, 1, @Len);
  for I := 0 to Length(Bytes) - 1 do
    Result.SetArrayElement(I, TValue.From<Byte>(Bytes[I]));
end;

{ TStringBuilderConverter }

function TStringBuilderConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TStringBuilder);
end;

procedure TStringBuilderConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
begin
  if Value.AsObject = nil then
    Writer.WriteNull
  else
    Writer.WriteValue(TStringBuilder(Value.AsObject).ToString);
end;

function TStringBuilderConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var SB: TStringBuilder;
begin
  if Reader.TokenType = TJsonToken.Null then Exit(TValue.From<TStringBuilder>(nil));
  
  if (ExistingValue.IsObject) and (ExistingValue.AsObject <> nil) then
  begin
    SB := TStringBuilder(ExistingValue.AsObject);
    SB.Clear;
    SB.Append(Reader.Value);
    Result := ExistingValue;
  end
  else
    Result := TValue.From<TStringBuilder>(TStringBuilder.Create(Reader.Value));
end;

{ TValueConverter }

function TValueConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TValue);
end;

procedure TValueConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var InnerValue: TValue;
begin
  InnerValue := Value.AsType<TValue>;
  if InnerValue.IsEmpty then
    Writer.WriteNull
  else
    TJsonSerializer(Serializer).SerializeValue(Writer, InnerValue);
end;

function TValueConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var DeserializerObj: TJsonDeserializer; Dom: TJsonValue;
begin
  // Read as DOM, because the target type is unknown
  DeserializerObj := TJsonDeserializer(Serializer);
  Dom := DeserializerObj.BuildDomFromCurrent(Reader);
  // Wrap the DOM in a TValue
  Result := TValue.From<TValue>(TValue.From<TJsonValue>(Dom));
end;

{ TTimeSpanConverter }

function TTimeSpanConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TTimeSpan);
end;

procedure TTimeSpanConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
begin
  // Standard format: "1.02:03:04.555" (days.hours:minutes:seconds.millis)
  Writer.WriteValue(Value.AsType<TTimeSpan>.ToString);
end;

function TTimeSpanConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
begin
  if Reader.TokenType = TJsonToken.Str then
    Result := TValue.From<TTimeSpan>(TTimeSpan.Parse(Reader.Value))
  else if Reader.TokenType = TJsonToken.Integer then
    Result := TValue.From<TTimeSpan>(TTimeSpan.FromTicks(Reader.ValueAsInt))
  else
    Result := TValue.From<TTimeSpan>(TTimeSpan.Zero);
end;

{ TUnixDateTimeConverter }

function TUnixDateTimeConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := (TypeInfo = System.TypeInfo(TDateTime)) or (TypeInfo = System.TypeInfo(TDate));
end;

procedure TUnixDateTimeConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
begin
  Writer.WriteValue(DateTimeToUnix(Value.AsExtended, False));
end;

function TUnixDateTimeConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
begin
  if Reader.TokenType = TJsonToken.Integer then
    Result := TValue.From<TDateTime>(UnixToDateTime(Reader.ValueAsInt, False))
  else if Reader.TokenType = TJsonToken.Null then
    Result := TValue.From<TDateTime>(0)
  else
    Result := TValue.From<TDateTime>(ISO8601ToDate(Reader.Value));
end;

{ TMillisecondEpochConverter }

function TMillisecondEpochConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := (TypeInfo = System.TypeInfo(TDateTime));
end;

procedure TMillisecondEpochConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
begin
  // Java style: milliseconds since 1970
  Writer.WriteValue(DateTimeToUnix(Value.AsExtended, False) * 1000);
end;

function TMillisecondEpochConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
begin
  if Reader.TokenType = TJsonToken.Integer then
    Result := TValue.From<TDateTime>(UnixToDateTime(Reader.ValueAsInt div 1000, False))
  else
    Result := TValue.From<TDateTime>(0);
end;

{ TStreamConverter }

function TStreamConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var Ctx: TRttiContext; T: TRttiType;
begin
  if TypeInfo.Kind = tkClass then
  begin
    T := Ctx.GetType(TypeInfo);
    Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TStream);
  end
  else Result := False;
end;

procedure TStreamConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  Stream: TStream;
  MemStream: TMemoryStream;
  Bytes: TBytes;
  OldPos: Int64;
begin
  if Value.IsEmpty or (Value.AsObject = nil) then begin Writer.WriteNull; Exit; end;
  Stream := TStream(Value.AsObject);
  if Stream.Size > MaxInt then raise EJsonConverterError.Create('Stream is too large for Base64 encoding');
  OldPos := Stream.Position;
  try
    if Stream is TMemoryStream then
    begin
      MemStream := TMemoryStream(Stream);
      SetLength(Bytes, Integer(MemStream.Size));
      if Length(Bytes) > 0 then Move(MemStream.Memory^, Bytes[0], Length(Bytes));
    end
    else
    begin
      Stream.Position := 0;
      SetLength(Bytes, Integer(Stream.Size));
      if Length(Bytes) > 0 then Stream.ReadBuffer(Bytes[0], Length(Bytes));
    end;
    Writer.WriteValue(TNetEncoding.Base64.EncodeBytesToString(Bytes));
  finally
    Stream.Position := OldPos;
  end;
end;

function TStreamConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  Bytes: TBytes;
  Stream: TStream;
  Created: TValue;
begin
  if Reader.TokenType = TJsonToken.Null then
  begin
    TValue.Make(nil, ObjectType, Result);
    Exit;
  end;
  if not ExistingValue.IsEmpty and ExistingValue.IsObject and (ExistingValue.AsObject <> nil) then
  begin
    Result := ExistingValue;
    Stream := TStream(ExistingValue.AsObject);
  end
  else
  begin
    Created := TJsonActivator.CreateInstance(ObjectType);
    if not Created.IsObject or not (Created.AsObject is TStream) then raise EJsonConverterError.CreateFmt('Cannot create stream type %s', [ObjectType.Name]);
    Result := Created;
    Stream := TStream(Created.AsObject);
  end;
  Bytes := TNetEncoding.Base64.DecodeStringToBytes(Reader.Value);
  Stream.Size := 0;
  Stream.Position := 0;
  if Length(Bytes) > 0 then Stream.WriteBuffer(Bytes[0], Length(Bytes));
  Stream.Position := 0;
end;

{ TStringsConverter }

function TStringsConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var Ctx: TRttiContext; T: TRttiType;
begin
  if TypeInfo.Kind = tkClass then
  begin
    T := Ctx.GetType(TypeInfo);
    Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TStrings);
  end
  else Result := False;
end;

procedure TStringsConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var List: TStrings; S: string;
begin
  if Value.IsEmpty or (Value.AsObject = nil) then begin Writer.WriteNull; Exit; end;
  List := TStrings(Value.AsObject);
  Writer.WriteStartArray;
  for S in List do Writer.WriteValue(S);
  Writer.WriteEndArray;
end;

function TStringsConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  List: TStrings;
  Created: TValue;
begin
  if Reader.TokenType = TJsonToken.Null then
  begin
    TValue.Make(nil, ObjectType, Result);
    Exit;
  end;
  if Reader.TokenType <> TJsonToken.StartArray then raise EJsonConverterError.Create('Expected JSON array for TStrings');
  if not ExistingValue.IsEmpty and ExistingValue.IsObject and (ExistingValue.AsObject <> nil) then
  begin
    Result := ExistingValue;
    List := TStrings(ExistingValue.AsObject);
  end
  else
  begin
    Created := TJsonActivator.CreateInstance(ObjectType);
    if not Created.IsObject or not (Created.AsObject is TStrings) then raise EJsonConverterError.CreateFmt('Cannot create string list type %s', [ObjectType.Name]);
    Result := Created;
    List := TStrings(Created.AsObject);
  end;
  List.BeginUpdate;
  try
    List.Clear;
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndArray then Break;
      if Reader.TokenType = TJsonToken.Null then List.Add('') else List.Add(Reader.Value);
    end;
  finally
    List.EndUpdate;
  end;
end;

{ TCollectionConverter }

function TCollectionConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var Ctx: TRttiContext; T: TRttiType;
begin
  if TypeInfo.Kind = tkClass then
  begin
    T := Ctx.GetType(TypeInfo);
    Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TCollection);
  end
  else Result := False;
end;

procedure TCollectionConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var Coll: TCollection; Item: TCollectionItem;
begin
  if Value.IsEmpty or (Value.AsObject = nil) then begin Writer.WriteNull; Exit; end;
  Coll := TCollection(Value.AsObject);
  Writer.WriteStartArray;
  for Item in Coll do TJsonSerializer(Serializer).SerializeValue(Writer, Item);
  Writer.WriteEndArray;
end;

function TCollectionConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var Coll: TCollection; DeserializerObj: TJsonDeserializer; ItemDom: TJsonValue; NewItem: TCollectionItem;
begin
  if (ExistingValue.IsEmpty) or (ExistingValue.AsObject = nil) then raise Exception.Create('TCollection deserialization requires existing instance');
  Coll := TCollection(ExistingValue.AsObject);
  DeserializerObj := TJsonDeserializer(Serializer);
  
  if Reader.TokenType = TJsonToken.Null then begin Coll.Clear; Exit(ExistingValue); end;
  if Reader.TokenType <> TJsonToken.StartArray then raise Exception.Create('Expected Array');

  Coll.BeginUpdate;
  try
    Coll.Clear;
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndArray then Break;
      ItemDom := DeserializerObj.BuildDomFromCurrent(Reader);
      try
        NewItem := Coll.Add;
        DeserializerObj.Populate(NewItem, ItemDom);
      finally
        ItemDom.Free;
      end;
    end;
  finally
    Coll.EndUpdate;
  end;
  Result := ExistingValue;
end;

{ TPointConverter }

function TPointConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := (TypeInfo = System.TypeInfo(TPoint)) or (TypeInfo = System.TypeInfo(TPointF));
end;

procedure TPointConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  P: TPoint;
  PF: TPointF;
begin
  Writer.WriteStartObject;
  if Value.TypeInfo = System.TypeInfo(TPoint) then
  begin
    P := Value.AsType<TPoint>;
    Writer.WritePropertyName('x'); Writer.WriteValue(P.X);
    Writer.WritePropertyName('y'); Writer.WriteValue(P.Y);
  end
  else
  begin
    PF := Value.AsType<TPointF>;
    Writer.WritePropertyName('x'); Writer.WriteValue(PF.X);
    Writer.WritePropertyName('y'); Writer.WriteValue(PF.Y);
  end;
  Writer.WriteEndObject;
end;

function TPointConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var IsFloat: Boolean; PX, PY: Double; IX, IY: Integer; Prop: string;
begin
  IsFloat := ObjectType = System.TypeInfo(TPointF);
  IX := 0; IY := 0; PX := 0; PY := 0;
  
  if Reader.TokenType = TJsonToken.StartObject then
  begin
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndObject then Break;
      if Reader.TokenType = TJsonToken.PropertyName then
      begin
        Prop := LowerCase(Reader.Value);
        Reader.Read;
        if IsFloat then
        begin
          if Prop = 'x' then PX := Reader.ValueAsFloat else if Prop = 'y' then PY := Reader.ValueAsFloat;
        end
        else
        begin
          if Prop = 'x' then IX := Reader.ValueAsInt else if Prop = 'y' then IY := Reader.ValueAsInt;
        end;
      end;
    end;
  end;
  
  if IsFloat then Result := TValue.From<TPointF>(TPointF.Create(PX, PY))
  else Result := TValue.From<TPoint>(TPoint.Create(IX, IY));
end;

{ TRectConverter }

function TRectConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := (TypeInfo = System.TypeInfo(TRect)) or (TypeInfo = System.TypeInfo(TRectF));
end;

procedure TRectConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  R: TRect;
  RF: TRectF;
begin
  Writer.WriteStartObject;
  if Value.TypeInfo = System.TypeInfo(TRect) then
  begin
    R := Value.AsType<TRect>;
    Writer.WritePropertyName('left'); Writer.WriteValue(R.Left);
    Writer.WritePropertyName('top'); Writer.WriteValue(R.Top);
    Writer.WritePropertyName('right'); Writer.WriteValue(R.Right);
    Writer.WritePropertyName('bottom'); Writer.WriteValue(R.Bottom);
  end
  else
  begin
    RF := Value.AsType<TRectF>;
    Writer.WritePropertyName('left'); Writer.WriteValue(RF.Left);
    Writer.WritePropertyName('top'); Writer.WriteValue(RF.Top);
    Writer.WritePropertyName('right'); Writer.WriteValue(RF.Right);
    Writer.WritePropertyName('bottom'); Writer.WriteValue(RF.Bottom);
  end;
  Writer.WriteEndObject;
end;

function TRectConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var IsFloat: Boolean; R: TRect; RF: TRectF; Prop: string;
begin
  IsFloat := ObjectType = System.TypeInfo(TRectF);
  R := TRect.Empty; RF := TRectF.Empty;
  
  if Reader.TokenType = TJsonToken.StartObject then
  begin
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndObject then Break;
      if Reader.TokenType = TJsonToken.PropertyName then
      begin
        Prop := LowerCase(Reader.Value);
        Reader.Read;
        if IsFloat then
        begin
          if Prop = 'left' then RF.Left := Reader.ValueAsFloat
          else if Prop = 'top' then RF.Top := Reader.ValueAsFloat
          else if Prop = 'right' then RF.Right := Reader.ValueAsFloat
          else if Prop = 'bottom' then RF.Bottom := Reader.ValueAsFloat;
        end
        else
        begin
          if Prop = 'left' then R.Left := Reader.ValueAsInt
          else if Prop = 'top' then R.Top := Reader.ValueAsInt
          else if Prop = 'right' then R.Right := Reader.ValueAsInt
          else if Prop = 'bottom' then R.Bottom := Reader.ValueAsInt;
        end;
      end;
    end;
  end;
  if IsFloat then Result := TValue.From<TRectF>(RF) else Result := TValue.From<TRect>(R);
end;

{ TSizeConverter }

function TSizeConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := (TypeInfo = System.TypeInfo(TSize)) or (TypeInfo = System.TypeInfo(TSizeF));
end;

procedure TSizeConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  S: TSize;
  SF: TSizeF;
begin
  Writer.WriteStartObject;
  if Value.TypeInfo = System.TypeInfo(TSize) then
  begin
    S := Value.AsType<TSize>;
    Writer.WritePropertyName('width'); Writer.WriteValue(S.Width);
    Writer.WritePropertyName('height'); Writer.WriteValue(S.Height);
  end
  else
  begin
    SF := Value.AsType<TSizeF>;
    Writer.WritePropertyName('width'); Writer.WriteValue(SF.Width);
    Writer.WritePropertyName('height'); Writer.WriteValue(SF.Height);
  end;
  Writer.WriteEndObject;
end;

function TSizeConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var IsFloat: Boolean; S: TSize; SF: TSizeF; Prop: string;
begin
  IsFloat := ObjectType = System.TypeInfo(TSizeF);
  S.cx := 0; S.cy := 0; SF.cx := 0; SF.cy := 0;
  
  if Reader.TokenType = TJsonToken.StartObject then
  begin
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndObject then Break;
      if Reader.TokenType = TJsonToken.PropertyName then
      begin
        Prop := LowerCase(Reader.Value);
        Reader.Read;
        if IsFloat then
        begin
          if (Prop='width') or (Prop='cx') then SF.Width := Reader.ValueAsFloat
          else if (Prop='height') or (Prop='cy') then SF.Height := Reader.ValueAsFloat;
        end
        else
        begin
          if (Prop='width') or (Prop='cx') then S.Width := Reader.ValueAsInt
          else if (Prop='height') or (Prop='cy') then S.Height := Reader.ValueAsInt;
        end;
      end;
    end;
  end;
  if IsFloat then Result := TValue.From<TSizeF>(SF) else Result := TValue.From<TSize>(S);
end;

end.