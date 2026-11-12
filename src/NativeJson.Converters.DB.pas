{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Converters.DB;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  TypInfo,
  Rtti,
  Generics.Collections,
  System.NetEncoding,
  DateUtils,
  DB,
  FmtBCD,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  System.Rtti,
  System.Generics.Collections,
  System.NetEncoding,
  System.DateUtils,
  Data.DB,
  Data.FmtBcd,
  {$ENDIF}
  NativeJson.Serializer.Converter,
  NativeJson.Serializer.Writer,
  NativeJson.Core.Reader,
  NativeJson.Core.Tokens;

type
  TDataSetConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  TBcdConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  TFieldConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

procedure RegisterDBConverters(AList: TObjectList<TJsonConverter>);

implementation

function FieldAsNumberText(Field: TField): string;
begin
  // For currency and BCD fields AsString returns the exact decimal text.
  // Only the separator has to be changed to the dot that JSON
  // requires - so do not use the system FormatSettings.
  Result := Field.AsString;
  if FormatSettings.DecimalSeparator <> '.' then
    Result := StringReplace(Result, FormatSettings.DecimalSeparator, '.', []);
  Result := StringReplace(Result, FormatSettings.ThousandSeparator, '', [rfReplaceAll]);
  if Result = '' then Result := '0';
end;

procedure RegisterDBConverters(AList: TObjectList<TJsonConverter>);
begin
  AList.Add(TBcdConverter.Create);
  AList.Add(TFieldConverter.Create);
  AList.Add(TDataSetConverter.Create);
end;

{ TBcdConverter }

function TBcdConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
begin
  Result := TypeInfo = System.TypeInfo(TBcd);
end;

procedure TBcdConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
begin
  Writer.WriteRaw(BcdToStr(Value.AsType<TBcd>, TFormatSettings.Invariant));
end;

function TBcdConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  Bcd: TBcd;
  Text: string;
begin
  if Reader.TokenType = TJsonToken.Null then Exit(TValue.From<TBcd>(Default(TBcd)));
  if Reader.TokenType in [TJsonToken.Integer, TJsonToken.Float] then
    Text := Reader.RawValue
  else
    Text := Reader.Value;
  if not TryStrToBcd(Text, Bcd, TFormatSettings.Invariant) then
    raise EJsonReaderError.CreateFmt('Invalid BCD value "%s"', [Text]);
  Result := TValue.From<TBcd>(Bcd);
end;

{ TDataSetConverter }

function TDataSetConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var
  Ctx: TRttiContext;
  T: TRttiType;
begin
  if TypeInfo.Kind = tkClass then
  begin
    T := Ctx.GetType(TypeInfo);
    Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TDataSet);
  end
  else
    Result := False;
end;

procedure TDataSetConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  DataSet: TDataSet;
  Field: TField;
  Bookmark: TBookmark;
  Stream: TStream;
  StreamBytes: TBytes;
begin
  if Value.IsEmpty or (Value.AsObject = nil) then
  begin
    Writer.WriteNull;
    Exit;
  end;

  DataSet := TDataSet(Value.AsObject);

  if DataSet.IsEmpty then
  begin
    Writer.WriteStartArray;
    Writer.WriteEndArray;
    Exit;
  end;

  DataSet.DisableControls;
  try
    Bookmark := DataSet.GetBookmark;
    try
      DataSet.First;
      Writer.WriteStartArray;
      
      while not DataSet.Eof do
      begin
        Writer.WriteStartObject;
        for Field in DataSet.Fields do
        begin
          Writer.WritePropertyName(Field.FieldName);
          
          if Field.IsNull then
          begin
            Writer.WriteNull;
          end
          else
          begin
            case Field.DataType of
              ftString, ftWideString, ftMemo, ftWideMemo: 
                Writer.WriteValue(Field.AsString);
              
              ftSmallint, ftInteger, ftWord, ftAutoInc, ftLargeint, ftLongWord, ftShortint, ftByte:
                Writer.WriteValue(Field.AsLargeInt);
              
              ftCurrency, ftBCD, ftFMTBcd:
                Writer.WriteRaw(FieldAsNumberText(Field));
              ftFloat, ftExtended, ftSingle:
                Writer.WriteValue(Field.AsFloat);
              
              ftBoolean:
                Writer.WriteValue(Field.AsBoolean);
              
              ftDate, ftTime, ftDateTime, ftTimeStamp:
                Writer.WriteValue(DateToISO8601(Field.AsDateTime));
                
              ftBlob, ftGraphic, ftParadoxOle, ftDBaseOle, ftTypedBinary, ftCursor, ftOraBlob:
                begin
                  Stream := DataSet.CreateBlobStream(Field, bmRead);
                  try
                    SetLength(StreamBytes, Stream.Size);
                    if Stream.Size > 0 then
                      Stream.ReadBuffer(StreamBytes[0], Stream.Size);
                    Writer.WriteValue(TNetEncoding.Base64.EncodeBytesToString(StreamBytes));
                  finally
                    Stream.Free;
                  end;
                end;
                
              else
                Writer.WriteValue(Field.AsString);
            end;
          end;
        end;
        
        Writer.WriteEndObject;
        DataSet.Next;
      end;
      
      Writer.WriteEndArray;
    finally
      if DataSet.BookmarkValid(Bookmark) then
        DataSet.GotoBookmark(Bookmark);
      DataSet.FreeBookmark(Bookmark);
    end;
  finally
    DataSet.EnableControls;
  end;
end;

function TDataSetConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  DataSet: TDataSet;
  FieldName: string;
  Field: TField;
  Bytes: TBytes;
  Stream: TStream;
begin
  if (ExistingValue.IsEmpty) or (ExistingValue.AsObject = nil) then
    raise Exception.Create('DataSet deserialization requires an existing instance');
    
  DataSet := TDataSet(ExistingValue.AsObject);

  if Reader.TokenType = TJsonToken.Null then Exit(ExistingValue);
  if Reader.TokenType <> TJsonToken.StartArray then raise Exception.Create('Expected Array for DataSet');

  if not DataSet.Active then DataSet.Open;

  DataSet.DisableControls;
  try
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndArray then Break;

      if Reader.TokenType = TJsonToken.StartObject then
      begin
        DataSet.Append;
        try
          while Reader.Read do
          begin
            if Reader.TokenType = TJsonToken.EndObject then Break;

            if Reader.TokenType <> TJsonToken.PropertyName then raise Exception.Create('Expected Property Name');
            
            FieldName := Reader.Value;
            Field := DataSet.FindField(FieldName);
            
            if not Reader.Read then raise Exception.Create('Unexpected EOF');
            
            if Field <> nil then
            begin
              if Reader.TokenType = TJsonToken.Null then
                Field.Clear
              else
                case Field.DataType of
                  ftBlob, ftGraphic, ftTypedBinary:
                    begin
                      if Reader.TokenType = TJsonToken.Str then
                      begin
                        Bytes := TNetEncoding.Base64.DecodeStringToBytes(Reader.Value);
                        Stream := DataSet.CreateBlobStream(Field, bmWrite);
                        try
                          if Length(Bytes) > 0 then
                            Stream.WriteBuffer(Bytes[0], Length(Bytes));
                        finally
                          Stream.Free;
                        end;
                      end;
                    end;
                  ftDate, ftTime, ftDateTime, ftTimeStamp:
                    if Reader.TokenType = TJsonToken.Str then
                      Field.AsDateTime := ISO8601ToDate(Reader.Value);
                  else
                    Field.AsString := Reader.Value;
                end;
            end;
          end;
          DataSet.Post;
        except
          DataSet.Cancel;
          raise;
        end;
      end;
    end;
  finally
    DataSet.EnableControls;
  end;
  
  Result := ExistingValue;
end;

{ TFieldConverter }

function TFieldConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var
  Ctx: TRttiContext;
  T: TRttiType;
begin
  if TypeInfo.Kind = tkClass then
  begin
    T := Ctx.GetType(TypeInfo);
    Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TField);
  end
  else
    Result := False;
end;

procedure TFieldConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  Field: TField;
  Stream: TStream;
  StreamBytes: TBytes;
begin
  if Value.IsEmpty or (Value.AsObject = nil) then
  begin
    Writer.WriteNull;
    Exit;
  end;

  Field := TField(Value.AsObject);

  if Field.IsNull then
  begin
    Writer.WriteNull;
    Exit;
  end;

  case Field.DataType of
    ftString, ftWideString, ftMemo, ftWideMemo:
      Writer.WriteValue(Field.AsString);

    ftSmallint, ftInteger, ftWord, ftAutoInc, ftLargeint, ftLongWord, ftShortint, ftByte:
      Writer.WriteValue(Field.AsLargeInt);

    ftCurrency, ftBCD, ftFMTBcd:
      Writer.WriteRaw(FieldAsNumberText(Field));
    ftFloat, ftExtended, ftSingle:
      Writer.WriteValue(Field.AsFloat);

    ftBoolean:
      Writer.WriteValue(Field.AsBoolean);

    ftDate, ftTime, ftDateTime, ftTimeStamp:
      Writer.WriteValue(DateToISO8601(Field.AsDateTime));

    ftBlob, ftGraphic, ftParadoxOle, ftDBaseOle, ftTypedBinary, ftCursor, ftOraBlob:
      begin
        Stream := Field.DataSet.CreateBlobStream(Field, bmRead);
        try
          SetLength(StreamBytes, Stream.Size);
          if Stream.Size > 0 then
            Stream.ReadBuffer(StreamBytes[0], Stream.Size);
          Writer.WriteValue(TNetEncoding.Base64.EncodeBytesToString(StreamBytes));
        finally
          Stream.Free;
        end;
      end;
  else
    Writer.WriteValue(Field.AsString);
  end;
end;

function TFieldConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  Field: TField;
  Bytes: TBytes;
  Stream: TStream;
begin
  if (ExistingValue.IsEmpty) or (ExistingValue.AsObject = nil) or not (ExistingValue.AsObject is TField) then
    raise Exception.Create('TField deserialization requires an existing TField instance');

  Field := TField(ExistingValue.AsObject);

  if not Field.DataSet.Active then Field.DataSet.Open;
  if not (Field.DataSet.State in [dsEdit, dsInsert]) then Field.DataSet.Edit;

  if Reader.TokenType = TJsonToken.Null then
  begin
    Field.Clear;
    Exit(ExistingValue);
  end;

  case Field.DataType of
    ftBlob, ftGraphic, ftTypedBinary:
      begin
        if Reader.TokenType = TJsonToken.Str then
        begin
          Bytes := TNetEncoding.Base64.DecodeStringToBytes(Reader.Value);
          Stream := Field.DataSet.CreateBlobStream(Field, bmWrite);
          try
            if Length(Bytes) > 0 then
              Stream.WriteBuffer(Bytes[0], Length(Bytes));
          finally
            Stream.Free;
          end;
        end;
      end;
    ftDate, ftTime, ftDateTime, ftTimeStamp:
      if Reader.TokenType = TJsonToken.Str then
        Field.AsDateTime := ISO8601ToDate(Reader.Value);
    ftBoolean:
      if Reader.TokenType = TJsonToken.Boolean then
        Field.AsBoolean := Reader.ValueAsBool
      else
        Field.AsString := Reader.Value;
    ftSmallint, ftInteger, ftWord, ftAutoInc, ftLargeint, ftLongWord, ftShortint, ftByte:
      if Reader.TokenType = TJsonToken.Integer then
        Field.AsLargeInt := Reader.ValueAsInt
      else
        Field.AsString := Reader.Value;
    ftCurrency, ftBCD, ftFMTBcd:
      // Via AsFloat the value would go through a Double and lose digits beyond
      // 16 significant digits. The field parses the decimal text
      // itself, exactly.
      if Reader.TokenType in [TJsonToken.Float, TJsonToken.Integer] then
        Field.AsString := Reader.RawValue
      else
        Field.AsString := Reader.Value;
    ftFloat, ftExtended, ftSingle:
      if Reader.TokenType in [TJsonToken.Float, TJsonToken.Integer] then
        Field.AsFloat := Reader.ValueAsFloat
      else
        Field.AsString := Reader.Value;
  else
    Field.AsString := Reader.Value;
  end;

  Result := ExistingValue;
end;

end.