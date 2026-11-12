{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Package3.CodeGen.OpenApi;

interface

{$I NativeJson.inc}

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('codegen.openapi')]
  TCodeGenOpenApiTests = class
  public
    [Test] procedure OpenApi30SingleComponentBecomesRoot;
    [Test] procedure OpenApi30MultipleComponentsGenerateAll;
    [Test] procedure OpenApi31MultipleComponentsGenerateAll;
    [Test] procedure OpenApiComponentRefWorks;
    [Test] procedure OpenApi30NullableUsesNullableSemantics;
    [Test] procedure OpenApiFormatWithoutTypeInfersInteger;
    [Test] procedure OpenApiInt32UsesInteger;
    [Test] procedure OpenApiDoubleUsesDouble;
    [Test] procedure OpenApiDecimalCanUseCurrency;
    [Test] procedure OpenApiDiscriminatorProducesRuntimeDiagnostic;
    [Test] procedure DetectionCanBeDisabled;
    [Test] procedure OpenApiFileCanBeLoaded;
  end;

implementation

uses
  NativeJson.CodeGen,
  NativeJson.CodeGen.Options,
  NativeJson.CodeGen.Model,
  Package3.CodeGen.Helpers;

procedure TCodeGenOpenApiTests.OpenApi30SingleComponentBecomesRoot;
var
  Generator: TNativeJsonSchemaCodeGenerator;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.LoadSchema('{"openapi":"3.0.3","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":{"Customer":{"type":"object","additionalProperties":false,"properties":{"name":{"type":"string"}}}}}}');
    Assert.AreEqual('TCustomer', Generator.RootTypeName);
  finally
    Generator.Free;
  end;
end;

procedure TCodeGenOpenApiTests.OpenApi30MultipleComponentsGenerateAll;
var
  Code: string;
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Code := TypesOf('{"openapi":"3.0.3","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":{"Customer":{"type":"object","additionalProperties":false},"Order":{"type":"object","additionalProperties":false}}}}');
  AssertContains(Code, 'TCustomer = class');
  AssertContains(Code, 'TOrder = class');
  Diagnostics := DiagnosticsOf('{"openapi":"3.0.3","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":{"Customer":{"type":"object","additionalProperties":false},"Order":{"type":"object","additionalProperties":false}}}}');
  AssertDiagnostic(Diagnostics, 'CG012');
end;

procedure TCodeGenOpenApiTests.OpenApi31MultipleComponentsGenerateAll;
begin
  AssertContains(TypesOf('{"openapi":"3.1.0","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":{"A":{"type":"object","additionalProperties":false},"B":{"type":"string"}}}}'), 'TA = class');
end;

procedure TCodeGenOpenApiTests.OpenApiComponentRefWorks;
var
  Code: string;
begin
  Code := TypesOf('{"openapi":"3.1.0","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":{"Customer":{"type":"object","additionalProperties":false,"properties":{"address":{"$ref":"#/components/schemas/Address"}}},"Address":{"type":"object","additionalProperties":false,"properties":{"city":{"type":"string"}}}}}}');
  AssertContains(Code, 'FAddress: TAddress;');
  AssertContains(Code, 'FCity: string;');
end;

procedure TCodeGenOpenApiTests.OpenApi30NullableUsesNullableSemantics;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"openapi":"3.0.3","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":{"Value":{"type":"string","nullable":true}}}}');
  AssertDiagnostic(Diagnostics, 'CG103');
end;

procedure TCodeGenOpenApiTests.OpenApiFormatWithoutTypeInfersInteger;
begin
  AssertContains(TypesOf('{"openapi":"3.0.3","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":{"Value":{"format":"int64"}}}}'), '= Int64;');
end;

procedure TCodeGenOpenApiTests.OpenApiInt32UsesInteger;
begin
  AssertContains(TypesOf('{"openapi":"3.0.3","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":{"Value":{"type":"integer","format":"int32"}}}}'), '= Integer;');
end;

procedure TCodeGenOpenApiTests.OpenApiDoubleUsesDouble;
begin
  AssertContains(TypesOf('{"openapi":"3.0.3","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":{"Value":{"type":"number","format":"double"}}}}'), '= Double;');
end;

procedure TCodeGenOpenApiTests.OpenApiDecimalCanUseCurrency;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetPreferCurrencyForDecimal(True);
  AssertContains(TypesOf('{"openapi":"3.1.0","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":{"Value":{"type":"number","format":"decimal"}}}}', Options), '= Currency;');
end;

procedure TCodeGenOpenApiTests.OpenApiDiscriminatorProducesRuntimeDiagnostic;
var
  Diagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  Diagnostics := DiagnosticsOf('{"openapi":"3.1.0","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":{"Pet":{"type":"object","additionalProperties":false,"discriminator":{"propertyName":"kind"}}}}}');
  AssertDiagnostic(Diagnostics, 'CG013');
end;

procedure TCodeGenOpenApiTests.DetectionCanBeDisabled;
var
  Options: TJsonCodeGenOptions;
  Code: string;
begin
  Options := TJsonCodeGenOptions.Default.SetDetectOpenApi(False);
  Code := TypesOf('{"openapi":"3.1.0","info":{"title":"x","version":"1"},"paths":{},"components":{"schemas":{"Customer":{"type":"object","additionalProperties":false}}}}', Options);
  AssertContains(Code, 'TRoot = Variant;');
  AssertNotContains(Code, 'TCustomer = class');
end;

procedure TCodeGenOpenApiTests.OpenApiFileCanBeLoaded;
var
  Generator: TNativeJsonSchemaCodeGenerator;
  Code: string;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create;
  try
    Generator.LoadSchemaFromFile(TestDataFile('OpenApi31.json'));
    Code := Generator.GenerateTypes;
    AssertContains(Code, 'TCustomer = class');
    AssertContains(Code, 'TAddress = class');
  finally
    Generator.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeGenOpenApiTests);

end.
