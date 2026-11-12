{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Package3.CodeGen.References;

interface

{$I NativeJson.inc}

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('codegen.references')]
  TCodeGenReferenceTests = class
  public
    [Test] procedure LocalDefsReferenceCreatesSharedType;
    [Test] procedure LegacyDefinitionsReferenceWorks;
    [Test] procedure JsonPointerEscapesSlash;
    [Test] procedure JsonPointerEscapesTilde;
    [Test] procedure AnchorReferenceWorks;
    [Test] procedure NestedIdCreatesResource;
    [Test] procedure AbsoluteExternalReferenceWorks;
    [Test] procedure RelativeExternalReferenceWorks;
    [Test] procedure ExternalReferenceCanBeLoadedFromFile;
    [Test] procedure UnresolvedReferenceProducesError;
    [Test] procedure DynamicReferenceProducesStaticResolutionDiagnostic;
    [Test] procedure RecursiveReferenceProducesStaticResolutionDiagnostic;
    [Test] procedure Draft07RefIgnoresStructuralSibling;
    [Test] procedure Draft202012RefMergesStructuralSibling;
    [Test] procedure SelfRecursiveObjectUsesClassReference;
    [Test] procedure MutualRecursionCreatesForwardDeclarations;
    [Test] procedure RecursiveArrayAliasProducesFallbackDiagnostic;
    [Test] procedure GenerateUnusedDefinitionsTrueEmitsUnusedDefinition;
    [Test] procedure GenerateUnusedDefinitionsFalseSkipsUnusedDefinition;
  end;

implementation

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE}
  System.SysUtils,
  {$ENDIF}
  NativeJson.CodeGen,
  NativeJson.CodeGen.Options,
  NativeJson.CodeGen.Model,
  Package3.CodeGen.Helpers;

procedure TCodeGenReferenceTests.LocalDefsReferenceCreatesSharedType;
var
  Code: string;
begin
  Code := TypesOf('{"type":"object","additionalProperties":false,"properties":{"billing":{"$ref":"#/$defs/address"},"shipping":{"$ref":"#/$defs/address"}},"$defs":{"address":{"type":"object","additionalProperties":false,"properties":{"city":{"type":"string"}}}}}');
  Assert.AreEqual(1, CountText(Code, 'TAddress = class;'));
  AssertContains(Code, 'FBilling: TAddress;');
  AssertContains(Code, 'FShipping: TAddress;');
end;

procedure TCodeGenReferenceTests.LegacyDefinitionsReferenceWorks;
begin
  AssertContains(TypesOf('{"$schema":"http://json-schema.org/draft-07/schema#","type":"object","additionalProperties":false,"properties":{"item":{"$ref":"#/definitions/item"}},"definitions":{"item":{"type":"object","additionalProperties":false,"properties":{"id":{"type":"integer"}}}}}'), 'FItem: TItem;');
end;

procedure TCodeGenReferenceTests.JsonPointerEscapesSlash;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
  Code: string;
begin
  Code := TypesOf('{"type":"object","additionalProperties":false,"properties":{"value":{"$ref":"#/$defs/a~1b"}},"$defs":{"a/b":{"type":"string"}}}');
  Diagnostics := DiagnosticsOf('{"type":"object","additionalProperties":false,"properties":{"value":{"$ref":"#/$defs/a~1b"}},"$defs":{"a/b":{"type":"string"}}}');
  AssertContains(Code, 'FValue:');
  AssertNoDiagnostic(Diagnostics, 'CG004');
end;

procedure TCodeGenReferenceTests.JsonPointerEscapesTilde;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
  Code: string;
begin
  Code := TypesOf('{"type":"object","additionalProperties":false,"properties":{"value":{"$ref":"#/$defs/a~0b"}},"$defs":{"a~b":{"type":"integer"}}}');
  Diagnostics := DiagnosticsOf('{"type":"object","additionalProperties":false,"properties":{"value":{"$ref":"#/$defs/a~0b"}},"$defs":{"a~b":{"type":"integer"}}}');
  AssertContains(Code, 'FValue:');
  AssertNoDiagnostic(Diagnostics, 'CG004');
end;

procedure TCodeGenReferenceTests.AnchorReferenceWorks;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
  Code: string;
begin
  Code := TypesOf('{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"properties":{"address":{"$ref":"#address"}},"$defs":{"x":{"$anchor":"address","type":"object","additionalProperties":false,"properties":{"city":{"type":"string"}}}}}');
  Diagnostics := DiagnosticsOf('{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"properties":{"address":{"$ref":"#address"}},"$defs":{"x":{"$anchor":"address","type":"object","additionalProperties":false,"properties":{"city":{"type":"string"}}}}}');
  AssertContains(Code, 'FAddress:');
  AssertContains(Code, 'FCity: string;');
  AssertNoDiagnostic(Diagnostics, 'CG004');
end;

procedure TCodeGenReferenceTests.NestedIdCreatesResource;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
  Code: string;
begin
  Code := TypesOf('{"$id":"https://example.test/root.json","type":"object","additionalProperties":false,"properties":{"address":{"$ref":"address.json"}},"$defs":{"x":{"$id":"address.json","type":"object","additionalProperties":false,"properties":{"city":{"type":"string"}}}}}');
  Diagnostics := DiagnosticsOf('{"$id":"https://example.test/root.json","type":"object","additionalProperties":false,"properties":{"address":{"$ref":"address.json"}},"$defs":{"x":{"$id":"address.json","type":"object","additionalProperties":false,"properties":{"city":{"type":"string"}}}}}');
  AssertContains(Code, 'FAddress:');
  AssertContains(Code, 'FCity: string;');
  AssertNoDiagnostic(Diagnostics, 'CG004');
end;

procedure TCodeGenReferenceTests.AbsoluteExternalReferenceWorks;
var
  Generator: TNativeJsonSchemaCodeGenerator;
  Code: string;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.RegisterSchema('https://example.test/address.json', '{"type":"object","additionalProperties":false,"properties":{"city":{"type":"string"}}}');
    Generator.LoadSchema('{"type":"object","additionalProperties":false,"properties":{"address":{"$ref":"https://example.test/address.json"}}}', 'https://example.test/customer.json');
    Code := Generator.GenerateTypes;
    AssertContains(Code, 'FAddress:');
    AssertContains(Code, 'FCity: string;');
    AssertNoDiagnostic(Generator.Diagnostics, 'CG004');
  finally
    Generator.Free;
  end;
end;

procedure TCodeGenReferenceTests.RelativeExternalReferenceWorks;
var
  Generator: TNativeJsonSchemaCodeGenerator;
  Code: string;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.RegisterSchema('https://example.test/common/address.json', '{"type":"object","additionalProperties":false,"properties":{"city":{"type":"string"}}}');
    Generator.LoadSchema('{"type":"object","additionalProperties":false,"properties":{"address":{"$ref":"../common/address.json"}}}', 'https://example.test/schemas/customer.json');
    Code := Generator.GenerateTypes;
    AssertContains(Code, 'FAddress:');
    AssertContains(Code, 'FCity: string;');
    AssertNoDiagnostic(Generator.Diagnostics, 'CG004');
  finally
    Generator.Free;
  end;
end;

procedure TCodeGenReferenceTests.ExternalReferenceCanBeLoadedFromFile;
var
  Generator: TNativeJsonSchemaCodeGenerator;
  Code: string;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.RegisterSchemaFromFile('https://example.test/address.json', TestDataFile('ExternalAddress.schema.json'));
    Generator.LoadSchemaFromFile(TestDataFile('ExternalCustomer.schema.json'), 'https://example.test/customer.json');
    Code := Generator.GenerateTypes;
    AssertContains(Code, 'FAddress:');
    AssertContains(Code, 'FPostcode: string;');
    AssertNoDiagnostic(Generator.Diagnostics, 'CG004');
  finally
    Generator.Free;
  end;
end;

procedure TCodeGenReferenceTests.UnresolvedReferenceProducesError;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"type":"object","additionalProperties":false,"properties":{"x":{"$ref":"missing.json"}}}');
  AssertDiagnostic(Diagnostics, 'CG004');
end;

procedure TCodeGenReferenceTests.DynamicReferenceProducesStaticResolutionDiagnostic;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"properties":{"x":{"$dynamicRef":"#node"}},"$defs":{"n":{"$dynamicAnchor":"node","type":"string"}}}');
  AssertDiagnostic(Diagnostics, 'CG006');
end;

procedure TCodeGenReferenceTests.RecursiveReferenceProducesStaticResolutionDiagnostic;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"$schema":"https://json-schema.org/draft/2019-09/schema","$recursiveAnchor":true,"type":"object","additionalProperties":false,"properties":{"next":{"$recursiveRef":"#"}}}');
  AssertDiagnostic(Diagnostics, 'CG006');
end;

procedure TCodeGenReferenceTests.Draft07RefIgnoresStructuralSibling;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
  Code: string;
  Generator: TNativeJsonSchemaCodeGenerator;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.LoadSchema('{"$schema":"http://json-schema.org/draft-07/schema#","type":"object","additionalProperties":false,"properties":{"value":{"$ref":"#/$defs/base","type":"string"}},"$defs":{"base":{"type":"integer"}}}');
    Code := Generator.GenerateTypes;
    Diagnostics := Generator.Diagnostics;
    AssertContains(Code, 'TBase = Int64;');
    AssertContains(Code, 'FValue: TBase;');
    AssertDiagnostic(Diagnostics, 'CG005');
  finally
    Generator.Free;
  end;
end;

procedure TCodeGenReferenceTests.Draft202012RefMergesStructuralSibling;
begin
  AssertContains(TypesOf('{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"properties":{"value":{"$ref":"#/$defs/base","maximum":10}},"$defs":{"base":{"type":"integer","minimum":0}}}'), 'FValue: Integer;');
end;

procedure TCodeGenReferenceTests.SelfRecursiveObjectUsesClassReference;
var
  Code: string;
begin
  Code := TypesOf('{"$id":"https://example.test/node.json","type":"object","additionalProperties":false,"properties":{"value":{"type":"string"},"next":{"$ref":"#"}}}');
  AssertContains(Code, 'TRoot = class;');
  AssertContains(Code, 'FNext: TRoot;');
end;

procedure TCodeGenReferenceTests.MutualRecursionCreatesForwardDeclarations;
var
  Code: string;
begin
  Code := TypesOf('{"type":"object","additionalProperties":false,"properties":{"a":{"$ref":"#/$defs/a"}},"$defs":{"a":{"type":"object","additionalProperties":false,"properties":{"b":{"$ref":"#/$defs/b"}}},"b":{"type":"object","additionalProperties":false,"properties":{"a":{"$ref":"#/$defs/a"}}}}}');
  AssertContains(Code, 'TA = class;');
  AssertContains(Code, 'TB = class;');
  AssertContains(Code, 'FB: TB;');
  AssertContains(Code, 'FA: TA;');
end;

procedure TCodeGenReferenceTests.RecursiveArrayAliasProducesFallbackDiagnostic;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"$id":"https://example.test/list.json","type":"array","items":{"$ref":"#"}}');
  AssertDiagnostic(Diagnostics, 'CG112');
end;

procedure TCodeGenReferenceTests.GenerateUnusedDefinitionsTrueEmitsUnusedDefinition;
begin
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"$defs":{"unused":{"type":"object","additionalProperties":false,"properties":{"id":{"type":"integer"}}}}}'), 'TUnused = class');
end;

procedure TCodeGenReferenceTests.GenerateUnusedDefinitionsFalseSkipsUnusedDefinition;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetGenerateUnusedDefinitions(False);
  AssertNotContains(TypesOf('{"type":"object","additionalProperties":false,"$defs":{"unused":{"type":"object","additionalProperties":false,"properties":{"id":{"type":"integer"}}}}}', Options), 'TUnused = class');
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeGenReferenceTests);

end.
