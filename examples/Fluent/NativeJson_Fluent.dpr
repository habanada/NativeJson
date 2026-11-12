{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_Fluent;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  NativeJson.Main,
  NativeJson.Fluent, // fluent interface
  NativeJson.Settings;

type
  // A "foreign" class without attributes
  TLegacySystem = class
  public
    F_Internal_ID: Integer;
    SecretKey: string; // must not end up in the JSON
    LastLogin: TDateTime;
  end;

var
  Sys: TLegacySystem;
  Settings: TJsonSettings;
  Json: string;
begin
  Sys := TLegacySystem.Create;
  Settings := TJsonSettings.Create;
  try
    Sys.F_Internal_ID := 555;
    Sys.SecretKey := '12345';
    Sys.LastLogin := Now;

    // --- FLUENT CONFIGURATION ---
    // The rules are defined at runtime!
    Settings.Fluent.Entity<TLegacySystem>
      .Map('F_Internal_ID').Name('id').EndMember // rename
      .Map('SecretKey').Ignore;                  // ignore

    // Serialize with settings
    Settings.Formatting := TJsonFormatting.Indented;
    Json := JsonConvert.SerializeObject(Sys, Settings);
    
    Writeln(Json);
  finally
    Sys.Free;
    Settings.Free;
  end;
  ReadLn;
end.