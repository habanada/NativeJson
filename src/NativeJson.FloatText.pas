{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.FloatText;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils;
  {$ELSE}
  System.SysUtils;
  {$ENDIF}

function JsonTryParseDouble(const Text: string; out Value: Double): Boolean;
function JsonDoubleToText(Value: Double): string;
function JsonParseDecimal(const Text: string; out Negative: Boolean; out Digits: string; out Point: Integer): Boolean;
function JsonDoubleMatchesDecimal(Value: Double; const Digits: string; Point: Integer): Boolean;

implementation

type
  TDecimalDigits = record
    Digits: string;
    Point: Integer;
  end;

  TLimbs = array of Cardinal;

const
  PowersOfTen: array[0..22] of Double = (
    1E0, 1E1, 1E2, 1E3, 1E4, 1E5, 1E6, 1E7, 1E8, 1E9, 1E10, 1E11,
    1E12, 1E13, 1E14, 1E15, 1E16, 1E17, 1E18, 1E19, 1E20, 1E21, 1E22);
  LimbBase = 1000000000;
  HiddenBit: UInt64 = UInt64(1) shl 52;

function DoubleBits(const Value: Double): UInt64;
begin
  Move(Value, Result, SizeOf(Result));
end;

function BitsToDouble(const Bits: UInt64): Double;
begin
  Move(Bits, Result, SizeOf(Result));
end;

procedure SplitDouble(const Value: Double; out Mantissa: UInt64; out Exponent2, ExponentField: Integer);
var
  Bits: UInt64;
begin
  Bits := DoubleBits(Value);
  ExponentField := Integer((Bits shr 52) and $7FF);
  Mantissa := Bits and (HiddenBit - 1);
  if ExponentField = 0 then Exponent2 := -1074
  else
  begin
    Mantissa := Mantissa or HiddenBit;
    Exponent2 := ExponentField - 1075;
  end;
end;

procedure MultiplyLimbs(var Limbs: TLimbs; Factor: Cardinal);
var
  I: Integer;
  Carry, Product: UInt64;
begin
  Carry := 0;
  for I := 0 to High(Limbs) do
  begin
    Product := UInt64(Limbs[I]) * Factor + Carry;
    Limbs[I] := Cardinal(Product mod LimbBase);
    Carry := Product div LimbBase;
  end;
  while Carry > 0 do
  begin
    SetLength(Limbs, Length(Limbs) + 1);
    Limbs[High(Limbs)] := Cardinal(Carry mod LimbBase);
    Carry := Carry div LimbBase;
  end;
end;

function LimbsToString(const Limbs: TLimbs): string;
var
  I: Integer;
  Part: string;
begin
  Result := IntToStr(Limbs[High(Limbs)]);
  for I := High(Limbs) - 1 downto 0 do
  begin
    Part := IntToStr(Limbs[I]);
    Result := Result + StringOfChar('0', 9 - Length(Part)) + Part;
  end;
end;

function TrimTrailingZeros(const Value: string): string;
var
  N: Integer;
begin
  N := Length(Value);
  while (N > 0) and (Value[N] = '0') do Dec(N);
  Result := Copy(Value, 1, N);
end;

function ExactDecimal(Mantissa: UInt64; Exponent2: Integer): TDecimalDigits;
var
  Limbs: TLimbs;
  Text: string;
  Remaining, Step, I: Integer;
  Power: Cardinal;
begin
  Result.Digits := '';
  Result.Point := 0;
  if Mantissa = 0 then Exit;
  SetLength(Limbs, 3);
  Limbs[0] := Cardinal(Mantissa mod LimbBase);
  Mantissa := Mantissa div LimbBase;
  Limbs[1] := Cardinal(Mantissa mod LimbBase);
  Limbs[2] := Cardinal(Mantissa div LimbBase);
  while (Length(Limbs) > 1) and (Limbs[High(Limbs)] = 0) do SetLength(Limbs, Length(Limbs) - 1);
  if Exponent2 >= 0 then
  begin
    Remaining := Exponent2;
    while Remaining > 0 do
    begin
      Step := Remaining;
      if Step > 29 then Step := 29;
      MultiplyLimbs(Limbs, Cardinal(1) shl Step);
      Dec(Remaining, Step);
    end;
    Text := LimbsToString(Limbs);
    Result.Point := Length(Text);
  end
  else
  begin
    Remaining := -Exponent2;
    while Remaining > 0 do
    begin
      Step := Remaining;
      if Step > 13 then Step := 13;
      Power := 1;
      for I := 1 to Step do Power := Power * 5;
      MultiplyLimbs(Limbs, Power);
      Dec(Remaining, Step);
    end;
    Text := LimbsToString(Limbs);
    Result.Point := Length(Text) + Exponent2;
  end;
  Result.Digits := TrimTrailingZeros(Text);
end;

function CompareDecimal(const A, B: TDecimalDigits): Integer;
begin
  if (A.Digits = '') or (B.Digits = '') then
  begin
    if A.Digits = B.Digits then Exit(0);
    if A.Digits = '' then Exit(-1);
    Exit(1);
  end;
  if A.Point <> B.Point then
  begin
    if A.Point < B.Point then Exit(-1);
    Exit(1);
  end;
  Result := CompareStr(A.Digits, B.Digits);
  if Result < 0 then Result := -1 else if Result > 0 then Result := 1;
end;

function ParseDecimalText(const Text: string; out Negative: Boolean; out Decimal: TDecimalDigits): Boolean;
var
  I, N, ExponentValue, ExponentSign, Lead, IntegerDigits: Integer;
  All: string;
  SawDigit, SawExponentDigit: Boolean;
begin
  Result := False;
  Negative := False;
  Decimal.Digits := '';
  Decimal.Point := 0;
  N := Length(Text);
  I := 1;
  if (I <= N) and (Text[I] = '-') then
  begin
    Negative := True;
    Inc(I);
  end;
  All := '';
  IntegerDigits := 0;
  SawDigit := False;
  while (I <= N) and (Text[I] >= '0') and (Text[I] <= '9') do
  begin
    All := All + Text[I];
    Inc(IntegerDigits);
    SawDigit := True;
    Inc(I);
  end;
  if not SawDigit then Exit;
  if (I <= N) and (Text[I] = '.') then
  begin
    Inc(I);
    SawDigit := False;
    while (I <= N) and (Text[I] >= '0') and (Text[I] <= '9') do
    begin
      All := All + Text[I];
      SawDigit := True;
      Inc(I);
    end;
    if not SawDigit then Exit;
  end;
  ExponentValue := 0;
  if (I <= N) and ((Text[I] = 'e') or (Text[I] = 'E')) then
  begin
    Inc(I);
    ExponentSign := 1;
    if (I <= N) and ((Text[I] = '+') or (Text[I] = '-')) then
    begin
      if Text[I] = '-' then ExponentSign := -1;
      Inc(I);
    end;
    SawExponentDigit := False;
    while (I <= N) and (Text[I] >= '0') and (Text[I] <= '9') do
    begin
      if ExponentValue < 100000 then ExponentValue := ExponentValue * 10 + Ord(Text[I]) - Ord('0');
      SawExponentDigit := True;
      Inc(I);
    end;
    if not SawExponentDigit then Exit;
    ExponentValue := ExponentValue * ExponentSign;
  end;
  if I <= N then Exit;
  Lead := 0;
  while (Lead < Length(All)) and (All[Lead + 1] = '0') do Inc(Lead);
  Decimal.Digits := TrimTrailingZeros(Copy(All, Lead + 1, MaxInt));
  if Decimal.Digits <> '' then Decimal.Point := IntegerDigits - Lead + ExponentValue;
  Result := True;
end;

function JsonParseDecimal(const Text: string; out Negative: Boolean; out Digits: string; out Point: Integer): Boolean;
var
  Decimal: TDecimalDigits;
begin
  Result := ParseDecimalText(Text, Negative, Decimal);
  Digits := Decimal.Digits;
  Point := Decimal.Point;
end;

function RefineDouble(Seed: Double; const Target: TDecimalDigits): Double;
var
  Mantissa: UInt64;
  Exponent2, ExponentField, Attempt: Integer;
  Bits: UInt64;
  UpMid, DownMid: TDecimalDigits;
  C: Integer;
begin
  Result := Seed;
  for Attempt := 1 to 4 do
  begin
    SplitDouble(Result, Mantissa, Exponent2, ExponentField);
    if (ExponentField < 2) or (ExponentField > 2044) then Exit;
    Bits := DoubleBits(Result);
    UpMid := ExactDecimal(Mantissa * 2 + 1, Exponent2 - 1);
    C := CompareDecimal(Target, UpMid);
    if (C > 0) or ((C = 0) and ((Mantissa and 1) = 1)) then
    begin
      Result := BitsToDouble(Bits + 1);
      Continue;
    end;
    if Mantissa = HiddenBit then DownMid := ExactDecimal(Mantissa * 4 - 1, Exponent2 - 2)
    else DownMid := ExactDecimal(Mantissa * 2 - 1, Exponent2 - 1);
    C := CompareDecimal(Target, DownMid);
    if (C < 0) or ((C = 0) and ((Mantissa and 1) = 1)) then
    begin
      Result := BitsToDouble(Bits - 1);
      Continue;
    end;
    Exit;
  end;
end;

function FastPathAllowed(const Target: TDecimalDigits; out Value: Double): Boolean;
{$IF DEFINED(CPUX86) OR DEFINED(CPUI386)}
begin
  Value := 0;
  Result := False;
end;
{$ELSE}
var
  Scale: Integer;
  Whole: Int64;
begin
  Value := 0;
  Result := False;
  if Length(Target.Digits) > 15 then Exit;
  Scale := Target.Point - Length(Target.Digits);
  if (Scale < -22) or (Scale > 22) then Exit;
  Whole := StrToInt64(Target.Digits);
  if Scale >= 0 then Value := Whole * PowersOfTen[Scale]
  else Value := Whole / PowersOfTen[-Scale];
  Result := True;
end;
{$IFEND}

function JsonTryParseDouble(const Text: string; out Value: Double): Boolean;
var
  Negative: Boolean;
  Target: TDecimalDigits;
  Seed: Double;
  Whole: Int64;
begin
  if not ParseDecimalText(Text, Negative, Target) then
    Exit(TryStrToFloat(Text, Value, TFormatSettings.Invariant));
  if Target.Digits = '' then
  begin
    if Negative then Value := BitsToDouble(UInt64(1) shl 63) else Value := 0;
    Exit(True);
  end;
  if (Target.Point > 308) or (Target.Point < -306) then
    Exit(TryStrToFloat(Text, Value, TFormatSettings.Invariant));
  if (Target.Point >= Length(Target.Digits)) and (Target.Point <= 15) then
  begin
    Whole := StrToInt64(Target.Digits + StringOfChar('0', Target.Point - Length(Target.Digits)));
    Seed := Whole;
  end
  else if FastPathAllowed(Target, Seed) then
  begin
  end
  else
  begin
    if not TryStrToFloat(Text, Seed, TFormatSettings.Invariant) then Exit(False);
    if Seed < 0 then Seed := -Seed;
    Seed := RefineDouble(Seed, Target);
  end;
  if Negative then Seed := -Seed;
  Value := Seed;
  Result := True;
end;

function RoundDigits(const Source: TDecimalDigits; Precision: Integer): TDecimalDigits;
var
  Head: string;
  I: Integer;
  RoundUp: Boolean;
begin
  Result := Source;
  if Length(Source.Digits) <= Precision then Exit;
  Head := Copy(Source.Digits, 1, Precision);
  if Source.Digits[Precision + 1] > '5' then RoundUp := True
  else if Source.Digits[Precision + 1] < '5' then RoundUp := False
  else if Length(Source.Digits) > Precision + 1 then RoundUp := True
  else RoundUp := Odd(Ord(Head[Precision]) - Ord('0'));
  if RoundUp then
  begin
    I := Precision;
    while (I >= 1) and (Head[I] = '9') do
    begin
      Head[I] := '0';
      Dec(I);
    end;
    if I >= 1 then Head[I] := Chr(Ord(Head[I]) + 1)
    else
    begin
      Head := '1' + Head;
      Result.Point := Result.Point + 1;
    end;
  end;
  Result.Digits := TrimTrailingZeros(Head);
end;

function FormatDigits(const Source: TDecimalDigits; Negative: Boolean; Precision: Integer): string;
var
  Digits, ExponentText: string;
  Exponent: Integer;
begin
  Digits := Source.Digits;
  if (Source.Point > Precision) or (Source.Point < -3) then
  begin
    Result := Digits[1];
    if Length(Digits) > 1 then Result := Result + '.' + Copy(Digits, 2, MaxInt);
    Exponent := Source.Point - 1;
    ExponentText := IntToStr(Abs(Exponent));
    {$IFNDEF FPC}
    if Length(ExponentText) < 2 then ExponentText := '0' + ExponentText;
    {$ENDIF}
    if Exponent < 0 then Result := Result + 'E-' + ExponentText
    {$IFDEF FPC}
    else Result := Result + 'E' + ExponentText;
    {$ELSE}
    else Result := Result + 'E+' + ExponentText;
    {$ENDIF}
  end
  else if Source.Point <= 0 then Result := '0.' + StringOfChar('0', -Source.Point) + Digits
  else if Length(Digits) <= Source.Point then Result := Digits + StringOfChar('0', Source.Point - Length(Digits))
  else Result := Copy(Digits, 1, Source.Point) + '.' + Copy(Digits, Source.Point + 1, MaxInt);
  if Negative then Result := '-' + Result;
end;

function JsonDoubleMatchesDecimal(Value: Double; const Digits: string; Point: Integer): Boolean;
var
  Mantissa: UInt64;
  Exponent2, ExponentField: Integer;
  Exact, Rounded, Head: TDecimalDigits;
  Count, I: Integer;
  Carried: string;
begin
  Result := False;
  if Digits = '' then Exit(Value = 0);
  if Value = 0 then Exit;
  SplitDouble(Abs(Value), Mantissa, Exponent2, ExponentField);
  if ExponentField = $7FF then Exit;
  Exact := ExactDecimal(Mantissa, Exponent2);
  Count := Length(Digits);
  if Length(Exact.Digits) <= Count then
    Exit((Exact.Digits = Digits) and (Exact.Point = Point));
  Rounded := RoundDigits(Exact, Count);
  if (Rounded.Digits = Digits) and (Rounded.Point = Point) then Exit(True);
  if (Length(Exact.Digits) = Count + 1) and (Exact.Digits[Count + 1] = '5') then
  begin
    Head.Digits := Copy(Exact.Digits, 1, Count);
    Head.Point := Exact.Point;
    Carried := Head.Digits;
    I := Count;
    while (I >= 1) and (Carried[I] = '9') do
    begin
      Carried[I] := '0';
      Dec(I);
    end;
    if I >= 1 then Carried[I] := Chr(Ord(Carried[I]) + 1)
    else
    begin
      Carried := '1' + Carried;
      Inc(Head.Point);
    end;
    Result := (TrimTrailingZeros(Carried) = Digits) and (Head.Point = Point);
  end;
end;

function IncrementLast(const Source: TDecimalDigits): TDecimalDigits;
var
  Carried: string;
  I: Integer;
begin
  Carried := Source.Digits;
  Result.Point := Source.Point;
  I := Length(Carried);
  while (I >= 1) and (Carried[I] = '9') do
  begin
    Carried[I] := '0';
    Dec(I);
  end;
  if I >= 1 then Carried[I] := Chr(Ord(Carried[I]) + 1)
  else
  begin
    Carried := '1' + Carried;
    Inc(Result.Point);
  end;
  Result.Digits := TrimTrailingZeros(Carried);
end;

function TryShortest(Value: Double; const Exact: TDecimalDigits; Count: Integer; out Found: TDecimalDigits): Boolean;
var
  Nearest, Down, Up: TDecimalDigits;
  Candidate: Double;

  function Reads(const Digits: TDecimalDigits): Boolean;
  begin
    Result := JsonTryParseDouble(FormatDigits(Digits, False, 17), Candidate) and (Candidate = Value);
  end;

begin
  Nearest := RoundDigits(Exact, Count);
  if Reads(Nearest) then
  begin
    Found := Nearest;
    Exit(True);
  end;
  Down.Digits := TrimTrailingZeros(Copy(Exact.Digits, 1, Count));
  Down.Point := Exact.Point;
  Up := IncrementLast(Down);
  Result := False;
  if (Down.Digits <> Nearest.Digits) or (Down.Point <> Nearest.Point) then
  begin
    if Reads(Down) then
    begin
      Found := Down;
      Exit(True);
    end;
  end;
  if (Up.Digits <> Nearest.Digits) or (Up.Point <> Nearest.Point) then
  begin
    if Reads(Up) then
    begin
      Found := Up;
      Exit(True);
    end;
  end;
end;

function JsonDoubleToText(Value: Double): string;
var
  Mantissa: UInt64;
  Exponent2, ExponentField, Count: Integer;
  Exact, Rounded: TDecimalDigits;
  Negative, Ignored: Boolean;
  Candidate: Double;
  Quick: string;
begin
  Negative := (DoubleBits(Value) shr 63) <> 0;
  if Value = 0 then
  begin
    if Negative then Exit('-0');
    Exit('0');
  end;
  if Abs(Value) < 2.2250738585072014E-308 then
  begin
    SplitDouble(Abs(Value), Mantissa, Exponent2, ExponentField);
    Exact := ExactDecimal(Mantissa, Exponent2);
    for Count := 1 to 17 do
      if TryShortest(Abs(Value), Exact, Count, Rounded) then
        Exit(FormatDigits(Rounded, Negative, 17));
  end;
  Quick := FloatToStrF(Abs(Value), ffGeneral, 15, 0, TFormatSettings.Invariant);
  if ParseDecimalText(Quick, Ignored, Rounded) and JsonTryParseDouble(Quick, Candidate) and (Candidate = Abs(Value)) then
    Exit(FormatDigits(Rounded, Negative, 15));
  SplitDouble(Abs(Value), Mantissa, Exponent2, ExponentField);
  Exact := ExactDecimal(Mantissa, Exponent2);
  for Count := 15 to 16 do
    if TryShortest(Abs(Value), Exact, Count, Rounded) then
    begin
      if Count = 15 then Exit(FormatDigits(Rounded, Negative, 15));
      Exit(FormatDigits(Rounded, Negative, 17));
    end;
  Rounded := RoundDigits(Exact, 17);
  Result := FormatDigits(Rounded, Negative, 17);
end;

end.
