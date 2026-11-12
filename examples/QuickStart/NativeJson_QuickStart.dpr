{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_QuickStart;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  NativeJson.Main,       // the facade
  NativeJson.Attributes; // for [JsonProperty]

type
  TUser = class
  private
    FName: string;
    FAge: Integer;
  public
    [JsonProperty('full_name')] // attribute control
    property Name: string read FName write FName;
    property Age: Integer read FAge write FAge;
  end;

var
  User, Clone: TUser;
  Json: string;
begin
  User := TUser.Create;
  try
    User.Name := 'Delphi Developer';
    User.Age := 29;

    // 1. Serialize
    Json := JsonConvert.SerializeObject(User);
    Writeln('JSON: ' + Json);

    // 2. Deserialize
    Clone := JsonConvert.DeserializeObject<TUser>(Json);
    try
      Writeln('Restored: ' + Clone.Name);
    finally
      Clone.Free;
    end;
  finally
    User.Free;
  end;
  ReadLn;
end.