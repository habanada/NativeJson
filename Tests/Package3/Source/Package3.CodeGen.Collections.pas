{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Package3.CodeGen.Collections;

interface

{$I NativeJson.inc}

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('codegen.collections')]
  TCodeGenCollectionsTests = class
  public
    [Test] procedure RootArrayUsesDynamicArray;
    [Test] procedure ArrayOfStringsUsesStringItems;
    [Test] procedure ArrayOfObjectsCreatesItemType;
    [Test] procedure NestedArraysAreRepresented;
    [Test] procedure GenericListOptionUsesTList;
    [Test] procedure ObjectListOptionUsesTObjectListForClasses;
    [Test] procedure ObjectListOptionUsesTListForScalars;
    [Test] procedure RecordModeForcesDynamicArrays;
    [Test] procedure TypedAdditionalPropertiesUsesDictionary;
    [Test] procedure AdditionalPropertiesFalseIsNotDictionary;
    [Test] procedure AdditionalPropertiesFallbackUsesUnknownType;
    [Test] procedure AdditionalPropertiesIgnoreDoesNotUseDictionary;
    [Test] procedure OpenPatternPropertiesUseUnknownValueType;
    [Test] procedure ClosedPatternPropertiesCanUseDictionary;
    [Test] procedure FixedAndAdditionalPropertiesProduceDiagnostic;
    [Test] procedure HomogeneousPrefixItemsUseCommonType;
    [Test] procedure HeterogeneousPrefixItemsProduceDiagnostic;
    [Test] procedure Draft07TupleItemsAreRead;
    [Test] procedure ArrayLengthAttributesAreEmitted;
    [Test] procedure UniqueItemsAttributeIsEmitted;
    [Test] procedure OneSidedArrayLengthProducesDiagnostic;
  end;

implementation

uses
  NativeJson.CodeGen.Options,
  NativeJson.CodeGen.Model,
  Package3.CodeGen.Helpers;

procedure TCodeGenCollectionsTests.RootArrayUsesDynamicArray;
begin
  AssertContains(TypesOf('{"type":"array","items":{"type":"integer"}}'), 'TRoot = TArray<Int64>;');
end;

procedure TCodeGenCollectionsTests.ArrayOfStringsUsesStringItems;
begin
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"tags":{"type":"array","items":{"type":"string"}}}}'), 'FTags: TArray<string>;');
end;

procedure TCodeGenCollectionsTests.ArrayOfObjectsCreatesItemType;
var
  Code: string;
begin
  Code := TypesOf('{"type":"object","additionalProperties":false,"properties":{"items":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"name":{"type":"string"}}}}}}');
  AssertContains(Code, 'FItems: TArray<');
  AssertContains(Code, 'FName: string;');
  AssertContains(Code, '= class');
end;

procedure TCodeGenCollectionsTests.NestedArraysAreRepresented;
begin
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"matrix":{"type":"array","items":{"type":"array","items":{"type":"number"}}}}}'), 'FMatrix: TArray<TArray<Double>>;');
end;

procedure TCodeGenCollectionsTests.GenericListOptionUsesTList;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetArrayKind(TJsonCodeGenArrayKind.GenericLists);
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"items":{"type":"array","items":{"type":"string"}}}}', Options), 'FItems: TList<string>;');
end;

procedure TCodeGenCollectionsTests.ObjectListOptionUsesTObjectListForClasses;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetArrayKind(TJsonCodeGenArrayKind.ObjectLists);
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"items":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"id":{"type":"integer"}}}}}}', Options), 'FItems: TObjectList<');
end;

procedure TCodeGenCollectionsTests.ObjectListOptionUsesTListForScalars;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetArrayKind(TJsonCodeGenArrayKind.ObjectLists);
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"items":{"type":"array","items":{"type":"integer"}}}}', Options), 'FItems: TList<Int64>;');
end;

procedure TCodeGenCollectionsTests.RecordModeForcesDynamicArrays;
var
  Options: TJsonCodeGenOptions;
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Options := TJsonCodeGenOptions.Records;
  Options := Options.SetArrayKind(TJsonCodeGenArrayKind.GenericLists);
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"items":{"type":"array","items":{"type":"string"}}}}', Options), 'Items: TArray<string>;');
  Diagnostics := DiagnosticsOf('{"type":"object","additionalProperties":false,"properties":{"items":{"type":"array","items":{"type":"string"}}}}', Options);
  AssertDiagnostic(Diagnostics, 'CG101');
end;

procedure TCodeGenCollectionsTests.TypedAdditionalPropertiesUsesDictionary;
begin
  AssertContains(TypesOf('{"type":"object","additionalProperties":{"type":"integer"}}'), 'TRoot = TDictionary<string, Int64>;');
end;

procedure TCodeGenCollectionsTests.AdditionalPropertiesFalseIsNotDictionary;
begin
  AssertContains(TypesOf('{"type":"object","additionalProperties":false}'), 'TRoot = class');
end;

procedure TCodeGenCollectionsTests.AdditionalPropertiesFallbackUsesUnknownType;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetAdditionalPropertiesKind(TJsonCodeGenAdditionalPropertiesKind.FallbackType).SetUnknownType('TJsonValue').SetUnknownTypeUnit('NativeJson.Dom.Value');
  AssertContains(TypesOf('{"type":"object","additionalProperties":{"type":"string"}}', Options), 'TRoot = TJsonValue;');
end;

procedure TCodeGenCollectionsTests.AdditionalPropertiesIgnoreDoesNotUseDictionary;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetAdditionalPropertiesKind(TJsonCodeGenAdditionalPropertiesKind.Ignore);
  AssertNotContains(TypesOf('{"type":"object","additionalProperties":{"type":"string"}}', Options), 'TDictionary<');
end;

procedure TCodeGenCollectionsTests.OpenPatternPropertiesUseUnknownValueType;
begin
  AssertContains(TypesOf('{"type":"object","patternProperties":{"^x-":{"type":"string"}}}'), 'TRoot = TDictionary<string, Variant>;');
end;

procedure TCodeGenCollectionsTests.ClosedPatternPropertiesCanUseDictionary;
begin
  AssertContains(TypesOf('{"type":"object","patternProperties":{"^x-":{"type":"string"}},"additionalProperties":false}'), 'TRoot = TDictionary<string, string>;');
end;

procedure TCodeGenCollectionsTests.FixedAndAdditionalPropertiesProduceDiagnostic;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"type":"object","properties":{"id":{"type":"integer"}},"additionalProperties":{"type":"string"}}');
  AssertDiagnostic(Diagnostics, 'CG111');
end;

procedure TCodeGenCollectionsTests.HomogeneousPrefixItemsUseCommonType;
begin
  AssertContains(TypesOf('{"type":"array","prefixItems":[{"type":"integer"},{"type":"integer"}],"items":false}'), 'TRoot = TArray<Int64>;');
end;

procedure TCodeGenCollectionsTests.HeterogeneousPrefixItemsProduceDiagnostic;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"type":"array","prefixItems":[{"type":"integer"},{"type":"string"}],"items":false}');
  AssertDiagnostic(Diagnostics, 'CG009');
end;

procedure TCodeGenCollectionsTests.Draft07TupleItemsAreRead;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"$schema":"http://json-schema.org/draft-07/schema#","type":"array","items":[{"type":"integer"},{"type":"string"}],"additionalItems":false}');
  AssertDiagnostic(Diagnostics, 'CG009');
end;

procedure TCodeGenCollectionsTests.ArrayLengthAttributesAreEmitted;
begin
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"items":{"type":"array","minItems":2,"maxItems":5,"items":{"type":"string"}}}}'), '[JsonArrayLength(2, 5)]');
end;

procedure TCodeGenCollectionsTests.UniqueItemsAttributeIsEmitted;
begin
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"items":{"type":"array","uniqueItems":true,"items":{"type":"string"}}}}'), '[JsonUniqueItems]');
end;

procedure TCodeGenCollectionsTests.OneSidedArrayLengthProducesDiagnostic;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"type":"object","additionalProperties":false,"properties":{"items":{"type":"array","minItems":2,"items":{"type":"string"}}}}');
  AssertDiagnostic(Diagnostics, 'CG104');
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeGenCollectionsTests);

end.
