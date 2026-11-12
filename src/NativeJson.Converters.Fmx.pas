{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Converters.Fmx;

interface

uses
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  System.Rtti,
  System.Generics.Collections,
  System.UITypes,
  System.UIConsts,
  System.NetEncoding,
  FMX.Types,
  FMX.Graphics,
  FMX.Objects, // For TPath
  NativeJson.Serializer.Converter,
  NativeJson.Serializer.Writer,
  NativeJson.Core.Reader,
  NativeJson.Core.Tokens;

type
  // ===========================================================================
  // FMX GRAPHICS
  // ===========================================================================

  /// <summary>
  ///   Serializes TAlphaColor (FMX colors with transparency).
  ///   Format: "claRed" or "#AARRGGBB" (hex).
  /// </summary>
  TAlphaColorConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes FMX.Graphics.TBitmap as a Base64 string.
  /// </summary>
  TBitmapConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes FMX.Graphics.TFont (Family, Size, Style).
  /// </summary>
  TFontConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TPathData (vector paths) as an SVG string.
  ///   Example: "M 10,10 L 50,50 Z"
  /// </summary>
  TPathDataConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

procedure RegisterFmxConverters(AList: TObjectList<TJsonConverter>);

implementation

function EncodeMemoryStreamBase64(Stream: TMemoryStream): string;
var
  Bytes: TBytes;
begin
  if Stream.Size = 0 then Exit('');
  if Stream.Size > MaxInt then raise ERangeError.Create('Stream is too large for Base64 encoding');
  SetLength(Bytes, Integer(Stream.Size));
  Move(Stream.Memory^, Bytes[0], Length(Bytes));
  Result := TNetEncoding.Base64.EncodeBytesToString(Bytes);
end;

procedure RegisterFmxConverters(AList: TObjectList<TJsonConverter>);
begin
  AList.Add(TAlphaColorConverter.Create);
  AList.Add(TBitmapConverter.Create);
  AList.Add(TFontConverter.Create);
  AList.Add(TPathDataConverter.Create);
end;

{ TAlphaColorConverter }

function TAlphaColorConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  // TAlphaColor is an alias for Cardinal, but usually has its own RTTI info in FMX contexts
  // or we check the type name in case PTypeInfo is generic.
  // Safe check:
  Result := TypeInfo = System.TypeInfo(TAlphaColor);
end;

procedure TAlphaColorConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  C: TAlphaColor;
  S: string;
begin
  C := Value.AsType<TAlphaColor>;
  
  // Use the system function (returns 'claRed' or hex '#FF000000')
  // Note: AlphaColorToString returns hex without '#', it is added for standard conformance
  // if it is not a name.
  S := AlphaColorToString(C);
  
  // If it looks like a number (hex without prefix), make it pretty
  if (Length(S) > 0) and (S.Chars[0] in ['0'..'9', 'A'..'F', 'a'..'f']) and (not S.StartsWith('cla')) then
    S := '#' + S;
    
  Writer.WriteValue(S);
end;

function TAlphaColorConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  S: string;
  C: TAlphaColor;
  ColorValue: Integer;
begin
  if Reader.TokenType = TJsonToken.Integer then
    Result := TValue.From<TAlphaColor>(TAlphaColor(Reader.ValueAsInt))
  else if Reader.TokenType = TJsonToken.Str then
  begin
    S := Reader.Value;
    if S.StartsWith('#') then S := '$' + S.Substring(1);
    ColorValue := 0;
    if IdentToAlphaColor(S, ColorValue) or IdentToAlphaColor('cla' + S, ColorValue) then
      C := TAlphaColor(ColorValue)
    else
      C := StringToAlphaColor(S);
      
    Result := TValue.From<TAlphaColor>(C);
  end
  else
    Result := TValue.From<TAlphaColor>(TAlphaColorRec.Null);
end;

{ TBitmapConverter }

function TBitmapConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var
  Ctx: TRttiContext;
  T: TRttiType;
begin
  if TypeInfo.Kind <> tkClass then Exit(False);
  T := Ctx.GetType(TypeInfo);
  // FMX.Graphics.TBitmap
  Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(FMX.Graphics.TBitmap);
end;

procedure TBitmapConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  Bmp: TBitmap;
  Stream: TMemoryStream;
begin
  if Value.AsObject = nil then begin Writer.WriteNull; Exit; end;
  Bmp := TBitmap(Value.AsObject);
  
  if Bmp.IsEmpty then
  begin
    Writer.WriteNull; 
    Exit;
  end;

  Stream := TMemoryStream.Create;
  try
    Bmp.SaveToStream(Stream);
    Stream.Position := 0;
    Writer.WriteValue(EncodeMemoryStreamBase64(Stream));
  finally
    Stream.Free;
  end;
end;

function TBitmapConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  Bmp: TBitmap;
  Stream: TMemoryStream;
  Bytes: TBytes;
begin
  if Reader.TokenType = TJsonToken.Null then 
    Exit(TValue.From<TBitmap>(nil));

  // Use the existing bitmap or create a new one
  if (ExistingValue.IsObject) and (ExistingValue.AsObject <> nil) then
    Bmp := TBitmap(ExistingValue.AsObject)
  else
    Bmp := TBitmap.Create;

  try
    Bytes := TNetEncoding.Base64.DecodeStringToBytes(Reader.Value);
    Stream := TMemoryStream.Create;
    try
      if Length(Bytes) > 0 then Stream.WriteBuffer(Bytes[0], Length(Bytes));
      Stream.Position := 0;
      Bmp.LoadFromStream(Stream);
    finally
      Stream.Free;
    end;
    Result := TValue.From<TBitmap>(Bmp);
  except
    if (ExistingValue.AsObject = nil) then Bmp.Free; // Only free it if we created it
    raise;
  end;
end;

{ TFontConverter }

function TFontConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TFont);
end;

procedure TFontConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  F: TFont;
  Style: TFontStyle;
begin
  if Value.AsObject = nil then begin Writer.WriteNull; Exit; end;
  F := TFont(Value.AsObject);
  
  Writer.WriteStartObject;
  Writer.WritePropertyName('family'); Writer.WriteValue(F.Family);
  Writer.WritePropertyName('size'); Writer.WriteValue(F.Size);
  
  if F.Style <> [] then
  begin
    Writer.WritePropertyName('style');
    Writer.WriteStartArray;
    for Style in F.Style do
      Writer.WriteValue(GetEnumName(System.TypeInfo(TFontStyle), Ord(Style)));
    Writer.WriteEndArray;
  end;
  Writer.WriteEndObject;
end;

function TFontConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  F: TFont;
  Prop: string;
begin
  if (ExistingValue.IsObject) and (ExistingValue.AsObject <> nil) then
    F := TFont(ExistingValue.AsObject)
  else
    F := TFont.Create;

  if Reader.TokenType = TJsonToken.Null then Exit(TValue.From<TFont>(F));

  while Reader.Read do
  begin
    if Reader.TokenType = TJsonToken.EndObject then Break;
    if Reader.TokenType = TJsonToken.PropertyName then
    begin
      Prop := LowerCase(Reader.Value);
      Reader.Read;
      
      if Prop = 'family' then F.Family := Reader.Value
      else if Prop = 'size' then F.Size := Reader.ValueAsFloat
      else if Prop = 'style' then
      begin
        F.Style := [];
        if Reader.TokenType = TJsonToken.StartArray then
          while Reader.Read do
          begin
            if Reader.TokenType = TJsonToken.EndArray then Break;
            if Reader.TokenType = TJsonToken.Str then
            begin
              var SInt := GetEnumValue(System.TypeInfo(TFontStyle), Reader.Value);
              if SInt >= 0 then F.Style := F.Style + [TFontStyle(SInt)];
            end;
          end;
      end;
    end;
  end;
  Result := TValue.From<TFont>(F);
end;

{ TPathDataConverter }

function TPathDataConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TPathData);
end;

procedure TPathDataConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var P: TPathData;
begin
  if Value.AsObject = nil then begin Writer.WriteNull; Exit; end;
  P := TPathData(Value.AsObject);
  // FMX has a built-in Data property that returns the SVG path string!
  Writer.WriteValue(P.Data);
end;

function TPathDataConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var P: TPathData;
begin
  if (ExistingValue.IsObject) and (ExistingValue.AsObject <> nil) then
    P := TPathData(ExistingValue.AsObject)
  else
    P := TPathData.Create;

  if Reader.TokenType = TJsonToken.Null then 
  begin
    P.Clear;
    Exit(TValue.From<TPathData>(P));
  end;

  if Reader.TokenType = TJsonToken.Str then
    P.Data := Reader.Value // FMX parses the SVG string automatically
  else
    raise Exception.Create('Expected String for PathData');
    
  Result := TValue.From<TPathData>(P);
end;

end.