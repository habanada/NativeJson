{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Package3.CodeGen.Ownership;

interface

{$I NativeJson.inc}

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('codegen.ownership')]
  TCodeGenOwnershipTests = class
  public
    [Test] procedure DirectChildClassIsFreed;
    [Test] procedure DynamicArrayClassItemsAreFreed;
    [Test] procedure GenericListOfClassesFreesItemsAndList;
    [Test] procedure ObjectListOfClassesIsFreedOnce;
    [Test] procedure DictionaryClassValuesAreFreed;
    [Test] procedure MultipleOwnedCollectionsDeclareAllLocals;
    [Test] procedure OwnershipCanBeDisabled;
    [Test] procedure RecordsDoNotGenerateDestructor;
    [Test] procedure StringDefaultGeneratesConstructor;
    [Test] procedure IntegerDefaultGeneratesConstructor;
    [Test] procedure BooleanDefaultGeneratesConstructor;
    [Test] procedure NumberDefaultGeneratesConstructor;
    [Test] procedure DateTimeDefaultUsesIso8601;
    [Test] procedure DefaultsCanBeDisabled;
    [Test] procedure UnsupportedObjectDefaultProducesDiagnostic;
  end;

implementation

uses
  NativeJson.CodeGen.Options,
  NativeJson.CodeGen.Model,
  Package3.CodeGen.Helpers;

procedure TCodeGenOwnershipTests.DirectChildClassIsFreed;
var
  Code: string;
begin
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"child":{"type":"object","additionalProperties":false,"properties":{"name":{"type":"string"}}}}}', 'Demo.Models');
  AssertContains(Code, 'destructor TRoot.Destroy;');
  AssertContains(Code, 'FChild.Free;');
end;

procedure TCodeGenOwnershipTests.DynamicArrayClassItemsAreFreed;
var
  Code: string;
begin
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"children":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"name":{"type":"string"}}}}}}', 'Demo.Models');
  AssertContains(Code, 'LChildren: Integer;');
  AssertContains(Code, 'for LChildren := 0 to High(FChildren) do FChildren[LChildren].Free;');
end;

procedure TCodeGenOwnershipTests.GenericListOfClassesFreesItemsAndList;
var
  Options: TJsonCodeGenOptions;
  Code: string;
begin
  Options := TJsonCodeGenOptions.Default.SetArrayKind(TJsonCodeGenArrayKind.GenericLists);
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"children":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"name":{"type":"string"}}}}}}', 'Demo.Models', Options);
  AssertContains(Code, 'while FChildren <> nil do begin');
  AssertContains(Code, 'FChildren[FChildren.Count - 1].Free;');
  AssertContains(Code, 'FChildren.Free;');
end;

procedure TCodeGenOwnershipTests.ObjectListOfClassesIsFreedOnce;
var
  Options: TJsonCodeGenOptions;
  Code: string;
begin
  Options := TJsonCodeGenOptions.Default.SetArrayKind(TJsonCodeGenArrayKind.ObjectLists);
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"children":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"name":{"type":"string"}}}}}}', 'Demo.Models', Options);
  AssertContains(Code, 'FChildren: TObjectList<');
  AssertContains(Code, 'FChildren.Free;');
  AssertNotContains(Code, 'FChildren[FChildren.Count - 1].Free;');
end;

procedure TCodeGenOwnershipTests.DictionaryClassValuesAreFreed;
var
  Code: string;
begin
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"byId":{"type":"object","additionalProperties":{"type":"object","additionalProperties":false,"properties":{"name":{"type":"string"}}}}}}', 'Demo.Models');
  AssertContains(Code, 'LByIdValue:');
  AssertContains(Code, 'for LByIdValue in FById.Values do LByIdValue.Free;');
  AssertContains(Code, 'FById.Free;');
end;

procedure TCodeGenOwnershipTests.MultipleOwnedCollectionsDeclareAllLocals;
var
  Code: string;
begin
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"a":{"type":"array","items":{"type":"object","additionalProperties":false}},"b":{"type":"array","items":{"type":"object","additionalProperties":false}},"c":{"type":"object","additionalProperties":{"type":"object","additionalProperties":false}}}}', 'Demo.Models');
  AssertContains(Code, 'LA: Integer;');
  AssertContains(Code, 'LB: Integer;');
  AssertContains(Code, 'LCValue:');
end;

procedure TCodeGenOwnershipTests.OwnershipCanBeDisabled;
var
  Options: TJsonCodeGenOptions;
  Code: string;
begin
  Options := TJsonCodeGenOptions.Default.SetOwnsGeneratedObjects(False);
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"child":{"type":"object","additionalProperties":false}}}', 'Demo.Models', Options);
  AssertNotContains(Code, 'destructor TRoot.Destroy;');
  AssertNotContains(Code, 'FChild.Free;');
end;

procedure TCodeGenOwnershipTests.RecordsDoNotGenerateDestructor;
var
  Code: string;
begin
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"child":{"type":"object","additionalProperties":false}}}', 'Demo.Models', TJsonCodeGenOptions.Records);
  AssertContains(Code, 'TRoot = record');
  AssertNotContains(Code, 'destructor TRoot.Destroy;');
end;

procedure TCodeGenOwnershipTests.StringDefaultGeneratesConstructor;
var
  Code: string;
begin
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"name":{"type":"string","default":"guest"}}}', 'Demo.Models');
  AssertContains(Code, 'constructor TRoot.Create;');
  AssertContains(Code, 'FName := ''guest'';');
end;

procedure TCodeGenOwnershipTests.IntegerDefaultGeneratesConstructor;
var
  Code: string;
begin
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"count":{"type":"integer","default":42}}}', 'Demo.Models');
  AssertContains(Code, 'FCount := 42;');
end;

procedure TCodeGenOwnershipTests.BooleanDefaultGeneratesConstructor;
var
  Code: string;
begin
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"enabled":{"type":"boolean","default":true}}}', 'Demo.Models');
  AssertContains(Code, 'FEnabled := True;');
end;

procedure TCodeGenOwnershipTests.NumberDefaultGeneratesConstructor;
var
  Code: string;
begin
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"ratio":{"type":"number","default":2}}}', 'Demo.Models');
  AssertContains(Code, 'FRatio := 2.0;');
end;

procedure TCodeGenOwnershipTests.DateTimeDefaultUsesIso8601;
var
  Code: string;
begin
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"created":{"type":"string","format":"date-time","default":"2026-09-06T12:30:00Z"}}}', 'Demo.Models');
  AssertContains(Code, 'ISO8601ToDate(');
  AssertContains(Code, 'System.DateUtils');
end;

procedure TCodeGenOwnershipTests.DefaultsCanBeDisabled;
var
  Options: TJsonCodeGenOptions;
  Code: string;
begin
  Options := TJsonCodeGenOptions.Default.SetEmitDefaults(False);
  Code := UnitOf('{"type":"object","additionalProperties":false,"properties":{"name":{"type":"string","default":"guest"}}}', 'Demo.Models', Options);
  AssertNotContains(Code, 'constructor TRoot.Create;');
  AssertNotContains(Code, 'FName := ''guest'';');
end;

procedure TCodeGenOwnershipTests.UnsupportedObjectDefaultProducesDiagnostic;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"type":"object","additionalProperties":false,"properties":{"child":{"type":"object","additionalProperties":false,"default":{}}}}');
  AssertDiagnostic(Diagnostics, 'CG110');
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeGenOwnershipTests);

end.
