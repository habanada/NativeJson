{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Converters.Vcl;

interface

uses
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  System.Rtti,
  System.NetEncoding,
  System.Types,
  System.UITypes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Imaging.pngimage,
  Vcl.Imaging.jpeg,
  NativeJson.Serializer.Converter,
  NativeJson.Serializer.Writer,
  NativeJson.Core.Reader,
  NativeJson.Core.Tokens;

type
  TColorConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  TGraphicConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  TFontConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  TPointConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  TRectConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  TSizeConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  TMarginsConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

implementation

uses
  Winapi.Windows; 

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

{ TColorConverter }

function TColorConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TColor);
end;

procedure TColorConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  C: TColor;
  S: string;
begin
  C := Value.AsType<TColor>;
  S := ColorToString(C);
  if not S.StartsWith('cl') then
  begin
    var R := GetRValue(C);
    var G := GetGValue(C);
    var B := GetBValue(C);
    S := Format('#%.2x%.2x%.2x', [R, G, B]);
  end;
  Writer.WriteValue(S);
end;

function TColorConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  S: string;
  C: TColor;
begin
  if Reader.TokenType = TJsonToken.Integer then
    Result := TValue.From<TColor>(TColor(Reader.ValueAsInt))
  else if Reader.TokenType = TJsonToken.Str then
  begin
    S := Reader.Value;
    if S.StartsWith('#') and (S.Length = 7) then
    begin
      var R := StrToInt('$' + Copy(S, 2, 2));
      var G := StrToInt('$' + Copy(S, 4, 2));
      var B := StrToInt('$' + Copy(S, 6, 2));
      C := RGB(R, G, B);
    end
    else
      C := StringToColor(S);
    Result := TValue.From<TColor>(C);
  end
  else
    Result := TValue.From<TColor>(clNone);
end;

{ TGraphicConverter }

function TGraphicConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var
  Ctx: TRttiContext;
  T: TRttiType;
begin
  if TypeInfo.Kind <> tkClass then Exit(False);
  T := Ctx.GetType(TypeInfo);
  Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TGraphic);
end;

procedure TGraphicConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  Graphic: TGraphic;
  Stream: TMemoryStream;
begin
  if Value.IsEmpty or (Value.AsObject = nil) then
  begin
    Writer.WriteNull;
    Exit;
  end;
  Graphic := TGraphic(Value.AsObject);
  if Graphic.Empty then
  begin
    Writer.WriteNull;
    Exit;
  end;
  Stream := TMemoryStream.Create;
  try
    Graphic.SaveToStream(Stream);
    Stream.Position := 0;
    Writer.WriteValue(EncodeMemoryStreamBase64(Stream));
  finally
    Stream.Free;
  end;
end;

function TGraphicConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  Graphic: TGraphic;
  Stream: TMemoryStream;
  Bytes: TBytes;
  Ctx: TRttiContext;
  RttiType: TRttiType;
  MetaClass: TGraphicClass;
begin
  if Reader.TokenType = TJsonToken.Null then Exit(TValue.From<TGraphic>(nil));
  if (ObjectType = nil) or (ObjectType.Kind <> tkClass) then raise EJsonConverterError.Create('TGraphicConverter requires a class type');

  Ctx := TRttiContext.Create;
  try
    RttiType := Ctx.GetType(ObjectType);
    if not (RttiType is TRttiInstanceType) or not TRttiInstanceType(RttiType).MetaclassType.InheritsFrom(TGraphic) then
      raise EJsonConverterError.CreateFmt('Type %s is not a TGraphic descendant', [ObjectType.Name]);
    MetaClass := TGraphicClass(TRttiInstanceType(RttiType).MetaclassType);
  finally
    Ctx.Free;
  end;

  Graphic := MetaClass.Create;
  try
    Bytes := TNetEncoding.Base64.DecodeStringToBytes(Reader.Value);
    Stream := TMemoryStream.Create;
    try
      if Length(Bytes) > 0 then Stream.WriteBuffer(Bytes[0], Length(Bytes));
      Stream.Position := 0;
      Graphic.LoadFromStream(Stream);
    finally
      Stream.Free;
    end;
    Result := TValue.From<TGraphic>(Graphic);
  except
    Graphic.Free;
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
  if Value.IsEmpty or (Value.AsObject = nil) then
  begin
    Writer.WriteNull;
    Exit;
  end;
  F := TFont(Value.AsObject);
  Writer.WriteStartObject;
  Writer.WritePropertyName('name'); Writer.WriteValue(F.Name);
  Writer.WritePropertyName('size'); Writer.WriteValue(F.Size);
  Writer.WritePropertyName('color'); 
  
  // Inline Color Conversion
  var C := F.Color;
  var S := ColorToString(C);
  if not S.StartsWith('cl') then
    S := Format('#%.2x%.2x%.2x', [GetRValue(C), GetGValue(C), GetBValue(C)]);
  Writer.WriteValue(S);

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
  if (ExistingValue.IsEmpty) or (ExistingValue.AsObject = nil) then
    F := TFont.Create
  else
    F := TFont(ExistingValue.AsObject);

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
      else if Prop = 'color' then
      begin
        var S := Reader.Value;
        if S.StartsWith('#') then
          F.Color := RGB(StrToInt('$' + Copy(S,2,2)), StrToInt('$' + Copy(S,4,2)), StrToInt('$' + Copy(S,6,2)))
        else
          F.Color := StringToColor(S);
      end
      else if Prop = 'style' then
      begin
        F.Style := [];
        if Reader.TokenType = TJsonToken.StartArray then
        begin
          while Reader.Read do
          begin
            if Reader.TokenType = TJsonToken.EndArray then Break;
            if Reader.TokenType = TJsonToken.Str then
            begin
              var StyleInt := GetEnumValue(System.TypeInfo(TFontStyle), Reader.Value);
              if StyleInt >= 0 then
                F.Style := F.Style + [TFontStyle(StyleInt)];
            end;
          end;
        end;
      end;
    end;
  end;
  Result := TValue.From<TFont>(F);
end;

{ TPointConverter }

function TPointConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TPoint);
end;

procedure TPointConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var P: TPoint;
begin
  P := Value.AsType<TPoint>;
  Writer.WriteStartObject;
  Writer.WritePropertyName('x'); Writer.WriteValue(P.X);
  Writer.WritePropertyName('y'); Writer.WriteValue(P.Y);
  Writer.WriteEndObject;
end;

function TPointConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var P: TPoint; Prop: string;
begin
  P.X := 0; P.Y := 0;
  if Reader.TokenType = TJsonToken.StartObject then
  begin
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndObject then Break;
      if Reader.TokenType = TJsonToken.PropertyName then
      begin
        Prop := LowerCase(Reader.Value);
        Reader.Read;
        if Prop = 'x' then P.X := Reader.ValueAsInt
        else if Prop = 'y' then P.Y := Reader.ValueAsInt;
      end;
    end;
  end;
  Result := TValue.From<TPoint>(P);
end;

{ TRectConverter }

function TRectConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TRect);
end;

procedure TRectConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var R: TRect;
begin
  R := Value.AsType<TRect>;
  Writer.WriteStartObject;
  Writer.WritePropertyName('left'); Writer.WriteValue(R.Left);
  Writer.WritePropertyName('top'); Writer.WriteValue(R.Top);
  Writer.WritePropertyName('right'); Writer.WriteValue(R.Right);
  Writer.WritePropertyName('bottom'); Writer.WriteValue(R.Bottom);
  Writer.WriteEndObject;
end;

function TRectConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var R: TRect; Prop: string;
begin
  R := TRect.Empty;
  if Reader.TokenType = TJsonToken.StartObject then
  begin
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndObject then Break;
      if Reader.TokenType = TJsonToken.PropertyName then
      begin
        Prop := LowerCase(Reader.Value);
        Reader.Read;
        if Prop = 'left' then R.Left := Reader.ValueAsInt
        else if Prop = 'top' then R.Top := Reader.ValueAsInt
        else if Prop = 'right' then R.Right := Reader.ValueAsInt
        else if Prop = 'bottom' then R.Bottom := Reader.ValueAsInt;
      end;
    end;
  end;
  Result := TValue.From<TRect>(R);
end;

{ TSizeConverter }

function TSizeConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TSize);
end;

procedure TSizeConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var S: TSize;
begin
  S := Value.AsType<TSize>;
  Writer.WriteStartObject;
  Writer.WritePropertyName('width'); Writer.WriteValue(S.Width);
  Writer.WritePropertyName('height'); Writer.WriteValue(S.Height);
  Writer.WriteEndObject;
end;

function TSizeConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var S: TSize; Prop: string;
begin
  S.cx := 0; S.cy := 0;
  if Reader.TokenType = TJsonToken.StartObject then
  begin
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndObject then Break;
      if Reader.TokenType = TJsonToken.PropertyName then
      begin
        Prop := LowerCase(Reader.Value);
        Reader.Read;
        if (Prop = 'width') or (Prop = 'cx') then S.cx := Reader.ValueAsInt
        else if (Prop = 'height') or (Prop = 'cy') then S.cy := Reader.ValueAsInt;
      end;
    end;
  end;
  Result := TValue.From<TSize>(S);
end;

{ TMarginsConverter }

function TMarginsConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TMargins);
end;

procedure TMarginsConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var M: TMargins;
begin
  if Value.IsEmpty or (Value.AsObject = nil) then
  begin
    Writer.WriteNull;
    Exit;
  end;
  M := TMargins(Value.AsObject);
  Writer.WriteStartObject;
  Writer.WritePropertyName('left'); Writer.WriteValue(M.Left);
  Writer.WritePropertyName('top'); Writer.WriteValue(M.Top);
  Writer.WritePropertyName('right'); Writer.WriteValue(M.Right);
  Writer.WritePropertyName('bottom'); Writer.WriteValue(M.Bottom);
  Writer.WriteEndObject;
end;

function TMarginsConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var M: TMargins; Prop: string;
begin
  if (ExistingValue.IsEmpty) or (ExistingValue.AsObject = nil) then
    M := TMargins.Create(nil)
  else
    M := TMargins(ExistingValue.AsObject);

  if Reader.TokenType = TJsonToken.Null then Exit(TValue.From<TMargins>(M));

  if Reader.TokenType = TJsonToken.StartObject then
  begin
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndObject then Break;
      if Reader.TokenType = TJsonToken.PropertyName then
      begin
        Prop := LowerCase(Reader.Value);
        Reader.Read;
        if Prop = 'left' then M.Left := Reader.ValueAsInt
        else if Prop = 'top' then M.Top := Reader.ValueAsInt
        else if Prop = 'right' then M.Right := Reader.ValueAsInt
        else if Prop = 'bottom' then M.Bottom := Reader.ValueAsInt;
      end;
    end;
  end;
  Result := TValue.From<TMargins>(M);
end;

end.