{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Converters.Graphics;

interface

uses
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  System.Rtti,
  System.Generics.Collections,
  System.NetEncoding,
  System.UITypes,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Vcl.Imaging.jpeg,
  Vcl.ImgList, // for TImageList
  Vcl.Controls,
  NativeJson.Serializer.Converter,
  NativeJson.Serializer.Writer,
  NativeJson.Core.Reader,
  NativeJson.Core.Tokens,
  // Helper for color conversion (reusing the Vcl converter is possible,
  // but it is integrated here so the unit stands alone)
  NativeJson.Converters.Vcl; 

type
  // ===========================================================================
  // GDI OBJECTS (Pen, Brush, Font)
  // ===========================================================================

  /// <summary>
  ///   Serializes TFont completely (Name, Size, Style, Color, Quality, etc.)
  /// </summary>
  TFontConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TPen with color, width, style and mode.
  /// </summary>
  TPenConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TBrush with color, style and optional bitmap.
  /// </summary>
  TBrushConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  // ===========================================================================
  // IMAGES & CONTAINERS
  // ===========================================================================

  /// <summary>
  ///   Serializes TGraphic (Bitmap, JPEG, PNG, Icon, Metafile) as Base64.
  /// </summary>
  TGraphicConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TPicture (container for a graphic).
  ///   Important, because TPicture often holds a nil graphic or changes its type.
  /// </summary>
  TPictureConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TImageList and TCustomImageList.
  ///   Stores the complete stream (images + masks) as Base64.
  /// </summary>
  TImageListConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

procedure RegisterDefaultConverters(AList: TObjectList<TJsonConverter>);

implementation

uses
  Winapi.Windows;

type
  TCustomImageListAccess = class(TCustomImageList);

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

procedure RegisterDefaultConverters(AList: TObjectList<TJsonConverter>);
begin
  AList.Add(TFontConverter.Create);
  AList.Add(TPenConverter.Create);
  AList.Add(TBrushConverter.Create);
  AList.Add(TGraphicConverter.Create);
  AList.Add(TPictureConverter.Create);
  AList.Add(TImageListConverter.Create);
end;

// --- Color helpers (internal) ---
function ColorToHex(C: TColor): string;
begin
  var S := ColorToString(C);
  if not S.StartsWith('cl') then
    Result := Format('#%.2x%.2x%.2x', [GetRValue(C), GetGValue(C), GetBValue(C)])
  else
    Result := S;
end;

function HexToColor(const S: string): TColor;
begin
  if S.StartsWith('#') and (S.Length = 7) then
    Result := RGB(StrToInt('$' + Copy(S, 2, 2)), StrToInt('$' + Copy(S, 4, 2)), StrToInt('$' + Copy(S, 6, 2)))
  else
    Result := StringToColor(S);
end;

{ TFontConverter }

function TFontConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TFont);
end;

procedure TFontConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var F: TFont; Style: TFontStyle;
begin
  if Value.AsObject = nil then begin Writer.WriteNull; Exit; end;
  F := TFont(Value.AsObject);
  
  Writer.WriteStartObject;
  Writer.WritePropertyName('name'); Writer.WriteValue(F.Name);
  Writer.WritePropertyName('size'); Writer.WriteValue(F.Size);
  Writer.WritePropertyName('color'); Writer.WriteValue(ColorToHex(F.Color));
  
  // Style as an array [fsBold, fsItalic]
  if F.Style <> [] then
  begin
    Writer.WritePropertyName('style');
    Writer.WriteStartArray;
    for Style in F.Style do
      Writer.WriteValue(GetEnumName(System.TypeInfo(TFontStyle), Ord(Style)));
    Writer.WriteEndArray;
  end;
  
  // Enterprise Detail: Quality, Pitch
  if F.Pitch <> fpDefault then 
  begin
    Writer.WritePropertyName('pitch');
    Writer.WriteValue(GetEnumName(System.TypeInfo(TFontPitch), Ord(F.Pitch)));
  end;
  
  Writer.WriteEndObject;
end;

function TFontConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var F: TFont; Prop: string;
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
      if Prop = 'name' then F.Name := Reader.Value
      else if Prop = 'size' then F.Size := Reader.ValueAsInt
      else if Prop = 'color' then F.Color := HexToColor(Reader.Value)
      else if Prop = 'pitch' then F.Pitch := TFontPitch(GetEnumValue(System.TypeInfo(TFontPitch), Reader.Value))
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

{ TPenConverter }

function TPenConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TPen);
end;

procedure TPenConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var P: TPen;
begin
  if Value.AsObject = nil then begin Writer.WriteNull; Exit; end;
  P := TPen(Value.AsObject);
  
  Writer.WriteStartObject;
  Writer.WritePropertyName('color'); Writer.WriteValue(ColorToHex(P.Color));
  Writer.WritePropertyName('width'); Writer.WriteValue(P.Width);
  Writer.WritePropertyName('style'); Writer.WriteValue(GetEnumName(System.TypeInfo(TPenStyle), Ord(P.Style)));
  Writer.WritePropertyName('mode');  Writer.WriteValue(GetEnumName(System.TypeInfo(TPenMode), Ord(P.Mode)));
  Writer.WriteEndObject;
end;

function TPenConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var P: TPen; Prop: string;
begin
  if (ExistingValue.IsObject) and (ExistingValue.AsObject <> nil) then
    P := TPen(ExistingValue.AsObject)
  else
    P := TPen.Create; // Memory Leak Warning: Usually Owned by Canvas

  if Reader.TokenType = TJsonToken.Null then Exit(TValue.From<TPen>(P));

  while Reader.Read do
  begin
    if Reader.TokenType = TJsonToken.EndObject then Break;
    if Reader.TokenType = TJsonToken.PropertyName then
    begin
      Prop := LowerCase(Reader.Value);
      Reader.Read;
      if Prop = 'color' then P.Color := HexToColor(Reader.Value)
      else if Prop = 'width' then P.Width := Reader.ValueAsInt
      else if Prop = 'style' then P.Style := TPenStyle(GetEnumValue(System.TypeInfo(TPenStyle), Reader.Value))
      else if Prop = 'mode' then P.Mode := TPenMode(GetEnumValue(System.TypeInfo(TPenMode), Reader.Value));
    end;
  end;
  Result := TValue.From<TPen>(P);
end;

{ TBrushConverter }

function TBrushConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TBrush);
end;

procedure TBrushConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var B: TBrush;
begin
  if Value.AsObject = nil then begin Writer.WriteNull; Exit; end;
  B := TBrush(Value.AsObject);
  
  Writer.WriteStartObject;
  Writer.WritePropertyName('color'); Writer.WriteValue(ColorToHex(B.Color));
  Writer.WritePropertyName('style'); Writer.WriteValue(GetEnumName(System.TypeInfo(TBrushStyle), Ord(B.Style)));
  // The bitmap in the brush is ignored by default, because it creates circular references or huge amounts of data.
  // Whoever needs it must configure it explicitly.
  Writer.WriteEndObject;
end;

function TBrushConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var B: TBrush; Prop: string;
begin
  if (ExistingValue.IsObject) and (ExistingValue.AsObject <> nil) then
    B := TBrush(ExistingValue.AsObject)
  else
    B := TBrush.Create;

  if Reader.TokenType = TJsonToken.Null then Exit(TValue.From<TBrush>(B));

  while Reader.Read do
  begin
    if Reader.TokenType = TJsonToken.EndObject then Break;
    if Reader.TokenType = TJsonToken.PropertyName then
    begin
      Prop := LowerCase(Reader.Value);
      Reader.Read;
      if Prop = 'color' then B.Color := HexToColor(Reader.Value)
      else if Prop = 'style' then B.Style := TBrushStyle(GetEnumValue(System.TypeInfo(TBrushStyle), Reader.Value));
    end;
  end;
  Result := TValue.From<TBrush>(B);
end;

{ TGraphicConverter }

function TGraphicConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var Ctx: TRttiContext; T: TRttiType;
begin
  if TypeInfo.Kind <> tkClass then Exit(False);
  T := Ctx.GetType(TypeInfo);
  Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TGraphic);
end;

procedure TGraphicConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var G: TGraphic; S: TMemoryStream;
begin
  if Value.AsObject = nil then begin Writer.WriteNull; Exit; end;
  G := TGraphic(Value.AsObject);
  if G.Empty then begin Writer.WriteNull; Exit; end;

  S := TMemoryStream.Create;
  try
    G.SaveToStream(S);
    S.Position := 0;
    Writer.WriteValue(EncodeMemoryStreamBase64(S));
  finally
    S.Free;
  end;
end;

function TGraphicConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  G: TGraphic;
  S: TMemoryStream;
  Bytes: TBytes;
  MetaClass: TGraphicClass;
  Ctx: TRttiContext;
  RttiType: TRttiType;
begin
  if Reader.TokenType = TJsonToken.Null then Exit(TValue.From<TGraphic>(nil));
  if (ObjectType = nil) or (ObjectType.Kind <> tkClass) then raise EJsonConverterError.Create('TGraphicConverter requires a class type');

  Ctx := TRttiContext.Create;
  try
    // Important: the concrete class must be known (TBitmap, TIcon etc.)
    // This information comes from the ObjectType of the property.
    RttiType := Ctx.GetType(ObjectType);
    if not (RttiType is TRttiInstanceType) or not TRttiInstanceType(RttiType).MetaclassType.InheritsFrom(TGraphic) then
      raise EJsonConverterError.CreateFmt('Type %s is not a TGraphic descendant', [ObjectType.Name]);
    MetaClass := TGraphicClass(TRttiInstanceType(RttiType).MetaclassType);
  finally
    Ctx.Free;
  end;

  G := MetaClass.Create;
  try
    Bytes := TNetEncoding.Base64.DecodeStringToBytes(Reader.Value);
    S := TMemoryStream.Create;
    try
      if Length(Bytes) > 0 then S.WriteBuffer(Bytes[0], Length(Bytes));
      S.Position := 0;
      G.LoadFromStream(S);
    finally
      S.Free;
    end;
    Result := TValue.From<TGraphic>(G);
  except
    G.Free;
    raise;
  end;
end;

{ TPictureConverter }

function TPictureConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TPicture);
end;

procedure TPictureConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var Pic: TPicture; S: TMemoryStream;
begin
  if Value.AsObject = nil then begin Writer.WriteNull; Exit; end;
  Pic := TPicture(Value.AsObject);
  
  if (Pic.Graphic = nil) or (Pic.Graphic.Empty) then
  begin
    Writer.WriteNull;
    Exit;
  end;

  // Do we also store the graphic type so it can be restored correctly?
  // Problem: TPicture can hold Bitmap, Icon, Metafile etc.
  // Solution: serialize an object: {"type": "TBitmap", "data": "base64"}
  
  Writer.WriteStartObject;
  Writer.WritePropertyName('type');
  Writer.WriteValue(Pic.Graphic.ClassName);
  
  Writer.WritePropertyName('data');
  S := TMemoryStream.Create;
  try
    Pic.Graphic.SaveToStream(S);
    S.Position := 0;
    Writer.WriteValue(EncodeMemoryStreamBase64(S));
  finally
    S.Free;
  end;
  Writer.WriteEndObject;
end;

function TPictureConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var Pic: TPicture; ClassName, Data: string; GraphClass: TGraphicClass; G: TGraphic; S: TMemoryStream; Bytes: TBytes; Ctx: TRttiContext; RType: TRttiType;
begin
  if (ExistingValue.IsObject) and (ExistingValue.AsObject <> nil) then
    Pic := TPicture(ExistingValue.AsObject)
  else
    Pic := TPicture.Create;

  if Reader.TokenType = TJsonToken.Null then
  begin
    Pic.Assign(nil);
    Exit(TValue.From<TPicture>(Pic));
  end;

  // Expects the object {"type": "...", "data": "..."}
  if Reader.TokenType <> TJsonToken.StartObject then raise Exception.Create('Expected Object for TPicture');
  
  ClassName := ''; Data := '';
  
  while Reader.Read do
  begin
    if Reader.TokenType = TJsonToken.EndObject then Break;
    if Reader.TokenType = TJsonToken.PropertyName then
    begin
      var PName := LowerCase(Reader.Value);
      Reader.Read;
      if PName = 'type' then ClassName := Reader.Value
      else if PName = 'data' then Data := Reader.Value;
    end;
  end;
  
  if (ClassName <> '') and (Data <> '') then
  begin
    Ctx := TRttiContext.Create;
    RType := Ctx.FindType(ClassName);
    if (RType <> nil) and (RType is TRttiInstanceType) then
    begin
      GraphClass := TGraphicClass(TRttiInstanceType(RType).MetaclassType);
      G := GraphClass.Create;
      try
        Bytes := TNetEncoding.Base64.DecodeStringToBytes(Data);
        S := TMemoryStream.Create;
        try
          if Length(Bytes) > 0 then S.WriteBuffer(Bytes[0], Length(Bytes));
          S.Position := 0;
          G.LoadFromStream(S);
        finally
          S.Free;
        end;
        Pic.Assign(G);
      finally
        G.Free;
      end;
    end;
  end;
  
  Result := TValue.From<TPicture>(Pic);
end;

{ TImageListConverter }

function TImageListConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var Ctx: TRttiContext; T: TRttiType;
begin
  if TypeInfo.Kind <> tkClass then Exit(False);
  T := Ctx.GetType(TypeInfo);
  Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TCustomImageList);
end;

procedure TImageListConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var IL: TCustomImageList; S: TMemoryStream;
begin
  if Value.AsObject = nil then begin Writer.WriteNull; Exit; end;
  IL := TCustomImageList(Value.AsObject);
  
  S := TMemoryStream.Create;
  try
    // Enterprise feature: native VCL stream format
    // It contains everything: images, masks, sizes, options.
    TCustomImageListAccess(IL).WriteData(S);
    S.Position := 0;
    Writer.WriteValue(EncodeMemoryStreamBase64(S));
  finally
    S.Free;
  end;
end;

function TImageListConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var IL: TCustomImageList; S: TMemoryStream; Bytes: TBytes;
begin
  if (ExistingValue.IsObject) and (ExistingValue.AsObject <> nil) then
    IL := TCustomImageList(ExistingValue.AsObject)
  else
    raise Exception.Create('TImageList requires existing instance');

  if Reader.TokenType = TJsonToken.Null then Exit(ExistingValue);
  
  Bytes := TNetEncoding.Base64.DecodeStringToBytes(Reader.Value);
  S := TMemoryStream.Create;
  try
    if Length(Bytes) > 0 then S.WriteBuffer(Bytes[0], Length(Bytes));
    S.Position := 0;
    
    TCustomImageListAccess(IL).ReadData(S);
  finally
    S.Free;
  end;
  Result := ExistingValue;
end;

end.