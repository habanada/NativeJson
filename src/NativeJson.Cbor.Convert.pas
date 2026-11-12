{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Cbor.Convert;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Rtti,
  {$ELSE}
  System.SysUtils,
  System.Rtti,
  {$ENDIF}
  NativeJson.Settings,
  NativeJson.Cbor;

type
  CborConvert = class abstract
  public
    class function SerializeObject(const Value: TValue; Settings: TJsonSettings = nil; Options: TJsonCborOptions = nil): TBytes; static;
    class function DeserializeObject<T>(const Data: TBytes; Settings: TJsonSettings = nil; Options: TJsonCborOptions = nil): T; static;
  end;

implementation

uses
  NativeJson.Main;

class function CborConvert.SerializeObject(const Value: TValue; Settings: TJsonSettings; Options: TJsonCborOptions): TBytes;
var
  Json: string;
  Wrapped: Boolean;
begin
  if Settings = nil then
    Json := JsonConvert.SerializeObject(Value,
      procedure(S: TJsonSettings)
      begin
        S.WrapBytes := True;
      end)
  else
  begin
    Wrapped := Settings.WrapBytes;
    Settings.WrapBytes := True;
    try
      Json := JsonConvert.SerializeObject(Value, Settings);
    finally
      Settings.WrapBytes := Wrapped;
    end;
  end;
  Result := JsonToCbor(Json, Options);
end;

class function CborConvert.DeserializeObject<T>(const Data: TBytes; Settings: TJsonSettings; Options: TJsonCborOptions): T;
var
  Json: string;
  OwnOptions: TJsonCborOptions;
  Mode: TJsonCborBytesMode;
begin
  OwnOptions := nil;
  if Options = nil then
  begin
    OwnOptions := TJsonCborOptions.Create;
    Options := OwnOptions;
  end;
  Mode := Options.BytesMode;
  Options.BytesMode := cbmWrapped;
  try
    Json := CborToJson(Data, Options);
  finally
    Options.BytesMode := Mode;
    OwnOptions.Free;
  end;
  if Settings = nil then Result := JsonConvert.DeserializeObject<T>(Json)
  else Result := JsonConvert.DeserializeObject<T>(Json, Settings);
end;

end.
