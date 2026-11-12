{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.SystemJson;

interface

{$I NativeJson.inc}

uses
  System.JSON,
  NativeJson.Dom.Value,
  NativeJson.Schema.Validation,
  NativeJson.Schema.Validator;

function NativeJsonFromSystemJson(Value: System.JSON.TJSONValue): NativeJson.Dom.Value.TJsonValue;

function CreateSchemaValidator(Schema: System.JSON.TJSONValue; Options: TJsonSchemaValidationOptions = nil): TJsonSchemaValidator;
procedure RegisterSystemJsonSchema(Validator: TJsonSchemaValidator; const Uri: string; Schema: System.JSON.TJSONValue);
function ValidateSystemJson(Validator: TJsonSchemaValidator; Instance: System.JSON.TJSONValue): TJsonSchemaValidationResult; overload;
function ValidateSystemJson(Instance, Schema: System.JSON.TJSONValue; Options: TJsonSchemaValidationOptions = nil): TJsonSchemaValidationResult; overload;

implementation

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE}
  System.SysUtils,
  {$ENDIF}
  NativeJson.Dom.Primitive,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.JsonObject;

function NativeJsonFromSystemJson(Value: System.JSON.TJSONValue): NativeJson.Dom.Value.TJsonValue;
var
  Obj: NativeJson.Dom.JsonObject.TJsonObject;
  Arr: NativeJson.Dom.JsonArray.TJsonArray;
  Pair: System.JSON.TJSONPair;
  Item: System.JSON.TJSONValue;
  Raw: string;
begin
  if (Value = nil) or (Value is System.JSON.TJSONNull) then Exit(NativeJson.Dom.Primitive.TJsonNull.Create);
  if Value is System.JSON.TJSONBool then Exit(NativeJson.Dom.Primitive.TJsonBoolean.Create(System.JSON.TJSONBool(Value).AsBoolean));
  if Value is System.JSON.TJSONNumber then
  begin
    Raw := Value.Value;
    Exit(NativeJson.Dom.Primitive.TJsonNumber.Create(Raw, Raw.Contains('.') or Raw.Contains('e') or Raw.Contains('E')));
  end;
  if Value is System.JSON.TJSONArray then
  begin
    Arr := NativeJson.Dom.JsonArray.TJsonArray.Create;
    try
      for Item in System.JSON.TJSONArray(Value) do Arr.Add(NativeJsonFromSystemJson(Item));
      Exit(Arr);
    except
      Arr.Free;
      raise;
    end;
  end;
  if Value is System.JSON.TJSONObject then
  begin
    Obj := NativeJson.Dom.JsonObject.TJsonObject.Create;
    try
      for Pair in System.JSON.TJSONObject(Value) do Obj.AddPair(Pair.JsonString.Value, NativeJsonFromSystemJson(Pair.JsonValue));
      Exit(Obj);
    except
      Obj.Free;
      raise;
    end;
  end;
  Result := NativeJson.Dom.Primitive.TJsonString.Create(Value.Value);
end;

function CreateSchemaValidator(Schema: System.JSON.TJSONValue; Options: TJsonSchemaValidationOptions): TJsonSchemaValidator;
var
  NativeSchema: NativeJson.Dom.Value.TJsonValue;
begin
  if Schema = nil then raise EArgumentNilException.Create('Schema');
  NativeSchema := NativeJsonFromSystemJson(Schema);
  try
    Result := TJsonSchemaValidator.Create(NativeSchema, Options);
  finally
    NativeSchema.Free;
  end;
end;

procedure RegisterSystemJsonSchema(Validator: TJsonSchemaValidator; const Uri: string; Schema: System.JSON.TJSONValue);
var
  NativeSchema: NativeJson.Dom.Value.TJsonValue;
begin
  if Validator = nil then raise EArgumentNilException.Create('Validator');
  if Schema = nil then raise EArgumentNilException.Create('Schema');
  NativeSchema := NativeJsonFromSystemJson(Schema);
  try
    Validator.RegisterSchema(Uri, NativeSchema);
  finally
    NativeSchema.Free;
  end;
end;

function ValidateSystemJson(Validator: TJsonSchemaValidator; Instance: System.JSON.TJSONValue): TJsonSchemaValidationResult;
var
  NativeInstance: NativeJson.Dom.Value.TJsonValue;
begin
  if Validator = nil then raise EArgumentNilException.Create('Validator');
  if Instance = nil then raise EArgumentNilException.Create('Instance');
  NativeInstance := NativeJsonFromSystemJson(Instance);
  try
    Result := Validator.Validate(NativeInstance);
  finally
    NativeInstance.Free;
  end;
end;

function ValidateSystemJson(Instance, Schema: System.JSON.TJSONValue; Options: TJsonSchemaValidationOptions): TJsonSchemaValidationResult;
var
  Validator: TJsonSchemaValidator;
begin
  if Instance = nil then raise EArgumentNilException.Create('Instance');
  Validator := CreateSchemaValidator(Schema, Options);
  try
    Result := ValidateSystemJson(Validator, Instance);
  finally
    Validator.Free;
  end;
end;

end.
