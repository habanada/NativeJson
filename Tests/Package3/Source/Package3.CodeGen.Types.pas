{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Package3.CodeGen.Types;

interface

{$I NativeJson.inc}

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('codegen.types')]
  TCodeGenTypesTests = class
  public
    [Test] procedure StringProperty;
    [Test] procedure BooleanProperty;
    [Test] procedure UnboundedIntegerUsesInt64;
    [Test] procedure BoundedIntegerUsesInteger;
    [Test] procedure PreferInt32CanBeDisabled;
    [Test] procedure Int32FormatUsesInteger;
    [Test] procedure Int64FormatUsesInt64;
    [Test] procedure UInt32FormatUsesCardinal;
    [Test] procedure UInt64FormatUsesUInt64;
    [Test] procedure NumberUsesDouble;
    [Test] procedure FloatFormatUsesSingle;
    [Test] procedure DecimalCanPreferCurrency;
    [Test] procedure DateTimeFormatUsesTDateTime;
    [Test] procedure DateFormatUsesTDate;
    [Test] procedure TimeFormatUsesTTime;
    [Test] procedure UuidFormatUsesTGuid;
    [Test] procedure DurationFormatUsesTTimeSpan;
    [Test] procedure ByteFormatUsesTBytes;
    [Test] procedure StringsOnlyDisablesNativeFormats;
    [Test] procedure RequiredEmitsAttribute;
    [Test] procedure StringConstraintsEmitAttributes;
    [Test] procedure InclusiveRangeEmitsAttribute;
    [Test] procedure ExclusiveRangeEmitsAttribute;
    [Test] procedure MultipleOfEmitsAttribute;
    [Test] procedure ReadWriteDeprecatedEmitAttributes;
  end;

implementation

uses
  NativeJson.CodeGen.Options,
  Package3.CodeGen.Helpers;

const
  ObjectPrefix = '{"type":"object","additionalProperties":false,"properties":{';
  ObjectSuffix = '}}';

procedure TCodeGenTypesTests.StringProperty;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"string"}' + ObjectSuffix), 'FValue: string;');
end;

procedure TCodeGenTypesTests.BooleanProperty;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"boolean"}' + ObjectSuffix), 'FValue: Boolean;');
end;

procedure TCodeGenTypesTests.UnboundedIntegerUsesInt64;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"integer"}' + ObjectSuffix), 'FValue: Int64;');
end;

procedure TCodeGenTypesTests.BoundedIntegerUsesInteger;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"integer","minimum":-10,"maximum":10}' + ObjectSuffix), 'FValue: Integer;');
end;

procedure TCodeGenTypesTests.PreferInt32CanBeDisabled;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetPreferInt32WhenSafe(False);
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"integer","minimum":-10,"maximum":10}' + ObjectSuffix, Options), 'FValue: Int64;');
end;

procedure TCodeGenTypesTests.Int32FormatUsesInteger;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"integer","format":"int32"}' + ObjectSuffix), 'FValue: Integer;');
end;

procedure TCodeGenTypesTests.Int64FormatUsesInt64;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"integer","format":"int64"}' + ObjectSuffix), 'FValue: Int64;');
end;

procedure TCodeGenTypesTests.UInt32FormatUsesCardinal;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"integer","format":"uint32"}' + ObjectSuffix), 'FValue: Cardinal;');
end;

procedure TCodeGenTypesTests.UInt64FormatUsesUInt64;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"integer","format":"uint64"}' + ObjectSuffix), 'FValue: UInt64;');
end;

procedure TCodeGenTypesTests.NumberUsesDouble;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"number"}' + ObjectSuffix), 'FValue: Double;');
end;

procedure TCodeGenTypesTests.FloatFormatUsesSingle;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"number","format":"float"}' + ObjectSuffix), 'FValue: Single;');
end;

procedure TCodeGenTypesTests.DecimalCanPreferCurrency;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetPreferCurrencyForDecimal(True);
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"number","format":"decimal"}' + ObjectSuffix, Options), 'FValue: Currency;');
end;

procedure TCodeGenTypesTests.DateTimeFormatUsesTDateTime;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"string","format":"date-time"}' + ObjectSuffix), 'FValue: TDateTime;');
end;

procedure TCodeGenTypesTests.DateFormatUsesTDate;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"string","format":"date"}' + ObjectSuffix), 'FValue: TDate;');
end;

procedure TCodeGenTypesTests.TimeFormatUsesTTime;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"string","format":"time"}' + ObjectSuffix), 'FValue: TTime;');
end;

procedure TCodeGenTypesTests.UuidFormatUsesTGuid;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"string","format":"uuid"}' + ObjectSuffix), 'FValue: TGUID;');
end;

procedure TCodeGenTypesTests.DurationFormatUsesTTimeSpan;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"string","format":"duration"}' + ObjectSuffix), 'FValue: TTimeSpan;');
end;

procedure TCodeGenTypesTests.ByteFormatUsesTBytes;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"string","format":"byte"}' + ObjectSuffix), 'FValue: TBytes;');
end;

procedure TCodeGenTypesTests.StringsOnlyDisablesNativeFormats;
var
  Options: TJsonCodeGenOptions;
begin
  Options := TJsonCodeGenOptions.Default.SetFormatKind(TJsonCodeGenFormatKind.StringsOnly);
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"string","format":"uuid"}' + ObjectSuffix, Options), 'FValue: string;');
end;

procedure TCodeGenTypesTests.RequiredEmitsAttribute;
begin
  AssertContains(TypesOf('{"type":"object","additionalProperties":false,"required":["value"],"properties":{"value":{"type":"string"}}}'), '[JsonRequired]');
end;

procedure TCodeGenTypesTests.StringConstraintsEmitAttributes;
var
  Code: string;
begin
  Code := TypesOf(ObjectPrefix + '"value":{"type":"string","minLength":2,"maxLength":8,"pattern":"^[A-Z]+$"}' + ObjectSuffix);
  AssertContains(Code, '[JsonMinLength(2)]');
  AssertContains(Code, '[JsonMaxLength(8)]');
  AssertContains(Code, '[JsonPattern(''^[A-Z]+$'')]');
end;

procedure TCodeGenTypesTests.InclusiveRangeEmitsAttribute;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"number","minimum":1.25,"maximum":9.75}' + ObjectSuffix), '[JsonRange(''1.25'', ''9.75'')]');
end;

procedure TCodeGenTypesTests.ExclusiveRangeEmitsAttribute;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"number","exclusiveMinimum":1.25,"exclusiveMaximum":9.75}' + ObjectSuffix), '[JsonExclusiveRange(''1.25'', ''9.75'')]');
end;

procedure TCodeGenTypesTests.MultipleOfEmitsAttribute;
begin
  AssertContains(TypesOf(ObjectPrefix + '"value":{"type":"number","multipleOf":0.01}' + ObjectSuffix), '[JsonMultipleOf(''0.01'')]');
end;

procedure TCodeGenTypesTests.ReadWriteDeprecatedEmitAttributes;
var
  Code: string;
begin
  Code := TypesOf(ObjectPrefix + '"a":{"type":"string","readOnly":true},"b":{"type":"string","writeOnly":true},"c":{"type":"string","deprecated":true}' + ObjectSuffix);
  AssertContains(Code, '[JsonReadOnly]');
  AssertContains(Code, '[JsonWriteOnly]');
  AssertContains(Code, '[JsonDeprecated]');
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeGenTypesTests);

end.
