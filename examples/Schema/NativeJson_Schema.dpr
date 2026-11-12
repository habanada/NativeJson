{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_Schema;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  NativeJson.Main,
  NativeJson.Dom.JsonObject,
  NativeJson.Schema.Attributes; // validation attributes

type
  [JsonDescription('A product in the shopping cart')]
  TProduct = class
  private
    FSKU: string;
    FPrice: Double;
  public
    [JsonRequired]
    [JsonPattern('^[A-Z]{3}-\d{3}$')] // RegEx validation
    [JsonDescription('Article number (e.g. ABC-123)')]
    property SKU: string read FSKU write FSKU;

    [JsonRange('0.01', '9999.99')] // min/max validation
    property Price: Double read FPrice write FPrice;
  end;

var
  Schema: TJsonObject;
begin
  // Generate the schema from the class
  Schema := JsonConvert.GenerateSchema<TProduct>;
  try
    Writeln('--- JSON SCHEMA (Draft 2020-12) ---');
    Writeln(Schema.ToJson);
  finally
    Schema.Free;
  end;
  ReadLn;
end.