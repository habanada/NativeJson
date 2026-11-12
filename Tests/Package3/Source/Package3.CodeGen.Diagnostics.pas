{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Package3.CodeGen.Diagnostics;

interface

{$I NativeJson.inc}

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('codegen.diagnostics')]
  TCodeGenDiagnosticTests = class
  public
    [Test] procedure UnknownSchemaTypeProducesCG001;
    [Test] procedure NonStringTypeArrayEntryProducesCG002;
    [Test] procedure UnresolvedReferenceProducesErrorSeverity;
    [Test] procedure PatternPropertiesBesideFixedPropertiesProducesCG007;
    [Test] procedure UnevaluatedPropertiesInteractionProducesCG008;
    [Test] procedure RuntimeOnlyNotProducesCG013;
    [Test] procedure RuntimeOnlyIfThenElseProducesThreeDiagnostics;
    [Test] procedure RuntimeOnlyDependentSchemasProducesCG013;
    [Test] procedure RuntimeOnlyContainsProducesCG013;
    [Test] procedure RuntimeOnlyContentSchemaProducesCG013;
    [Test] procedure RequiredWithoutPropertySchemaProducesCG014;
    [Test] procedure IncompatiblePropertyIntersectionProducesCG015;
    [Test] procedure NonSchemaJsonValueProducesCG011;
    [Test] procedure OneSidedNumericRangeProducesCG105;
    [Test] procedure DiagnosticContainsSchemaPath;
    [Test] procedure DiagnosticContainsMessageText;
    [Test] procedure DiagnosticsAreStableAcrossRepeatedGeneration;
  end;

implementation

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE}
  System.SysUtils,
  {$ENDIF}
  NativeJson.CodeGen,
  NativeJson.CodeGen.Model,
  Package3.CodeGen.Helpers;

function FindDiagnostic(const Diagnostics: TArray<TJsonCodeGenDiagnostic>; const Code: string): TJsonCodeGenDiagnostic;
var
  Diagnostic: TJsonCodeGenDiagnostic;
begin
  for Diagnostic in Diagnostics do if SameText(Diagnostic.Code, Code) then Exit(Diagnostic);
  Result := TJsonCodeGenDiagnostic.Create(TJsonCodeGenDiagnosticSeverity.Info, '', '', '');
end;

procedure TCodeGenDiagnosticTests.UnknownSchemaTypeProducesCG001;
begin
  AssertDiagnostic(DiagnosticsOf('{"type":"widget"}'), 'CG001');
end;

procedure TCodeGenDiagnosticTests.NonStringTypeArrayEntryProducesCG002;
begin
  AssertDiagnostic(DiagnosticsOf('{"type":["string",17]}'), 'CG002');
end;

procedure TCodeGenDiagnosticTests.UnresolvedReferenceProducesErrorSeverity;
var
  Diagnostic: TJsonCodeGenDiagnostic;
begin
  Diagnostic := FindDiagnostic(DiagnosticsOf('{"$ref":"missing.json"}'), 'CG004');
  Assert.AreEqual(Integer(TJsonCodeGenDiagnosticSeverity.Error), Integer(Diagnostic.Severity));
end;

procedure TCodeGenDiagnosticTests.PatternPropertiesBesideFixedPropertiesProducesCG007;
begin
  AssertDiagnostic(DiagnosticsOf('{"type":"object","properties":{"fixed":{"type":"string"}},"patternProperties":{"^x-":{"type":"string"}}}'), 'CG007');
end;

procedure TCodeGenDiagnosticTests.UnevaluatedPropertiesInteractionProducesCG008;
begin
  AssertDiagnostic(DiagnosticsOf('{"type":"object","additionalProperties":true,"unevaluatedProperties":false}'), 'CG008');
end;

procedure TCodeGenDiagnosticTests.RuntimeOnlyNotProducesCG013;
begin
  AssertDiagnostic(DiagnosticsOf('{"type":"string","not":{"const":"x"}}'), 'CG013');
end;

procedure TCodeGenDiagnosticTests.RuntimeOnlyIfThenElseProducesThreeDiagnostics;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"type":"object","if":{"properties":{"kind":{"const":"a"}}},"then":{"required":["a"]},"else":{"required":["b"]}}');
  Assert.AreEqual(3, CountDiagnostic(Diagnostics, 'CG013'));
end;

procedure TCodeGenDiagnosticTests.RuntimeOnlyDependentSchemasProducesCG013;
begin
  AssertDiagnostic(DiagnosticsOf('{"type":"object","dependentSchemas":{"creditCard":{"required":["billingAddress"]}}}'), 'CG013');
end;

procedure TCodeGenDiagnosticTests.RuntimeOnlyContainsProducesCG013;
begin
  AssertDiagnostic(DiagnosticsOf('{"type":"array","contains":{"type":"integer"}}'), 'CG013');
end;

procedure TCodeGenDiagnosticTests.RuntimeOnlyContentSchemaProducesCG013;
begin
  AssertDiagnostic(DiagnosticsOf('{"type":"string","contentMediaType":"application/json","contentSchema":{"type":"object"}}'), 'CG013');
end;

procedure TCodeGenDiagnosticTests.RequiredWithoutPropertySchemaProducesCG014;
begin
  AssertDiagnostic(DiagnosticsOf('{"type":"object","additionalProperties":false,"required":["id"]}'), 'CG014');
end;

procedure TCodeGenDiagnosticTests.IncompatiblePropertyIntersectionProducesCG015;
begin
  AssertDiagnostic(DiagnosticsOf('{"allOf":[{"type":"object","additionalProperties":false,"properties":{"x":{"type":"string"}}},{"type":"object","additionalProperties":false,"properties":{"x":{"type":"integer"}}}]}'), 'CG015');
end;

procedure TCodeGenDiagnosticTests.NonSchemaJsonValueProducesCG011;
begin
  AssertDiagnostic(DiagnosticsOf('42'), 'CG011');
end;

procedure TCodeGenDiagnosticTests.OneSidedNumericRangeProducesCG105;
begin
  AssertDiagnostic(DiagnosticsOf('{"type":"object","additionalProperties":false,"properties":{"x":{"type":"number","minimum":0}}}'), 'CG105');
end;

procedure TCodeGenDiagnosticTests.DiagnosticContainsSchemaPath;
var
  Diagnostic: TJsonCodeGenDiagnostic;
begin
  Diagnostic := FindDiagnostic(DiagnosticsOf('{"type":"object","additionalProperties":false,"properties":{"x":{"$ref":"missing.json"}}}'), 'CG004');
  Assert.AreEqual('/properties/x/$ref', Diagnostic.SchemaPath);
end;

procedure TCodeGenDiagnosticTests.DiagnosticContainsMessageText;
var
  Diagnostic: TJsonCodeGenDiagnostic;
begin
  Diagnostic := FindDiagnostic(DiagnosticsOf('{"type":"object","additionalProperties":false,"required":["id"]}'), 'CG014');
  Assert.IsTrue(Pos('id', LowerCase(Diagnostic.MessageText)) > 0);
end;

procedure TCodeGenDiagnosticTests.DiagnosticsAreStableAcrossRepeatedGeneration;
var
  Generator: TNativeJsonSchemaCodeGenerator;
  A, B: TArray<TJsonCodeGenDiagnostic>;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.LoadSchema('{"type":["string","null"]}');
    Generator.GenerateTypes;
    A := Generator.Diagnostics;
    Generator.GenerateTypes;
    B := Generator.Diagnostics;
    Assert.AreEqual(Length(A), Length(B));
    Assert.AreEqual(A[0].Code, B[0].Code);
  finally
    Generator.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeGenDiagnosticTests);

end.
