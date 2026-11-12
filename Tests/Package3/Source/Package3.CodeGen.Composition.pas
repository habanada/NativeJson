{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Package3.CodeGen.Composition;

interface

{$I NativeJson.inc}

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('codegen.composition')]
  TCodeGenCompositionTests = class
  public
    [Test] procedure AllOfIntegerAndNumberKeepsInteger;
    [Test] procedure AllOfIncompatibleTypesProducesDiagnostic;
    [Test] procedure AllOfMergesObjectProperties;
    [Test] procedure AllOfSamePropertyUsesIntersection;
    [Test] procedure OneOfIntegerAndNumberUsesDouble;
    [Test] procedure AnyOfScalarMixtureUsesVariant;
    [Test] procedure UnionFallbackOptionUsesConfiguredType;
    [Test] procedure NullableNativeDefaultKeepsTypeAndWarns;
    [Test] procedure NullableVariantUsesVariant;
    [Test] procedure NullableFallbackUsesConfiguredType;
    [Test] procedure SafeStringEnumCreatesDelphiEnum;
    [Test] procedure UnsafeStringEnumCreatesScalarConstants;
    [Test] procedure ScalarConstantsOptionDisablesDelphiEnum;
    [Test] procedure MixedEnumUsesFallbackAndDiagnostic;
    [Test] procedure ConstInfersTypeAndProducesRuntimeDiagnostic;
    [Test] procedure FalseSchemaProducesFallbackAndDiagnostic;
    [Test] procedure ObjectOneOfMergesProperties;
    [Test] procedure ObjectOneOfRequiredOnlyWhenCommon;
    [Test] procedure ArrayOneOfMergesItemType;
  end;

implementation

uses
  NativeJson.CodeGen.Options,
  NativeJson.CodeGen.Model,
  Package3.CodeGen.Helpers;

procedure TCodeGenCompositionTests.AllOfIntegerAndNumberKeepsInteger;
begin
  AssertContains(TypesOf('{"allOf":[{"type":"integer"},{"type":"number"}]}'), 'TRoot = Int64;');
end;

procedure TCodeGenCompositionTests.AllOfIncompatibleTypesProducesDiagnostic;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"allOf":[{"type":"string"},{"type":"integer"}]}');
  AssertDiagnostic(Diagnostics, 'CG003');
end;

procedure TCodeGenCompositionTests.AllOfMergesObjectProperties;
var
  Code: string;
begin
  Code := TypesOf('{"allOf":[{"type":"object","additionalProperties":false,"properties":{"a":{"type":"string"}}},{"type":"object","additionalProperties":false,"properties":{"b":{"type":"integer"}}}]}');
  AssertContains(Code, 'FA: string;');
  AssertContains(Code, 'FB: Int64;');
end;

procedure TCodeGenCompositionTests.AllOfSamePropertyUsesIntersection;
begin
  AssertContains(TypesOf('{"allOf":[{"type":"object","additionalProperties":false,"properties":{"value":{"type":"number"}}},{"type":"object","additionalProperties":false,"properties":{"value":{"type":"integer"}}}]}'), 'FValue: Int64;');
end;

procedure TCodeGenCompositionTests.OneOfIntegerAndNumberUsesDouble;
begin
  AssertContains(TypesOf('{"oneOf":[{"type":"integer"},{"type":"number"}]}'), 'TRoot = Double;');
end;

procedure TCodeGenCompositionTests.AnyOfScalarMixtureUsesVariant;
begin
  AssertContains(TypesOf('{"anyOf":[{"type":"string"},{"type":"integer"}]}'), 'TRoot = Variant;');
end;

procedure TCodeGenCompositionTests.UnionFallbackOptionUsesConfiguredType;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetUnionKind(TJsonCodeGenUnionKind.FallbackType).SetUnknownType('TJsonValue').SetUnknownTypeUnit('NativeJson.Dom.Value');
  AssertContains(TypesOf('{"oneOf":[{"type":"string"},{"type":"integer"}]}', Options), 'TRoot = TJsonValue;');
end;

procedure TCodeGenCompositionTests.NullableNativeDefaultKeepsTypeAndWarns;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  AssertContains(TypesOf('{"type":["string","null"]}'), 'TRoot = string;');
  Diagnostics := DiagnosticsOf('{"type":["string","null"]}');
  AssertDiagnostic(Diagnostics, 'CG103');
end;

procedure TCodeGenCompositionTests.NullableVariantUsesVariant;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetNullableKind(TJsonCodeGenNullableKind.VariantForScalars);
  AssertContains(TypesOf('{"type":["string","null"]}', Options), 'TRoot = Variant;');
end;

procedure TCodeGenCompositionTests.NullableFallbackUsesConfiguredType;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetNullableKind(TJsonCodeGenNullableKind.FallbackType).SetUnknownType('TJsonValue').SetUnknownTypeUnit('NativeJson.Dom.Value');
  AssertContains(TypesOf('{"type":["integer","null"]}', Options), 'TRoot = TJsonValue;');
end;

procedure TCodeGenCompositionTests.SafeStringEnumCreatesDelphiEnum;
begin
  AssertContains(TypesOf('{"type":"string","enum":["Red","Green","Blue"]}'), 'TRoot = (Red, Green, Blue);');
end;

procedure TCodeGenCompositionTests.UnsafeStringEnumCreatesScalarConstants;
var
  Code: string;
begin
  Code := TypesOf('{"type":"string","enum":["in progress","done"]}');
  AssertContains(Code, 'TRoot = string;');
  AssertContains(Code, 'const');
  AssertContains(Code, ': TRoot = ''in progress'';');
end;

procedure TCodeGenCompositionTests.ScalarConstantsOptionDisablesDelphiEnum;
var
  Options: TJsonCodeGenOptions;
  Code: string;
begin
  Options := TJsonCodeGenOptions.Default.SetEnumKind(TJsonCodeGenEnumKind.ScalarConstants);
  Code := TypesOf('{"type":"string","enum":["Red","Green"]}', Options);
  AssertContains(Code, 'TRoot = string;');
  AssertContains(Code, ': TRoot = ''Red'';');
end;

procedure TCodeGenCompositionTests.MixedEnumUsesFallbackAndDiagnostic;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  AssertContains(TypesOf('{"enum":["x",1,true]}'), 'TRoot = Variant;');
  Diagnostics := DiagnosticsOf('{"enum":["x",1,true]}');
  AssertDiagnostic(Diagnostics, 'CG108');
end;

procedure TCodeGenCompositionTests.ConstInfersTypeAndProducesRuntimeDiagnostic;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  AssertContains(TypesOf('{"const":42}'), 'TRoot = Int64;');
  Diagnostics := DiagnosticsOf('{"const":42}');
  AssertDiagnostic(Diagnostics, 'CG013');
end;

procedure TCodeGenCompositionTests.FalseSchemaProducesFallbackAndDiagnostic;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  AssertContains(TypesOf('false'), 'TRoot = Variant;');
  Diagnostics := DiagnosticsOf('false');
  AssertDiagnostic(Diagnostics, 'CG010');
end;

procedure TCodeGenCompositionTests.ObjectOneOfMergesProperties;
var
  Code: string;
begin
  Code := TypesOf('{"oneOf":[{"type":"object","additionalProperties":false,"properties":{"a":{"type":"string"}}},{"type":"object","additionalProperties":false,"properties":{"b":{"type":"integer"}}}]}');
  AssertContains(Code, 'FA: string;');
  AssertContains(Code, 'FB: Int64;');
end;

procedure TCodeGenCompositionTests.ObjectOneOfRequiredOnlyWhenCommon;
var
  Code: string;
begin
  Code := TypesOf('{"oneOf":[{"type":"object","additionalProperties":false,"required":["same","onlyA"],"properties":{"same":{"type":"string"},"onlyA":{"type":"string"}}},{"type":"object","additionalProperties":false,"required":["same"],"properties":{"same":{"type":"string"},"onlyB":{"type":"string"}}}]}');
  Assert.AreEqual(1, CountText(Code, '[JsonRequired]'));
end;

procedure TCodeGenCompositionTests.ArrayOneOfMergesItemType;
begin
  AssertContains(TypesOf('{"oneOf":[{"type":"array","items":{"type":"integer"}},{"type":"array","items":{"type":"number"}}]}'), 'TRoot = TArray<Double>;');
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeGenCompositionTests);

end.
