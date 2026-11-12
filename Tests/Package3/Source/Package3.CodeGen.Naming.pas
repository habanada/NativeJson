{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Package3.CodeGen.Naming;

interface

{$I NativeJson.inc}

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('codegen.naming')]
  TCodeGenNamingTests = class
  public
    [Test] procedure CamelCaseBecomesPascalCase;
    [Test] procedure KebabCaseBecomesPascalCase;
    [Test] procedure SpaceSeparatedBecomesPascalCase;
    [Test] procedure SnakeCaseBecomesPascalCase;
    [Test] procedure ScreamingSnakeBecomesPascalCase;
    [Test] procedure LeadingDigitIsEscaped;
    [Test] procedure EmptyNameGetsIdentifier;
    [Test] procedure ReservedWordIsEscaped;
    [Test] procedure ReservedClassMemberIsRenamed;
    [Test] procedure RecordKeepsReservedClassMember;
    [Test] procedure CollidingConvertedNamesAreNumbered;
    [Test] procedure JsonPropertyPreservesOriginalName;
    [Test] procedure JsonPropertyEscapesApostrophe;
    [Test] procedure TypePrefixIsConfigurable;
    [Test] procedure RootTypeNameIsConfigurable;
    [Test] procedure TitleCanNameDefinition;
    [Test] procedure TitleNamingCanBeDisabled;
    [Test] procedure DuplicateTypeNamesAreNumbered;
    [Test] procedure ExternalJsonFileNameDropsExtension;
  end;

implementation

uses
  NativeJson.CodeGen,
  NativeJson.CodeGen.Names,
  NativeJson.CodeGen.Options,
  Package3.CodeGen.Helpers;

procedure TCodeGenNamingTests.CamelCaseBecomesPascalCase;
begin
  Assert.AreEqual('UserName', TJsonCodeGenNameAllocator.DelphiIdentifier('userName'));
end;

procedure TCodeGenNamingTests.KebabCaseBecomesPascalCase;
begin
  Assert.AreEqual('UserName', TJsonCodeGenNameAllocator.DelphiIdentifier('user-name'));
end;

procedure TCodeGenNamingTests.SpaceSeparatedBecomesPascalCase;
begin
  Assert.AreEqual('UserName', TJsonCodeGenNameAllocator.DelphiIdentifier('user name'));
end;

procedure TCodeGenNamingTests.SnakeCaseBecomesPascalCase;
begin
  Assert.AreEqual('UserName', TJsonCodeGenNameAllocator.DelphiIdentifier('user_name'));
end;

procedure TCodeGenNamingTests.ScreamingSnakeBecomesPascalCase;
begin
  Assert.AreEqual('UserName', TJsonCodeGenNameAllocator.DelphiIdentifier('USER_NAME'));
end;

procedure TCodeGenNamingTests.LeadingDigitIsEscaped;
begin
  Assert.AreEqual('_123Name', TJsonCodeGenNameAllocator.DelphiIdentifier('123-name'));
end;

procedure TCodeGenNamingTests.EmptyNameGetsIdentifier;
begin
  Assert.AreEqual('_', TJsonCodeGenNameAllocator.DelphiIdentifier(''));
end;

procedure TCodeGenNamingTests.ReservedWordIsEscaped;
begin
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"type":{"type":"string"}}}'), 'property &Type: string read FType write FType;');
end;

procedure TCodeGenNamingTests.ReservedClassMemberIsRenamed;
begin
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"create":{"type":"string"}}}'), 'property CreateValue: string read FCreateValue write FCreateValue;');
end;

procedure TCodeGenNamingTests.RecordKeepsReservedClassMember;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Records;
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"create":{"type":"string"}}}', Options), 'Create: string;');
end;

procedure TCodeGenNamingTests.CollidingConvertedNamesAreNumbered;
var
  Code: string;
begin
  Code := TypesOf('{"type":"object","additionalProperties":false,"properties":{"user-name":{"type":"string"},"user name":{"type":"string"}}}');
  AssertContains(Code, 'property UserName: string');
  AssertContains(Code, 'property UserName2: string');
end;

procedure TCodeGenNamingTests.JsonPropertyPreservesOriginalName;
begin
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"user-name":{"type":"string"}}}'), '[JsonProperty(''user-name'')]');
end;

procedure TCodeGenNamingTests.JsonPropertyEscapesApostrophe;
begin
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"properties":{"owner''s-name":{"type":"string"}}}'), '[JsonProperty(''owner''''s-name'')]');
end;

procedure TCodeGenNamingTests.TypePrefixIsConfigurable;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetTypePrefix('N');
  AssertContains(TypesOf('{"type":"object","additionalProperties":false}', Options), 'NRoot = class');
end;

procedure TCodeGenNamingTests.RootTypeNameIsConfigurable;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetRootTypeName('Customer');
  AssertContains(TypesOf('{"type":"object","additionalProperties":false}', Options), 'TCustomer = class');
end;

procedure TCodeGenNamingTests.TitleCanNameDefinition;
var
  Code: string;
begin
  Code := TypesOf('{"type":"object","additionalProperties":false,"properties":{"item":{"$ref":"#/$defs/x"}},"$defs":{"x":{"title":"Invoice Line","type":"object","additionalProperties":false}}}');
  AssertContains(Code, 'TInvoiceLine = class');
end;

procedure TCodeGenNamingTests.TitleNamingCanBeDisabled;
var
  Options: TJsonCodeGenOptions;
  Code: string;
begin
  Options := TJsonCodeGenOptions.Default.SetUseTitlesForTypeNames(False);
  Code := TypesOf('{"type":"object","additionalProperties":false,"properties":{"item":{"$ref":"#/$defs/x"}},"$defs":{"x":{"title":"Invoice Line","type":"object","additionalProperties":false}}}', Options);
  AssertContains(Code, 'TX = class');
end;

procedure TCodeGenNamingTests.DuplicateTypeNamesAreNumbered;
var
  Code: string;
begin
  Code := TypesOf('{"type":"object","additionalProperties":false,"properties":{"a":{"$ref":"#/$defs/a"},"b":{"$ref":"#/$defs/b"}},"$defs":{"a":{"title":"Thing","type":"object","additionalProperties":false},"b":{"title":"Thing","type":"object","additionalProperties":false}}}');
  AssertContains(Code, 'TThing = class');
  AssertContains(Code, 'TThing2 = class');
end;


procedure TCodeGenNamingTests.ExternalJsonFileNameDropsExtension;
var
  Generator: TNativeJsonSchemaCodeGenerator;
  Code: string;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.RegisterSchema('https://example.test/address.json', '{"type":"object","additionalProperties":false,"properties":{"city":{"type":"string"}}}');
    Generator.LoadSchema('{"type":"object","additionalProperties":false,"properties":{"address":{"$ref":"https://example.test/address.json"}}}', 'https://example.test/customer.json');
    Code := Generator.GenerateTypes;
    AssertContains(Code, 'TAddress = class');
    AssertNotContains(Code, 'TAddressJson = class');
  finally
    Generator.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeGenNamingTests);

end.
