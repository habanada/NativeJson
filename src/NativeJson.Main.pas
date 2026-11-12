{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Main;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  Rtti,
  TypInfo,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.Dom.Value,
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.Primitive,
  NativeJson.Dom.Io,
  NativeJson.Pointer,
  NativeJson.Comparer,
  NativeJson.Patch,
  NativeJson.Diff,
  NativeJson.Sequence,
  NativeJson.Attributes,
  NativeJson.NamingStrategy,
  NativeJson.Serializer.Writer,
  NativeJson.Serializer.Core,
  NativeJson.Deserializer.Core,
  NativeJson.Settings,
  NativeJson.Validation,
  NativeJson.Schema.Generator,
  NativeJson.Schema.Validation,
  NativeJson.Schema.Validator;

type
  TJsonSettings = NativeJson.Settings.TJsonSettings;
  TJsonFormatting = NativeJson.Serializer.Writer.TJsonFormatting;
  TJsonEnumHandling = NativeJson.Serializer.Writer.TJsonEnumHandling;
  TJsonPreserveReferences = NativeJson.Serializer.Writer.TJsonPreserveReferences;
  TJsonTypeNameHandling = NativeJson.Serializer.Writer.TJsonTypeNameHandling;
  TJsonNamingStrategyClass = NativeJson.NamingStrategy.TJsonNamingStrategyClass;
  TJsonNullValueHandling = NativeJson.Attributes.TJsonNullValueHandling;
  TJsonDefaultValueHandling = NativeJson.Attributes.TJsonDefaultValueHandling;
  TJsonMissingMemberHandling = NativeJson.Attributes.TJsonMissingMemberHandling;
  TJsonMemberType = NativeJson.Attributes.TJsonMemberType;
  TJsonMemberTypes = NativeJson.Attributes.TJsonMemberTypes;
  TJsonValidationResult = NativeJson.Validation.TJsonValidationResult;
  TJsonValidationError = NativeJson.Validation.TJsonValidationError;
  TJsonSchemaDialect = NativeJson.Schema.Validation.TJsonSchemaDialect;
  EJsonSchemaException = NativeJson.Schema.Validation.EJsonSchemaException;
  TJsonSchemaValidationError = NativeJson.Schema.Validation.TJsonSchemaValidationError;
  TJsonSchemaValidationResult = NativeJson.Schema.Validation.TJsonSchemaValidationResult;
  TJsonSchemaValidationOptions = NativeJson.Schema.Validation.TJsonSchemaValidationOptions;
  TJsonSchemaValidator = NativeJson.Schema.Validator.TJsonSchemaValidator;
  TJsonSchemaFormatValidator = NativeJson.Schema.Validator.TJsonSchemaFormatValidator;
  EJsonPointerError = NativeJson.Pointer.EJsonPointerError;
  TJsonPointer = NativeJson.Pointer.TJsonPointer;
  TJsonComparer = NativeJson.Comparer.TJsonComparer;
  EJsonPatchError = NativeJson.Patch.EJsonPatchError;
  TJsonPatch = NativeJson.Patch.TJsonPatch;
  EJsonDiffError = NativeJson.Diff.EJsonDiffError;
  TJsonDiff = NativeJson.Diff.TJsonDiff;

  TJsonSettingsProc = reference to procedure(Settings: TJsonSettings);

  JsonConvert = class abstract
  private
    class var FDefaultSettings: TJsonSettingsProc;
    class procedure ConfigureSerializer(Serializer: TJsonSerializer; Settings: TJsonSettings); static;
    class procedure ConfigureDeserializer(Deserializer: TJsonDeserializer; Settings: TJsonSettings); static;
    class function NewSettings: TJsonSettings; static;
    class function TextFromBytes(const RawBytes: TBytes; NumItems: Integer): string; static;
    class function ReadStream(Stream: TStream): string; static;
  public
    class function SerializeObject(const Value: TValue): string; overload; static;
    class function SerializeObject(const Value: TValue; Formatting: TJsonFormatting): string; overload; static;
    class function SerializeObject(const Value: TValue; Settings: TJsonSettings): string; overload; static;
    class function SerializeObject(const Value: TValue; Formatting: TJsonFormatting; EnumHandling: TJsonEnumHandling; const DateFormat: string; PreserveReferences: TJsonPreserveReferences; NamingStrategy: TJsonNamingStrategyClass = nil; NullValueHandling: TJsonNullValueHandling = TJsonNullValueHandling.Include): string; overload; static;
    class procedure SerializeObjectToStream(const Value: TValue; Stream: TStream; Settings: TJsonSettings = nil); overload; static;
    class function DeserializeObject<T>(const Json: string): T; overload; static;
    class function DeserializeObject<T>(const Json: string; Settings: TJsonSettings): T; overload; static;
    class function DeserializeObject<T>(const Json, DateFormat: string): T; overload; static;
    class function DeserializeObject<T>(const Json, DateFormat: string; NamingStrategy: TJsonNamingStrategyClass; MissingMemberHandling: TJsonMissingMemberHandling = TJsonMissingMemberHandling.Ignore): T; overload; static;
    class function DeserializeObject(const Json: string): TJsonValue; overload; static;
    class function DeserializeObject(const Json: string; Settings: TJsonSettings): TJsonValue; overload; static;
    class procedure PopulateObject(const Value: TObject; const Json: string); overload; static;
    class procedure PopulateObject(const Value: TObject; const Json: string; Settings: TJsonSettings); overload; static;

    // --- Delphi object <-> RFC 6902 ---------------------------------------
    // Contract: this API works exclusively on the serialized
    // JSON representation. CreatePatch serializes both objects with
    // the same NativeJson configuration and produces RFC 6902 from it.
    // ApplyPatch patches this JSON representation and materializes a
    // NEW T instance from it; the source object is not changed via Populate.
    //
    // State that is not part of the JSON mapping (e.g. [JsonIgnore],
    // MemberSelection/ShouldSerialize or purely serializer-side, non-
    // invertible transformers) is not copied from the source object.
    // After ApplyPatch such state comes only from the constructor, factory
    // or deserialization. So for round-trip capable settings:
    // Serialize(ApplyPatch(A, CreatePatch(A, B))) is semantically Serialize(B).
    // The caller owns the object returned by ApplyPatch.
    class function CreatePatch<T: class>(const OldValue, NewValue: T): TJsonArray; overload; static;
    class function CreatePatch<T: class>(const OldValue, NewValue: T; Settings: TJsonSettings): TJsonArray; overload; static;
    class function ApplyPatch<T: class>(const Value: T; const Patch: TJsonValue): T; overload; static;
    class function ApplyPatch<T: class>(const Value: T; const Patch: TJsonValue; Settings: TJsonSettings): T; overload; static;

    class function GenerateSchema<T>: NativeJson.Dom.JsonObject.TJsonObject; overload; static;
    class function GenerateSchema<T>(Settings: TJsonSettings): NativeJson.Dom.JsonObject.TJsonObject; overload; static;
    class function FormatJson(const Json: string; Formatting: TJsonFormatting): string; static;
    class function ValidateJsonSchema(const Json, SchemaJson: string; Options: TJsonSchemaValidationOptions = nil): TJsonSchemaValidationResult; overload; static;
    class function ValidateJsonSchema(const Json: string; Schema: NativeJson.Dom.Value.TJsonValue; Options: TJsonSchemaValidationOptions = nil): TJsonSchemaValidationResult; overload; static;

    class property DefaultSettings: TJsonSettingsProc read FDefaultSettings write FDefaultSettings;

    class function SerializeObject(const Value: TValue; const Config: TJsonSettingsProc): string; overload; static;
    class procedure SerializeObjectToStream(const Value: TValue; Stream: TStream; const Config: TJsonSettingsProc); overload; static;
    class procedure SerializeToFile(const Value: TValue; const FileName: string); overload; static;
    class procedure SerializeToFile(const Value: TValue; const FileName: string; Settings: TJsonSettings); overload; static;
    class procedure SerializeToFile(const Value: TValue; const FileName: string; const Config: TJsonSettingsProc); overload; static;

    class function DeserializeObject<T>(const Json: string; const Config: TJsonSettingsProc): T; overload; static;
    class function DeserializeFromStream<T>(Stream: TStream): T; overload; static;
    class function DeserializeFromStream<T>(Stream: TStream; Settings: TJsonSettings): T; overload; static;
    class function DeserializeFromStream<T>(Stream: TStream; const Config: TJsonSettingsProc): T; overload; static;
    class function DeserializeFromStream(Stream: TStream): TJsonValue; overload; static;

    // --- Sequential reading ----------------------------------------------
    // For a top-level array: read one element, process it,
    // free it, next. Peak memory therefore depends on the
    // size of ONE element, not on the count.
    //
    // For classes the handler gets the finished object and owns it
    // afterwards - whoever does not keep it frees it. Otherwise the
    // saved memory is gone again right away.
    class function DeserializeSequence<T>(const Json: string;
      const Handler: TProc<T>; Settings: TJsonSettings = nil): Integer; static;
    class function DeserializeSequenceFromStream<T>(Stream: TStream;
      const Handler: TProc<T>; Settings: TJsonSettings = nil): Integer; static;
    class function DeserializeSequenceFromFile<T>(const FileName: string;
      const Handler: TProc<T>; Settings: TJsonSettings = nil): Integer; static;
    class function DeserializeFromFile<T>(const FileName: string): T; overload; static;
    class function DeserializeFromFile<T>(const FileName: string; Settings: TJsonSettings): T; overload; static;
    class function DeserializeFromFile<T>(const FileName: string; const Config: TJsonSettingsProc): T; overload; static;
    class function DeserializeFromFile(const FileName: string): TJsonValue; overload; static;

    class function TryDeserializeObject<T>(const Json: string; out Value: T; out ErrorMessage: string): Boolean; overload; static;
    class function TryDeserializeObject<T>(const Json: string; Settings: TJsonSettings; out Value: T; out ErrorMessage: string): Boolean; overload; static;
    class function TryDeserializeFromFile<T>(const FileName: string; out Value: T; out ErrorMessage: string): Boolean; static;

    class function SerializeToBytes(const Value: TValue): TBytes; overload; static;
    class function SerializeToBytes(const Value: TValue; Settings: TJsonSettings): TBytes; overload; static;
    class function SerializeToBytes(const Value: TValue; const Config: TJsonSettingsProc): TBytes; overload; static;
    class function DeserializeFromBytes<T>(const RawBytes: TBytes): T; overload; static;
    class function DeserializeFromBytes<T>(const RawBytes: TBytes; Settings: TJsonSettings): T; overload; static;
    class function DeserializeFromBytes<T>(const RawBytes: TBytes; const Config: TJsonSettingsProc): T; overload; static;
    class function DeserializeFromBytes(const RawBytes: TBytes): TJsonValue; overload; static;

    class function Validate(const Value: TValue): TJsonValidationResult; overload; static;
    class function Validate(const Value: TValue; Settings: TJsonSettings): TJsonValidationResult; overload; static;
    class function IsValid(const Value: TValue): Boolean; overload; static;
    class function IsValid(const Value: TValue; out ErrorMessage: string): Boolean; overload; static;
  end;

implementation

class procedure JsonConvert.ConfigureSerializer(Serializer: TJsonSerializer; Settings: TJsonSettings);
begin
  if (Serializer = nil) or (Settings = nil) then Exit;
  Serializer.Formatting := Settings.Formatting;
  Serializer.WrapBytes := Settings.WrapBytes;
  Serializer.EnumHandling := Settings.EnumHandling;
  Serializer.DateFormat := Settings.DateFormat;
  Serializer.PreserveReferences := Settings.PreserveReferences;
  Serializer.TypeNameHandling := Settings.TypeNameHandling;
  Serializer.NamingStrategy := Settings.GetEffectiveNamingStrategy;
  Serializer.NullValueHandling := Settings.NullValueHandling;
  Serializer.DefaultValueHandling := Settings.DefaultValueHandling;
  Serializer.FluentContext := Settings.Fluent;
  Serializer.MemberSelection := Settings.MemberSelection;
  Serializer.KeySerializers := Settings.KeySerializers;
  Serializer.ValueTransformers := Settings.ValueTransformers;
end;

class procedure JsonConvert.ConfigureDeserializer(Deserializer: TJsonDeserializer; Settings: TJsonSettings);
begin
  if (Deserializer = nil) or (Settings = nil) then Exit;
  Deserializer.DateFormat := Settings.DateFormat;
  Deserializer.NamingStrategy := Settings.GetEffectiveNamingStrategy;
  Deserializer.MissingMemberHandling := Settings.MissingMemberHandling;
  Deserializer.StrictTypes := Settings.StrictTypes;
  Deserializer.Json5 := Settings.Json5;
  Deserializer.FluentContext := Settings.Fluent;
  Deserializer.MemberSelection := Settings.MemberSelection;
  Deserializer.CollectionAdapters := Settings.CollectionAdapters;
  Deserializer.Factories := Settings.Factories;
  Deserializer.KeyDeserializers := Settings.KeyDeserializers;
end;

class function JsonConvert.SerializeObject(const Value: TValue): string;
var
  Settings: TJsonSettings;
begin
  Settings := NewSettings;
  try
    Result := SerializeObject(Value, Settings);
  finally
    Settings.Free;
  end;
end;

class function JsonConvert.SerializeObject(const Value: TValue; Formatting: TJsonFormatting): string;
begin
  Result := SerializeObject(Value, Formatting, TJsonEnumHandling.ByName, '', TJsonPreserveReferences.None);
end;

class function JsonConvert.SerializeObject(const Value: TValue; Settings: TJsonSettings): string;
var
  Serializer: TJsonSerializer;
  LocalSettings: TJsonSettings;
begin
  LocalSettings := nil;
  if Settings = nil then
  begin
    LocalSettings := NewSettings;
    Settings := LocalSettings;
  end;
  try
    Serializer := TJsonSerializer.Create;
    try
      ConfigureSerializer(Serializer, Settings);
      Result := Serializer.SerializeToString(Value);
    finally
      Serializer.Free;
    end;
  finally
    LocalSettings.Free;
  end;
end;

class function JsonConvert.SerializeObject(const Value: TValue; Formatting: TJsonFormatting; EnumHandling: TJsonEnumHandling; const DateFormat: string; PreserveReferences: TJsonPreserveReferences; NamingStrategy: TJsonNamingStrategyClass; NullValueHandling: TJsonNullValueHandling): string;
var
  Settings: TJsonSettings;
begin
  Settings := NewSettings;
  try
    Settings.Formatting := Formatting;
    Settings.EnumHandling := EnumHandling;
    Settings.DateFormat := DateFormat;
    Settings.PreserveReferences := PreserveReferences;
    Settings.NamingStrategy := NamingStrategy;
    Settings.NullValueHandling := NullValueHandling;
    Result := SerializeObject(Value, Settings);
  finally
    Settings.Free;
  end;
end;

class procedure JsonConvert.SerializeObjectToStream(const Value: TValue; Stream: TStream; Settings: TJsonSettings);
var
  Serializer: TJsonSerializer;
  LocalSettings: TJsonSettings;
begin
  if Stream = nil then raise EArgumentNilException.Create('Stream');
  LocalSettings := nil;
  if Settings = nil then
  begin
    LocalSettings := NewSettings;
    Settings := LocalSettings;
  end;
  try
    Serializer := TJsonSerializer.Create;
    try
      ConfigureSerializer(Serializer, Settings);
      Serializer.Serialize(Stream, Value);
    finally
      Serializer.Free;
    end;
  finally
    LocalSettings.Free;
  end;
end;

class function JsonConvert.DeserializeObject<T>(const Json: string): T;
var
  Settings: TJsonSettings;
begin
  Settings := NewSettings;
  try
    Result := DeserializeObject<T>(Json, Settings);
  finally
    Settings.Free;
  end;
end;

class function JsonConvert.DeserializeObject<T>(const Json: string; Settings: TJsonSettings): T;
var
  Deserializer: TJsonDeserializer;
  LocalSettings: TJsonSettings;
  Value: TValue;
begin
  LocalSettings := nil;
  if Settings = nil then
  begin
    LocalSettings := NewSettings;
    Settings := LocalSettings;
  end;
  try
    Deserializer := TJsonDeserializer.Create;
    try
      ConfigureDeserializer(Deserializer, Settings);
      Value := Deserializer.Deserialize(Json, System.TypeInfo(T));
      if Value.IsEmpty then Result := Default(T) else Result := Value.AsType<T>;
    finally
      Deserializer.Free;
    end;
  finally
    LocalSettings.Free;
  end;
end;

class function JsonConvert.DeserializeObject<T>(const Json, DateFormat: string): T;
begin
  Result := DeserializeObject<T>(Json, DateFormat, nil, TJsonMissingMemberHandling.Ignore);
end;

class function JsonConvert.DeserializeObject<T>(const Json, DateFormat: string; NamingStrategy: TJsonNamingStrategyClass; MissingMemberHandling: TJsonMissingMemberHandling): T;
var
  Settings: TJsonSettings;
begin
  Settings := NewSettings;
  try
    Settings.DateFormat := DateFormat;
    Settings.NamingStrategy := NamingStrategy;
    Settings.MissingMemberHandling := MissingMemberHandling;
    Result := DeserializeObject<T>(Json, Settings);
  finally
    Settings.Free;
  end;
end;

class function JsonConvert.DeserializeObject(const Json: string): TJsonValue;
var
  Deserializer: TJsonDeserializer;
  Value: TValue;
begin
  Deserializer := TJsonDeserializer.Create;
  try
    Value := Deserializer.Deserialize(Json, System.TypeInfo(TJsonValue));
    if Value.IsEmpty then Result := nil else Result := Value.AsType<TJsonValue>;
  finally
    Deserializer.Free;
  end;
end;

class function JsonConvert.DeserializeObject(const Json: string; Settings: TJsonSettings): TJsonValue;
var
  Deserializer: TJsonDeserializer;
  Value: TValue;
begin
  Deserializer := TJsonDeserializer.Create;
  try
    ConfigureDeserializer(Deserializer, Settings);
    Value := Deserializer.Deserialize(Json, System.TypeInfo(TJsonValue));
    if Value.IsEmpty then Result := nil else Result := Value.AsType<TJsonValue>;
  finally
    Deserializer.Free;
  end;
end;

class procedure JsonConvert.PopulateObject(const Value: TObject; const Json: string);
begin
  PopulateObject(Value, Json, nil);
end;

class procedure JsonConvert.PopulateObject(const Value: TObject; const Json: string; Settings: TJsonSettings);
var
  Deserializer: TJsonDeserializer;
  Dom: TJsonValue;
  LocalSettings: TJsonSettings;
begin
  if Value = nil then raise EArgumentNilException.Create('Value');
  if Trim(Json) = '' then Exit;
  LocalSettings := nil;
  if Settings = nil then
  begin
    LocalSettings := NewSettings;
    Settings := LocalSettings;
  end;
  try
    Deserializer := TJsonDeserializer.Create;
    try
      ConfigureDeserializer(Deserializer, Settings);
      Dom := JsonConvert.DeserializeObject(Json);
      try
        Deserializer.Populate(Value, Dom);
      finally
        Dom.Free;
      end;
    finally
      Deserializer.Free;
    end;
  finally
    LocalSettings.Free;
  end;
end;

class function JsonConvert.CreatePatch<T>(const OldValue, NewValue: T): TJsonArray;
begin
  Result := CreatePatch<T>(OldValue, NewValue, nil);
end;

class function JsonConvert.CreatePatch<T>(const OldValue, NewValue: T;
  Settings: TJsonSettings): TJsonArray;
var
  LocalSettings: TJsonSettings;
  OldDom, NewDom: TJsonValue;
begin
  LocalSettings := nil;
  OldDom := nil;
  NewDom := nil;
  if Settings = nil then
  begin
    LocalSettings := NewSettings;
    Settings := LocalSettings;
  end;
  try
    // Deliberately uses the existing serializer facade. That way attributes,
    // fluent mapping, naming, converters and DefaultSettings apply exactly
    // as for normal NativeJson JSON. No second mapping path.
    OldDom := DomFromText(SerializeObject(TValue.From<T>(OldValue), Settings));
    NewDom := DomFromText(SerializeObject(TValue.From<T>(NewValue), Settings));
    Result := TJsonDiff.Compare(OldDom, NewDom);
  finally
    NewDom.Free;
    OldDom.Free;
    LocalSettings.Free;
  end;
end;

class function JsonConvert.ApplyPatch<T>(const Value: T;
  const Patch: TJsonValue): T;
begin
  Result := ApplyPatch<T>(Value, Patch, nil);
end;

class function JsonConvert.ApplyPatch<T>(const Value: T;
  const Patch: TJsonValue; Settings: TJsonSettings): T;
var
  LocalSettings: TJsonSettings;
  Deserializer: TJsonDeserializer;
  SourceDom, PatchedDom: TJsonValue;
  Deserialized: TValue;
begin
  Result := nil;
  LocalSettings := nil;
  Deserializer := nil;
  SourceDom := nil;
  PatchedDom := nil;
  if Settings = nil then
  begin
    LocalSettings := NewSettings;
    Settings := LocalSettings;
  end;
  try
    // Like TJsonPatch.Apply, this layer first patches a JSON mapping and
    // then reads a NEW instance. The source object is not changed via
    // Populate; normal serializer hooks run as in SerializeObject.
    SourceDom := DomFromText(SerializeObject(TValue.From<T>(Value), Settings));
    PatchedDom := TJsonPatch.Apply(SourceDom, Patch);

    Deserializer := TJsonDeserializer.Create;
    ConfigureDeserializer(Deserializer, Settings);
    Deserialized := Deserializer.Deserialize(PatchedDom, System.TypeInfo(T));
    if not Deserialized.IsEmpty then
      Result := Deserialized.AsType<T>;
  finally
    Deserializer.Free;
    PatchedDom.Free;
    SourceDom.Free;
    LocalSettings.Free;
  end;
end;

class function JsonConvert.GenerateSchema<T>: NativeJson.Dom.JsonObject.TJsonObject;
begin
  Result := GenerateSchema<T>(nil);
end;

class function JsonConvert.GenerateSchema<T>(Settings: TJsonSettings): NativeJson.Dom.JsonObject.TJsonObject;
var
  Generator: TJsonSchemaGenerator;
begin
  if Settings <> nil then Generator := TJsonSchemaGenerator.Create(Settings.Fluent) else Generator := TJsonSchemaGenerator.Create;
  try
    if Settings <> nil then
    begin
      Generator.EnumHandling := Settings.EnumHandling;
      Generator.MemberSelection := Settings.MemberSelection;
    end;
    Result := Generator.Generate<T>;
  finally
    Generator.Free;
  end;
end;

class function JsonConvert.NewSettings: TJsonSettings;
begin
  Result := TJsonSettings.Create;
  try
    if Assigned(FDefaultSettings) then FDefaultSettings(Result);
  except
    Result.Free;
    raise;
  end;
end;

class function JsonConvert.TextFromBytes(const RawBytes: TBytes; NumItems: Integer): string;
var
  Encoding: TEncoding;
  Preamble: Integer;
begin
  if NumItems <= 0 then Exit('');
  Encoding := nil;
  Preamble := TEncoding.GetBufferEncoding(RawBytes, Encoding, TEncoding.UTF8);
  if Preamble >= NumItems then Exit('');
  Result := Encoding.GetString(RawBytes, Preamble, NumItems - Preamble);
end;

class function JsonConvert.ReadStream(Stream: TStream): string;
const
  Block = 64 * 1024;
  AtEndMessage = 'Stream is positioned at the end. After writing to a stream, set Position to 0 before reading it back.';
  TooLarge = 'Stream is larger than 2 GB and cannot be read into a string';
var
  RawBytes: TBytes;
  Total, BytesRead: Integer;
  StreamSize, RunStart, Expected: Int64;
begin
  if Stream = nil then raise EArgumentNilException.Create('Stream');

  // The most common usage error: the same stream was just written and
  // is therefore at the end. Without this check zero bytes are read and
  // a syntax error is reported - and one looks for it in the JSON.
  StreamSize := Stream.Size;
  RunStart := Stream.Position;
  if (StreamSize > 0) and (RunStart >= StreamSize) then raise EJsonDeserializationError.Create(AtEndMessage);
  if StreamSize = 0 then raise EJsonDeserializationError.Create('Stream contains no data');

  Expected := StreamSize - RunStart;
  if Expected >= MaxInt then raise EJsonDeserializationError.Create(TooLarge);
  if Expected > 0 then SetLength(RawBytes, Expected + 1) else SetLength(RawBytes, Block);

  Total := 0;
  repeat
    if Total = Length(RawBytes) then
    begin
      if Length(RawBytes) > MaxInt div 2 then raise EJsonDeserializationError.Create(TooLarge);
      SetLength(RawBytes, Length(RawBytes) * 2);
    end;
    BytesRead := Stream.Read(RawBytes[Total], Length(RawBytes) - Total);
    Inc(Total, BytesRead);
  until BytesRead = 0;

  Result := TextFromBytes(RawBytes, Total);
end;

class function JsonConvert.SerializeToBytes(const Value: TValue): TBytes;
begin
  Result := SerializeToBytes(Value, TJsonSettings(nil));
end;

class function JsonConvert.SerializeToBytes(const Value: TValue; Settings: TJsonSettings): TBytes;
var
  Buffer: TBytesStream;
begin
  Buffer := TBytesStream.Create;
  try
    SerializeObjectToStream(Value, Buffer, Settings);
    Result := Copy(Buffer.Bytes, 0, Buffer.Size);
  finally
    Buffer.Free;
  end;
end;

class function JsonConvert.SerializeToBytes(const Value: TValue; const Config: TJsonSettingsProc): TBytes;
var
  Settings: TJsonSettings;
begin
  Settings := NewSettings;
  try
    if Assigned(Config) then Config(Settings);
    Result := SerializeToBytes(Value, Settings);
  finally
    Settings.Free;
  end;
end;

class function JsonConvert.DeserializeFromBytes<T>(const RawBytes: TBytes): T;
begin
  Result := DeserializeObject<T>(TextFromBytes(RawBytes, Length(RawBytes)));
end;

class function JsonConvert.DeserializeFromBytes<T>(const RawBytes: TBytes; Settings: TJsonSettings): T;
begin
  Result := DeserializeObject<T>(TextFromBytes(RawBytes, Length(RawBytes)), Settings);
end;

class function JsonConvert.DeserializeFromBytes<T>(const RawBytes: TBytes; const Config: TJsonSettingsProc): T;
begin
  Result := DeserializeObject<T>(TextFromBytes(RawBytes, Length(RawBytes)), Config);
end;

class function JsonConvert.DeserializeFromBytes(const RawBytes: TBytes): TJsonValue;
begin
  Result := DeserializeObject(TextFromBytes(RawBytes, Length(RawBytes)));
end;

class function JsonConvert.SerializeObject(const Value: TValue; const Config: TJsonSettingsProc): string;
var
  Settings: TJsonSettings;
begin
  Settings := NewSettings;
  try
    if Assigned(Config) then Config(Settings);
    Result := SerializeObject(Value, Settings);
  finally
    Settings.Free;
  end;
end;

class procedure JsonConvert.SerializeObjectToStream(const Value: TValue; Stream: TStream; const Config: TJsonSettingsProc);
var
  Settings: TJsonSettings;
begin
  Settings := NewSettings;
  try
    if Assigned(Config) then Config(Settings);
    SerializeObjectToStream(Value, Stream, Settings);
  finally
    Settings.Free;
  end;
end;

class procedure JsonConvert.SerializeToFile(const Value: TValue; const FileName: string);
begin
  SerializeToFile(Value, FileName, TJsonSettings(nil));
end;

class procedure JsonConvert.SerializeToFile(const Value: TValue; const FileName: string; Settings: TJsonSettings);
var
  FileStream: TFileStream;
begin
  FileStream := TFileStream.Create(FileName, fmCreate);
  try
    SerializeObjectToStream(Value, FileStream, Settings);
  finally
    FileStream.Free;
  end;
end;

class procedure JsonConvert.SerializeToFile(const Value: TValue; const FileName: string; const Config: TJsonSettingsProc);
var
  Settings: TJsonSettings;
begin
  Settings := NewSettings;
  try
    if Assigned(Config) then Config(Settings);
    SerializeToFile(Value, FileName, Settings);
  finally
    Settings.Free;
  end;
end;

class function JsonConvert.DeserializeObject<T>(const Json: string; const Config: TJsonSettingsProc): T;
var
  Settings: TJsonSettings;
begin
  Settings := NewSettings;
  try
    if Assigned(Config) then Config(Settings);
    Result := DeserializeObject<T>(Json, Settings);
  finally
    Settings.Free;
  end;
end;

class function JsonConvert.DeserializeFromStream<T>(Stream: TStream): T;
begin
  Result := DeserializeObject<T>(ReadStream(Stream));
end;

class function JsonConvert.DeserializeFromStream<T>(Stream: TStream; Settings: TJsonSettings): T;
begin
  Result := DeserializeObject<T>(ReadStream(Stream), Settings);
end;

class function JsonConvert.DeserializeFromStream<T>(Stream: TStream; const Config: TJsonSettingsProc): T;
begin
  Result := DeserializeObject<T>(ReadStream(Stream), Config);
end;

class function JsonConvert.DeserializeFromStream(Stream: TStream): TJsonValue;
begin
  Result := DeserializeObject(ReadStream(Stream));
end;

class function JsonConvert.DeserializeSequence<T>(const Json: string;
  const Handler: TProc<T>; Settings: TJsonSettings): Integer;
var
  ElementSeq: TJsonElementSequence;
  Deserializer: TJsonDeserializer;
  LocalSettings: TJsonSettings;
  Element: TJsonValue;
  InputValue: TValue;
begin
  if not Assigned(Handler) then raise EArgumentNilException.Create('Handler');
  Result := 0;
  LocalSettings := nil;
  if Settings = nil then
  begin
    LocalSettings := NewSettings;
    Settings := LocalSettings;
  end;
  try
    // ONE deserializer for all elements. Building it per element
    // would warm up the RTTI cache every time and eat up the
    // gain again.
    Deserializer := TJsonDeserializer.Create;
    try
      ConfigureDeserializer(Deserializer, Settings);
      ElementSeq := TJsonElementSequence.Create(Json);
      try
        while ElementSeq.NextItem(Element) do
        begin
          try
            InputValue := Deserializer.Deserialize(Element, System.TypeInfo(T));
          finally
            // The node is no longer needed once the object
            // exists. Freeing it is the whole point.
            Element.Free;
          end;
          Inc(Result);
          if InputValue.IsEmpty then Handler(Default(T)) else Handler(InputValue.AsType<T>);
        end;
      finally
        ElementSeq.Free;
      end;
    finally
      Deserializer.Free;
    end;
  finally
    LocalSettings.Free;
  end;
end;

class function JsonConvert.DeserializeSequenceFromStream<T>(Stream: TStream;
  const Handler: TProc<T>; Settings: TJsonSettings): Integer;
begin
  Result := DeserializeSequence<T>(ReadStream(Stream), Handler, Settings);
end;

class function JsonConvert.DeserializeSequenceFromFile<T>(const FileName: string;
  const Handler: TProc<T>; Settings: TJsonSettings): Integer;
var
  AStream: TFileStream;
begin
  AStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := DeserializeSequenceFromStream<T>(AStream, Handler, Settings);
  finally
    AStream.Free;
  end;
end;

class function JsonConvert.DeserializeFromFile<T>(const FileName: string): T;
begin
  Result := DeserializeFromFile<T>(FileName, TJsonSettings(nil));
end;

class function JsonConvert.DeserializeFromFile<T>(const FileName: string; Settings: TJsonSettings): T;
var
  FileStream: TFileStream;
begin
  FileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := DeserializeFromStream<T>(FileStream, Settings);
  finally
    FileStream.Free;
  end;
end;

class function JsonConvert.DeserializeFromFile<T>(const FileName: string; const Config: TJsonSettingsProc): T;
var
  Settings: TJsonSettings;
begin
  Settings := NewSettings;
  try
    if Assigned(Config) then Config(Settings);
    Result := DeserializeFromFile<T>(FileName, Settings);
  finally
    Settings.Free;
  end;
end;

class function JsonConvert.DeserializeFromFile(const FileName: string): TJsonValue;
var
  FileStream: TFileStream;
begin
  FileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := DeserializeFromStream(FileStream);
  finally
    FileStream.Free;
  end;
end;

class function JsonConvert.TryDeserializeObject<T>(const Json: string; out Value: T; out ErrorMessage: string): Boolean;
begin
  Result := TryDeserializeObject<T>(Json, nil, Value, ErrorMessage);
end;

class function JsonConvert.TryDeserializeObject<T>(const Json: string; Settings: TJsonSettings; out Value: T; out ErrorMessage: string): Boolean;
begin
  Value := Default(T);
  ErrorMessage := '';
  try
    Value := DeserializeObject<T>(Json, Settings);
    Result := True;
  except
    on E: Exception do
    begin
      Value := Default(T);
      ErrorMessage := E.ClassName + ': ' + E.Message;
      Result := False;
    end;
  end;
end;

class function JsonConvert.TryDeserializeFromFile<T>(const FileName: string; out Value: T; out ErrorMessage: string): Boolean;
begin
  Value := Default(T);
  ErrorMessage := '';
  try
    Value := DeserializeFromFile<T>(FileName);
    Result := True;
  except
    on E: Exception do
    begin
      Value := Default(T);
      ErrorMessage := E.ClassName + ': ' + E.Message;
      Result := False;
    end;
  end;
end;

class function JsonConvert.Validate(const Value: TValue): TJsonValidationResult;
begin
  Result := Validate(Value, nil);
end;

class function JsonConvert.Validate(const Value: TValue; Settings: TJsonSettings): TJsonValidationResult;
var
  RuleValidator: TJsonValidator;
  LocalSettings: TJsonSettings;
begin
  LocalSettings := nil;
  if Settings = nil then
  begin
    LocalSettings := NewSettings;
    Settings := LocalSettings;
  end;
  try
    RuleValidator := TJsonValidator.Create(Settings.Fluent);
    try
      RuleValidator.NamingStrategy := Settings.GetEffectiveNamingStrategy;
      RuleValidator.MemberSelection := Settings.MemberSelection;
      Result := RuleValidator.Validate(Value);
    finally
      RuleValidator.Free;
    end;
  finally
    LocalSettings.Free;
  end;
end;

class function JsonConvert.IsValid(const Value: TValue): Boolean;
var
  IgnoredMessage: string;
begin
  Result := IsValid(Value, IgnoredMessage);
end;

class function JsonConvert.IsValid(const Value: TValue; out ErrorMessage: string): Boolean;
var
  Outcome: TJsonValidationResult;
begin
  Outcome := Validate(Value);
  try
    Result := Outcome.IsValid;
    if Result then ErrorMessage := '' else ErrorMessage := Outcome.ToString;
  finally
    Outcome.Free;
  end;
end;

class function JsonConvert.ValidateJsonSchema(const Json, SchemaJson: string; Options: TJsonSchemaValidationOptions): TJsonSchemaValidationResult;
var
  Schema: NativeJson.Dom.Value.TJsonValue;
begin
  Schema := DeserializeObject(SchemaJson);
  try
    Result := ValidateJsonSchema(Json, Schema, Options);
  finally
    Schema.Free;
  end;
end;

class function JsonConvert.ValidateJsonSchema(const Json: string; Schema: NativeJson.Dom.Value.TJsonValue; Options: TJsonSchemaValidationOptions): TJsonSchemaValidationResult;
var
  Validator: TJsonSchemaValidator;
  Instance: NativeJson.Dom.Value.TJsonValue;
begin
  if Schema = nil then raise EArgumentNilException.Create('Schema');
  Instance := DomFromText(Json);
  try
    Validator := TJsonSchemaValidator.Create(Schema, Options);
    try
      Result := Validator.Validate(Instance);
    finally
      Validator.Free;
    end;
  finally
    Instance.Free;
  end;
end;

class function JsonConvert.FormatJson(const Json: string; Formatting: TJsonFormatting): string;
var
  Value: NativeJson.Dom.Value.TJsonValue;
begin
  // Own reader, own DOM, own writer. Numbers keep their
  // notation: 1e2 stays 1e2, and an integer beyond
  // Int64 is not passed through floating point.
  if not TryDomFromText(Json, Value) then
    raise EJsonDeserializationError.Create('Invalid JSON');
  try
    Result := DomToText(Value, Formatting, 2);
  finally
    Value.Free;
  end;
end;

end.
