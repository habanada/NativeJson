{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Test2_NumberFormats;

{$I NativeJson.inc}

// TEST PACKAGE 2 - Number formats
//
//   Probes the number types systematically at their limits instead of
//   only by sampling.
//
//   Two axes:
//     1. Notation in the JSON: exponent, sign, leading zeros
//     2. Limits per target type: below, bottom, zero, top, above

{$APPTYPE CONSOLE}

uses
  SysUtils,
  NativeJson.Compat,
  Rtti,
  Demo.Assert in '..\..\examples\Demos\Demo.Assert.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Serializer.Writer;

type
  TValueSet = class
  private
    FShortInt: ShortInt;
    FByte: Byte;
    FSmallInt: SmallInt;
    FWord: Word;
    FInteger: Integer;
    FCardinal: Cardinal;
    FInt64: Int64;
    FUInt64: UInt64;
    FSingle: Single;
    FDouble: Double;
    FCurrencyCode: Currency;
  public
    property ShortIntValue: ShortInt read FShortInt write FShortInt;
    property ByteValue: Byte read FByte write FByte;
    property SmallIntValue: SmallInt read FSmallInt write FSmallInt;
    property WordValue: Word read FWord write FWord;
    property IntValue: Integer read FInteger write FInteger;
    property CardinalValue: Cardinal read FCardinal write FCardinal;
    property Int64Value: Int64 read FInt64 write FInt64;
    property UInt64Value: UInt64 read FUInt64 write FUInt64;
    property SingleValue: Single read FSingle write FSingle;
    property DoubleValue: Double read FDouble write FDouble;
    property CurrencyValue: Currency read FCurrencyCode write FCurrencyCode;
  end;

// Reads a single field and reports either the value as text
// or the word EXCEPTION. That way acceptance and rejection fit into
// the same check.
function ReadField(const Fld, Json: string; Fetch: TFunc<TValueSet, string>): string;
var
  W: TValueSet;
begin
  try
    W := JsonConvert.DeserializeObject<TValueSet>('{"' + Fld + '":' + Json + '}');
    try
      Result := Fetch(W);
    finally
      W.Free;
    end;
  except
    Result := 'EXCEPTION';
  end;
end;

function WholeValue(const Fld, Json: string): string;
begin
  Result := ReadField(Fld, Json,
    function(W: TValueSet): string
    begin
      if Fld = 'ShortIntValue' then Result := IntToStr(W.ShortIntValue)
      else if Fld = 'ByteValue' then Result := IntToStr(W.ByteValue)
      else if Fld = 'SmallIntValue' then Result := IntToStr(W.SmallIntValue)
      else if Fld = 'WordValue' then Result := IntToStr(W.WordValue)
      else if Fld = 'IntValue' then Result := IntToStr(W.IntValue)
      else if Fld = 'CardinalValue' then Result := UIntToStr(W.CardinalValue)
      else if Fld = 'Int64Value' then Result := IntToStr(W.Int64Value)
      else if Fld = 'UInt64Value' then Result := UIntToStr(W.UInt64Value)
      else Result := '?';
    end);
end;

procedure CheckLimits(const Fld, Below, Bottom, Top, Above: string);
begin
  Check(Fld + ' below is rejected', 'EXCEPTION', WholeValue(Fld, Below));
  Check(Fld + ' smallest value', Bottom, WholeValue(Fld, Bottom));
  Check(Fld + ' zero', '0', WholeValue(Fld, '0'));
  Check(Fld + ' largest value', Top, WholeValue(Fld, Top));
  Check(Fld + ' above is rejected', 'EXCEPTION', WholeValue(Fld, Above));
end;

// ---------------------------------------------------------------------------

procedure Step1_LimitsPerType;
begin
  Section('1. Every integer type at its four corners');
  CheckLimits('ShortIntValue', '-129', '-128', '127', '128');
  CheckLimits('ByteValue', '-1', '0', '255', '256');
  CheckLimits('SmallIntValue', '-32769', '-32768', '32767', '32768');
  CheckLimits('WordValue', '-1', '0', '65535', '65536');
  CheckLimits('IntValue', '-2147483649', '-2147483648', '2147483647', '2147483648');
  CheckLimits('CardinalValue', '-1', '0', '4294967295', '4294967296');
  CheckLimits('Int64Value', '-9223372036854775809', '-9223372036854775808',
    '9223372036854775807', '9223372036854775808');
  Check('UInt64Value below is rejected', 'EXCEPTION', WholeValue('UInt64Value', '-1'));
  Check('UInt64Value zero', '0', WholeValue('UInt64Value', '0'));
  Check('UInt64Value largest value', '18446744073709551615',
    WholeValue('UInt64Value', '18446744073709551615'));
  Check('UInt64Value above is rejected', 'EXCEPTION',
    WholeValue('UInt64Value', '18446744073709551616'));
end;

procedure Step2_Exponents;
begin
  Section('2. Exponential notation is valid JSON');
  Writeln('       1e2 means 100. Whoever only asks TryStrToInt64 rejects it.');
  Check('Lower case e', '100', WholeValue('IntValue', '1e2'));
  Check('Upper case E', '100', WholeValue('IntValue', '1E2'));
  Check('With plus', '100', WholeValue('IntValue', '1e+2'));
  // 1e-2 is 0.01 and therefore NOT a whole number. Silently truncating to 0
  // would be the worse answer - the same line as for 1.5.
  Check('Negative exponent is not a whole number', 'EXCEPTION', WholeValue('IntValue', '1e-2'));
  Check('Exponent with a whole result', '10', WholeValue('IntValue', '1e+1'));
  Check('100e-2 is a whole number', '1', WholeValue('IntValue', '100e-2'));

  // The route via Double answered these cases silently wrong:
  // 9007199254740993 is the first whole number that a Double can no longer
  // tell apart from its neighbor.
  Check('Beyond Double precision', '9007199254740993',
    WholeValue('Int64Value', '9007199254740993.0'));
  Check('The same with exponent', '9007199254740993',
    WholeValue('Int64Value', '9007199254740993e0'));
  Check('Real fraction is rejected', 'EXCEPTION',
    WholeValue('Int64Value', '9007199254740992.5'));
  Check('Tiny fraction is rejected', 'EXCEPTION',
    WholeValue('IntValue', '1.00000000000000001'));
  Check('9.21e18 still fits into Int64', '9210000000000000000',
    WholeValue('Int64Value', '9.21e18'));
  Check('1e19 fits into UInt64', '10000000000000000000',
    WholeValue('UInt64Value', '1e19'));
  Check('Sign and exponent', '-100', WholeValue('IntValue', '-1e2'));
  Check('Exponent breaks the range', 'EXCEPTION', WholeValue('IntValue', '1e20'));

  // According to the specification 1.0 is a whole number.
  Check('1.0 is a whole number', '1', WholeValue('IntValue', '1.0'));
  Check('1.5 is not', 'EXCEPTION', WholeValue('IntValue', '1.5'));
end;

procedure Step3_InvalidNotations;
begin
  Section('3. What the tokenizer has to reject');
  Check('Leading zero', 'EXCEPTION', WholeValue('IntValue', '007'));
  Check('Leading plus', 'EXCEPTION', WholeValue('IntValue', '+7'));
  Check('Dot without a digit', 'EXCEPTION', WholeValue('IntValue', '7.'));
  Check('Only a minus', 'EXCEPTION', WholeValue('IntValue', '-'));
  Check('Exponent without a digit', 'EXCEPTION', WholeValue('IntValue', '1e'));
  Check('Hexadecimal', 'EXCEPTION', WholeValue('IntValue', '0x1F'));
  Writeln('       Zero with a fraction is allowed, on the other hand.');
  Check('0.0 is valid', '0', WholeValue('IntValue', '0.0'));
end;

procedure Step4_FloatRoundTrip;
var
  W, K: TValueSet;
  Json: string;
  A, B: Double;
begin
  Section('4. Floating point there and back');
  W := TValueSet.Create;
  try
    A := 0.1;
    B := 0.2;
    W.SingleValue := 0.1;
    W.DoubleValue := A + B;
    W.CurrencyValue := 1234.5678;
    Json := JsonConvert.SerializeObject(W);
    Show('JSON', Json);

    CheckContains('Single short', '"SingleValue":0.1', Json);
    CheckContains('Double complete', '"DoubleValue":0.30000000000000004', Json);
    CheckContains('Currency exact', '"CurrencyValue":1234.5678', Json);

    K := JsonConvert.DeserializeObject<TValueSet>(Json);
    try
      CheckTrue('Single bit-exact', K.SingleValue = W.SingleValue, FloatToStr(K.SingleValue));
      CheckTrue('Double bit-exact', K.DoubleValue = W.DoubleValue, FloatToStr(K.DoubleValue));
      CheckTrue('Currency bit-exact', K.CurrencyValue = W.CurrencyValue, CurrToStr(K.CurrencyValue));
    finally
      K.Free;
    end;
  finally
    W.Free;
  end;
end;

procedure Step5_FloatLimits;
begin
  Section('5. Floating point outside the target range');
  Check('Single too large', 'EXCEPTION',
    ReadField('SingleValue', '1e40', function(W: TValueSet): string begin Result := 'ok'; end));
  Check('Double copes with 1e40', 'ok',
    ReadField('DoubleValue', '1e40', function(W: TValueSet): string begin Result := 'ok'; end));
  Check('Double too large', 'EXCEPTION',
    ReadField('DoubleValue', '1e400', function(W: TValueSet): string begin Result := 'ok'; end));
  Check('Currency too large', 'EXCEPTION',
    ReadField('CurrencyValue', '1e30', function(W: TValueSet): string begin Result := 'ok'; end));
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('TEST PACKAGE 2 - NUMBER FORMATS AND LIMITS');

    Step1_LimitsPerType;
    Step2_Exponents;
    Step3_InvalidNotations;
    Step4_FloatRoundTrip;
    Step5_FloatLimits;

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
