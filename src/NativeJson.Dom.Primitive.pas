{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Dom.Primitive;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Math,
  {$ELSE}
  System.SysUtils,
  System.Math,
  {$ENDIF}
  NativeJson.Dom.Value;

type
  TJsonString = class(TJsonValue)
  private
    FValue: string;
    class function EscapeString(const S: string): string; static;
  public
    constructor Create(const Value: string);
    function GetJsonType: TJsonType; override;
    function AsString: string; override;
    function AsInteger: Int64; override;
    function AsDouble: Double; override;
    function AsCurrency: Currency; override;
    function AsBoolean: Boolean; override;
    function Clone: TJsonValue; override;
    function ToJson: string; override;
  end;

  TJsonBytes = class(TJsonString)
  private
    FBytes: TBytes;
  public
    constructor Create(const ABytes: TBytes; const AText: string); overload;
    function Clone: TJsonValue; override;
    property Bytes: TBytes read FBytes;
  end;

  TJsonNumber = class(TJsonValue)
  private
    FInt: Int64;
    FFloat: Double;
    FIsFloat: Boolean;
    FResolved: Boolean;
    FRaw: string;
    procedure Resolve;
  public
    constructor Create(Value: Int64); overload;
    constructor Create(Value: Integer); overload;
    constructor Create(Value: Double); overload;
    constructor Create(const Raw: string; Value: Double); overload;
    constructor Create(const Raw: string; Value: Int64); overload;
    constructor Create(const Raw: string; IsFloat: Boolean); overload;
    class function FromCurrency(const InputValue: Currency): TJsonNumber; static;
    class function CurrencyToText(const InputValue: Currency): string; static;
    function GetJsonType: TJsonType; override;
    function AsString: string; override;
    function AsInteger: Int64; override;
    function AsDouble: Double; override;
    function AsCurrency: Currency; override;
    function AsRawText: string; override;
    function AsBoolean: Boolean; override;
    function Clone: TJsonValue; override;
    function ToJson: string; override;
  end;

  TJsonBoolean = class(TJsonValue)
  private
    FValue: Boolean;
  public
    constructor Create(Value: Boolean);
    function GetJsonType: TJsonType; override;
    function AsString: string; override;
    function AsInteger: Int64; override;
    function AsDouble: Double; override;
    function AsBoolean: Boolean; override;
    function Clone: TJsonValue; override;
    function ToJson: string; override;
  end;

  TJsonNull = class(TJsonValue)
  public
    function GetJsonType: TJsonType; override;
    function IsNull: Boolean; override;
    function AsString: string; override;
    function AsInteger: Int64; override;
    function AsDouble: Double; override;
    function AsBoolean: Boolean; override;
    function Clone: TJsonValue; override;
    function ToJson: string; override;
  end;

implementation

uses
  NativeJson.FloatText,
  NativeJson.Serializer.Writer;

constructor TJsonString.Create(const Value: string);
begin
  inherited Create;
  FValue := Value;
end;

function TJsonString.GetJsonType: TJsonType;
begin
  Result := TJsonType.jtString;
end;

function TJsonString.AsString: string;
begin
  Result := FValue;
end;

function TJsonString.AsInteger: Int64;
begin
  if not TryStrToInt64(FValue, Result) then
    Result := 0;
end;

function TJsonString.AsDouble: Double;
var
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Invariant;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := ',';
  if not TryStrToFloat(FValue, Result, FS) then
    Result := 0.0;
end;

function TJsonString.AsCurrency: Currency;
begin
  // Amounts from foreign systems often arrive as strings.
  if not TryStrToCurr(FValue, Result, TFormatSettings.Invariant) then Result := 0;
end;

function TJsonString.AsBoolean: Boolean;
begin
  if SameText(FValue, 'true') then
    Exit(True);
  if SameText(FValue, 'false') then
    Exit(False);
  Result := False;
end;

function TJsonString.Clone: TJsonValue;
begin
  Result := TJsonString.Create(FValue);
end;

constructor TJsonBytes.Create(const ABytes: TBytes; const AText: string);
begin
  inherited Create(AText);
  FBytes := Copy(ABytes, 0, Length(ABytes));
end;

function TJsonBytes.Clone: TJsonValue;
begin
  Result := TJsonBytes.Create(FBytes, AsString);
end;

class function TJsonString.EscapeString(const S: string): string;
var
  I, Len, Extra: Integer;
  P, Dest: PChar;
  C: Char;
begin
  Len := Length(S);
  Extra := 0;
  P := PChar(S);
  for I := 0 to Len - 1 do
  begin
    C := P^;
    case C of
      '"', '\', #8, #9, #10, #12, #13: Inc(Extra);
      #0..#7, #11, #14..#31: Inc(Extra, 5);
    end;
    Inc(P);
  end;
  if Extra = 0 then
  begin
    Result := '"' + S + '"';
    Exit;
  end;
  SetLength(Result, Len + Extra + 2);
  Dest := PChar(Result);
  Dest^ := '"';
  Inc(Dest);
  P := PChar(S);
  for I := 0 to Len - 1 do
  begin
    C := P^;
    case C of
      '"':
        begin
          Dest^ := '\';
          Inc(Dest);
          Dest^ := '"';
          Inc(Dest);
        end;
      '\':
        begin
          Dest^ := '\';
          Inc(Dest);
          Dest^ := '\';
          Inc(Dest);
        end;
      #8:
        begin
          Dest^ := '\';
          Inc(Dest);
          Dest^ := 'b';
          Inc(Dest);
        end;
      #9:
        begin
          Dest^ := '\';
          Inc(Dest);
          Dest^ := 't';
          Inc(Dest);
        end;
      #10:
        begin
          Dest^ := '\';
          Inc(Dest);
          Dest^ := 'n';
          Inc(Dest);
        end;
      #12:
        begin
          Dest^ := '\';
          Inc(Dest);
          Dest^ := 'f';
          Inc(Dest);
        end;
      #13:
        begin
          Dest^ := '\';
          Inc(Dest);
          Dest^ := 'r';
          Inc(Dest);
        end;
      #0..#7, #11, #14..#31:
        begin
          Dest^ := '\';
          Inc(Dest);
          Dest^ := 'u';
          Inc(Dest);
          Dest^ := '0';
          Inc(Dest);
          Dest^ := '0';
          Inc(Dest);
          Dest^ := Char(Ord('0') + (Ord(C) shr 4));
          Inc(Dest);
          if (Ord(C) and $F) < 10 then
            Dest^ := Char(Ord('0') + (Ord(C) and $F))
          else
            Dest^ := Char(Ord('a') + (Ord(C) and $F) - 10);
          Inc(Dest);
        end;
    else
      begin
        Dest^ := C;
        Inc(Dest);
      end;
    end;
    Inc(P);
  end;
  Dest^ := '"';
end;

function TJsonString.ToJson: string;
begin
  Result := EscapeString(FValue);
end;

constructor TJsonNumber.Create(Value: Int64);
begin
  inherited Create;
  FInt := Value;
  FFloat := Value;
  FIsFloat := False;
  FResolved := True;
end;

constructor TJsonNumber.Create(Value: Integer);
begin
  Create(Int64(Value));
end;

constructor TJsonNumber.Create(Value: Double);
begin
  inherited Create;
  FFloat := Value;
  try
    FInt := Round(Value);
  except
    FInt := 0;
  end;
  FIsFloat := True;
  FResolved := True;
end;

constructor TJsonNumber.Create(const Raw: string; Value: Double);
begin
  inherited Create;
  FFloat := Value;
  if not IsNan(Value) and (Value > -9.2e18) and (Value < 9.2e18) then FInt := Round(Value);
  FIsFloat := True;
  FResolved := True;
  FRaw := Raw;
end;

constructor TJsonNumber.Create(const Raw: string; Value: Int64);
begin
  inherited Create;
  FInt := Value;
  FFloat := Value;
  FIsFloat := False;
  FResolved := True;
  FRaw := Raw;
end;

constructor TJsonNumber.Create(const Raw: string; IsFloat: Boolean);
begin
  inherited Create;
  FRaw := Raw;
  FIsFloat := IsFloat;
end;

procedure TJsonNumber.Resolve;
var
  UnsignedValue: UInt64;
begin
  if FResolved then Exit;
  FResolved := True;
  if not JsonTryParseDouble(FRaw, FFloat) then
    if FRaw.StartsWith('-') then FFloat := NegInfinity else FFloat := Infinity;
  if FIsFloat then
  begin
    try
      FInt := Round(FFloat);
    except
      FInt := 0;
    end;
  end
  else if not TryStrToInt64(FRaw, FInt) then
  begin
    if TryStrToUInt64(FRaw, UnsignedValue) and (UnsignedValue <= UInt64(High(Int64))) then FInt := Int64(UnsignedValue) else FInt := 0;
  end;
end;

function TJsonNumber.AsRawText: string;
begin
  if FRaw <> '' then Result := FRaw else Result := AsString;
end;

class function TJsonNumber.CurrencyToText(const InputValue: Currency): string;
begin
  Result := CurrencyToJson(InputValue);
end;

class function TJsonNumber.FromCurrency(const InputValue: Currency): TJsonNumber;
begin
  Result := TJsonNumber.Create(CurrencyToText(InputValue), InputValue);
end;

function TJsonNumber.AsCurrency: Currency;
begin
  // The raw text is the only lossless source. Only if it is missing
  // or cannot be read as Currency, the Double value is used.
  if (FRaw <> '') and TryStrToCurr(FRaw, Result, TFormatSettings.Invariant) then Exit;
  Resolve;
  if FIsFloat then Result := FFloat else Result := FInt;
end;

function TJsonNumber.GetJsonType: TJsonType;
begin
  if FIsFloat then
    Result := TJsonType.jtFloat
  else
    Result := TJsonType.jtInteger;
end;

function TJsonNumber.AsString: string;
var
  FS: TFormatSettings;
begin
  Resolve;
  if FIsFloat then
  begin
    FS := TFormatSettings.Invariant;
    FS.DecimalSeparator := '.';
    FS.ThousandSeparator := ',';
    Result := FloatToStr(FFloat, FS);
  end
  else
    Result := IntToStr(FInt);
end;

function TJsonNumber.AsInteger: Int64;
begin
  Resolve;
  Result := FInt;
end;

function TJsonNumber.AsDouble: Double;
begin
  Resolve;
  Result := FFloat;
end;

function TJsonNumber.AsBoolean: Boolean;
begin
  Resolve;
  if FIsFloat then
    Result := FFloat <> 0.0
  else
    Result := FInt <> 0;
end;

function TJsonNumber.Clone: TJsonValue;
begin
  if FRaw <> '' then Result := TJsonNumber.Create(FRaw, FIsFloat)
  else if FIsFloat then Result := TJsonNumber.Create(FFloat)
  else Result := TJsonNumber.Create(FInt);
end;

function NeedsRangeCheck(const Raw: string): Boolean;
var
  I: Integer;
begin
  if (Raw = '') or (Length(Raw) > 300) then Exit(True);
  for I := 1 to Length(Raw) do
    case Raw[I] of
      '0'..'9', '.', '-', '+': ;
    else
      Exit(True);
    end;
  Result := False;
end;

function TJsonNumber.ToJson: string;
begin
  if FIsFloat and NeedsRangeCheck(FRaw) then
  begin
    Resolve;
    if IsNan(FFloat) or IsInfinite(FFloat) then
      raise EJsonValueError.Create('JSON does not support NaN or Infinity');
  end;
  if FRaw <> '' then Result := FRaw else Result := AsString;
end;

constructor TJsonBoolean.Create(Value: Boolean);
begin
  inherited Create;
  FValue := Value;
end;

function TJsonBoolean.GetJsonType: TJsonType;
begin
  Result := TJsonType.jtBoolean;
end;

function TJsonBoolean.AsString: string;
begin
  if FValue then
    Result := 'true'
  else
    Result := 'false';
end;

function TJsonBoolean.AsInteger: Int64;
begin
  if FValue then
    Result := 1
  else
    Result := 0;
end;

function TJsonBoolean.AsDouble: Double;
begin
  if FValue then
    Result := 1.0
  else
    Result := 0.0;
end;

function TJsonBoolean.AsBoolean: Boolean;
begin
  Result := FValue;
end;

function TJsonBoolean.Clone: TJsonValue;
begin
  Result := TJsonBoolean.Create(FValue);
end;

function TJsonBoolean.ToJson: string;
begin
  if FValue then
    Result := 'true'
  else
    Result := 'false';
end;

function TJsonNull.GetJsonType: TJsonType;
begin
  Result := TJsonType.jtNull;
end;

function TJsonNull.IsNull: Boolean;
begin
  Result := True;
end;

function TJsonNull.AsString: string;
begin
  Result := '';
end;

function TJsonNull.AsInteger: Int64;
begin
  Result := 0;
end;

function TJsonNull.AsDouble: Double;
begin
  Result := 0.0;
end;

function TJsonNull.AsBoolean: Boolean;
begin
  Result := False;
end;

function TJsonNull.Clone: TJsonValue;
begin
  Result := TJsonNull.Create;
end;

function TJsonNull.ToJson: string;
begin
  Result := 'null';
end;

end.
