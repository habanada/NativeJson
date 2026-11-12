{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo01_Basics;

{$I NativeJson.inc}

{
  DEMO 1 - Basics

  Shows: serializing, deserializing, nested objects,
         renaming via attribute, [JsonIgnore], formatting,
         null handling and naming strategies.

  Every step prints what was expected and what came out.
}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Rtti,
  Demo.Assert in 'Demo.Assert.pas',
  Demo.Model in 'Demo.Model.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.NamingStrategy,
  NativeJson.Serializer.Writer;

type
  // Classes that are only needed here may live in the .dpr.
  // (Only for $type polymorphism do they have to be in a unit.)
  TContact = class
  private
    FName: string;
    FPhone: string;
    FNote: string;
    FAddress: TAddress;
  public
    destructor Destroy; override;

    [JsonProperty('contact_name')]
    property Name: string read FName write FName;

    property Phone: string read FPhone write FPhone;

    [JsonIgnore]
    property Note: string read FNote write FNote;

    // Deliberately stays nil -> shows the null handling
    property Address: TAddress read FAddress write FAddress;
  end;

destructor TContact.Destroy;
begin
  FAddress.Free;
  inherited;
end;

// ---------------------------------------------------------------------------

procedure Step1_SimpleRoundTrip;
var
  Original, CopyObj: TAddress;
  Json: string;
begin
  Section('1. Simple round trip (object -> JSON -> object)');
  Original := TAddress.Create;
  try
    Original.Street := 'Example Street 1';
    Original.ZipCode := '12345';
    Original.City := 'Exampletown';
    Original.Country := 'DE';

    Json := JsonConvert.SerializeObject(Original);
    Show('JSON', Json);

    CheckContains('Street is in the JSON', '"Street":"Example Street 1"', Json);
    CheckContains('ZipCode is in the JSON', '"ZipCode":"12345"', Json);

    CopyObj := JsonConvert.DeserializeObject<TAddress>(Json);
    try
      Check('Street after round trip', Original.Street, CopyObj.Street);
      Check('ZipCode after round trip', Original.ZipCode, CopyObj.ZipCode);
      Check('City after round trip', Original.City, CopyObj.City);
      Check('Country after round trip', Original.Country, CopyObj.Country);
    finally
      CopyObj.Free;
    end;
  finally
    Original.Free;
  end;
end;

procedure Step2_AttributesAndIgnore;
var
  Contact: TContact;
  Json: string;
begin
  Section('2. [JsonProperty] and [JsonIgnore]');
  Contact := TContact.Create;
  try
    Contact.Name := 'Selahattin';
    Contact.Phone := '04231-000';
    Contact.Note := 'must not leave the house';

    Json := JsonConvert.SerializeObject(Contact);
    Show('JSON', Json);

    CheckContains('Renamed to contact_name', '"contact_name":"Selahattin"', Json);
    CheckNotContains('Original name does not appear', '"Name"', Json);
    CheckNotContains('Note is ignored', 'must not leave the house', Json);
    CheckContains('Phone is present', '"Phone":"04231-000"', Json);
  finally
    Contact.Free;
  end;
end;

procedure Step3_NullHandling;
var
  Contact: TContact;
  Settings: TJsonSettings;
  WithNull, WithoutNull: string;
begin
  Section('3. Null handling (Include vs. Ignore)');
  Contact := TContact.Create;
  Settings := TJsonSettings.Create;
  try
    Contact.Name := 'Without address';
    // Contact.Address stays nil

    WithNull := JsonConvert.SerializeObject(Contact);
    Show('Include', WithNull);
    CheckContains('nil object is written as null', '"Address":null', WithNull);

    Settings.NullValueHandling := TJsonNullValueHandling.Ignore;
    WithoutNull := JsonConvert.SerializeObject(Contact, Settings);
    Show('Ignore', WithoutNull);
    CheckNotContains('nil object is omitted', '"Address"', WithoutNull);
  finally
    Contact.Free;
    Settings.Free;
  end;
end;

procedure Step4_DefaultValues;
var
  Counter: TMeterReading;
  Settings: TJsonSettings;
  Full, Lean: string;
begin
  Section('4. Omit empty default values');
  Counter := TMeterReading.Create;
  Settings := TJsonSettings.Create;
  try
    Counter.Designation := 'Meter A';
    Counter.Val := 0; // default value

    // TMeterReading only has public fields -> MemberSelection needed
    Settings.MemberSelection := [TJsonMemberType.mtProperties, TJsonMemberType.mtFields];
    Full := JsonConvert.SerializeObject(Counter, Settings);
    Show('Include', Full);
    CheckContains('Value 0 is written', '"Val":0', Full);

    Settings.DefaultValueHandling := TJsonDefaultValueHandling.Ignore;
    Lean := JsonConvert.SerializeObject(Counter, Settings);
    Show('Ignore', Lean);
    CheckNotContains('Value 0 is dropped', '"Val"', Lean);
    CheckContains('Designation stays', '"Designation":"Meter A"', Lean);
  finally
    Counter.Free;
    Settings.Free;
  end;
end;

procedure Step5_Nested;
var
  Customer, CopyObj: TCustomer;
  Json: string;
begin
  Section('5. Nested objects (read-only property is filled)');
  Customer := TCustomer.Create;
  try
    Customer.Number := 'K-10042';
    Customer.Name := 'Example Ltd';
    Customer.Salutation := saCompany;
    Customer.Email := 'info@example.org';
    Customer.Address.City := 'Exampletown';
    Customer.Address.ZipCode := '12345';

    Json := JsonConvert.SerializeObject(Customer);
    Show('JSON', Json);

    CheckContains('Address is embedded', '"Address":{', Json);
    CheckContains('Enum as name', '"Salutation":"saCompany"', Json);

    CopyObj := JsonConvert.DeserializeObject<TCustomer>(Json);
    try
      CheckTrue('Address instance exists', CopyObj.Address <> nil);
      Check('City in child object', 'Exampletown', CopyObj.Address.City);
      Check('ZipCode in child object', '12345', CopyObj.Address.ZipCode);
      CheckTrue('Enum read correctly', CopyObj.Salutation = saCompany, 'Salutation');
      Check('InternalNote stays empty (JsonIgnore)', '', CopyObj.InternalNote);
    finally
      CopyObj.Free;
    end;
  finally
    Customer.Free;
  end;
end;

procedure Step6_Formatting;
var
  Address: TAddress;
  Compact, Pretty: string;
begin
  Section('6. Formatting');
  Address := TAddress.Create;
  try
    Address.City := 'Exampletown';

    Compact := JsonConvert.SerializeObject(Address, TJsonFormatting.None);
    Pretty := JsonConvert.SerializeObject(Address, TJsonFormatting.Indented);

    Show('None', Compact);
    CheckNotContains('Compact has no line breaks', sLineBreak, Compact);
    CheckTrue('Indented is longer', Length(Pretty) > Length(Compact),
      Format('%d vs %d chars', [Length(Pretty), Length(Compact)]));
    Writeln;
    Writeln(Pretty);
  finally
    Address.Free;
  end;
end;

procedure Step7_NamingStrategies;
var
  Address: TAddress;
  Settings: TJsonSettings;
  Json: string;
  Back: TAddress;
begin
  Section('7. Naming strategies (snake_case, camelCase, ...)');
  Address := TAddress.Create;
  Settings := TJsonSettings.Create;
  try
    Address.Street := 'Main Road 1';

    Settings.CaseStyle := jcSnake;
    Json := JsonConvert.SerializeObject(Address, Settings);
    Show('snake', Json);
    CheckContains('snake_case', '"street":"Main Road 1"', Json);

    Settings.CaseStyle := jcUpper;
    Json := JsonConvert.SerializeObject(Address, Settings);
    Show('upper', Json);
    CheckContains('UPPERCASE', '"STREET"', Json);

    Settings.CaseStyle := jcCamel;
    Json := JsonConvert.SerializeObject(Address, Settings);
    Show('camel', Json);
    CheckContains('camelCase', '"street"', Json);

    // Cross-check: the same strategy must also apply when reading
    Settings.CaseStyle := jcSnake;
    Json := JsonConvert.SerializeObject(Address, Settings);
    Back := JsonConvert.DeserializeObject<TAddress>(Json, Settings);
    try
      Check('Round trip with snake_case', 'Main Road 1', Back.Street);
    finally
      Back.Free;
    end;
  finally
    Address.Free;
    Settings.Free;
  end;
end;

procedure Step8_ScalarValues;
var
  Json: string;
begin
  Section('8. Single values instead of objects');

  Json := JsonConvert.SerializeObject(42);
  Check('Integer', '42', Json);

  Json := JsonConvert.SerializeObject('Hello');
  Check('String', '"Hello"', Json);

  Json := JsonConvert.SerializeObject(True);
  Check('Boolean', 'true', Json);

  Check('Integer back', 42, JsonConvert.DeserializeObject<Integer>('42'));
  Check('String back', 'Hello', JsonConvert.DeserializeObject<string>('"Hello"'));
  Check('Boolean back', True, JsonConvert.DeserializeObject<Boolean>('true'));
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 1 - BASICS');

    Step1_SimpleRoundTrip;
    Step2_AttributesAndIgnore;
    Step3_NullHandling;
    Step4_DefaultValues;
    Step5_Nested;
    Step6_Formatting;
    Step7_NamingStrategies;
    Step8_ScalarValues;

    ExitCode := Summary;
  except
    on E: Exception do
    begin
      Writeln('ABORTED: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
  if ParamCount = 0 then
  begin
    Writeln;
    Writeln('Press Enter ...');
    Readln;
  end;
end.
