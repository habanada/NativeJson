{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Converters.System;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  TypInfo,
  Rtti,
  Generics.Collections,
  Variants,
  System.TimeSpan,
  DateUtils,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  System.Rtti,
  System.Generics.Collections,
  System.Variants,
  System.TimeSpan,
  System.DateUtils,
  {$ENDIF}
  NativeJson.Serializer.Converter,
  NativeJson.Serializer.Writer,
  NativeJson.Core.Reader,
  NativeJson.Core.Tokens;

type
  // ===========================================================================
  // BASIC SYSTEM TYPES
  // ===========================================================================

  /// <summary>
  ///   Serializes TGUID.
  ///   Format: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" (lower case, without braces).
  /// </summary>
  TGuidConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TStringBuilder efficiently as a string.
  /// </summary>
  TStringBuilderConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   The "unwrapper". If a TValue is inside a TValue, this converter unpacks
  ///   it and hands it back to the serializer. Important for generics.
  /// </summary>
  TValueConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  // ===========================================================================
  // DATE & TIME (High Precision)
  // ===========================================================================

  /// <summary>
  ///   Serializes TTimeSpan.
  ///   Format: standard ("1.05:30:00") or ticks, depending on the setting (default: string).
  /// </summary>
  TTimeSpanConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  // ===========================================================================
  // THE BEAST: VARIANT HANDLING
  // ===========================================================================

  /// <summary>
  ///   Powerful converter for variants.
  ///   Features:
  ///   - Keeps data types (Int, Bool, Float) instead of turning everything into strings.
  ///   - Serializes variant arrays (VarArray) as JSON arrays!
  ///   - Detects TDateTime in the variant and formats it as ISO8601.
  ///   - Handles Null and Unassigned correctly.
  /// </summary>
  TVariantConverter = class(TJsonConverter)
  private
    procedure WriteVariantArray(Writer: TJsonWriter; const V: Variant; Serializer: TJsonSerializerContext);
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

procedure RegisterSystemConverters(AList: TObjectList<TJsonConverter>);

implementation

uses
  NativeJson.Serializer.Core, // For the recursive call on TValue/Variant
  NativeJson.Deserializer.Core,
  NativeJson.Dom.Value;

procedure RegisterSystemConverters(AList: TObjectList<TJsonConverter>);
begin
  AList.Add(TGuidConverter.Create);
  AList.Add(TStringBuilderConverter.Create);
  AList.Add(TValueConverter.Create);
  AList.Add(TTimeSpanConverter.Create);
  AList.Add(TVariantConverter.Create);
end;

{ TGuidConverter }

function TGuidConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TGUID);
end;

procedure TGuidConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
begin
  // Remove the curly braces for clean JSON
  // GUIDToString returns '{...}', we want '...'
  Writer.WriteValue(Value.AsType<TGUID>.ToString.Trim(['{', '}']).ToLower);
end;

function TGuidConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  S: string;
begin
  if Reader.TokenType = TJsonToken.Null then
    Exit(TValue.From<TGUID>(Default(TGUID)));

  if Reader.TokenType = TJsonToken.Str then
  begin
    S := Reader.Value;
    // Tolerant when reading: with or without braces
    if (S.Length > 0) and (S.Chars[0] <> '{') then
      S := '{' + S + '}';
    Result := TValue.From<TGUID>(StringToGUID(S));
  end
  else
    raise Exception.Create('Expected String for GUID');
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
var
  SB: TStringBuilder;
begin
  if Reader.TokenType = TJsonToken.Null then
    Exit(TValue.From<TStringBuilder>(nil));

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
var
  Inner: TValue;
begin
  Inner := Value.AsType<TValue>;
  if Inner.IsEmpty then
    Writer.WriteNull
  else
    // Recursion: ask the serializer to serialize the CONTENT
    TJsonSerializer(Serializer).SerializeValue(Writer, Inner);
end;

function TValueConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  Deser: TJsonDeserializer;
  Dom: TJsonValue;
begin
  // Since a TValue can be anything, it is read as a DOM tree.
  // This is the safest way to keep structure information.
  Deser := TJsonDeserializer(Serializer);
  Dom := Deser.BuildDomFromCurrent(Reader);
  // Return a TValue that holds the TJsonValue.
  // The caller must know how to handle it (typically AsType<TJsonValue>).
  Result := TValue.From<TValue>(TValue.From<TJsonValue>(Dom));
end;

{ TTimeSpanConverter }

function TTimeSpanConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TTimeSpan);
end;

procedure TTimeSpanConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
begin
  // Standard format: "d.hh:mm:ss.fff"
  Writer.WriteValue(Value.AsType<TTimeSpan>.ToString);
end;

function TTimeSpanConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
begin
  if Reader.TokenType = TJsonToken.Str then
    Result := TValue.From<TTimeSpan>(TTimeSpan.Parse(Reader.Value))
  else if (Reader.TokenType = TJsonToken.Integer) or (Reader.TokenType = TJsonToken.Float) then
    // Fallback: assume ticks or TotalDays? Ticks are assumed for precision.
    Result := TValue.From<TTimeSpan>(TTimeSpan.FromTicks(Reader.ValueAsInt))
  else
    Result := TValue.From<TTimeSpan>(TTimeSpan.Zero);
end;

{ TVariantConverter }

function TVariantConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(Variant);
end;

procedure TVariantConverter.WriteVariantArray(Writer: TJsonWriter; const V: Variant; Serializer: TJsonSerializerContext);
var
  I, LowBound, HighBound: Integer;
  Element: Variant;
begin
  // Support for one-dimensional variant arrays
  if VarArrayDimCount(V) <> 1 then
    raise Exception.Create('Only 1-dimensional Variant Arrays are supported');

  LowBound := VarArrayLowBound(V, 1);
  HighBound := VarArrayHighBound(V, 1);

  Writer.WriteStartArray;
  for I := LowBound to HighBound do
  begin
    Element := VarArrayGet(V, [I]);
    // Recursion for elements (in case of nested arrays)
    if VarIsArray(Element) then
      WriteVariantArray(Writer, Element, Serializer)
    else
      // Wrap it in a TValue and use the main serialization,
      // so converters (e.g. for dates) apply.
      TJsonSerializer(Serializer).SerializeValue(Writer, TValue.FromVariant(Element));
  end;
  Writer.WriteEndArray;
end;

procedure TVariantConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  V: Variant;
  VType: Integer;
begin
  V := Value.AsVariant;
  VType := VarType(V) and varTypeMask;

  if VarIsNull(V) or VarIsEmpty(V) then
  begin
    Writer.WriteNull;
    Exit;
  end;

  if VarIsArray(V) then
  begin
    WriteVariantArray(Writer, V, Serializer);
    Exit;
  end;

  // Type-appropriate serialization
  case VType of
    varSmallint, varInteger, varByte, varShortInt, varWord, varLongWord, varInt64, varUInt64:
      Writer.WriteValue(Int64(V)); // Cast to Int64 covers all integers

    varSingle, varDouble, varCurrency:
      Writer.WriteValue(Double(V));

    varBoolean:
      Writer.WriteValue(Boolean(V));

    varDate:
      // Use ISO8601 for dates in the variant
      Writer.WriteValue(DateToISO8601(VarToDateTime(V)));

    varString, varUString, varOleStr:
      Writer.WriteValue(string(V));

    else
      // Fallback: string conversion
      Writer.WriteValue(VarToStr(V));
  end;
end;

function TVariantConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  Dom: TJsonValue;
begin
  // Dynamic type detection when reading
  case Reader.TokenType of
    TJsonToken.Str:
      Result := TValue.From<Variant>(Reader.Value);
      
    TJsonToken.Integer:
      Result := TValue.From<Variant>(Reader.ValueAsInt);
      
    TJsonToken.Float:
      Result := TValue.From<Variant>(Reader.ValueAsFloat);
      
    TJsonToken.Boolean:
      Result := TValue.From<Variant>(Reader.ValueAsBool);
      
    TJsonToken.Null, TJsonToken.Undefined:
      Result := TValue.From<Variant>(Null);
      
    TJsonToken.StartArray:
      begin
        // Reading a variant array is complex, because the size is unknown.
        // Use the DOM route: Array -> DOM -> TValue (TJsonArray)
        // The user gets a TJsonArray in the variant.
        // Real VarArray creation would be possible here, but inefficient without prior knowledge.
        // Strategy: return a TValue that contains a TJsonArray.
        
        // Alternative: read it as a TValue list and convert it at the end.
        // For the "massive upgrade": try to build a VarArrayOf.
        // But that is a performance hit. Stay with the safe DOM.
        Dom := TJsonDeserializer(Serializer).BuildDomFromCurrent(Reader);
        Result := TValue.From<TValue>(TValue.From<TJsonValue>(Dom));
      end;
      
    else
      Result := TValue.From<Variant>(Unassigned);
  end;
end;

end.