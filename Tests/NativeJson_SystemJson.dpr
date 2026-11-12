{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_SystemJson;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.JSON,
  Demo.Assert in '..\examples\Demos\Demo.Assert.pas',
  NativeJson.Dom.Value,
  NativeJson.Dom.Io,
  NativeJson.Schema.Validation,
  NativeJson.Schema.Validator,
  NativeJson.SystemJson;

function Parse(const Text: string): System.JSON.TJSONValue;
begin
  Result := System.JSON.TJSONObject.ParseJSONValue(Text);
  if Result = nil then raise Exception.Create('System.JSON could not parse: ' + Text);
end;

function Converted(const Text: string): string;
var
  Source: System.JSON.TJSONValue;
  Target: NativeJson.Dom.Value.TJsonValue;
begin
  Source := Parse(Text);
  try
    Target := NativeJsonFromSystemJson(Source);
    try
      Result := DomToText(Target);
    finally
      Target.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure Step1_Conversion;
var
  Source: System.JSON.TJSONValue;
  Target: NativeJson.Dom.Value.TJsonValue;
begin
  Section('1. System.JSON to NativeJson DOM');
  Check('Object, array, nested',
    '{"name":"Anna","active":true,"note":null,"tags":["a","b"],"address":{"city":"Exampletown"}}',
    Converted('{"name":"Anna","active":true,"note":null,"tags":["a","b"],"address":{"city":"Exampletown"}}'));
  Check('Integer beyond Double precision keeps its text', '[9007199254740993]', Converted('[9007199254740993]'));
  Check('UInt64 maximum keeps its text', '[18446744073709551615]', Converted('[18446744073709551615]'));
  Check('Decimal keeps its text', '[1234567890123.4567]', Converted('[1234567890123.4567]'));
  Check('Exponent keeps its text', '[1e2]', Converted('[1e2]'));
  Check('Escaped string', '["a\"b\\c"]', Converted('["a\"b\\c"]'));

  Source := Parse('{"amount":1234567890123.4567}');
  try
    Target := NativeJsonFromSystemJson(Source);
    try
      CheckTrue('Currency exact from the raw text',
        Target.Values['amount'].AsCurrency = StrToCurr('1234567890123.4567', TFormatSettings.Invariant),
        CurrToStr(Target.Values['amount'].AsCurrency));
    finally
      Target.Free;
    end;
  finally
    Source.Free;
  end;

  Target := NativeJsonFromSystemJson(nil);
  try
    Check('nil becomes null', 'null', DomToText(Target));
  finally
    Target.Free;
  end;
end;

procedure Step2_OneShotValidation;
var
  Schema, Good, Bad: System.JSON.TJSONValue;
  R: TJsonSchemaValidationResult;
begin
  Section('2. ValidateSystemJson in one call');
  Schema := Parse('{"type":"object","properties":{"name":{"type":"string"},' +
    '"age":{"type":"integer","minimum":18}},"required":["name"]}');
  Good := Parse('{"name":"Anna","age":40}');
  Bad := Parse('{"age":12}');
  try
    R := ValidateSystemJson(Good, Schema);
    CheckTrue('Valid instance', R.IsValid, R.ToString);
    R := ValidateSystemJson(Bad, Schema);
    CheckTrue('Invalid instance is rejected', not R.IsValid, R.ToString);
    Check('Two errors', 2, R.ErrorCount);
    CheckContains('Error path points to age', '/age', R.ToString);
  finally
    Bad.Free;
    Good.Free;
    Schema.Free;
  end;
end;

procedure Step3_ReusedValidator;
var
  Schema, Address, Good, Bad: System.JSON.TJSONValue;
  Validator: TJsonSchemaValidator;
  R: TJsonSchemaValidationResult;
begin
  Section('3. One validator, registered schema, many instances');
  Schema := Parse('{"type":"object","properties":{"home":{"$ref":"https://example.org/address.json"}}}');
  Address := Parse('{"type":"object","required":["city"]}');
  Validator := nil;
  try
    Validator := CreateSchemaValidator(Schema);
    RegisterSystemJsonSchema(Validator, 'https://example.org/address.json', Address);
  finally
    Address.Free;
    Schema.Free;
  end;
  try
    Good := Parse('{"home":{"city":"Exampletown"}}');
    Bad := Parse('{"home":{"zip":"12345"}}');
    try
      R := ValidateSystemJson(Validator, Good);
      CheckTrue('Valid after the source schemas were freed', R.IsValid, R.ToString);
      R := ValidateSystemJson(Validator, Bad);
      CheckTrue('Registered schema is applied', not R.IsValid, R.ToString);
      CheckContains('Error path points into home', '/home', R.ToString);
    finally
      Bad.Free;
      Good.Free;
    end;
  finally
    Validator.Free;
  end;
end;

procedure Step4_Arguments;
var
  Schema: System.JSON.TJSONValue;
begin
  Section('4. nil arguments');
  Schema := Parse('{"type":"string"}');
  try
    CheckError('nil instance', procedure begin ValidateSystemJson(System.JSON.TJSONValue(nil), Schema); end);
    CheckError('nil schema', procedure begin CreateSchemaValidator(nil).Free; end);
    CheckError('nil validator', procedure begin ValidateSystemJson(TJsonSchemaValidator(nil), Schema); end);
  finally
    Schema.Free;
  end;
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    Title('NATIVEJSON - SYSTEM.JSON INTEROP');
    Step1_Conversion;
    Step2_OneShotValidation;
    Step3_ReusedValidator;
    Step4_Arguments;
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
