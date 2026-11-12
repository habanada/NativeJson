{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Cbor;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE}
  System.SysUtils,
  {$ENDIF}
  NativeJson.Dom.Value;

type
  EJsonCborError = class(Exception);

  TJsonCborBytesMode = (cbmBase64Url, cbmBase64, cbmHex, cbmWrapped);
  TJsonCborKeyMode = (ckmStringify, ckmText, ckmInteger);
  TJsonCborKeyOrder = (ckoBytewise, ckoLengthFirst);
  TJsonCborDuplicateKeys = (cdkError, cdkFirstWins, cdkLastWins);
  TJsonCborNonFinite = (cnfError, cnfNull, cnfText);
  TJsonCborTagMode = (ctmDrop, ctmWrap);

  TJsonCborOptions = class
  private
    FBytesMode: TJsonCborBytesMode;
    FBytesKey: string;
    FKeyMode: TJsonCborKeyMode;
    FDuplicateKeys: TJsonCborDuplicateKeys;
    FNonFinite: TJsonCborNonFinite;
    FTagMode: TJsonCborTagMode;
    FTagKey: string;
    FValueKey: string;
    FUndefinedAsNull: Boolean;
    FMaxDepth: Integer;
    FDeterministic: Boolean;
    FKeyOrder: TJsonCborKeyOrder;
    FPreferredFloats: Boolean;
    FExactDecimals: Boolean;
    FShortestSinglePrecision: Boolean;
  public
    constructor Create;
    property BytesMode: TJsonCborBytesMode read FBytesMode write FBytesMode;
    property BytesKey: string read FBytesKey write FBytesKey;
    property KeyMode: TJsonCborKeyMode read FKeyMode write FKeyMode;
    property DuplicateKeys: TJsonCborDuplicateKeys read FDuplicateKeys write FDuplicateKeys;
    property NonFinite: TJsonCborNonFinite read FNonFinite write FNonFinite;
    property TagMode: TJsonCborTagMode read FTagMode write FTagMode;
    property TagKey: string read FTagKey write FTagKey;
    property ValueKey: string read FValueKey write FValueKey;
    property UndefinedAsNull: Boolean read FUndefinedAsNull write FUndefinedAsNull;
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
    property Deterministic: Boolean read FDeterministic write FDeterministic;
    property KeyOrder: TJsonCborKeyOrder read FKeyOrder write FKeyOrder;
    property PreferredFloats: Boolean read FPreferredFloats write FPreferredFloats;
    property ExactDecimals: Boolean read FExactDecimals write FExactDecimals;
    property ShortestSinglePrecision: Boolean read FShortestSinglePrecision write FShortestSinglePrecision;
  end;

function CborToDom(const Data: TBytes; Options: TJsonCborOptions = nil): TJsonValue;
function CborToDomAt(const Data: TBytes; var Position: Integer; Options: TJsonCborOptions = nil): TJsonValue;
function CborToJson(const Data: TBytes; Options: TJsonCborOptions = nil): string;
function DomToCbor(Value: TJsonValue; Options: TJsonCborOptions = nil): TBytes;
function JsonToCbor(const Json: string; Options: TJsonCborOptions = nil): TBytes;
function CborToHex(const Data: TBytes): string;
function CborFromHex(const Hex: string): TBytes;

implementation

uses
  {$IFDEF FPC}
  Generics.Collections,
  {$ELSE}
  System.Generics.Collections,
  {$ENDIF}
  NativeJson.Dom.Primitive,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.Io,
  NativeJson.FloatText,
  NativeJson.Serializer.Writer;

const
  Base64StandardAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  Base64UrlAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  HexAlphabet = '0123456789abcdef';
  LimbBase = 1000000000;
  MaxDecimalExponent = 100000;
  MaxFormattedExponent = 400;
  Major_Unsigned = 0;
  Major_Negative = 1;
  Major_Bytes = 2;
  Major_Text = 3;
  Major_Array = 4;
  Major_Map = 5;
  Major_Tag = 6;
  Major_Simple = 7;
  BreakByte = $FF;
  MaxSingleMagnitude = 3.4028234663852886E38;

type
  TLimbs = array of Cardinal;

constructor TJsonCborOptions.Create;
begin
  inherited Create;
  FBytesMode := cbmBase64Url;
  FBytesKey := '@bytes';
  FKeyMode := ckmStringify;
  FDuplicateKeys := cdkError;
  FNonFinite := cnfError;
  FTagMode := ctmDrop;
  FTagKey := '@tag';
  FValueKey := '@value';
  FUndefinedAsNull := True;
  FMaxDepth := 256;
  FDeterministic := False;
  FKeyOrder := ckoBytewise;
  FPreferredFloats := True;
  FExactDecimals := True;
  FShortestSinglePrecision := False;
end;

function CborToHex(const Data: TBytes): string;
var
  I: Integer;
begin
  SetLength(Result, Length(Data) * 2);
  for I := 0 to High(Data) do
  begin
    Result[I * 2 + 1] := HexAlphabet[(Data[I] shr 4) + 1];
    Result[I * 2 + 2] := HexAlphabet[(Data[I] and 15) + 1];
  end;
end;

function HexDigit(C: Char): Integer;
begin
  if (C >= '0') and (C <= '9') then Result := Ord(C) - Ord('0')
  else if (C >= 'a') and (C <= 'f') then Result := Ord(C) - Ord('a') + 10
  else if (C >= 'A') and (C <= 'F') then Result := Ord(C) - Ord('A') + 10
  else Result := -1;
end;

function CborFromHex(const Hex: string): TBytes;
var
  I, Count, High4, Low4: Integer;
  Clean: string;
begin
  Clean := '';
  for I := 1 to Length(Hex) do
    if (Hex[I] <> ' ') and (Hex[I] <> #9) and (Hex[I] <> #13) and (Hex[I] <> #10) then Clean := Clean + Hex[I];
  if Odd(Length(Clean)) then raise EJsonCborError.Create('Hex text has an odd number of digits');
  Count := Length(Clean) div 2;
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
  begin
    High4 := HexDigit(Clean[I * 2 + 1]);
    Low4 := HexDigit(Clean[I * 2 + 2]);
    if (High4 < 0) or (Low4 < 0) then raise EJsonCborError.CreateFmt('Invalid hex digit near position %d', [I * 2 + 1]);
    Result[I] := Byte(High4 * 16 + Low4);
  end;
end;

function EncodeBase64(const Data: TBytes; Url: Boolean): string;
var
  Alphabet: string;
  I, Count, Chunk, Left: Integer;
begin
  if Url then Alphabet := Base64UrlAlphabet else Alphabet := Base64StandardAlphabet;
  Result := '';
  Count := Length(Data);
  I := 0;
  while I + 2 < Count do
  begin
    Chunk := (Integer(Data[I]) shl 16) or (Integer(Data[I + 1]) shl 8) or Data[I + 2];
    Result := Result + Alphabet[(Chunk shr 18) + 1] + Alphabet[((Chunk shr 12) and 63) + 1] +
      Alphabet[((Chunk shr 6) and 63) + 1] + Alphabet[(Chunk and 63) + 1];
    Inc(I, 3);
  end;
  Left := Count - I;
  if Left = 1 then
  begin
    Chunk := Integer(Data[I]) shl 16;
    Result := Result + Alphabet[(Chunk shr 18) + 1] + Alphabet[((Chunk shr 12) and 63) + 1];
    if not Url then Result := Result + '==';
  end
  else if Left = 2 then
  begin
    Chunk := (Integer(Data[I]) shl 16) or (Integer(Data[I + 1]) shl 8);
    Result := Result + Alphabet[(Chunk shr 18) + 1] + Alphabet[((Chunk shr 12) and 63) + 1] + Alphabet[((Chunk shr 6) and 63) + 1];
    if not Url then Result := Result + '=';
  end;
end;

function Base64Value(C: Char): Integer;
begin
  if (C >= 'A') and (C <= 'Z') then Result := Ord(C) - Ord('A')
  else if (C >= 'a') and (C <= 'z') then Result := Ord(C) - Ord('a') + 26
  else if (C >= '0') and (C <= '9') then Result := Ord(C) - Ord('0') + 52
  else if (C = '+') or (C = '-') then Result := 62
  else if (C = '/') or (C = '_') then Result := 63
  else Result := -1;
end;

function TryDecodeBase64(const Text: string; out Data: TBytes): Boolean;
var
  I, Bits, Count, V: Integer;
  Buffer: Cardinal;
  Clean: string;
begin
  Result := False;
  Data := nil;
  Clean := Text;
  while (Clean <> '') and (Clean[Length(Clean)] = '=') do SetLength(Clean, Length(Clean) - 1);
  if Length(Clean) mod 4 = 1 then Exit;
  SetLength(Data, (Length(Clean) * 6) div 8);
  Buffer := 0;
  Bits := 0;
  Count := 0;
  for I := 1 to Length(Clean) do
  begin
    V := Base64Value(Clean[I]);
    if V < 0 then Exit;
    Buffer := (Buffer shl 6) or Cardinal(V);
    Inc(Bits, 6);
    if Bits >= 8 then
    begin
      Dec(Bits, 8);
      Data[Count] := Byte((Buffer shr Bits) and $FF);
      Inc(Count);
    end;
  end;
  SetLength(Data, Count);
  Result := True;
end;

function Utf8Encode(const Text: string): TBytes;
var
  I, N, Count: Integer;
  Code: Cardinal;
  C: Word;
begin
  N := Length(Text);
  SetLength(Result, N * 3);
  Count := 0;
  I := 1;
  while I <= N do
  begin
    C := Ord(Text[I]);
    Code := C;
    if (C >= $D800) and (C <= $DBFF) then
    begin
      if (I < N) and (Ord(Text[I + 1]) >= $DC00) and (Ord(Text[I + 1]) <= $DFFF) then
      begin
        Code := $10000 + ((Cardinal(C) - $D800) shl 10) + (Cardinal(Ord(Text[I + 1])) - $DC00);
        Inc(I);
      end
      else raise EJsonCborError.Create('Text contains an unpaired surrogate and cannot be encoded as UTF-8');
    end
    else if (C >= $DC00) and (C <= $DFFF) then
      raise EJsonCborError.Create('Text contains an unpaired surrogate and cannot be encoded as UTF-8');
    if Code < $80 then
    begin
      Result[Count] := Byte(Code);
      Inc(Count);
    end
    else if Code < $800 then
    begin
      Result[Count] := Byte($C0 or (Code shr 6));
      Result[Count + 1] := Byte($80 or (Code and $3F));
      Inc(Count, 2);
    end
    else if Code < $10000 then
    begin
      Result[Count] := Byte($E0 or (Code shr 12));
      Result[Count + 1] := Byte($80 or ((Code shr 6) and $3F));
      Result[Count + 2] := Byte($80 or (Code and $3F));
      Inc(Count, 3);
    end
    else
    begin
      Result[Count] := Byte($F0 or (Code shr 18));
      Result[Count + 1] := Byte($80 or ((Code shr 12) and $3F));
      Result[Count + 2] := Byte($80 or ((Code shr 6) and $3F));
      Result[Count + 3] := Byte($80 or (Code and $3F));
      Inc(Count, 4);
    end;
    Inc(I);
  end;
  SetLength(Result, Count);
end;

function TryUtf8Decode(const Data: TBytes; Start, Count: Integer; out Text: string): Boolean;
var
  I, Last, Extra, Used: Integer;
  B: Byte;
  Code, MinCode: Cardinal;
begin
  Result := False;
  Text := '';
  SetLength(Text, Count);
  Used := 0;
  I := Start;
  Last := Start + Count;
  while I < Last do
  begin
    B := Data[I];
    Inc(I);
    if B < $80 then
    begin
      Inc(Used);
      Text[Used] := Char(B);
      Continue;
    end;
    if (B >= $C2) and (B <= $DF) then begin Extra := 1; Code := B and $1F; MinCode := $80; end
    else if (B >= $E0) and (B <= $EF) then begin Extra := 2; Code := B and $0F; MinCode := $800; end
    else if (B >= $F0) and (B <= $F4) then begin Extra := 3; Code := B and $07; MinCode := $10000; end
    else Exit;
    if I + Extra > Last then Exit;
    while Extra > 0 do
    begin
      if (Data[I] and $C0) <> $80 then Exit;
      Code := (Code shl 6) or (Data[I] and $3F);
      Inc(I);
      Dec(Extra);
    end;
    if (Code < MinCode) or (Code > $10FFFF) or ((Code >= $D800) and (Code <= $DFFF)) then Exit;
    if Code >= $10000 then
    begin
      Dec(Code, $10000);
      Inc(Used);
      Text[Used] := Char($D800 + (Code shr 10));
      Inc(Used);
      Text[Used] := Char($DC00 + (Code and $3FF));
    end
    else
    begin
      Inc(Used);
      Text[Used] := Char(Code);
    end;
  end;
  SetLength(Text, Used);
  Result := True;
end;

procedure MultiplyLimbs(var Limbs: TLimbs; Factor: Cardinal; Addend: Cardinal);
var
  I: Integer;
  Carry, Product: UInt64;
begin
  Carry := Addend;
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

function LimbsToText(const Limbs: TLimbs): string;
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

function TextToLimbs(const Digits: string): TLimbs;
var
  I, Count, Start: Integer;
begin
  Count := (Length(Digits) + 8) div 9;
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
  begin
    Start := Length(Digits) - (I + 1) * 9 + 1;
    if Start < 1 then Result[I] := Cardinal(StrToInt(Copy(Digits, 1, Start + 8)))
    else Result[I] := Cardinal(StrToInt(Copy(Digits, Start, 9)));
  end;
  while (Length(Result) > 1) and (Result[High(Result)] = 0) do SetLength(Result, Length(Result) - 1);
end;

function BytesToDecimal(const Data: TBytes; Start, Count: Integer): string;
var
  Limbs: TLimbs;
  I: Integer;
begin
  SetLength(Limbs, 1);
  Limbs[0] := 0;
  for I := Start to Start + Count - 1 do MultiplyLimbs(Limbs, 256, Data[I]);
  Result := LimbsToText(Limbs);
end;

function DecimalToBytes(const Digits: string): TBytes;
var
  Limbs: TLimbs;
  Collected: TBytes;
  I, Count: Integer;
  Remainder, Current: UInt64;
  AllZero: Boolean;
begin
  Limbs := TextToLimbs(Digits);
  SetLength(Collected, 0);
  Count := 0;
  repeat
    Remainder := 0;
    AllZero := True;
    for I := High(Limbs) downto 0 do
    begin
      Current := Remainder * LimbBase + Limbs[I];
      Limbs[I] := Cardinal(Current div 256);
      Remainder := Current mod 256;
      if Limbs[I] <> 0 then AllZero := False;
    end;
    SetLength(Collected, Count + 1);
    Collected[Count] := Byte(Remainder);
    Inc(Count);
  until AllZero;
  if (Count = 1) and (Collected[0] = 0) then Exit(nil);
  SetLength(Result, Count);
  for I := 0 to Count - 1 do Result[I] := Collected[Count - 1 - I];
end;

function DecimalAddOne(const Digits: string): string;
var
  I: Integer;
begin
  Result := Digits;
  I := Length(Result);
  while (I >= 1) and (Result[I] = '9') do
  begin
    Result[I] := '0';
    Dec(I);
  end;
  if I >= 1 then Result[I] := Chr(Ord(Result[I]) + 1) else Result := '1' + Result;
end;

function DecimalSubOne(const Digits: string): string;
var
  I: Integer;
begin
  Result := Digits;
  I := Length(Result);
  while (I >= 1) and (Result[I] = '0') do
  begin
    Result[I] := '9';
    Dec(I);
  end;
  if I >= 1 then Result[I] := Chr(Ord(Result[I]) - 1);
  I := 1;
  while (I < Length(Result)) and (Result[I] = '0') do Inc(I);
  Result := Copy(Result, I, MaxInt);
end;

function DecimalMultiplyPower(const Digits: string; Base: Cardinal; Exponent: Integer): string;
var
  Limbs: TLimbs;
  Remaining, Step, I: Integer;
  Factor: Cardinal;
begin
  Limbs := TextToLimbs(Digits);
  Remaining := Exponent;
  while Remaining > 0 do
  begin
    Step := Remaining;
    if Base = 2 then
    begin
      if Step > 29 then Step := 29;
    end
    else if Step > 13 then Step := 13;
    Factor := 1;
    for I := 1 to Step do Factor := Factor * Base;
    MultiplyLimbs(Limbs, Factor, 0);
    Dec(Remaining, Step);
  end;
  Result := LimbsToText(Limbs);
end;

function CompareDigits(const A, B: string): Integer;
begin
  if Length(A) <> Length(B) then
  begin
    if Length(A) < Length(B) then Exit(-1);
    Exit(1);
  end;
  Result := CompareStr(A, B);
  if Result < 0 then Result := -1 else if Result > 0 then Result := 1;
end;

function PlainDecimalText(Negative: Boolean; const Digits: string; Exponent: Int64): string;
var
  Sign: string;
  Scale: Integer;
begin
  if Negative then Sign := '-' else Sign := '';
  if Digits = '0' then Exit('0');
  if (Exponent > MaxFormattedExponent) or (Exponent < -MaxFormattedExponent) then
    Exit(Sign + Digits + 'E' + IntToStr(Exponent));
  Scale := Integer(Exponent);
  if Scale >= 0 then Result := Sign + Digits + StringOfChar('0', Scale)
  else if -Scale < Length(Digits) then
    Result := Sign + Copy(Digits, 1, Length(Digits) + Scale) + '.' + Copy(Digits, Length(Digits) + Scale + 1, MaxInt)
  else
    Result := Sign + '0.' + StringOfChar('0', -Scale - Length(Digits)) + Digits;
end;

function HalfToDouble(Half: Word): Double;
var
  Sign, Exponent, Mantissa, Biased: Integer;
  Bits: UInt64;
begin
  Sign := (Half shr 15) and 1;
  Exponent := (Half shr 10) and $1F;
  Mantissa := Half and $3FF;
  if Exponent = 31 then
  begin
    if Mantissa = 0 then Bits := UInt64($7FF) shl 52
    else Bits := (UInt64($7FF) shl 52) or (UInt64(Mantissa) shl 42);
  end
  else if Exponent = 0 then
  begin
    if Mantissa = 0 then Bits := 0
    else
    begin
      Biased := -14 + 1023;
      while (Mantissa and $400) = 0 do
      begin
        Mantissa := Mantissa shl 1;
        Dec(Biased);
      end;
      Mantissa := Mantissa and $3FF;
      Bits := (UInt64(Biased) shl 52) or (UInt64(Mantissa) shl 42);
    end;
  end
  else
    Bits := (UInt64(Exponent - 15 + 1023) shl 52) or (UInt64(Mantissa) shl 42);
  Bits := Bits or (UInt64(Sign) shl 63);
  Move(Bits, Result, SizeOf(Result));
end;

function TryDoubleToHalf(Value: Double; out Half: Word): Boolean;
var
  Bits: UInt64;
  Sign, Exponent, Mantissa, Shift: Integer;
  Full: UInt64;
begin
  Result := False;
  Move(Value, Bits, SizeOf(Bits));
  Sign := Integer(Bits shr 63);
  Exponent := Integer((Bits shr 52) and $7FF);
  Full := Bits and ((UInt64(1) shl 52) - 1);
  if (Exponent = 0) and (Full = 0) then
  begin
    Half := Word(Sign shl 15);
    Exit(True);
  end;
  if Exponent = 0 then Exit;
  Exponent := Exponent - 1023;
  if (Exponent >= -14) and (Exponent <= 15) then
  begin
    if (Full and ((UInt64(1) shl 42) - 1)) <> 0 then Exit;
    Mantissa := Integer(Full shr 42);
    Half := Word((Sign shl 15) or ((Exponent + 15) shl 10) or Mantissa);
    Exit(True);
  end;
  if (Exponent >= -24) and (Exponent < -14) then
  begin
    Full := Full or (UInt64(1) shl 52);
    Shift := 52 - (Exponent + 24);
    if (Full and ((UInt64(1) shl Shift) - 1)) <> 0 then Exit;
    Mantissa := Integer(Full shr Shift);
    Half := Word((Sign shl 15) or Mantissa);
    Exit(True);
  end;
end;

function IsFiniteDouble(const Value: Double): Boolean;
var
  Bits: UInt64;
begin
  Move(Value, Bits, SizeOf(Bits));
  Result := ((Bits shr 52) and $7FF) <> $7FF;
end;

type
  TCborOutput = class
  private
    FData: TBytes;
    FLen: Integer;
    procedure Reserve(Extra: Integer);
  public
    procedure Put(B: Byte);
    procedure PutBytes(const Source: TBytes);
    procedure PutHead(Major: Byte; Argument: UInt64);
    function ToBytes: TBytes;
  end;

procedure TCborOutput.Reserve(Extra: Integer);
var
  Capacity: Integer;
begin
  Capacity := Length(FData);
  if FLen + Extra <= Capacity then Exit;
  if Capacity < 256 then Capacity := 256;
  while Capacity < FLen + Extra do Capacity := Capacity * 2;
  SetLength(FData, Capacity);
end;

procedure TCborOutput.Put(B: Byte);
begin
  Reserve(1);
  FData[FLen] := B;
  Inc(FLen);
end;

procedure TCborOutput.PutBytes(const Source: TBytes);
begin
  if Length(Source) = 0 then Exit;
  Reserve(Length(Source));
  Move(Source[0], FData[FLen], Length(Source));
  Inc(FLen, Length(Source));
end;

procedure TCborOutput.PutHead(Major: Byte; Argument: UInt64);
var
  Lead: Byte;
  I, Size: Integer;
begin
  Lead := Byte(Major shl 5);
  if Argument < 24 then
  begin
    Put(Lead or Byte(Argument));
    Exit;
  end;
  if Argument <= $FF then begin Put(Lead or 24); Size := 1; end
  else if Argument <= $FFFF then begin Put(Lead or 25); Size := 2; end
  else if Argument <= $FFFFFFFF then begin Put(Lead or 26); Size := 4; end
  else begin Put(Lead or 27); Size := 8; end;
  for I := Size - 1 downto 0 do Put(Byte((Argument shr (I * 8)) and $FF));
end;

function TCborOutput.ToBytes: TBytes;
begin
  SetLength(Result, FLen);
  if FLen > 0 then Move(FData[0], Result[0], FLen);
end;

function CompareEncoded(const A, B: TBytes): Integer;
var
  I, N: Integer;
begin
  N := Length(A);
  if Length(B) < N then N := Length(B);
  for I := 0 to N - 1 do
    if A[I] <> B[I] then
    begin
      if A[I] < B[I] then Exit(-1);
      Exit(1);
    end;
  if Length(A) < Length(B) then Exit(-1);
  if Length(A) > Length(B) then Exit(1);
  Result := 0;
end;

type
  TDomCborWriter = class
  private
    FOptions: TJsonCborOptions;
    FOut: TCborOutput;
    procedure WriteText(const Text: string);
    procedure WriteKey(const Key: string);
    function CompareKeys(const A, B: TBytes): Integer;
    procedure WriteMagnitude(Negative: Boolean; const Magnitude: string);
    procedure WriteBignum(Negative: Boolean; const Magnitude: string);
    procedure WriteSigned(Value: Int64);
    procedure WriteDouble(Value: Double);
    procedure WriteDecimalFraction(Negative: Boolean; const Digits: string; Point: Integer);
    procedure WriteNumber(Node: TJsonValue);
    function TryWriteBytes(Obj: TJsonObject): Boolean;
    function TryWriteTag(Obj: TJsonObject; Level: Integer): Boolean;
    procedure WriteObject(Obj: TJsonObject; Level: Integer);
    procedure WriteSortedObject(Obj: TJsonObject; Level: Integer);
    procedure WriteArray(Arr: TJsonArray; Level: Integer);
  public
    constructor Create(AOptions: TJsonCborOptions; AOutput: TCborOutput);
    procedure Write(Value: TJsonValue; Level: Integer);
  end;

constructor TDomCborWriter.Create(AOptions: TJsonCborOptions; AOutput: TCborOutput);
begin
  inherited Create;
  FOptions := AOptions;
  FOut := AOutput;
end;

procedure TDomCborWriter.WriteText(const Text: string);
var
  Encoded: TBytes;
begin
  Encoded := Utf8Encode(Text);
  FOut.PutHead(Major_Text, Length(Encoded));
  FOut.PutBytes(Encoded);
end;

function IsIntegerKey(const Key: string; out Negative: Boolean; out Magnitude: string): Boolean;
var
  Start, I: Integer;
begin
  Result := False;
  Negative := Key.StartsWith('-');
  Start := 1;
  if Negative then Start := 2;
  Magnitude := Copy(Key, Start, MaxInt);
  if (Magnitude = '') or (Length(Magnitude) > 20) then Exit;
  if (Magnitude[1] = '0') and ((Length(Magnitude) > 1) or Negative) then Exit;
  for I := 1 to Length(Magnitude) do
    if (Magnitude[I] < '0') or (Magnitude[I] > '9') then Exit;
  if Negative then Result := CompareDigits(Magnitude, '18446744073709551616') <= 0
  else Result := CompareDigits(Magnitude, '18446744073709551615') <= 0;
end;

procedure TDomCborWriter.WriteKey(const Key: string);
var
  Negative: Boolean;
  Magnitude: string;
begin
  if (FOptions.KeyMode = ckmInteger) and IsIntegerKey(Key, Negative, Magnitude) then
    WriteMagnitude(Negative, Magnitude)
  else
    WriteText(Key);
end;

function TDomCborWriter.CompareKeys(const A, B: TBytes): Integer;
begin
  if (FOptions.KeyOrder = ckoLengthFirst) and (Length(A) <> Length(B)) then
  begin
    if Length(A) < Length(B) then Exit(-1);
    Exit(1);
  end;
  Result := CompareEncoded(A, B);
end;

procedure TDomCborWriter.WriteBignum(Negative: Boolean; const Magnitude: string);
var
  Bytes: TBytes;
begin
  if Negative then
  begin
    FOut.PutHead(Major_Tag, 3);
    Bytes := DecimalToBytes(DecimalSubOne(Magnitude));
  end
  else
  begin
    FOut.PutHead(Major_Tag, 2);
    Bytes := DecimalToBytes(Magnitude);
  end;
  FOut.PutHead(Major_Bytes, Length(Bytes));
  FOut.PutBytes(Bytes);
end;

procedure TDomCborWriter.WriteMagnitude(Negative: Boolean; const Magnitude: string);
var
  Value: UInt64;
begin
  if Negative then
  begin
    if CompareDigits(Magnitude, '18446744073709551616') > 0 then
    begin
      WriteBignum(True, Magnitude);
      Exit;
    end;
    if Magnitude = '18446744073709551616' then Value := High(UInt64)
    else if TryStrToUInt64(Magnitude, Value) then Value := Value - 1
    else
    begin
      WriteBignum(True, Magnitude);
      Exit;
    end;
    FOut.PutHead(Major_Negative, Value);
  end
  else
  begin
    if (CompareDigits(Magnitude, '18446744073709551615') > 0) or not TryStrToUInt64(Magnitude, Value) then
    begin
      WriteBignum(False, Magnitude);
      Exit;
    end;
    FOut.PutHead(Major_Unsigned, Value);
  end;
end;

procedure TDomCborWriter.WriteSigned(Value: Int64);
begin
  if Value >= 0 then FOut.PutHead(Major_Unsigned, UInt64(Value))
  else FOut.PutHead(Major_Negative, UInt64(-(Value + 1)));
end;

procedure TDomCborWriter.WriteDouble(Value: Double);
var
  Half: Word;
  Single32: Single;
  Bits32: Cardinal;
  Bits64: UInt64;
  I: Integer;
begin
  Move(Value, Bits64, SizeOf(Bits64));
  if not IsFiniteDouble(Value) then
  begin
    FOut.Put($F9);
    if (Bits64 and ((UInt64(1) shl 52) - 1)) <> 0 then
    begin
      FOut.Put($7E);
      FOut.Put($00);
    end
    else if (Bits64 shr 63) = 0 then
    begin
      FOut.Put($7C);
      FOut.Put($00);
    end
    else
    begin
      FOut.Put($FC);
      FOut.Put($00);
    end;
    Exit;
  end;
  if FOptions.PreferredFloats then
  begin
    if TryDoubleToHalf(Value, Half) then
    begin
      FOut.Put($F9);
      FOut.Put(Byte(Half shr 8));
      FOut.Put(Byte(Half and $FF));
      Exit;
    end;
    if Abs(Value) <= MaxSingleMagnitude then
    begin
      Single32 := Value;
      if Double(Single32) = Value then
      begin
        Move(Single32, Bits32, SizeOf(Bits32));
        FOut.Put($FA);
        for I := 3 downto 0 do FOut.Put(Byte((Bits32 shr (I * 8)) and $FF));
        Exit;
      end;
    end;
  end;
  FOut.Put($FB);
  for I := 7 downto 0 do FOut.Put(Byte((Bits64 shr (I * 8)) and $FF));
end;

procedure TDomCborWriter.WriteDecimalFraction(Negative: Boolean; const Digits: string; Point: Integer);
begin
  FOut.PutHead(Major_Tag, 4);
  FOut.PutHead(Major_Array, 2);
  WriteSigned(Int64(Point) - Length(Digits));
  WriteMagnitude(Negative, Digits);
end;

procedure TDomCborWriter.WriteNumber(Node: TJsonValue);
var
  Raw, Digits: string;
  Negative, IsInteger: Boolean;
  Point: Integer;
  Value: Double;
  Bits: UInt64;
begin
  Raw := Node.AsRawText;
  IsInteger := Node.GetJsonType = TJsonType.jtInteger;
  if not JsonParseDecimal(Raw, Negative, Digits, Point) then
    raise EJsonCborError.CreateFmt('The number "%s" cannot be encoded', [Raw]);
  if Digits = '' then
  begin
    if IsInteger then
    begin
      FOut.PutHead(Major_Unsigned, 0);
      Exit;
    end;
    Bits := 0;
    if Negative then Bits := UInt64(1) shl 63;
    Move(Bits, Value, SizeOf(Value));
    WriteDouble(Value);
    Exit;
  end;
  if IsInteger and (Point >= Length(Digits)) then
  begin
    WriteMagnitude(Negative, Digits + StringOfChar('0', Point - Length(Digits)));
    Exit;
  end;
  Value := Node.AsDouble;
  if FOptions.ExactDecimals then
  begin
    if not IsFiniteDouble(Value) or not JsonDoubleMatchesDecimal(Value, Digits, Point) then
    begin
      WriteDecimalFraction(Negative, Digits, Point);
      Exit;
    end;
  end
  else if not IsFiniteDouble(Value) then
    raise EJsonCborError.CreateFmt('The number "%s" is outside the range of a Double', [Raw]);
  WriteDouble(Value);
end;

function TDomCborWriter.TryWriteBytes(Obj: TJsonObject): Boolean;
var
  Item: TJsonValue;
  Bytes: TBytes;
begin
  Result := False;
  if (Obj.Count <> 1) or not Obj.TryGetValue(FOptions.BytesKey, Item) then Exit;
  if Item.GetJsonType <> TJsonType.jtString then Exit;
  if not TryDecodeBase64(Item.AsString, Bytes) then
    raise EJsonCborError.CreateFmt('The value of "%s" is not valid Base64 text', [FOptions.BytesKey]);
  FOut.PutHead(Major_Bytes, Length(Bytes));
  FOut.PutBytes(Bytes);
  Result := True;
end;

function TDomCborWriter.TryWriteTag(Obj: TJsonObject; Level: Integer): Boolean;
var
  TagItem, Content: TJsonValue;
  Tag: UInt64;
begin
  Result := False;
  if FOptions.TagMode <> ctmWrap then Exit;
  if (Obj.Count <> 2) or not Obj.TryGetValue(FOptions.TagKey, TagItem) or not Obj.TryGetValue(FOptions.ValueKey, Content) then Exit;
  if (TagItem.GetJsonType <> TJsonType.jtInteger) or not TryStrToUInt64(TagItem.AsRawText, Tag) then Exit;
  FOut.PutHead(Major_Tag, Tag);
  Write(Content, Level + 1);
  Result := True;
end;

procedure TDomCborWriter.WriteArray(Arr: TJsonArray; Level: Integer);
var
  I: Integer;
begin
  FOut.PutHead(Major_Array, Arr.Count);
  for I := 0 to Arr.Count - 1 do Write(Arr.Items[I], Level + 1);
end;

procedure TDomCborWriter.WriteObject(Obj: TJsonObject; Level: Integer);
var
  Pair: TPair<string, TJsonValue>;
begin
  if TryWriteBytes(Obj) then Exit;
  if TryWriteTag(Obj, Level) then Exit;
  if FOptions.Deterministic then
  begin
    WriteSortedObject(Obj, Level);
    Exit;
  end;
  FOut.PutHead(Major_Map, Obj.Count);
  for Pair in Obj do
  begin
    WriteKey(Pair.Key);
    Write(Pair.Value, Level + 1);
  end;
end;

procedure TDomCborWriter.WriteSortedObject(Obj: TJsonObject; Level: Integer);
var
  Pair: TPair<string, TJsonValue>;
  Keys: array of TBytes;
  Values: array of TJsonValue;
  Order, Scratch: array of Integer;
  Count, I, Width, Left, Mid, Right, A, B, K: Integer;
  Probe: TCborOutput;
  Saved: TCborOutput;
begin
  Count := Obj.Count;
  SetLength(Keys, Count);
  SetLength(Values, Count);
  SetLength(Order, Count);
  SetLength(Scratch, Count);
  I := 0;
  Saved := FOut;
  for Pair in Obj do
  begin
    Probe := TCborOutput.Create;
    try
      FOut := Probe;
      WriteKey(Pair.Key);
      Keys[I] := Probe.ToBytes;
    finally
      FOut := Saved;
      Probe.Free;
    end;
    Values[I] := Pair.Value;
    Order[I] := I;
    Inc(I);
  end;
  Width := 1;
  while Width < Count do
  begin
    Left := 0;
    while Left < Count do
    begin
      Mid := Left + Width;
      if Mid > Count then Mid := Count;
      Right := Left + 2 * Width;
      if Right > Count then Right := Count;
      A := Left;
      B := Mid;
      K := Left;
      while (A < Mid) and (B < Right) do
      begin
        if CompareKeys(Keys[Order[B]], Keys[Order[A]]) < 0 then begin Scratch[K] := Order[B]; Inc(B); end
        else begin Scratch[K] := Order[A]; Inc(A); end;
        Inc(K);
      end;
      while A < Mid do begin Scratch[K] := Order[A]; Inc(A); Inc(K); end;
      while B < Right do begin Scratch[K] := Order[B]; Inc(B); Inc(K); end;
      Left := Right;
    end;
    for I := 0 to Count - 1 do Order[I] := Scratch[I];
    Width := Width * 2;
  end;
  FOut.PutHead(Major_Map, Count);
  for I := 0 to Count - 1 do
  begin
    FOut.PutBytes(Keys[Order[I]]);
    Write(Values[Order[I]], Level + 1);
  end;
end;

procedure TDomCborWriter.Write(Value: TJsonValue; Level: Integer);
begin
  if Level > FOptions.MaxDepth then
    raise EJsonCborError.CreateFmt('Nesting deeper than MaxDepth (%d)', [FOptions.MaxDepth]);
  if Value = nil then
  begin
    FOut.Put($F6);
    Exit;
  end;
  if Value is TJsonBytes then
  begin
    FOut.PutHead(Major_Bytes, Length(TJsonBytes(Value).Bytes));
    FOut.PutBytes(TJsonBytes(Value).Bytes);
    Exit;
  end;
  case Value.GetJsonType of
    TJsonType.jtNull, TJsonType.jtNone: FOut.Put($F6);
    TJsonType.jtBoolean:
      if Value.AsBoolean then FOut.Put($F5) else FOut.Put($F4);
    TJsonType.jtInteger, TJsonType.jtFloat: WriteNumber(Value);
    TJsonType.jtObject: WriteObject(TJsonObject(Value), Level);
    TJsonType.jtArray: WriteArray(TJsonArray(Value), Level);
  else
    WriteText(Value.AsString);
  end;
end;

type
  TCborReader = class
  private
    FData: TBytes;
    FPos: Integer;
    FOptions: TJsonCborOptions;
    procedure Fail(const Text: string);
    function Remaining: Integer;
    function ReadByte: Byte;
    function ReadArgument(Info: Byte; AllowIndefinite: Boolean; out Indefinite: Boolean): UInt64;
    function ReadTextChunk(Size: UInt64): string;
    function ReadByteChunk(Size: UInt64): TBytes;
    function ReadByteString(Info: Byte): TBytes;
    function ReadTextString(Info: Byte): string;
    function EncodeBytesText(const Bytes: TBytes): string;
    function FloatNode(Value: Double; Width: Integer): TJsonValue;
    function ReadFloat(Info: Byte): TJsonValue;
    function ReadArray(Info: Byte; Level: Integer): TJsonValue;
    function ReadMap(Info: Byte; Level: Integer): TJsonValue;
    function ReadKey(Level: Integer): string;
    function ReadTag(Info: Byte; Level: Integer): TJsonValue;
    function ReadBignum(Tag: UInt64): TJsonValue;
    function ReadScaled(Tag: UInt64; Level: Integer): TJsonValue;
    function NumberNode(const Text: string): TJsonValue;
  public
    constructor Create(const AData: TBytes; APosition: Integer; AOptions: TJsonCborOptions);
    function ReadItem(Level: Integer): TJsonValue;
    property Position: Integer read FPos;
  end;

constructor TCborReader.Create(const AData: TBytes; APosition: Integer; AOptions: TJsonCborOptions);
begin
  inherited Create;
  FData := AData;
  FPos := APosition;
  FOptions := AOptions;
end;

procedure TCborReader.Fail(const Text: string);
begin
  raise EJsonCborError.CreateFmt('CBOR: %s at byte %d', [Text, FPos]);
end;

function TCborReader.Remaining: Integer;
begin
  Result := System.Length(FData) - FPos;
end;

function TCborReader.ReadByte: Byte;
begin
  if FPos >= System.Length(FData) then Fail('Unexpected end of data');
  Result := FData[FPos];
  Inc(FPos);
end;

function TCborReader.ReadArgument(Info: Byte; AllowIndefinite: Boolean; out Indefinite: Boolean): UInt64;
var
  Size, I: Integer;
begin
  Indefinite := False;
  if Info < 24 then Exit(Info);
  if Info = 31 then
  begin
    if not AllowIndefinite then Fail('Indefinite length is not allowed here');
    Indefinite := True;
    Exit(0);
  end;
  if Info > 27 then Fail('Reserved additional information ' + IntToStr(Info));
  Size := 1 shl (Info - 24);
  if Remaining < Size then Fail('Unexpected end of data');
  Result := 0;
  for I := 1 to Size do Result := (Result shl 8) or ReadByte;
end;

function TCborReader.ReadByteChunk(Size: UInt64): TBytes;
begin
  if Size > UInt64(Remaining) then Fail('Length exceeds the remaining data');
  SetLength(Result, Integer(Size));
  if Size > 0 then Move(FData[FPos], Result[0], Integer(Size));
  Inc(FPos, Integer(Size));
end;

function TCborReader.ReadTextChunk(Size: UInt64): string;
begin
  if Size > UInt64(Remaining) then Fail('Length exceeds the remaining data');
  if not TryUtf8Decode(FData, FPos, Integer(Size), Result) then Fail('Text string is not valid UTF-8');
  Inc(FPos, Integer(Size));
end;

function TCborReader.ReadByteString(Info: Byte): TBytes;
var
  Indefinite: Boolean;
  Size: UInt64;
  Initial: Byte;
  Chunk: TBytes;
  Used: Integer;
begin
  Size := ReadArgument(Info, True, Indefinite);
  if not Indefinite then Exit(ReadByteChunk(Size));
  Result := nil;
  Used := 0;
  while True do
  begin
    Initial := ReadByte;
    if Initial = BreakByte then Break;
    if (Initial shr 5 <> Major_Bytes) or ((Initial and 31) = 31) then Fail('Invalid chunk in an indefinite-length byte string');
    Chunk := ReadByteChunk(ReadArgument(Initial and 31, False, Indefinite));
    SetLength(Result, Used + System.Length(Chunk));
    if System.Length(Chunk) > 0 then Move(Chunk[0], Result[Used], System.Length(Chunk));
    Inc(Used, System.Length(Chunk));
  end;
end;

function TCborReader.ReadTextString(Info: Byte): string;
var
  Indefinite: Boolean;
  Size: UInt64;
  Initial: Byte;
begin
  Size := ReadArgument(Info, True, Indefinite);
  if not Indefinite then Exit(ReadTextChunk(Size));
  Result := '';
  while True do
  begin
    Initial := ReadByte;
    if Initial = BreakByte then Break;
    if (Initial shr 5 <> Major_Text) or ((Initial and 31) = 31) then Fail('Invalid chunk in an indefinite-length text string');
    Result := Result + ReadTextChunk(ReadArgument(Initial and 31, False, Indefinite));
  end;
end;

function TCborReader.EncodeBytesText(const Bytes: TBytes): string;
begin
  case FOptions.BytesMode of
    cbmBase64: Result := EncodeBase64(Bytes, False);
    cbmHex: Result := CborToHex(Bytes);
  else
    Result := EncodeBase64(Bytes, True);
  end;
end;

function TCborReader.NumberNode(const Text: string): TJsonValue;
begin
  Result := TJsonNumber.Create(Text, (Pos('.', Text) > 0) or (Pos('E', Text) > 0) or (Pos('e', Text) > 0));
end;

function TCborReader.FloatNode(Value: Double; Width: Integer): TJsonValue;
var
  Bits: UInt64;
  Text: string;
begin
  Move(Value, Bits, SizeOf(Bits));
  if ((Bits shr 52) and $7FF) = $7FF then
  begin
    case FOptions.NonFinite of
      cnfNull: Exit(TJsonNull.Create);
      cnfText:
        begin
          if (Bits and ((UInt64(1) shl 52) - 1)) <> 0 then Exit(TJsonString.Create('NaN'));
          if (Bits shr 63) = 0 then Exit(TJsonString.Create('Infinity'));
          Exit(TJsonString.Create('-Infinity'));
        end;
    else
      Fail('NaN and Infinity cannot be represented in JSON');
    end;
  end;
  if FOptions.ShortestSinglePrecision and (Width < 8) then Text := SingleToJson(Single(Value))
  else Text := JsonDoubleToText(Value);
  if (Pos('.', Text) = 0) and (Pos('E', Text) = 0) and (Pos('e', Text) = 0) then Text := Text + '.0';
  Result := TJsonNumber.Create(Text, True);
end;

function TCborReader.ReadFloat(Info: Byte): TJsonValue;
var
  Raw: UInt64;
  I: Integer;
  Single32: Single;
  Bits32: Cardinal;
  Value: Double;
begin
  Raw := 0;
  case Info of
    25:
      begin
        if Remaining < 2 then Fail('Unexpected end of data');
        for I := 1 to 2 do Raw := (Raw shl 8) or ReadByte;
        Exit(FloatNode(HalfToDouble(Word(Raw)), 2));
      end;
    26:
      begin
        if Remaining < 4 then Fail('Unexpected end of data');
        for I := 1 to 4 do Raw := (Raw shl 8) or ReadByte;
        Bits32 := Cardinal(Raw);
        Move(Bits32, Single32, SizeOf(Single32));
        if ((Bits32 shr 23) and $FF) = $FF then
        begin
          Raw := (UInt64(Bits32 shr 31) shl 63) or (UInt64($7FF) shl 52);
          if (Bits32 and $7FFFFF) <> 0 then Raw := Raw or (UInt64(1) shl 51);
          Move(Raw, Value, SizeOf(Value));
        end
        else Value := Single32;
        Exit(FloatNode(Value, 4));
      end;
  else
    begin
      if Remaining < 8 then Fail('Unexpected end of data');
      for I := 1 to 8 do Raw := (Raw shl 8) or ReadByte;
      Move(Raw, Value, SizeOf(Value));
      Result := FloatNode(Value, 8);
    end;
  end;
end;

function TCborReader.ReadArray(Info: Byte; Level: Integer): TJsonValue;
var
  Arr: TJsonArray;
  Indefinite: Boolean;
  Count: UInt64;
  I: UInt64;
begin
  Count := ReadArgument(Info, True, Indefinite);
  if (not Indefinite) and (Count > UInt64(Remaining)) then Fail('Array length exceeds the remaining data');
  Arr := TJsonArray.Create;
  try
    if Indefinite then
    begin
      while True do
      begin
        if (Remaining > 0) and (FData[FPos] = BreakByte) then
        begin
          Inc(FPos);
          Break;
        end;
        Arr.Add(ReadItem(Level + 1));
      end;
    end
    else
    begin
      I := 0;
      while I < Count do
      begin
        Arr.Add(ReadItem(Level + 1));
        Inc(I);
      end;
    end;
  except
    Arr.Free;
    raise;
  end;
  Result := Arr;
end;

function TCborReader.ReadKey(Level: Integer): string;
var
  Initial: Byte;
  Item: TJsonValue;
begin
  if FPos >= System.Length(FData) then Fail('Unexpected end of data');
  Initial := FData[FPos];
  if (FOptions.KeyMode = ckmText) and (Initial shr 5 <> Major_Text) then Fail('Map key is not a text string');
  if Initial shr 5 = Major_Bytes then
  begin
    Inc(FPos);
    Exit(EncodeBytesText(ReadByteString(Initial and 31)));
  end;
  Item := ReadItem(Level);
  try
    case Item.GetJsonType of
      TJsonType.jtString: Result := Item.AsString;
      TJsonType.jtInteger, TJsonType.jtFloat: Result := Item.AsRawText;
      TJsonType.jtBoolean, TJsonType.jtNull: Result := Item.ToJson;
    else
      Fail('Unsupported map key type');
    end;
  finally
    Item.Free;
  end;
end;

function TCborReader.ReadMap(Info: Byte; Level: Integer): TJsonValue;
var
  Obj: TJsonObject;
  Indefinite: Boolean;
  Count, I: UInt64;
  Key: string;
  Item: TJsonValue;

  procedure ReadPair;
  begin
    Key := ReadKey(Level + 1);
    Item := ReadItem(Level + 1);
    if Obj.Contains(Key) then
    begin
      case FOptions.DuplicateKeys of
        cdkFirstWins:
          begin
            Item.Free;
            Exit;
          end;
        cdkLastWins: Obj.Remove(Key);
      else
        Item.Free;
        Fail('Duplicate map key "' + Key + '"');
      end;
    end;
    Obj.AddPair(Key, Item);
  end;

begin
  Count := ReadArgument(Info, True, Indefinite);
  if (not Indefinite) and (Count > UInt64(Remaining) div 2) then Fail('Map length exceeds the remaining data');
  Obj := TJsonObject.Create;
  try
    if Indefinite then
    begin
      while True do
      begin
        if (Remaining > 0) and (FData[FPos] = BreakByte) then
        begin
          Inc(FPos);
          Break;
        end;
        ReadPair;
      end;
    end
    else
    begin
      I := 0;
      while I < Count do
      begin
        ReadPair;
        Inc(I);
      end;
    end;
  except
    Obj.Free;
    raise;
  end;
  Result := Obj;
end;

function TCborReader.ReadBignum(Tag: UInt64): TJsonValue;
var
  Initial: Byte;
  Bytes: TBytes;
  Text: string;
begin
  Initial := ReadByte;
  if Initial shr 5 <> Major_Bytes then Fail('A bignum tag must contain a byte string');
  Bytes := ReadByteString(Initial and 31);
  Text := BytesToDecimal(Bytes, 0, Length(Bytes));
  if Tag = 3 then Text := '-' + DecimalAddOne(Text);
  Result := NumberNode(Text);
end;

function TCborReader.ReadScaled(Tag: UInt64; Level: Integer): TJsonValue;
var
  Content, ExponentNode, MantissaNode: TJsonValue;
  Exponent: Int64;
  Mantissa, Digits, Text: string;
  Negative: Boolean;
begin
  Content := ReadItem(Level + 1);
  try
    if (Content.GetJsonType <> TJsonType.jtArray) or (TJsonArray(Content).Count <> 2) then
      Fail('A decimal fraction or bigfloat must be an array of two integers');
    ExponentNode := TJsonArray(Content).Items[0];
    MantissaNode := TJsonArray(Content).Items[1];
    if (ExponentNode.GetJsonType <> TJsonType.jtInteger) or (MantissaNode.GetJsonType <> TJsonType.jtInteger) then
      Fail('A decimal fraction or bigfloat must be an array of two integers');
    if not TryStrToInt64(ExponentNode.AsRawText, Exponent) then Fail('Exponent out of range');
    Mantissa := MantissaNode.AsRawText;
    Negative := (Mantissa <> '') and (Mantissa[1] = '-');
    if Negative then Digits := Copy(Mantissa, 2, MaxInt) else Digits := Mantissa;
    if Tag = 4 then
      Text := PlainDecimalText(Negative, Digits, Exponent)
    else
    begin
      if (Exponent > MaxDecimalExponent) or (Exponent < -MaxDecimalExponent) then Fail('Bigfloat exponent too large');
      if Digits = '0' then Text := '0'
      else if Exponent >= 0 then Text := PlainDecimalText(Negative, DecimalMultiplyPower(Digits, 2, Integer(Exponent)), 0)
      else Text := PlainDecimalText(Negative, DecimalMultiplyPower(Digits, 5, Integer(-Exponent)), Exponent);
    end;
    Result := NumberNode(Text);
  finally
    Content.Free;
  end;
end;

function TCborReader.ReadTag(Info: Byte; Level: Integer): TJsonValue;
var
  Indefinite: Boolean;
  Tag: UInt64;
  Content: TJsonValue;
  Wrapper: TJsonObject;
begin
  Tag := ReadArgument(Info, False, Indefinite);
  if (Tag = 2) or (Tag = 3) then Exit(ReadBignum(Tag));
  if (Tag = 4) or (Tag = 5) then Exit(ReadScaled(Tag, Level));
  Content := ReadItem(Level + 1);
  if FOptions.TagMode <> ctmWrap then Exit(Content);
  Wrapper := TJsonObject.Create;
  try
    Wrapper.AddPair(FOptions.TagKey, TJsonNumber.Create(UIntToStr(Tag), False));
    Wrapper.AddPair(FOptions.ValueKey, Content);
  except
    Wrapper.Free;
    Content.Free;
    raise;
  end;
  Result := Wrapper;
end;

function TCborReader.ReadItem(Level: Integer): TJsonValue;
var
  Initial, Info: Byte;
  Major: Integer;
  Indefinite: Boolean;
  Argument: UInt64;
  Bytes: TBytes;
  Wrapper: TJsonObject;
begin
  if Level > FOptions.MaxDepth then Fail('Nesting deeper than MaxDepth (' + IntToStr(FOptions.MaxDepth) + ')');
  Initial := ReadByte;
  Major := Initial shr 5;
  Info := Initial and 31;
  case Major of
    Major_Unsigned:
      begin
        Argument := ReadArgument(Info, False, Indefinite);
        Result := NumberNode(UIntToStr(Argument));
      end;
    Major_Negative:
      begin
        Argument := ReadArgument(Info, False, Indefinite);
        if Argument = High(UInt64) then Result := NumberNode('-18446744073709551616')
        else Result := NumberNode('-' + UIntToStr(Argument + 1));
      end;
    Major_Bytes:
      begin
        Bytes := ReadByteString(Info);
        if FOptions.BytesMode = cbmWrapped then
        begin
          Wrapper := TJsonObject.Create;
          try
            Wrapper.AddPair(FOptions.BytesKey, EncodeBase64(Bytes, True));
          except
            Wrapper.Free;
            raise;
          end;
          Result := Wrapper;
        end
        else Result := TJsonBytes.Create(Bytes, EncodeBytesText(Bytes));
      end;
    Major_Text: Result := TJsonString.Create(ReadTextString(Info));
    Major_Array: Result := ReadArray(Info, Level);
    Major_Map: Result := ReadMap(Info, Level);
    Major_Tag: Result := ReadTag(Info, Level);
  else
    case Info of
      20: Result := TJsonBoolean.Create(False);
      21: Result := TJsonBoolean.Create(True);
      22: Result := TJsonNull.Create;
      23:
        begin
          if not FOptions.UndefinedAsNull then Fail('The simple value undefined cannot be represented in JSON');
          Result := TJsonNull.Create;
        end;
      25, 26, 27: Result := ReadFloat(Info);
      31: Fail('Unexpected break');
      24: Fail('Unsupported simple value');
      28, 29, 30: Fail('Reserved additional information ' + IntToStr(Info));
    else
      Fail('Unsupported simple value ' + IntToStr(Info));
    end;
  end;
end;

function UseOptions(Options: TJsonCborOptions; out Own: TJsonCborOptions): TJsonCborOptions;
begin
  Own := nil;
  if Options = nil then
  begin
    Own := TJsonCborOptions.Create;
    Result := Own;
  end
  else Result := Options;
end;

function CborToDomAt(const Data: TBytes; var Position: Integer; Options: TJsonCborOptions): TJsonValue;
var
  Own, Used: TJsonCborOptions;
  Reader: TCborReader;
begin
  if (Position < 0) or (Position > Length(Data)) then raise EJsonCborError.Create('CBOR: start position is outside the data');
  Used := UseOptions(Options, Own);
  try
    Reader := TCborReader.Create(Data, Position, Used);
    try
      Result := Reader.ReadItem(0);
      Position := Reader.Position;
    finally
      Reader.Free;
    end;
  finally
    Own.Free;
  end;
end;

function CborToDom(const Data: TBytes; Options: TJsonCborOptions): TJsonValue;
var
  Position: Integer;
begin
  Position := 0;
  Result := CborToDomAt(Data, Position, Options);
  if Position <> Length(Data) then
  begin
    Result.Free;
    raise EJsonCborError.CreateFmt('CBOR: %d unexpected byte(s) after the first data item', [Length(Data) - Position]);
  end;
end;

function CborToJson(const Data: TBytes; Options: TJsonCborOptions): string;
var
  Dom: TJsonValue;
begin
  Dom := CborToDom(Data, Options);
  try
    Result := DomToText(Dom);
  finally
    Dom.Free;
  end;
end;

function DomToCbor(Value: TJsonValue; Options: TJsonCborOptions): TBytes;
var
  Own, Used: TJsonCborOptions;
  Output: TCborOutput;
  Writer: TDomCborWriter;
begin
  Used := UseOptions(Options, Own);
  try
    Output := TCborOutput.Create;
    try
      Writer := TDomCborWriter.Create(Used, Output);
      try
        Writer.Write(Value, 0);
      finally
        Writer.Free;
      end;
      Result := Output.ToBytes;
    finally
      Output.Free;
    end;
  finally
    Own.Free;
  end;
end;

function JsonToCbor(const Json: string; Options: TJsonCborOptions): TBytes;
var
  Dom: TJsonValue;
begin
  Dom := DomFromText(Json);
  try
    Result := DomToCbor(Dom, Options);
  finally
    Dom.Free;
  end;
end;

end.
