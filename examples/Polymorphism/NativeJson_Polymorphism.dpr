{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_Polymorphism;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Generics.Collections,
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Settings; // for TypeNameHandling

type
  TCircle = class;
  TRectangle = class;

  // The base class must know its child classes (for deserialization)
  [JsonKnownType('TCircle')]
  [JsonKnownType('TRectangle')]
  TShape = class
  public
    Name: string;
  end;

  TCircle = class(TShape)
  public
    Radius: Double;
  end;

  TRectangle = class(TShape)
  public
    Width, Height: Double;
  end;

var
  Shapes: TObjectList<TShape>;
  Settings: TJsonSettings;
  Json: string;
  C: TCircle;
  R: TRectangle;
begin
  Shapes := TObjectList<TShape>.Create;
  Settings := TJsonSettings.Create;
  try
    // Fill the polymorphic list
    C := TCircle.Create; C.Name := 'MyCircle'; C.Radius := 10.5;
    Shapes.Add(C);
    
    R := TRectangle.Create; R.Name := 'MyRect'; R.Width := 20; R.Height := 30;
    Shapes.Add(R);

    // Enable TypeNameHandling so that "$type" is written
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
    // TShape and its descendants only have public fields, no properties
    Settings.MemberSelection := [TJsonMemberType.mtProperties, TJsonMemberType.mtFields];
    Settings.Formatting := TJsonFormatting.Indented;

    Json := JsonConvert.SerializeObject(Shapes, Settings);
    Writeln(Json);
    
    // Proof: the JSON now contains "$type": "NativeJson_Polymorphism.TCircle"
  finally
    Shapes.Free;
    Settings.Free;
  end;
  ReadLn;
end.