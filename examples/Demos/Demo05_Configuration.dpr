{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo05_Configuration;

{$I NativeJson.inc}

{
  DEMO 5 - Runtime configuration (fluent API)

  Shows: renaming, ignoring, fixed order, value transformation,
         conditional writing, lifecycle hooks, naming strategy per type
         and the choice between properties and public fields.

  The point: foreign classes that must not be decorated with attributes
  (e.g. from a third-party library) can still be controlled.
}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Rtti,
  Demo.Assert in 'Demo.Assert.pas',
  Demo.Model in 'Demo.Model.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Fluent,
  NativeJson.NamingStrategy,
  NativeJson.Serializer.Writer;

function NewAddress: TAddress;
begin
  Result := TAddress.Create;
  Result.Street := 'Example Street 1';
  Result.ZipCode := '12345';
  Result.City := 'Exampletown';
  Result.Country := 'DE';
end;

// ---------------------------------------------------------------------------

procedure Step1_RenameAndIgnore;
var
  Address: TAddress;
  Settings: TJsonSettings;
  Json: string;
begin
  Section('1. Renaming and ignoring without attributes');
  Address := NewAddress;
  Settings := TJsonSettings.Create;
  try
    Settings.Fluent.Entity<TAddress>
      .Map('Street').Name('street').EndMember
      .Map('ZipCode').Name('zip').EndMember
      .Map('Country').Ignore;

    Json := JsonConvert.SerializeObject(Address, Settings);
    Show('JSON', Json);

    CheckContains('Street is called street', '"street":"Example Street 1"', Json);
    CheckContains('ZipCode is called zip', '"zip":"12345"', Json);
    CheckContains('City unchanged', '"City":"Exampletown"', Json);
    CheckNotContains('Country is gone', 'Country', Json);
  finally
    Address.Free;
    Settings.Free;
  end;
end;

procedure Step2_FixedOrder;
var
  Address: TAddress;
  Settings: TJsonSettings;
  Json: string;
begin
  Section('2. Fixed field order');
  Address := NewAddress;
  Settings := TJsonSettings.Create;
  try
    // Without Order the order is not guaranteed.
    // With Order it becomes predictable - important for interfaces
    // that check for a fixed layout or compute signatures.
    Settings.Fluent.Entity<TAddress>
      .Map('Country').Order(1).EndMember
      .Map('ZipCode').Order(2).EndMember
      .Map('City').Order(3).EndMember
      .Map('Street').Order(4);

    Json := JsonConvert.SerializeObject(Address, Settings);
    Show('JSON', Json);

    Check('Exact order',
      '{"Country":"DE","ZipCode":"12345","City":"Exampletown","Street":"Example Street 1"}',
      Json);
  finally
    Address.Free;
    Settings.Free;
  end;
end;

procedure Step3_ChangeValues;
var
  Customer: TCustomer;
  Settings: TJsonSettings;
  Json: string;
begin
  Section('3. Changing values when writing (masking)');
  Customer := TCustomer.Create;
  Settings := TJsonSettings.Create;
  try
    Customer.Number := 'K-10042';
    Customer.Name := 'Example Ltd';
    Customer.Email := 'purchasing@example.org';

    Settings.Fluent.Entity<TCustomer>
      .Map('Email').Transform(
        function(const InValue: TValue): TValue
        var
          S: string;
          P: Integer;
        begin
          S := InValue.AsString;
          P := Pos('@', S);
          if P > 1 then S := '***' + Copy(S, P, Length(S));
          Result := TValue.From<string>(S);
        end)
      .EndMember;

    Json := JsonConvert.SerializeObject(Customer, Settings);
    Show('JSON', Json);

    CheckContains('Address masked', '"Email":"***@example.org"', Json);
    CheckNotContains('Original value no longer included', 'purchasing@', Json);
    Check('Object itself unchanged', 'purchasing@example.org', Customer.Email);
  finally
    Customer.Free;
    Settings.Free;
  end;
end;

procedure Step4_ConditionalWrite;
var
  Customer: TCustomer;
  Settings: TJsonSettings;
  WithEmail, WithoutEmail: string;
begin
  Section('4. Write a field only under a condition');
  Customer := TCustomer.Create;
  Settings := TJsonSettings.Create;
  try
    Customer.Number := 'K-10042';
    Customer.Name := 'Example Ltd';
    Customer.Email := 'purchasing@example.org';

    // Rule: only send the address if a customer number is present
    Settings.Fluent.Entity<TCustomer>.SetShouldSerialize('Email',
      function(Instance: TCustomer): Boolean
      begin
        Result := Instance.Number <> '';
      end);

    WithEmail := JsonConvert.SerializeObject(Customer, Settings);
    Show('with number', WithEmail);
    CheckContains('Email is written', '"Email"', WithEmail);

    Customer.Number := '';
    WithoutEmail := JsonConvert.SerializeObject(Customer, Settings);
    Show('without number', WithoutEmail);
    CheckNotContains('Email is dropped', '"Email"', WithoutEmail);
  finally
    Customer.Free;
    Settings.Free;
  end;
end;

procedure Step5_Hooks;
var
  Address, CopyObj: TAddress;
  Settings: TJsonSettings;
  Json: string;
  BeforeWrite, AfterRead: Integer;
begin
  Section('5. Lifecycle hooks (before writing / after reading)');
  Address := NewAddress;
  Settings := TJsonSettings.Create;
  BeforeWrite := 0;
  AfterRead := 0;
  try
    Settings.Fluent.Entity<TAddress>
      .OnSerializing(
        procedure(Instance: TAddress)
        begin
          Inc(BeforeWrite);
          Instance.Country := UpperCase(Instance.Country);
        end)
      .OnDeserialized(
        procedure(Instance: TAddress)
        begin
          Inc(AfterRead);
          if Instance.Country = '' then Instance.Country := 'DE';
        end);

    Json := JsonConvert.SerializeObject(Address, Settings);
    Check('OnSerializing was called', 1, BeforeWrite);
    CheckContains('Country in upper case', '"Country":"DE"', Json);

    CopyObj := JsonConvert.DeserializeObject<TAddress>(
      '{"Street":"Short Lane 1","City":"Bremen"}', Settings);
    try
      Check('OnDeserialized was called', 1, AfterRead);
      Check('Missing country was filled in', 'DE', CopyObj.Country);
    finally
      CopyObj.Free;
    end;
  finally
    Address.Free;
    Settings.Free;
  end;
end;

procedure Step6_NamingStrategyPerType;
var
  Address: TAddress;
  Customer: TCustomer;
  Settings: TJsonSettings;
  JsonAddress, JsonCustomer: string;
begin
  Section('6. Naming strategy for one type only');
  Address := NewAddress;
  Customer := TCustomer.Create;
  Settings := TJsonSettings.Create;
  try
    Customer.Number := 'K-1';
    Customer.Name := 'Test';

    Settings.Fluent.Entity<TAddress>.SetNamingStrategy(TSnakeCaseNamingStrategy);

    JsonAddress := JsonConvert.SerializeObject(Address, Settings);
    JsonCustomer := JsonConvert.SerializeObject(Customer, Settings);

    Show('Address', JsonAddress);
    Show('Customer', JsonCustomer);

    CheckContains('Address in snake_case', '"street"', JsonAddress);
    CheckContains('Customer stays unchanged', '"Number":"K-1"', JsonCustomer);
  finally
    Address.Free;
    Customer.Free;
    Settings.Free;
  end;
end;

procedure Step7_MemberSelection;
var
  Counter: TMeterReading;
  Settings: TJsonSettings;
  Standard, Global, PerType: string;
begin
  Section('7. Properties or public fields?');
  Counter := TMeterReading.Create;
  Settings := TJsonSettings.Create;
  try
    Counter.Designation := 'Hall 3';
    Counter.Val := 42;

    // TMeterReading only has public fields, no properties.
    Standard := JsonConvert.SerializeObject(Counter);
    Show('Standard', Standard);
    Check('Without switching the object stays empty', '{}', Standard);

    Settings.MemberSelection := [TJsonMemberType.mtProperties, TJsonMemberType.mtFields];
    Global := JsonConvert.SerializeObject(Counter, Settings);
    Show('Global', Global);
    CheckContains('Field Designation', '"Designation":"Hall 3"', Global);
    CheckContains('Field Val', '"Val":42', Global);

    Settings.MemberSelection := [];
    Settings.Fluent.Entity<TMeterReading>.SelectMembers([TJsonMemberType.mtFields]);
    PerType := JsonConvert.SerializeObject(Counter, Settings);
    Show('Per type', PerType);
    CheckContains('Also possible via fluent', '"Designation":"Hall 3"', PerType);
  finally
    Counter.Free;
    Settings.Free;
  end;
end;

procedure Step8_OverrideAttributes;
var
  Customer: TCustomer;
  Settings: TJsonSettings;
  Json: string;
begin
  Section('8. Fluent beats attribute');
  Customer := TCustomer.Create;
  Settings := TJsonSettings.Create;
  try
    Customer.Number := 'K-10042';
    Customer.Name := 'Example Ltd';
    Customer.InternalNote := 'Pays on time';

    // InternalNote carries [JsonIgnore]. A custom name via fluent
    // brings the field back into the JSON for this one call.
    Settings.Fluent.Entity<TCustomer>
      .Map('InternalNote').Name('internal').EndMember;

    Json := JsonConvert.SerializeObject(Customer, Settings);
    Show('JSON', Json);
    CheckContains('Ignored field is visible again',
      '"internal":"Pays on time"', Json);

    // Without fluent it stays invisible
    Json := JsonConvert.SerializeObject(Customer);
    CheckNotContains('Default stays unchanged', 'on time', Json);
  finally
    Customer.Free;
    Settings.Free;
  end;
end;

procedure Step9_NoMixUpInCache;
var
  Address: TAddress;
  S1, S2: TJsonSettings;
  FirstRun, SecondRun: string;
begin
  Section('9. Two configurations in a row must not get mixed up');

  // Background: the library remembers the member analysis per type and
  // configuration. If a TJsonSettings is freed and a new one is created
  // right after, the memory manager often returns the same address.
  // The cache must still keep the two apart.
  Address := NewAddress;
  try
    S1 := TJsonSettings.Create;
    try
      S1.Fluent.Entity<TAddress>.Map('City').Name('first_variant').EndMember;
      FirstRun := JsonConvert.SerializeObject(Address, S1);
    finally
      S1.Free;
    end;

    S2 := TJsonSettings.Create;
    try
      S2.Fluent.Entity<TAddress>.Map('City').Name('second_variant').EndMember;
      SecondRun := JsonConvert.SerializeObject(Address, S2);
    finally
      S2.Free;
    end;

    Show('1st run', FirstRun);
    Show('2nd run', SecondRun);

    CheckContains('First run uses its name', '"first_variant":"Exampletown"', FirstRun);
    CheckContains('Second run uses its name', '"second_variant":"Exampletown"', SecondRun);
    CheckNotContains('No leftover from the first run', 'first_variant', SecondRun);
  finally
    Address.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 5 - RUNTIME CONFIGURATION');

    Step1_RenameAndIgnore;
    Step2_FixedOrder;
    Step3_ChangeValues;
    Step4_ConditionalWrite;
    Step5_Hooks;
    Step6_NamingStrategyPerType;
    Step7_MemberSelection;
    Step8_OverrideAttributes;
    Step9_NoMixUpInCache;

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
