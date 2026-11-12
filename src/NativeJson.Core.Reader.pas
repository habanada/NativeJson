{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Core.Reader;

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
  NativeJson.Core.Tokens,
  NativeJson.Core.Tokenizer,
  NativeJson.FloatText;

type
  EJsonReaderError = class(Exception);

  TJsonReadState = (Start, Complete, ObjectStart, ObjectNextProperty, ObjectProperty, ObjectValue, ObjectAfterValue, ArrayStart, ArrayNextValue, ArrayAfterValue, Closed, Error);

  TJsonReader = class
  private
    FTokenizer: TJsonTokenizer;
    FOwnsTokenizer: Boolean;
    FState: TJsonReadState;
    FDepth: Integer;
    FQuoteChar: Char;
    FStateStack: TArray<TJsonReadState>;
    FStateStackTop: Integer;
    FCurrentValueString: string;
    FHasConvertedValue: Boolean;
    FTokenType: TJsonToken;
    procedure PushParentState(StateAfterContainer: TJsonReadState);
    procedure PopParentState;
    procedure BeginValue(Token: TJsonToken; StateAfterValue: TJsonReadState);
    function DecodeString(Start: PChar; Len: Integer): string;
    function DecodeString5(Start: PChar; Len: Integer): string;
    function ParseUnicode(var P: PChar; EndP: PChar): Char;
    function GetJson5: Boolean;
    procedure SetJson5(Value: Boolean);
    function GetValueAsString: string;
    function GetValueAsInteger: Int64;
    function GetValueAsDouble: Double;
    function GetValueAsBoolean: Boolean;
    function GetRawValue: string;
    function GetLineNumber: Integer;
    function GetLinePosition: Integer;
    procedure RaiseExpected(const Msg: string);
  public
    constructor Create(const Json: string); overload;
    constructor Create(ATokenizer: TJsonTokenizer); overload;
    destructor Destroy; override;
    function Read: Boolean;
    procedure Close;
    property TokenType: TJsonToken read FTokenType;
    property Value: string read GetValueAsString;
    property ValueAsInt: Int64 read GetValueAsInteger;
    property ValueAsFloat: Double read GetValueAsDouble;
    property ValueAsBool: Boolean read GetValueAsBoolean;
    property RawValue: string read GetRawValue;
    property Depth: Integer read FDepth;
    property LineNumber: Integer read GetLineNumber;
    property LinePosition: Integer read GetLinePosition;
    property QuoteChar: Char read FQuoteChar write FQuoteChar;
    property Json5: Boolean read GetJson5 write SetJson5;
  end;

implementation

constructor TJsonReader.Create(const Json: string);
begin
  inherited Create;
  FTokenizer := TJsonTokenizer.Create(Json);
  FOwnsTokenizer := True;
  FState := TJsonReadState.Start;
  FQuoteChar := '"';
  FStateStackTop := -1;
  SetLength(FStateStack, 16);
  FTokenType := TJsonToken.None;
end;

constructor TJsonReader.Create(ATokenizer: TJsonTokenizer);
begin
  inherited Create;
  if ATokenizer = nil then raise EArgumentNilException.Create('ATokenizer');
  FTokenizer := ATokenizer;
  FOwnsTokenizer := False;
  FState := TJsonReadState.Start;
  FQuoteChar := '"';
  FStateStackTop := -1;
  SetLength(FStateStack, 16);
  FTokenType := TJsonToken.None;
end;

destructor TJsonReader.Destroy;
begin
  if FOwnsTokenizer then FTokenizer.Free;
  inherited;
end;

procedure TJsonReader.Close;
begin
  FState := TJsonReadState.Closed;
  FTokenType := TJsonToken.None;
end;

function TJsonReader.GetJson5: Boolean;
begin
  Result := FTokenizer.Json5;
end;

procedure TJsonReader.SetJson5(Value: Boolean);
begin
  FTokenizer.Json5 := Value;
end;

function TJsonReader.GetLineNumber: Integer;
begin
  Result := FTokenizer.LineNumber;
end;

function TJsonReader.GetLinePosition: Integer;
begin
  Result := FTokenizer.LinePosition;
end;

procedure TJsonReader.RaiseExpected(const Msg: string);
begin
  raise EJsonReaderError.CreateFmt('%s at line %d, pos %d', [Msg, LineNumber, LinePosition]);
end;

procedure TJsonReader.PushParentState(StateAfterContainer: TJsonReadState);
begin
  Inc(FStateStackTop);
  if FStateStackTop >= Length(FStateStack) then SetLength(FStateStack, Length(FStateStack) * 2);
  FStateStack[FStateStackTop] := StateAfterContainer;
  Inc(FDepth);
end;

procedure TJsonReader.PopParentState;
begin
  if FStateStackTop < 0 then
  begin
    FState := TJsonReadState.Complete;
    Exit;
  end;
  FState := FStateStack[FStateStackTop];
  Dec(FStateStackTop);
  if FDepth > 0 then Dec(FDepth);
end;

procedure TJsonReader.BeginValue(Token: TJsonToken; StateAfterValue: TJsonReadState);
begin
  case Token of
    TJsonToken.StartObject:
      begin
        PushParentState(StateAfterValue);
        FState := TJsonReadState.ObjectStart;
      end;
    TJsonToken.StartArray:
      begin
        PushParentState(StateAfterValue);
        FState := TJsonReadState.ArrayStart;
      end;
  else
    if not (Token in TokenValues) then RaiseExpected('Expected JSON value');
    if (Token = TJsonToken.Str) and FTokenizer.IsIdentifier then RaiseExpected('Expected JSON value');
    FState := StateAfterValue;
  end;
end;

function TJsonReader.Read: Boolean;
var
  Token: TJsonToken;
begin
  if FState = TJsonReadState.Closed then Exit(False);
  FHasConvertedValue := False;
  FCurrentValueString := '';

  while True do
  begin
    if not FTokenizer.Read then
    begin
      if FState in [TJsonReadState.Start, TJsonReadState.Complete, TJsonReadState.Closed] then
      begin
        FState := TJsonReadState.Closed;
        FTokenType := TJsonToken.None;
        Exit(False);
      end;
      RaiseExpected('Unexpected end of JSON');
    end;

    Token := FTokenizer.TokenType;
    if Token = TJsonToken.Comment then Continue;

    case FState of
      TJsonReadState.Start:
        begin
          BeginValue(Token, TJsonReadState.Complete);
          FTokenType := Token;
          Exit(True);
        end;

      TJsonReadState.Complete:
        RaiseExpected('Unexpected content after root JSON value');

      TJsonReadState.ObjectStart:
        begin
          if Token = TJsonToken.EndObject then
          begin
            PopParentState;
            FTokenType := Token;
            Exit(True);
          end;
          if (Token <> TJsonToken.Str) and not FTokenizer.IsIdentifier then RaiseExpected('Expected property name or "}"');
          FState := TJsonReadState.ObjectProperty;
          FTokenType := TJsonToken.PropertyName;
          Exit(True);
        end;

      TJsonReadState.ObjectNextProperty:
        begin
          if (Token = TJsonToken.EndObject) and FTokenizer.Json5 then
          begin
            PopParentState;
            FTokenType := Token;
            Exit(True);
          end;
          if (Token <> TJsonToken.Str) and not FTokenizer.IsIdentifier then RaiseExpected('Expected property name after comma');
          FState := TJsonReadState.ObjectProperty;
          FTokenType := TJsonToken.PropertyName;
          Exit(True);
        end;

      TJsonReadState.ObjectProperty:
        begin
          if Token <> TJsonToken.Colon then RaiseExpected('Expected ":" after property name');
          FState := TJsonReadState.ObjectValue;
          Continue;
        end;

      TJsonReadState.ObjectValue:
        begin
          BeginValue(Token, TJsonReadState.ObjectAfterValue);
          FTokenType := Token;
          Exit(True);
        end;

      TJsonReadState.ObjectAfterValue:
        begin
          if Token = TJsonToken.Comma then
          begin
            FState := TJsonReadState.ObjectNextProperty;
            Continue;
          end;
          if Token = TJsonToken.EndObject then
          begin
            PopParentState;
            FTokenType := Token;
            Exit(True);
          end;
          RaiseExpected('Expected "," or "}"');
        end;

      TJsonReadState.ArrayStart:
        begin
          if Token = TJsonToken.EndArray then
          begin
            PopParentState;
            FTokenType := Token;
            Exit(True);
          end;
          BeginValue(Token, TJsonReadState.ArrayAfterValue);
          FTokenType := Token;
          Exit(True);
        end;

      TJsonReadState.ArrayNextValue:
        begin
          if (Token = TJsonToken.EndArray) and FTokenizer.Json5 then
          begin
            PopParentState;
            FTokenType := Token;
            Exit(True);
          end;
          BeginValue(Token, TJsonReadState.ArrayAfterValue);
          FTokenType := Token;
          Exit(True);
        end;

      TJsonReadState.ArrayAfterValue:
        begin
          if Token = TJsonToken.Comma then
          begin
            FState := TJsonReadState.ArrayNextValue;
            Continue;
          end;
          if Token = TJsonToken.EndArray then
          begin
            PopParentState;
            FTokenType := Token;
            Exit(True);
          end;
          RaiseExpected('Expected "," or "]"');
        end;
    else
      Exit(False);
    end;
  end;
end;

function TJsonReader.ParseUnicode(var P: PChar; EndP: PChar): Char;
var
  I, V: Integer;
  C: Char;
begin
  V := 0;
  for I := 0 to 3 do
  begin
    Inc(P);
    if P >= EndP then RaiseExpected('Incomplete unicode escape');
    C := P^;
    case C of
      '0'..'9': V := (V shl 4) or (Ord(C) - Ord('0'));
      'a'..'f': V := (V shl 4) or (Ord(C) - Ord('a') + 10);
      'A'..'F': V := (V shl 4) or (Ord(C) - Ord('A') + 10);
    else
      RaiseExpected('Invalid unicode escape');
    end;
  end;
  Result := Char(V);
end;

function TJsonReader.DecodeString(Start: PChar; Len: Integer): string;
var
  P, EndP, Dest: PChar;
  C: Char;
begin
  EndP := Start + Len;
  P := Start;
  while (P < EndP) and (P^ <> '\') do Inc(P);
  if P >= EndP then
  begin
    SetString(Result, Start, Len);
    Exit;
  end;

  SetLength(Result, Len);
  Dest := PChar(Result);
  P := Start;
  while P < EndP do
  begin
    if P^ = '\' then
    begin
      Inc(P);
      if P >= EndP then RaiseExpected('Incomplete escape sequence');
      case P^ of
        '"', '\', '/': C := P^;
        'b': C := #8;
        'f': C := #12;
        'n': C := #10;
        'r': C := #13;
        't': C := #9;
        'u': C := ParseUnicode(P, EndP);
      else
        RaiseExpected('Invalid escape sequence');
        C := #0;
      end;
      Dest^ := C;
    end
    else
      Dest^ := P^;
    Inc(Dest);
    Inc(P);
  end;
  SetLength(Result, NativeInt(Dest - PChar(Result)));
end;

function TJsonReader.DecodeString5(Start: PChar; Len: Integer): string;
var
  P, EndP, Dest: PChar;
  I, InputValue: Integer;
begin
  EndP := Start + Len;
  P := Start;
  while (P < EndP) and (P^ <> '\') do Inc(P);
  if P >= EndP then
  begin
    SetString(Result, Start, Len);
    Exit;
  end;

  SetLength(Result, Len);
  Dest := PChar(Result);
  P := Start;
  while P < EndP do
  begin
    if P^ <> '\' then
    begin
      Dest^ := P^;
      Inc(Dest);
      Inc(P);
      Continue;
    end;
    Inc(P);
    if P >= EndP then RaiseExpected('Incomplete escape sequence');
    case P^ of
      'b': Dest^ := #8;
      'f': Dest^ := #12;
      'n': Dest^ := #10;
      'r': Dest^ := #13;
      't': Dest^ := #9;
      'v': Dest^ := #11;
      '0': Dest^ := #0;
      'u': Dest^ := ParseUnicode(P, EndP);
      'x':
        begin
          InputValue := 0;
          for I := 1 to 2 do
          begin
            Inc(P);
            if P >= EndP then RaiseExpected('Incomplete hex escape');
            case P^ of
              '0'..'9': InputValue := (InputValue shl 4) or (Ord(P^) - Ord('0'));
              'a'..'f': InputValue := (InputValue shl 4) or (Ord(P^) - Ord('a') + 10);
              'A'..'F': InputValue := (InputValue shl 4) or (Ord(P^) - Ord('A') + 10);
            else
              RaiseExpected('Invalid hex escape');
            end;
          end;
          Dest^ := Char(InputValue);
        end;
      #13:
        begin
          if (P + 1 < EndP) and (P[1] = #10) then Inc(P);
          Inc(P);
          Continue;
        end;
      #10, #$2028, #$2029:
        begin
          Inc(P);
          Continue;
        end;
    else
      Dest^ := P^;
    end;
    Inc(Dest);
    Inc(P);
  end;
  SetLength(Result, NativeInt(Dest - PChar(Result)));
end;

function TJsonReader.GetValueAsString: string;
begin
  if FHasConvertedValue then Exit(FCurrentValueString);
  case FTokenType of
    TJsonToken.Str, TJsonToken.PropertyName:
      if FTokenizer.Json5 then
        FCurrentValueString := DecodeString5(FTokenizer.ValueStart, FTokenizer.ValueLength)
      else
        FCurrentValueString := DecodeString(FTokenizer.ValueStart, FTokenizer.ValueLength);
    TJsonToken.Integer, TJsonToken.Float, TJsonToken.Boolean, TJsonToken.Date, TJsonToken.Bytes: FCurrentValueString := FTokenizer.Value;
  else
    FCurrentValueString := '';
  end;
  FHasConvertedValue := True;
  Result := FCurrentValueString;
end;

function TJsonReader.GetValueAsInteger: Int64;
var
  UnsignedValue: UInt64;
  FloatValue: Double;
begin
  if FTokenType = TJsonToken.Integer then
  begin
    if TryStrToInt64(FTokenizer.Value, Result) then Exit;
    // Does not fit into Int64. For an unsigned 64-bit target the bits are
    // still correct - so do not abort here. The deserializer decides later
    // about the target type based on RawValue.
    if TryStrToUInt64(FTokenizer.Value, UnsignedValue) then Exit(Int64(UnsignedValue));
    Result := 0;
    Exit;
  end;
  if FTokenType = TJsonToken.Float then
  begin
    FloatValue := GetValueAsDouble;
    // Round would raise an exception at 1e20 before anyone could
    // reject the value.
    if IsNan(FloatValue) or (FloatValue < -9.2E18) or (FloatValue > 9.2E18) then Exit(0);
    Result := Round(FloatValue);
    Exit;
  end;
  Result := 0;
end;

function TJsonReader.GetValueAsDouble: Double;
begin
  if FTokenType in [TJsonToken.Integer, TJsonToken.Float] then
  begin
    if JsonTryParseDouble(FTokenizer.Value, Result) then Exit;
    if FTokenizer.Json5 then
    begin
      if FTokenizer.Value = 'Infinity' then Exit(Infinity);
      if FTokenizer.Value = '-Infinity' then Exit(NegInfinity);
      if FTokenizer.Value = 'NaN' then Exit(NaN);
    end;
    RaiseExpected('Invalid number');
  end;
  Result := 0;
end;

function TJsonReader.GetRawValue: string;
begin
  Result := FTokenizer.Value;
end;

function TJsonReader.GetValueAsBoolean: Boolean;
begin
  Result := (FTokenType = TJsonToken.Boolean) and SameText(FTokenizer.Value, 'true');
end;

end.
