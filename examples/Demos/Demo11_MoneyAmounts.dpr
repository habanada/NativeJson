{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo11_MoneyAmounts;

{$I NativeJson.inc}

// DEMO 11 - Exact money amounts
//
//   In Delphi Currency is not a floating point type but an Int64 scaled
//   by 10000. That is exactly why it exists: money must not round.
//
//   A detour through Extended would depend on the platform: on Win64 it is
//   a Double with about 15 significant digits, on Win32 it is 80 bits wide.
//   NativeJson reads and writes Currency from its text instead. This demo
//   walks through the limits.

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Math,
  Rtti,
  Demo.Assert in 'Demo.Assert.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Dom.Value,
  NativeJson.Dom.Primitive,
  NativeJson.Serializer.Writer;

type
  TInvoice = class
  private
    FNumber: string;
    FNet: Currency;
    FTax: Currency;
    FGross: Currency;
    FRate: Double;
  public
    property Number: string read FNumber write FNumber;
    property Net: Currency read FNet write FNet;
    property Tax: Currency read FTax write FTax;
    property Gross: Currency read FGross write FGross;
    property Rate: Double read FRate write FRate;
  end;

function AmountFromRaw(Raw: Int64): Currency;
begin
  // Large Currency values can NOT be written as a literal.
  // The compiler evaluates floating point literals as Extended and only
  // then converts to Currency - on Win64 Extended is just a Double, and
  // that does not have 17 significant digits. The smallest value
  // -922337203685477.5808 even fails on Win32 with E2099, because
  // Delphi reads the minus as negation of a POSITIVE literal, and
  // +922337203685477.5808 is already outside the value range.
  //
  // Currency is an Int64 scaled by 10000. Via the raw bits
  // every value is exact and without compiler floating point.
  Result := PCurrency(@Raw)^;
end;

procedure CheckAmount(const Name: string; const Val: Currency; const Expected: string);
var
  Invoice, Back: TInvoice;
  Json: string;
begin
  Invoice := TInvoice.Create;
  try
    Invoice.Net := Val;
    Json := JsonConvert.SerializeObject(Invoice);
    CheckContains(Name + ' written', '"Net":' + Expected, Json);

    Back := JsonConvert.DeserializeObject<TInvoice>(Json);
    try
      CheckTrue(Name + ' read back', Back.Net = Val,
        CurrToStr(Back.Net));
    finally
      Back.Free;
    end;
  finally
    Invoice.Free;
  end;
end;

// ---------------------------------------------------------------------------

procedure Step1_EverydayAmounts;
begin
  Section('1. Amounts that occur every day');
  CheckAmount('Zero', 0, '0');
  CheckAmount('Whole euro', 42, '42');
  CheckAmount('With cents', 1234.56, '1234.56');
  CheckAmount('Four decimal places', 1234.5678, '1234.5678');
  CheckAmount('Negative', -19.99, '-19.99');
  CheckAmount('Smallest amount', 0.0001, '0.0001');
  CheckAmount('Small negative', -0.0001, '-0.0001');
  Writeln('       Trailing decimal zeros are cut off - 42.5000 becomes 42.5,');
  Writeln('       so existing output does not change.');
end;

procedure Step2_WhereDoubleFails;
begin
  Section('2. Where a Double loses digits');
  // From 16 significant digits on a Double can no longer tell every
  // Currency apart. The expected values are exact.
  CheckAmount('12 digits plus 4', AmountFromRaw(1234567890123456), '123456789012.3456');
  CheckAmount('13 digits plus 4', AmountFromRaw(12345678901234567), '1234567890123.4567');
  Writeln('       Via Double these became 123456789012.346 and');
  Writeln('       1234567890123.46 - and something else again on Win32.');
end;

procedure Step3_BoundaryValues;
var
  Invoice, Back: TInvoice;
  Json: string;
  Max, Min: Currency;
begin
  Section('3. The limits of the type');
  // Both limits MUST come via the raw bits - as a literal
  // the compiler reports E2099, see the comment at AmountFromRaw.
  Max := AmountFromRaw(High(Int64));
  Min := AmountFromRaw(Low(Int64));

  // First check separately whether the RTL reads these texts exactly at all.
  // Otherwise, for a red round trip, you do not know whether our converter
  // or StrToCurr lost the digits.
  CheckTrue('StrToCurr reads the maximum',
    StrToCurr('922337203685477.5807', TFormatSettings.Invariant) = Max,
    CurrToStr(StrToCurr('922337203685477.5807', TFormatSettings.Invariant)));
  CheckTrue('StrToCurr reads the minimum',
    StrToCurr('-922337203685477.5808', TFormatSettings.Invariant) = Min,
    CurrToStr(StrToCurr('-922337203685477.5808', TFormatSettings.Invariant)));

  Invoice := TInvoice.Create;
  try
    Invoice.Net := Max;
    Invoice.Tax := Min;
    Json := JsonConvert.SerializeObject(Invoice);
    Show('JSON', Json);
    CheckContains('Largest amount', '"Net":922337203685477.5807', Json);
    CheckContains('Smallest amount', '"Tax":-922337203685477.5808', Json);

    Back := JsonConvert.DeserializeObject<TInvoice>(Json);
    try
      CheckTrue('Maximum back', Back.Net = Max, CurrToStr(Back.Net));
      CheckTrue('Minimum back', Back.Tax = Min, CurrToStr(Back.Tax));
    finally
      Back.Free;
    end;
  finally
    Invoice.Free;
  end;
end;

procedure Step4_TotalStaysConsistent;
var
  Invoice, Back: TInvoice;
  Json: string;
begin
  Section('4. Net plus tax must equal gross - also afterwards');
  Invoice := TInvoice.Create;
  try
    Invoice.Number := 'RE-2026-0815';
    Invoice.Net := 8493.27;
    Invoice.Tax := 1613.72;
    Invoice.Gross := Invoice.Net + Invoice.Tax;
    Invoice.Rate := 1.0873;

    Json := JsonConvert.SerializeObject(Invoice);
    Show('Invoice', Json);

    Back := JsonConvert.DeserializeObject<TInvoice>(Json);
    try
      CheckTrue('Total still matches',
        Back.Net + Back.Tax = Back.Gross,
        CurrToStr(Back.Net + Back.Tax) + ' vs ' + CurrToStr(Back.Gross));
      CheckTrue('Gross unchanged', Back.Gross = Invoice.Gross, CurrToStr(Back.Gross));
      // The rate is deliberately a Double and stays one.
      CheckTrue('Rate stays floating point',
        SameValue(Back.Rate, 1.0873, 0.0000001), FloatToStr(Back.Rate));
    finally
      Back.Free;
    end;
  finally
    Invoice.Free;
  end;
end;

procedure Step5_ForeignFormats;
var
  Invoice: TInvoice;
begin
  Section('5. What comes in from foreign systems');

  // Many partners send amounts as strings so that no JavaScript
  // parser turns them into a Double on the way.
  Invoice := JsonConvert.DeserializeObject<TInvoice>('{"Net":"1234.5678"}');
  try
    CheckTrue('Amount as string', Invoice.Net = 1234.5678, CurrToStr(Invoice.Net));
  finally
    Invoice.Free;
  end;

  Invoice := JsonConvert.DeserializeObject<TInvoice>('{"Net":100}');
  try
    CheckTrue('Whole number without a dot', Invoice.Net = 100, CurrToStr(Invoice.Net));
  finally
    Invoice.Free;
  end;

  // Currency cannot hold more than four decimal places - that is
  // a property of the type, not of the library. What matters is that it
  // does not blow up and rounds commercially.
  Invoice := JsonConvert.DeserializeObject<TInvoice>('{"Net":1.00005}');
  try
    Show('1.00005 becomes', CurrToStr(Invoice.Net));
    CheckTrue('Fifth digit is rounded, not rejected',
      (Invoice.Net >= 1.0) and (Invoice.Net <= 1.0001), CurrToStr(Invoice.Net));
  finally
    Invoice.Free;
  end;
end;

procedure Step6_DomKeepsTheText;
var
  Dom: TJsonValue;
begin
  Section('6. The DOM route stays exact too');
  Dom := JsonConvert.DeserializeObject('{"amount":1234567890123.4567}');
  try
    CheckTrue('AsCurrency is exact',
      Dom.Values['amount'].AsCurrency = AmountFromRaw(12345678901234567),
      CurrToStr(Dom.Values['amount'].AsCurrency));
    // AsDouble may well be inexact - that is what a Double is.
    Show('AsDouble for comparison', FloatToStr(Dom.Values['amount'].AsDouble));
  finally
    Dom.Free;
  end;

  Dom := JsonConvert.DeserializeObject('{"amount":"99.95"}');
  try
    CheckTrue('String in the DOM',
      Dom.Values['amount'].AsCurrency = 99.95,
      CurrToStr(Dom.Values['amount'].AsCurrency));
  finally
    Dom.Free;
  end;
end;

procedure Step7_PlatformEquality;
var
  Invoice: TInvoice;
  Json: string;
begin
  Section('7. The same output on Win32 and Win64');
  Invoice := TInvoice.Create;
  try
    Invoice.Net := AmountFromRaw(12345678901234567);
    Json := JsonConvert.SerializeObject(Invoice);
{$IFDEF WIN64}
    Show('Platform', 'Win64');
{$ELSE}
    Show('Platform', 'Win32');
{$ENDIF}
    Show('Output', Json);
    CheckContains('Output is platform independent', '1234567890123.4567', Json);
    Writeln('       This line must read the same on both platforms.');
    Writeln('       Previously it did not, because Extended has different widths.');
  finally
    Invoice.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 11 - EXACT MONEY AMOUNTS');

    Step1_EverydayAmounts;
    Step2_WhereDoubleFails;
    Step3_BoundaryValues;
    Step4_TotalStaysConsistent;
    Step5_ForeignFormats;
    Step6_DomKeepsTheText;
    Step7_PlatformEquality;

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
