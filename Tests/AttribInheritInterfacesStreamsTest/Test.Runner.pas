{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Test.Runner;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils, Classes, TypInfo, Rtti,
  {$ELSE}
  System.SysUtils, System.Classes, System.TypInfo, System.Rtti,
  {$ENDIF}
  Test.Logistics.Model,
  NativeJson.Main, NativeJson.Dom.JsonObject, NativeJson.Fluent, NativeJson.Attributes, NativeJson.Serializer.Writer;

procedure RunComplexSuite;

implementation

// Create a complex object
function CreateMockShipment: TShipmentOrder;
var
  P: TParcel;
  Pal: TPallet;
  RawPDF: TBytes;
begin
  Result := TShipmentOrder.Create;
  Result.Status := ssInTransit;
  Result.SecretNote := 'Top Secret Delivery code 1234'; // should become visible via fluent

  // 1. Fill polymorphism
  P := TParcel.Create;
  P.TrackingCode := 'DHL-123';
  P.Weight := 2.5;
  P.IsFragile := True;
  Result.Cargo.Add(P);

  Pal := TPallet.Create;
  Pal.TrackingCode := 'EUR-PAL-99';
  Pal.Weight := 150.0;
  Pal.LayerCount := 3;
  Pal.Material := 'Wood';
  Result.Cargo.Add(Pal);

  // 2. Fill the dictionary (test Variant support)
  Result.Meta.Add('Priority', 1); // Integer
  Result.Meta.Add('CustomerName', 'Acme Corp'); // String
  Result.Meta.Add('IsExpress', True); // Boolean
  Result.Meta.Add('CustomData', 3.14159); // Float

  // 3. Fill the stream (test binary support)
  RawPDF := TEncoding.UTF8.GetBytes('%PDF-1.4 Mock Data...');
  Result.Document.WriteBuffer(RawPDF[0], Length(RawPDF));
  Result.Document.Position := 0;
end;

procedure RunComplexSuite;
var
  Shipment: TShipmentOrder;
  Settings: TJsonSettings;
  JsonOutput: string;
  SchemaOutput: TJsonObject;
  Rehydrated: TShipmentOrder;
  SchemaStr: string;
begin
  Writeln('=== STARTING ENTERPRISE COMPLEXITY TEST ===');
  
  Shipment := CreateMockShipment;
  Settings := TJsonSettings.Create;
  try
    // ---------------------------------------------------------
    // TEST 1: Fluent Configuration Override
    // ---------------------------------------------------------
    Writeln('[1] Configuring Fluent Rules...');
    
    // Rule: we want to see 'SecretNote' DESPITE [JsonIgnore].
    // And we rename 'FStatus' to 'current_state'.
    Settings.Fluent.Entity<TShipmentOrder>
      .Map('SecretNote')
        .Name('admin_note')
        .Required(True)     // fluent mapping overrides [JsonIgnore]
      .EndMember
      .Map('Status').Name('current_state');

    // Rule: enable polymorphism
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
    Settings.Formatting := TJsonFormatting.Indented;

    // ---------------------------------------------------------
    // TEST 2: Serialization (High Pressure)
    // ---------------------------------------------------------
    Writeln('[2] Serializing complex structure...');
    JsonOutput := JsonConvert.SerializeObject(Shipment, Settings);
    
    Writeln('--- JSON RESULT (Snippet) ---');
    Writeln(Copy(JsonOutput, 1, 500) + '...'); 
    Writeln('-----------------------------');

    // Checks
    if Pos('admin_note', JsonOutput) > 0 then Writeln(' -> OK: Fluent override works (Secret visible)')
    else Writeln(' -> FAIL: SecretNote missing');

    if Pos('current_state', JsonOutput) > 0 then Writeln(' -> OK: Renaming works')
    else Writeln(' -> FAIL: Status renaming failed');

    if Pos('$type', JsonOutput) > 0 then Writeln(' -> OK: Polymorphism active ($type present)')
    else Writeln(' -> FAIL: Polymorphism missing');

    // ---------------------------------------------------------
    // TEST 3: Schema Generation (Swagger Ready)
    // ---------------------------------------------------------
    Writeln('[3] Generating High-End Schema...');
    // The schema should use the fluent settings too!
    SchemaOutput := JsonConvert.GenerateSchema<TShipmentOrder>(Settings);
    try
      SchemaStr := SchemaOutput.ToJson;
      if Pos('oneOf', SchemaStr) > 0 then Writeln(' -> OK: Polymorphism Schema (oneOf) generated')
      else Writeln(' -> FAIL: No oneOf in Schema');
      
      if Pos('contentEncoding', SchemaStr) > 0 then Writeln(' -> OK: Stream detected as Base64')
      else Writeln(' -> FAIL: Stream Schema wrong');
      
      // Writeln(SchemaStr); // Optional debug
    finally
      SchemaOutput.Free;
    end;

    // ---------------------------------------------------------
    // TEST 4: Roundtrip (Deserialization)
    // ---------------------------------------------------------
    Writeln('[4] Roundtrip Deserialization...');
    Rehydrated := JsonConvert.DeserializeObject<TShipmentOrder>(JsonOutput, Settings);
    try
      if Rehydrated.Cargo.InternalList.Count = 2 then
        Writeln(' -> OK: Duck Typing List restored (Count 2)')
      else
        Writeln(' -> FAIL: List count mismatch');

      if Rehydrated.Cargo.InternalList[0] is TParcel then
        Writeln(' -> OK: Polymorphism restored (Item 1 is TParcel)')
      else
        Writeln(' -> FAIL: Item 1 type mismatch');

      if Rehydrated.Document.Size > 0 then
        Writeln(' -> OK: Stream restored')
      else
        Writeln(' -> FAIL: Stream empty');
        
    finally
      Rehydrated.Free;
    end;

  finally
    Settings.Free;
    Shipment.Free;
  end;
  
  Writeln('=== SUITE FINISHED ===');
end;

end.