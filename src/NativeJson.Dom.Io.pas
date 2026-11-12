{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Dom.Io;

// Text to DOM and DOM to text - without RTTI and without System.JSON.
//
//   This unit deliberately sits low: it only knows the tokenizer, the DOM
//   and the writer. That way the schema generator, validator and
//   code generator can read and write JSON without pulling in the serializer and
//   with it half of the RTTI machinery.

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  {$ENDIF}
  NativeJson.Core.Reader,
  NativeJson.Core.Tokens,
  NativeJson.Dom.Value,
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.Primitive,
  NativeJson.Serializer.Writer;

type
  EJsonDomError = class(Exception);

// Builds a DOM from text. Invalid JSON raises EJsonDomError,
// nil is never returned. The caller owns the result.
function DomFromText(const Json: string): TJsonValue;

// Like DomFromText, but reports errors through the return value.
function TryDomFromText(const Json: string; out InputValue: TJsonValue): Boolean;

// Builds ONE element from a reader that is already positioned on its first
// token. For the sequence reader, which processes a large array piece by piece
// instead of loading it into memory as a whole.
function DomFromReader(Reader: TJsonReader): TJsonValue;

// Outputs a DOM. Numbers keep their notation from the input.
function DomToText(Value: TJsonValue;
  Formatting: TJsonFormatting = TJsonFormatting.None;
  Indentation: Integer = 2): string;

// Writes a DOM into an already open writer.
procedure WriteDom(Writer: TJsonWriter; Value: TJsonValue);

implementation

uses
  {$IFDEF FPC}
  Generics.Collections;
  {$ELSE}
  System.Generics.Collections;
  {$ENDIF}

function BuildFromCurrent(Reader: TJsonReader): TJsonValue; forward;

function BuildObject(Reader: TJsonReader): TJsonValue;
var
  Obj: TJsonObject;
  Name: string;
begin
  Obj := TJsonObject.Create;
  try
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndObject then Exit(Obj);
      if Reader.TokenType <> TJsonToken.PropertyName then
        raise EJsonDomError.Create('Expected property name');
      Name := Reader.Value;
      if not Reader.Read then
        raise EJsonDomError.Create('Unexpected end while reading property value');
      Obj.AddPair(Name, BuildFromCurrent(Reader));
    end;
    raise EJsonDomError.Create('Unterminated object');
  except
    Obj.Free;
    raise;
  end;
end;

function BuildList(Reader: TJsonReader): TJsonValue;
var
  Arr: TJsonArray;
begin
  Arr := TJsonArray.Create;
  try
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndArray then Exit(Arr);
      Arr.Add(BuildFromCurrent(Reader));
    end;
    raise EJsonDomError.Create('Unterminated array');
  except
    Arr.Free;
    raise;
  end;
end;

function BuildFromCurrent(Reader: TJsonReader): TJsonValue;
begin
  case Reader.TokenType of
    TJsonToken.StartObject: Result := BuildObject(Reader);
    TJsonToken.StartArray: Result := BuildList(Reader);
    TJsonToken.Str: Result := TJsonString.Create(Reader.Value);
    // The raw text is the only lossless source. 1e2 stays 1e2,
    // and a number beyond Int64 loses nothing.
    TJsonToken.Integer: Result := TJsonNumber.Create(Reader.RawValue, False);
    TJsonToken.Float: Result := TJsonNumber.Create(Reader.RawValue, True);
    TJsonToken.Boolean: Result := TJsonBoolean.Create(Reader.ValueAsBool);
    TJsonToken.Null, TJsonToken.Undefined: Result := TJsonNull.Create;
  else
    raise EJsonDomError.Create('Token cannot be converted to DOM');
  end;
end;

function DomFromReader(Reader: TJsonReader): TJsonValue;
begin
  if Reader = nil then raise EJsonDomError.Create('Reader is nil');
  Result := BuildFromCurrent(Reader);
end;

function DomFromText(const Json: string): TJsonValue;
var
  Reader: TJsonReader;
begin
  Reader := TJsonReader.Create(Json);
  try
    if not Reader.Read then raise EJsonDomError.Create('Empty JSON input');
    Result := BuildFromCurrent(Reader);
    // Nothing may follow the value. Without this check
    // {"a":1} xyz would pass silently.
    try
      if Reader.Read then raise EJsonDomError.Create('Unexpected content after the JSON value');
    except
      Result.Free;
      raise;
    end;
  finally
    Reader.Free;
  end;
end;

function TryDomFromText(const Json: string; out InputValue: TJsonValue): Boolean;
begin
  InputValue := nil;
  try
    InputValue := DomFromText(Json);
    Result := True;
  except
    InputValue := nil;
    Result := False;
  end;
end;

procedure WriteDom(Writer: TJsonWriter; Value: TJsonValue);
var
  Pair: TPair<string, TJsonValue>;
  I: Integer;
  Raw: string;
begin
  if (Value = nil) or (Value is TJsonNull) then
  begin
    Writer.WriteNull;
    Exit;
  end;
  if Value is TJsonObject then
  begin
    Writer.WriteStartObject;
    for Pair in TJsonObject(Value) do
    begin
      Writer.WritePropertyName(Pair.Key);
      WriteDom(Writer, Pair.Value);
    end;
    Writer.WriteEndObject;
    Exit;
  end;
  if Value is TJsonArray then
  begin
    Writer.WriteStartArray;
    for I := 0 to TJsonArray(Value).Count - 1 do
      WriteDom(Writer, TJsonArray(Value)[I]);
    Writer.WriteEndArray;
    Exit;
  end;
  if Value is TJsonBoolean then
  begin
    Writer.WriteValue(Value.AsBoolean);
    Exit;
  end;
  if Value is TJsonNumber then
  begin
    // Via WriteRaw, so the notation of the input is kept.
    // WriteValue(Double) would turn 1e2 into 100 and send large integers
    // through the floating point representation.
    Raw := Value.AsRawText;
    if Raw = '' then Raw := '0';
    Writer.WriteRaw(Raw);
    Exit;
  end;
  Writer.WriteValue(Value.AsString);
end;

function DomToText(Value: TJsonValue; Formatting: TJsonFormatting;
  Indentation: Integer): string;
var
  Writer: TJsonWriter;
begin
  Writer := TJsonWriter.Create;
  try
    Writer.Formatting := Formatting;
    Writer.IndentCharCount := Indentation;
    WriteDom(Writer, Value);
    Writer.Flush;
    Result := Writer.ToJson;
  finally
    Writer.Free;
  end;
end;

end.
