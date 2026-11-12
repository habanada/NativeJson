{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Package3.CodeGen.Output;

interface

{$I NativeJson.inc}

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('codegen.output')]
  TCodeGenOutputTests = class
  public
    [Test] procedure UnitStructureIsComplete;
    [Test] procedure ScopedEnumsDirectiveIsEmitted;
    [Test] procedure JsonPropertyAttributesAddNativeJsonAttributesUse;
    [Test] procedure SchemaAttributesAddSchemaAttributesUse;
    [Test] procedure GenericsUseIsEmittedWhenNeeded;
    [Test] procedure VariantsUseIsEmittedWhenNeeded;
    [Test] procedure UnknownTypeUnitIsEmitted;
    [Test] procedure EmbeddedSchemaIsEmittedByDefault;
    [Test] procedure EmbeddedSchemaCanBeDisabled;
    [Test] procedure JsonPropertyAttributesCanBeDisabled;
    [Test] procedure SchemaAttributesCanBeDisabled;
    [Test] procedure IndentSizeIsRespected;
    [Test] procedure NegativeIndentIsClampedToZero;
    [Test] procedure SameSchemaGeneratesDeterministically;
    [Test] procedure SameGeneratorCanGenerateTwiceDeterministically;
    [Test] procedure LoadJsonValueClonesInput;
    [Test] procedure SaveUnitToFileWritesUtf8Source;
    [Test] procedure GenerateWithoutSchemaRaises;
    [Test] procedure EmptySchemaRaises;
    [Test] procedure InvalidJsonRaises;
    [Test] procedure InvalidJsonFileRaises;
    [Test] procedure EmptyUnitNameRaises;
    [Test] procedure RootTypeNameReturnsGeneratedType;
  end;

implementation

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE}
  System.SysUtils,
  {$ENDIF}
  NativeJson.Dom.Value,
  NativeJson.Dom.Io,
  System.IOUtils,
  NativeJson.CodeGen,
  NativeJson.CodeGen.Options,
  NativeJson.CodeGen.Repository,
  Package3.CodeGen.Helpers;

const
  SimpleObject = '{"type":"object","additionalProperties":false,"required":["name"],"properties":{"name":{"type":"string","minLength":1}}}';

procedure TCodeGenOutputTests.UnitStructureIsComplete;
var
  Code: string;
begin
  Code := UnitOf(SimpleObject, 'Demo.Models');
  AssertContains(Code, 'unit Demo.Models;');
  AssertContains(Code, 'interface');
  AssertContains(Code, 'type');
  AssertContains(Code, 'implementation');
  AssertContains(Code, 'end.');
  AssertBefore(Code, 'interface', 'implementation');
end;

procedure TCodeGenOutputTests.ScopedEnumsDirectiveIsEmitted;
begin
  AssertContains(UnitOf(SimpleObject, 'Demo.Models'), '{$SCOPEDENUMS ON}');
end;

procedure TCodeGenOutputTests.JsonPropertyAttributesAddNativeJsonAttributesUse;
begin
  AssertContains(UnitOf(SimpleObject, 'Demo.Models'), 'NativeJson.Attributes');
end;

procedure TCodeGenOutputTests.SchemaAttributesAddSchemaAttributesUse;
begin
  AssertContains(UnitOf(SimpleObject, 'Demo.Models'), 'NativeJson.Schema.Attributes');
end;

procedure TCodeGenOutputTests.GenericsUseIsEmittedWhenNeeded;
begin
  AssertContains(UnitOf('{"type":"object","additionalProperties":{"type":"string"}}', 'Demo.Models'), 'System.Generics.Collections');
end;

procedure TCodeGenOutputTests.VariantsUseIsEmittedWhenNeeded;
begin
  AssertContains(UnitOf('{"oneOf":[{"type":"string"},{"type":"integer"}]}', 'Demo.Models'), 'System.Variants');
end;

procedure TCodeGenOutputTests.UnknownTypeUnitIsEmitted;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetUnknownType('TJsonValue').SetUnknownTypeUnit('NativeJson.Dom.Value');
  AssertContains(UnitOf('{}', 'Demo.Models', Options), 'NativeJson.Dom.Value');
end;

procedure TCodeGenOutputTests.EmbeddedSchemaIsEmittedByDefault;
begin
  AssertContains(TypesOf(SimpleObject), 'CJsonSchema: string =');
end;

procedure TCodeGenOutputTests.EmbeddedSchemaCanBeDisabled;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetEmbedSchema(False);
  AssertNotContains(TypesOf(SimpleObject, Options), 'CJsonSchema');
end;

procedure TCodeGenOutputTests.JsonPropertyAttributesCanBeDisabled;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetEmitJsonPropertyAttributes(False);
  AssertNotContains(TypesOf(SimpleObject, Options), '[JsonProperty(');
end;

procedure TCodeGenOutputTests.SchemaAttributesCanBeDisabled;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetEmitSchemaAttributes(False);
  AssertNotContains(TypesOf(SimpleObject, Options), '[JsonRequired]');
  AssertNotContains(TypesOf(SimpleObject, Options), '[JsonMinLength(');
end;

procedure TCodeGenOutputTests.IndentSizeIsRespected;
var
  Options: TJsonCodeGenOptions;
  Code: string;
begin
  Options := TJsonCodeGenOptions.Default.SetIndentSize(4);
  Code := TypesOf(SimpleObject, Options);
  AssertContains(Code, '    TRoot = class;');
  AssertContains(Code, '        FName: string;');
end;

procedure TCodeGenOutputTests.NegativeIndentIsClampedToZero;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetIndentSize(-5);
  Assert.AreEqual(0, Options.IndentSize);
end;

procedure TCodeGenOutputTests.SameSchemaGeneratesDeterministically;
var
  A, B: string;
begin
  A := UnitOf(SimpleObject, 'Demo.Models');
  B := UnitOf(SimpleObject, 'Demo.Models');
  Assert.AreEqual(A, B);
end;

procedure TCodeGenOutputTests.SameGeneratorCanGenerateTwiceDeterministically;
var
  Generator: TNativeJsonSchemaCodeGenerator;
  A, B: string;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.LoadSchema(SimpleObject);
    A := Generator.GenerateUnit('Demo.Models');
    B := Generator.GenerateUnit('Demo.Models');
    Assert.AreEqual(A, B);
  finally
    Generator.Free;
  end;
end;

procedure TCodeGenOutputTests.LoadJsonValueClonesInput;
var
  Generator: TNativeJsonSchemaCodeGenerator;
  Value: TJsonValue;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Value := DomFromText(SimpleObject);
    try
      Generator.LoadSchema(Value);
    finally
      Value.Free;
    end;
    AssertContains(Generator.GenerateTypes, 'FName: string;');
  finally
    Generator.Free;
  end;
end;

procedure TCodeGenOutputTests.SaveUnitToFileWritesUtf8Source;
var
  Generator: TNativeJsonSchemaCodeGenerator;
  FileName, Code: string;
begin
  FileName := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.LoadSchema(SimpleObject);
    Generator.SaveUnitToFile(FileName, 'Demo.Generated');
    Assert.IsTrue(TFile.Exists(FileName));
    Code := TFile.ReadAllText(FileName);
    AssertContains(Code, 'unit Demo.Generated;');
  finally
    Generator.Free;
    if TFile.Exists(FileName) then TFile.Delete(FileName);
  end;
end;

procedure TCodeGenOutputTests.GenerateWithoutSchemaRaises;
var
  Generator: TNativeJsonSchemaCodeGenerator;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Assert.WillRaise(procedure begin Generator.GenerateTypes; end, EJsonCodeGenError);
  finally
    Generator.Free;
  end;
end;

procedure TCodeGenOutputTests.EmptySchemaRaises;
var
  Generator: TNativeJsonSchemaCodeGenerator;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Assert.WillRaise(procedure begin Generator.LoadSchema(''); end, EJsonCodeGenError);
  finally
    Generator.Free;
  end;
end;

procedure TCodeGenOutputTests.InvalidJsonRaises;
begin
  Assert.WillRaise(procedure begin TNativeJsonSchemaCodeGenerator.SchemaToTypes('{broken'); end, EJsonCodeGenRepository);
end;

procedure TCodeGenOutputTests.InvalidJsonFileRaises;
var
  Generator: TNativeJsonSchemaCodeGenerator;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Assert.WillRaise(procedure begin Generator.LoadSchemaFromFile(TestDataFile('Invalid.schema.json')); end, EJsonCodeGenRepository);
  finally
    Generator.Free;
  end;
end;

procedure TCodeGenOutputTests.EmptyUnitNameRaises;
var
  Generator: TNativeJsonSchemaCodeGenerator;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.LoadSchema(SimpleObject);
    Assert.WillRaise(procedure begin Generator.GenerateUnit(''); end, EArgumentException);
  finally
    Generator.Free;
  end;
end;

procedure TCodeGenOutputTests.RootTypeNameReturnsGeneratedType;
var
  Generator: TNativeJsonSchemaCodeGenerator;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.LoadSchema(SimpleObject);
    Assert.AreEqual('TRoot', Generator.RootTypeName);
  finally
    Generator.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeGenOutputTests);

end.
