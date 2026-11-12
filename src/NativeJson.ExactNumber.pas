{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.ExactNumber;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils;
  {$ELSE}
  System.SysUtils;
  {$ENDIF}

type
  TJsonExactNumber = record
  private
    FSign: Integer;
    FDigits: string;
    FPower10: Int64;
    FValid: Boolean;
    class function CompareDigits(const A, B: string): Integer; static;
    class function SubtractDigits(const A, B: string): string; static;
    class function ModDigits(const A, B: string): string; static;
    class function DivSmall(const A: string; Divisor: Integer; out Remainder: Integer): string; static;
    class function FactorOut(var A: string; Divisor: Integer): Integer; static;
  public
    class function TryParse(const Text: string; out Value: TJsonExactNumber): Boolean; static;
    function Compare(const Other: TJsonExactNumber): Integer;
    function CompareToInt64(Value: Int64): Integer;
    function Equals(const Other: TJsonExactNumber): Boolean;
    function IsInteger: Boolean;
    function IsNegative: Boolean;
    function IsPositive: Boolean;
    function IsZero: Boolean;
    function IsMultipleOf(const Divisor: TJsonExactNumber): Boolean;
    function ToCanonical: string;
    property Valid: Boolean read FValid;
  end;

implementation

class function TJsonExactNumber.CompareDigits(const A, B: string): Integer;
begin
  if Length(A) < Length(B) then Exit(-1);
  if Length(A) > Length(B) then Exit(1);
  Result := CompareStr(A, B);
  if Result < 0 then Result := -1 else if Result > 0 then Result := 1;
end;

class function TJsonExactNumber.SubtractDigits(const A, B: string): string;
var
  I, J, Borrow, D: Integer;
begin
  Result := A;
  J := Length(B);
  Borrow := 0;
  for I := Length(A) downto 1 do
  begin
    D := Ord(Result[I]) - Ord('0') - Borrow;
    if J > 0 then
    begin
      Dec(D, Ord(B[J]) - Ord('0'));
      Dec(J);
    end;
    if D < 0 then
    begin
      Inc(D, 10);
      Borrow := 1;
    end
    else Borrow := 0;
    Result[I] := Char(Ord('0') + D);
  end;
  I := 1;
  while (I < Length(Result)) and (Result[I] = '0') do Inc(I);
  if I > 1 then Delete(Result, 1, I - 1);
end;

class function TJsonExactNumber.ModDigits(const A, B: string): string;
var
  I: Integer;
begin
  if B = '1' then Exit('0');
  Result := '0';
  for I := 1 to Length(A) do
  begin
    if Result = '0' then Result := A[I] else Result := Result + A[I];
    while (Length(Result) > 1) and (Result[1] = '0') do Delete(Result, 1, 1);
    while CompareDigits(Result, B) >= 0 do Result := SubtractDigits(Result, B);
  end;
end;

class function TJsonExactNumber.DivSmall(const A: string; Divisor: Integer; out Remainder: Integer): string;
var
  I, N, Q: Integer;
  Started: Boolean;
begin
  Result := '';
  Remainder := 0;
  Started := False;
  for I := 1 to Length(A) do
  begin
    N := Remainder * 10 + Ord(A[I]) - Ord('0');
    Q := N div Divisor;
    Remainder := N mod Divisor;
    if (Q <> 0) or Started then
    begin
      Result := Result + Char(Ord('0') + Q);
      Started := True;
    end;
  end;
  if Result = '' then Result := '0';
end;

class function TJsonExactNumber.FactorOut(var A: string; Divisor: Integer): Integer;
var
  Remainder: Integer;
  Q: string;
begin
  Result := 0;
  while A <> '0' do
  begin
    Q := DivSmall(A, Divisor, Remainder);
    if Remainder <> 0 then Exit;
    A := Q;
    Inc(Result);
  end;
end;

class function TJsonExactNumber.TryParse(const Text: string; out Value: TJsonExactNumber): Boolean;
var
  S, IntPart, FracPart, ExpPart, Digits: string;
  P, I: Integer;
  Negative, ExpNegative: Boolean;
  ExpValue, Digit: Int64;
begin
  Value := Default(TJsonExactNumber);
  S := Trim(Text);
  if S = '' then Exit(False);
  P := 1;
  Negative := False;
  if S[P] = '-' then
  begin
    Negative := True;
    Inc(P);
    if P > Length(S) then Exit(False);
  end;

  IntPart := '';
  while (P <= Length(S)) and CharInSet(S[P], ['0'..'9']) do
  begin
    IntPart := IntPart + S[P];
    Inc(P);
  end;
  if IntPart = '' then Exit(False);
  if (Length(IntPart) > 1) and (IntPart[1] = '0') then Exit(False);

  FracPart := '';
  if (P <= Length(S)) and (S[P] = '.') then
  begin
    Inc(P);
    while (P <= Length(S)) and CharInSet(S[P], ['0'..'9']) do
    begin
      FracPart := FracPart + S[P];
      Inc(P);
    end;
    if FracPart = '' then Exit(False);
  end;

  ExpValue := 0;
  if (P <= Length(S)) and CharInSet(S[P], ['e', 'E']) then
  begin
    Inc(P);
    if P > Length(S) then Exit(False);
    ExpNegative := False;
    if CharInSet(S[P], ['+', '-']) then
    begin
      ExpNegative := S[P] = '-';
      Inc(P);
    end;
    if (P > Length(S)) or not CharInSet(S[P], ['0'..'9']) then Exit(False);
    ExpPart := Copy(S, P, MaxInt);
    for I := 1 to Length(ExpPart) do
    begin
      if not CharInSet(ExpPart[I], ['0'..'9']) then Exit(False);
      Digit := Ord(ExpPart[I]) - Ord('0');
      if ExpValue > (High(Int64) - Digit) div 10 then Exit(False);
      ExpValue := ExpValue * 10 + Digit;
    end;
    if ExpNegative then ExpValue := -ExpValue;
    P := Length(S) + 1;
  end;
  if P <= Length(S) then Exit(False);

  Digits := IntPart + FracPart;
  I := 1;
  while (I <= Length(Digits)) and (Digits[I] = '0') do Inc(I);
  if I > Length(Digits) then
  begin
    Value.FSign := 0;
    Value.FDigits := '0';
    Value.FPower10 := 0;
    Value.FValid := True;
    Exit(True);
  end;
  if I > 1 then Delete(Digits, 1, I - 1);

  if ExpValue < Low(Int64) + Length(FracPart) then Exit(False);
  Value.FPower10 := ExpValue - Length(FracPart);
  while (Length(Digits) > 1) and (Digits[Length(Digits)] = '0') do
  begin
    Delete(Digits, Length(Digits), 1);
    if Value.FPower10 = High(Int64) then Exit(False);
    Inc(Value.FPower10);
  end;

  if Negative then Value.FSign := -1 else Value.FSign := 1;
  Value.FDigits := Digits;
  Value.FValid := True;
  Result := True;
end;

function TJsonExactNumber.Compare(const Other: TJsonExactNumber): Integer;
var
  MagA, MagB, OverflowA, OverflowB: Int64;
  C: Integer;
begin
  if not FValid or not Other.FValid then raise EConvertError.Create('Invalid exact JSON number');
  if FSign < Other.FSign then Exit(-1);
  if FSign > Other.FSign then Exit(1);
  if FSign = 0 then Exit(0);
  if FPower10 > High(Int64) - Length(FDigits) then
  begin
    OverflowA := FPower10 - (High(Int64) - Length(FDigits));
    MagA := High(Int64);
  end
  else
  begin
    OverflowA := 0;
    MagA := FPower10 + Length(FDigits);
  end;
  if Other.FPower10 > High(Int64) - Length(Other.FDigits) then
  begin
    OverflowB := Other.FPower10 - (High(Int64) - Length(Other.FDigits));
    MagB := High(Int64);
  end
  else
  begin
    OverflowB := 0;
    MagB := Other.FPower10 + Length(Other.FDigits);
  end;
  if OverflowA < OverflowB then C := -1 else if OverflowA > OverflowB then C := 1
  else if MagA < MagB then C := -1 else if MagA > MagB then C := 1 else
  begin
    if Length(FDigits) = Length(Other.FDigits) then C := CompareDigits(FDigits, Other.FDigits)
    else if Length(FDigits) < Length(Other.FDigits) then C := CompareDigits(FDigits + StringOfChar('0', Length(Other.FDigits) - Length(FDigits)), Other.FDigits)
    else C := CompareDigits(FDigits, Other.FDigits + StringOfChar('0', Length(FDigits) - Length(Other.FDigits)));
  end;
  if FSign < 0 then Result := -C else Result := C;
end;

function TJsonExactNumber.CompareToInt64(Value: Int64): Integer;
var
  Other: TJsonExactNumber;
begin
  if not TryParse(IntToStr(Value), Other) then raise EConvertError.Create('Cannot convert Int64 to exact JSON number');
  Result := Compare(Other);
end;

function TJsonExactNumber.Equals(const Other: TJsonExactNumber): Boolean;
begin
  Result := FValid and Other.FValid and (FSign = Other.FSign) and (FDigits = Other.FDigits) and (FPower10 = Other.FPower10);
end;

function TJsonExactNumber.IsInteger: Boolean;
begin
  Result := FValid and ((FSign = 0) or (FPower10 >= 0));
end;

function TJsonExactNumber.IsNegative: Boolean;
begin
  Result := FValid and (FSign < 0);
end;

function TJsonExactNumber.IsPositive: Boolean;
begin
  Result := FValid and (FSign > 0);
end;

function TJsonExactNumber.IsZero: Boolean;
begin
  Result := FValid and (FSign = 0);
end;

function TJsonExactNumber.IsMultipleOf(const Divisor: TJsonExactNumber): Boolean;
var
  OddPart, Temp: string;
  ExpDiff: Int64;
  Need2, Need5, Have: Integer;
begin
  if not FValid or not Divisor.FValid or Divisor.IsZero then Exit(False);
  if IsZero then Exit(True);
  if FPower10 < Divisor.FPower10 then Exit(False);
  if (Divisor.FPower10 < 0) and (FPower10 > High(Int64) + Divisor.FPower10) then ExpDiff := High(Int64) else ExpDiff := FPower10 - Divisor.FPower10;
  OddPart := Divisor.FDigits;
  Need2 := FactorOut(OddPart, 2);
  Need5 := FactorOut(OddPart, 5);
  if ExpDiff < Need2 then
  begin
    Temp := FDigits;
    Have := FactorOut(Temp, 2);
    if Int64(Have) + ExpDiff < Need2 then Exit(False);
  end;
  if ExpDiff < Need5 then
  begin
    Temp := FDigits;
    Have := FactorOut(Temp, 5);
    if Int64(Have) + ExpDiff < Need5 then Exit(False);
  end;
  Result := (OddPart = '1') or (ModDigits(FDigits, OddPart) = '0');
end;

function TJsonExactNumber.ToCanonical: string;
var
  P: Integer;
begin
  if not FValid then Exit('');
  if FSign = 0 then Exit('0');
  if FPower10 = 0 then Result := FDigits
  else if (FPower10 > 0) and (FPower10 <= 64) then Result := FDigits + StringOfChar('0', Integer(FPower10))
  else if (FPower10 < 0) and (FPower10 > -Int64(Length(FDigits))) then
  begin
    P := Length(FDigits) + Integer(FPower10);
    Result := Copy(FDigits, 1, P) + '.' + Copy(FDigits, P + 1, MaxInt);
  end
  else Result := FDigits + 'e' + IntToStr(FPower10);
  if FSign < 0 then Result := '-' + Result;
end;

end.
