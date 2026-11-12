{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_ObjectPatch;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  Rtti,
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Fluent,
  NativeJson.NamingStrategy,
  NativeJson.Dom.Value,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.Io;

type
  TAddress = class(TPersistent)
  private
    FCity: string;
    FPostalCode: string;
  published
    property City: string read FCity write FCity;
    property PostalCode: string read FPostalCode write FPostalCode;
  end;

  TCustomer = class(TPersistent)
  private
    FName: string;
    FAge: Integer;
    FDisplayName: string;
    FInternalNote: string;
    FAddress: TAddress;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Name: string read FName write FName;
    property Age: Integer read FAge write FAge;
    [JsonProperty('display_name')]
    property DisplayName: string read FDisplayName write FDisplayName;
    [JsonIgnore]
    property InternalNote: string read FInternalNote write FInternalNote;
    property Address: TAddress read FAddress;
  end;

constructor TCustomer.Create;
begin
  inherited Create;
  FAddress := TAddress.Create;
end;

destructor TCustomer.Destroy;
begin
  FAddress.Free;
  inherited;
end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create('FAILED: ' + MessageText);
end;

procedure CheckEquals(const Expected, Actual, MessageText: string);
begin
  if Expected <> Actual then
    raise Exception.CreateFmt('FAILED: %s. Expected "%s", got "%s"',
      [MessageText, Expected, Actual]);
end;

procedure CheckEqualsInt(Expected, Actual: Integer; const MessageText: string);
begin
  if Expected <> Actual then
    raise Exception.CreateFmt('FAILED: %s. Expected %d, got %d',
      [MessageText, Expected, Actual]);
end;

procedure CheckPatch(Patch: TJsonValue; const ExpectedJson, MessageText: string);
var
  Expected: TJsonValue;
begin
  Expected := DomFromText(ExpectedJson);
  try
    Check(Patch <> nil, MessageText + ': patch is nil');
    Check(TJsonComparer.DeepEquals(Expected, Patch),
      MessageText + '. Expected ' + Expected.ToJson + ', got ' + Patch.ToJson);
  finally
    Expected.Free;
  end;
end;

function NewCustomer(const AName: string; AAge: Integer;
  const ADisplayName, ACity, APostalCode: string): TCustomer;
begin
  Result := TCustomer.Create;
  try
    Result.Name := AName;
    Result.Age := AAge;
    Result.DisplayName := ADisplayName;
    Result.Address.City := ACity;
    Result.Address.PostalCode := APostalCode;
  except
    Result.Free;
    raise;
  end;
end;

procedure TestCreatePatchAndApply;
var
  OldCustomer, NewCustomerValue, Updated: TCustomer;
  Patch: TJsonArray;
  PatchBefore, OldBefore, NewBefore: string;
begin
  OldCustomer := nil;
  NewCustomerValue := nil;
  Updated := nil;
  Patch := nil;
  try
    OldCustomer := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '10115');
    NewCustomerValue := NewCustomer('Peter', 41, 'Peter M.', 'Berlin', '10115');
    OldBefore := JsonConvert.SerializeObject(OldCustomer);
    NewBefore := JsonConvert.SerializeObject(NewCustomerValue);

    Patch := JsonConvert.CreatePatch<TCustomer>(OldCustomer, NewCustomerValue);
    CheckPatch(Patch, '[{"op":"replace","path":"/Age","value":41}]',
      'basic object diff');
    PatchBefore := Patch.ToJson;

    Updated := JsonConvert.ApplyPatch<TCustomer>(OldCustomer, Patch);
    Check(Updated <> nil, 'ApplyPatch returns an object');
    Check(Updated <> OldCustomer, 'ApplyPatch returns a new instance');
    Check(Updated.Address <> OldCustomer.Address,
      'nested owned object is not aliased to source');
    CheckEquals('Peter', Updated.Name, 'name preserved');
    CheckEqualsInt(41, Updated.Age, 'age patched');
    CheckEquals('Berlin', Updated.Address.City, 'nested city preserved');

    CheckEqualsInt(40, OldCustomer.Age, 'source object remains unchanged');
    Check(JsonConvert.SerializeObject(OldCustomer) = OldBefore,
      'source serialization remains unchanged');
    Check(JsonConvert.SerializeObject(NewCustomerValue) = NewBefore,
      'target serialization remains unchanged');
    Check(Patch.ToJson = PatchBefore, 'patch DOM remains unchanged');
  finally
    Patch.Free;
    Updated.Free;
    NewCustomerValue.Free;
    OldCustomer.Free;
  end;
end;

procedure TestNestedPathAndAttributeName;
var
  OldCustomer, NewCustomerValue: TCustomer;
  Patch: TJsonArray;
begin
  OldCustomer := nil;
  NewCustomerValue := nil;
  Patch := nil;
  try
    OldCustomer := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '10115');
    NewCustomerValue := NewCustomer('Peter', 40, 'Peter X.', 'Berlin', '10115');
    Patch := JsonConvert.CreatePatch<TCustomer>(OldCustomer, NewCustomerValue);
    CheckPatch(Patch,
      '[{"op":"replace","path":"/display_name","value":"Peter X."}]',
      'JsonProperty name is used in patch path');
  finally
    Patch.Free;
    NewCustomerValue.Free;
    OldCustomer.Free;
  end;

  OldCustomer := nil;
  NewCustomerValue := nil;
  Patch := nil;
  try
    OldCustomer := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '10115');
    NewCustomerValue := NewCustomer('Peter', 40, 'Peter M.', 'Hamburg', '10115');
    Patch := JsonConvert.CreatePatch<TCustomer>(OldCustomer, NewCustomerValue);
    CheckPatch(Patch,
      '[{"op":"replace","path":"/Address/City","value":"Hamburg"}]',
      'nested object property path');
  finally
    Patch.Free;
    NewCustomerValue.Free;
    OldCustomer.Free;
  end;
end;

procedure TestSettingsAreSharedByDiffAndApply;
var
  OldCustomer, NewCustomerValue, Updated: TCustomer;
  Patch: TJsonArray;
  Settings: TJsonSettings;
begin
  OldCustomer := nil;
  NewCustomerValue := nil;
  Updated := nil;
  Patch := nil;
  Settings := nil;
  try
    OldCustomer := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '10115');
    NewCustomerValue := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '20095');
    Settings := TJsonSettings.Create;
    Settings.CaseStyle := TJsonCaseStyle.jcSnake;
    Patch := JsonConvert.CreatePatch<TCustomer>(OldCustomer, NewCustomerValue,
      Settings);
    CheckPatch(Patch,
      '[{"op":"replace","path":"/address/postal_code","value":"20095"}]',
      'naming settings are used by object diff');

    Updated := JsonConvert.ApplyPatch<TCustomer>(OldCustomer, Patch, Settings);
    Check(Updated <> nil, 'settings ApplyPatch returns object');
    CheckEquals('20095', Updated.Address.PostalCode,
      'same settings deserialize patched DOM');

    // Settings still belongs to the caller and must still be usable normally
    // after both calls.
    Check(Pos('"postal_code"', JsonConvert.SerializeObject(Updated, Settings)) > 0,
      'caller-owned settings remains valid');
  finally
    Settings.Free;
    Patch.Free;
    Updated.Free;
    NewCustomerValue.Free;
    OldCustomer.Free;
  end;
end;

procedure TestDefaultSettingsAreHonored;
var
  PreviousDefaults: TJsonSettingsProc;
  OldCustomer, NewCustomerValue, Updated: TCustomer;
  Patch: TJsonArray;
begin
  PreviousDefaults := JsonConvert.DefaultSettings;
  OldCustomer := nil;
  NewCustomerValue := nil;
  Updated := nil;
  Patch := nil;
  try
    JsonConvert.DefaultSettings :=
      procedure(Settings: TJsonSettings)
      begin
        Settings.CaseStyle := TJsonCaseStyle.jcSnake;
      end;
    OldCustomer := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '10115');
    NewCustomerValue := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '20095');

    Patch := JsonConvert.CreatePatch<TCustomer>(OldCustomer, NewCustomerValue);
    CheckPatch(Patch,
      '[{"op":"replace","path":"/address/postal_code","value":"20095"}]',
      'default settings are used by CreatePatch');
    Updated := JsonConvert.ApplyPatch<TCustomer>(OldCustomer, Patch);
    Check(Updated <> nil, 'default settings ApplyPatch returns object');
    CheckEquals('20095', Updated.Address.PostalCode,
      'default settings are used by ApplyPatch');
  finally
    Updated.Free;
    Patch.Free;
    NewCustomerValue.Free;
    OldCustomer.Free;
    JsonConvert.DefaultSettings := PreviousDefaults;
  end;
end;

procedure TestIgnoredMembersDoNotLeakIntoPatch;
var
  OldCustomer, NewCustomerValue: TCustomer;
  Patch: TJsonArray;
begin
  OldCustomer := nil;
  NewCustomerValue := nil;
  Patch := nil;
  try
    OldCustomer := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '10115');
    NewCustomerValue := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '10115');
    OldCustomer.InternalNote := 'old secret';
    NewCustomerValue.InternalNote := 'new secret';
    Patch := JsonConvert.CreatePatch<TCustomer>(OldCustomer, NewCustomerValue);
    CheckPatch(Patch, '[]', 'JsonIgnore member does not create patch');
  finally
    Patch.Free;
    NewCustomerValue.Free;
    OldCustomer.Free;
  end;
end;

procedure TestApplyPatchUsesJsonStateOnly;
var
  Customer, Updated: TCustomer;
  Patch: TJsonValue;
begin
  Customer := nil;
  Updated := nil;
  Patch := nil;
  try
    Customer := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '10115');
    Customer.InternalNote := 'secret source state';
    Patch := DomFromText(
      '[{"op":"replace","path":"/Age","value":41}]');

    Updated := JsonConvert.ApplyPatch<TCustomer>(Customer, Patch);
    Check(Updated <> nil, 'JSON-state ApplyPatch returns object');
    CheckEqualsInt(41, Updated.Age, 'JSON-state patch is applied');
    CheckEquals('secret source state', Customer.InternalNote,
      'ignored state on source remains untouched');
    CheckEquals('', Updated.InternalNote,
      'JsonIgnore state is not copied into the materialized object');
  finally
    Patch.Free;
    Updated.Free;
    Customer.Free;
  end;
end;

procedure TestObjectRoundTripInvariant;
var
  OldCustomer, TargetCustomer, Updated: TCustomer;
  Patch: TJsonArray;
  Settings: TJsonSettings;
  ExpectedDom, ActualDom: TJsonValue;
begin
  OldCustomer := nil;
  TargetCustomer := nil;
  Updated := nil;
  Patch := nil;
  Settings := nil;
  ExpectedDom := nil;
  ActualDom := nil;
  try
    OldCustomer := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '10115');
    TargetCustomer := NewCustomer('Anna', 41, 'Anna A.', 'Hamburg', '20095');
    OldCustomer.InternalNote := 'old hidden state';
    TargetCustomer.InternalNote := 'new hidden state';

    Settings := TJsonSettings.Create;
    Settings.CaseStyle := TJsonCaseStyle.jcSnake;

    Patch := JsonConvert.CreatePatch<TCustomer>(OldCustomer, TargetCustomer,
      Settings);
    Updated := JsonConvert.ApplyPatch<TCustomer>(OldCustomer, Patch, Settings);

    ExpectedDom := DomFromText(JsonConvert.SerializeObject(TargetCustomer,
      Settings));
    ActualDom := DomFromText(JsonConvert.SerializeObject(Updated, Settings));
    Check(TJsonComparer.DeepEquals(ExpectedDom, ActualDom),
      'Serialize(ApplyPatch(A, CreatePatch(A,B))) equals Serialize(B)');
  finally
    ActualDom.Free;
    ExpectedDom.Free;
    Updated.Free;
    Patch.Free;
    Settings.Free;
    TargetCustomer.Free;
    OldCustomer.Free;
  end;
end;

procedure TestFluentMappingAndFactoryIntegration;
var
  OldCustomer, NewCustomerValue, Updated: TCustomer;
  Patch: TJsonArray;
  Settings: TJsonSettings;
  FactoryCalls: Integer;
begin
  OldCustomer := nil;
  NewCustomerValue := nil;
  Updated := nil;
  Patch := nil;
  Settings := nil;
  FactoryCalls := 0;
  try
    OldCustomer := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '10115');
    NewCustomerValue := NewCustomer('Anna', 40, 'Peter M.', 'Berlin', '10115');
    OldCustomer.InternalNote := 'source-only state';

    Settings := TJsonSettings.Create;
    Settings.Fluent.Entity<TCustomer>
      .Map('Name').Name('customer_name').EndMember;
    Settings.RegisterFactory<TCustomer>(
      function(RType: TRttiType): TObject
      begin
        if RType = nil then
          raise Exception.Create('Factory received no RTTI type');
        Inc(FactoryCalls);
        Result := TCustomer.Create;
        TCustomer(Result).InternalNote := 'factory state';
      end);

    Patch := JsonConvert.CreatePatch<TCustomer>(OldCustomer, NewCustomerValue,
      Settings);
    CheckPatch(Patch,
      '[{"op":"replace","path":"/customer_name","value":"Anna"}]',
      'Fluent member name is used by object diff');

    Updated := JsonConvert.ApplyPatch<TCustomer>(OldCustomer, Patch, Settings);
    Check(Updated <> nil, 'Fluent/factory ApplyPatch returns object');
    CheckEqualsInt(1, FactoryCalls, 'registered factory is used by ApplyPatch');
    CheckEquals('Anna', Updated.Name,
      'Fluent-mapped property is deserialized after patch');
    CheckEquals('factory state', Updated.InternalNote,
      'non-JSON state comes from factory, not the source object');
    CheckEquals('source-only state', OldCustomer.InternalNote,
      'factory integration does not mutate the source object');
  finally
    Updated.Free;
    Patch.Free;
    Settings.Free;
    NewCustomerValue.Free;
    OldCustomer.Free;
  end;
end;

procedure TestPatchTestUsesSemanticEquality;
var
  Customer, Updated: TCustomer;
  Patch: TJsonValue;
begin
  Customer := nil;
  Updated := nil;
  Patch := nil;
  try
    Customer := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '10115');
    Patch := DomFromText(
      '[{"op":"test","path":"/Age","value":40.0},' +
      '{"op":"replace","path":"/Age","value":41}]');
    Updated := JsonConvert.ApplyPatch<TCustomer>(Customer, Patch);
    CheckEqualsInt(41, Updated.Age,
      'RFC-6902 test uses semantic number equality through object API');
    CheckEqualsInt(40, Customer.Age, 'test/replace leaves source unchanged');
  finally
    Patch.Free;
    Updated.Free;
    Customer.Free;
  end;
end;

procedure TestNilTransitions;
var
  Target, Created, Removed: TCustomer;
  Patch: TJsonArray;
begin
  Target := nil;
  Created := nil;
  Removed := nil;
  Patch := nil;
  try
    Target := NewCustomer('Anna', 33, 'Anna A.', 'Hamburg', '20095');

    Patch := JsonConvert.CreatePatch<TCustomer>(nil, Target);
    Created := JsonConvert.ApplyPatch<TCustomer>(nil, Patch);
    Check(Created <> nil, 'nil source can be replaced with object');
    CheckEquals('Anna', Created.Name, 'created object name');
    CheckEqualsInt(33, Created.Age, 'created object age');
    Patch.Free;
    Patch := nil;
    Created.Free;
    Created := nil;

    Patch := JsonConvert.CreatePatch<TCustomer>(Target, nil);
    CheckPatch(Patch, '[{"op":"replace","path":"","value":null}]',
      'object to nil uses root replacement with JSON null');
    Removed := JsonConvert.ApplyPatch<TCustomer>(Target, Patch);
    Check(Removed = nil, 'root null deserializes to nil class reference');
    CheckEquals('Anna', Target.Name, 'source survives object-to-nil patch');
  finally
    Patch.Free;
    Removed.Free;
    Created.Free;
    Target.Free;
  end;
end;

procedure TestInvalidPatchIsTransactional;
var
  Customer, Updated: TCustomer;
  Patch: TJsonValue;
  Raised: Boolean;
begin
  Customer := nil;
  Updated := nil;
  Patch := nil;
  Raised := False;
  try
    Customer := NewCustomer('Peter', 40, 'Peter M.', 'Berlin', '10115');
    Patch := DomFromText(
      '[{"op":"replace","path":"/DoesNotExist","value":1}]');
    try
      Updated := JsonConvert.ApplyPatch<TCustomer>(Customer, Patch);
    except
      on E: EJsonPatchError do
        Raised := True;
    end;
    Check(Raised, 'invalid patch raises EJsonPatchError');
    Check(Updated = nil, 'invalid patch returns no partial object');
    CheckEqualsInt(40, Customer.Age,
      'invalid patch cannot partially mutate source object');
    CheckEquals('Peter', Customer.Name,
      'invalid patch preserves source properties');
  finally
    Patch.Free;
    Updated.Free;
    Customer.Free;
  end;
end;

begin
  {$IFNDEF FPC}ReportMemoryLeaksOnShutdown := True;{$ENDIF}
  try
    TestCreatePatchAndApply;
    TestNestedPathAndAttributeName;
    TestSettingsAreSharedByDiffAndApply;
    TestDefaultSettingsAreHonored;
    TestIgnoredMembersDoNotLeakIntoPatch;
    TestApplyPatchUsesJsonStateOnly;
    TestObjectRoundTripInvariant;
    TestFluentMappingAndFactoryIntegration;
    TestPatchTestUsesSemanticEquality;
    TestNilTransitions;
    TestInvalidPatchIsTransactional;
    Writeln('NativeJson Object Diff/Patch tests: OK');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
