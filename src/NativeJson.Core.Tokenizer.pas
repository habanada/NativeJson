{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Core.Tokenizer;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE}
  System.SysUtils,
  {$ENDIF}
  NativeJson.Core.Tokens;

type
  EJsonTokenizerError = class(Exception);

  TJsonTokenizer = class
  private
    FSource: string;
    FJson: PChar;
    FCurr: PChar;
    FEnd: PChar;
    FTokenType: TJsonToken;
    FValueStart: PChar;
    FValueLen: Integer;
    FLine: Integer;
    FLineStart: PChar;
    FJson5: Boolean;
    FIsIdentifier: Boolean;
    FNormalized: string;
    function IsEof: Boolean; inline;
    function GetValue: string;
    function GetLinePos: Integer;
    procedure SkipWhitespace;
    procedure ParseString;
    procedure ParseNumber;
    procedure ParseLiteral(const Literal: string; Token: TJsonToken);
    procedure ParseComment;
    function SkipJson5Whitespace: Boolean;
    function MatchWord(const AWord: string): Boolean;
    procedure ParseString5(Quote: Char);
    procedure ParseNumber5;
    procedure ParseIdentifier5;
    procedure SetNormalized(const Text: string);
  public
    constructor Create(const Json: string);
    function Read: Boolean;
    property Json5: Boolean read FJson5 write FJson5;
    property IsIdentifier: Boolean read FIsIdentifier;
    property TokenType: TJsonToken read FTokenType;
    property ValueStart: PChar read FValueStart;
    property ValueLength: Integer read FValueLen;
    property Value: string read GetValue;
    property LineNumber: Integer read FLine;
    property LinePosition: Integer read GetLinePos;
  end;

implementation

constructor TJsonTokenizer.Create(const Json: string);
begin
  inherited Create;
  FSource := Json;
  if FSource = '' then
  begin
    FJson := nil;
    FCurr := nil;
    FEnd := nil;
    FLineStart := nil;
  end
  else
  begin
    FJson := PChar(FSource);
    FCurr := FJson;
    FEnd := FJson + Length(FSource);
    FLineStart := FJson;
  end;
  FLine := 1;
  FTokenType := TJsonToken.None;
end;

function TJsonTokenizer.IsEof: Boolean;
begin
  Result := (FCurr = nil) or (FCurr >= FEnd);
end;

function TJsonTokenizer.GetLinePos: Integer;
begin
  if (FCurr = nil) or (FLineStart = nil) then
    Exit(1);
  Result := NativeInt(FCurr - FLineStart) + 1;
end;

function TJsonTokenizer.GetValue: string;
begin
  if (FValueStart <> nil) and (FValueLen > 0) then
    SetString(Result, FValueStart, FValueLen)
  else
    Result := '';
end;

procedure TJsonTokenizer.SkipWhitespace;
begin
  while not IsEof do
  begin
    case FCurr^ of
      #9, #32: Inc(FCurr);
      #10:
        begin
          Inc(FCurr);
          Inc(FLine);
          FLineStart := FCurr;
        end;
      #13:
        begin
          Inc(FCurr);
          if not IsEof and (FCurr^ = #10) then Inc(FCurr);
          Inc(FLine);
          FLineStart := FCurr;
        end;
    else
      if not FJson5 or not SkipJson5Whitespace then Exit;
    end;
  end;
end;

function TJsonTokenizer.SkipJson5Whitespace: Boolean;
begin
  Result := True;
  case FCurr^ of
    #11, #12, #$A0, #$FEFF, #$1680, #$2000..#$200A, #$202F, #$205F, #$3000:
      Inc(FCurr);
    #$2028, #$2029:
      begin
        Inc(FCurr);
        Inc(FLine);
        FLineStart := FCurr;
      end;
  else
    Result := False;
  end;
end;

function IsIdentifierStart(C: Char): Boolean;
begin
  case C of
    'A'..'Z', 'a'..'z', '_', '$': Result := True;
    #$A0, #$FEFF, #$1680, #$2000..#$200A, #$2028, #$2029, #$202F, #$205F, #$3000: Result := False;
  else
    Result := Ord(C) >= $80;
  end;
end;

function IsIdentifierChar(C: Char): Boolean;
begin
  Result := IsIdentifierStart(C) or ((C >= '0') and (C <= '9'));
end;

function TJsonTokenizer.MatchWord(const AWord: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if FEnd - FCurr < Length(AWord) then Exit;
  for I := 1 to Length(AWord) do
    if FCurr[I - 1] <> AWord[I] then Exit;
  if (FCurr + Length(AWord) < FEnd) and IsIdentifierChar(FCurr[Length(AWord)]) then Exit;
  Inc(FCurr, Length(AWord));
  Result := True;
end;

procedure TJsonTokenizer.SetNormalized(const Text: string);
begin
  FNormalized := Text;
  FValueStart := PChar(FNormalized);
  FValueLen := Length(FNormalized);
end;

procedure TJsonTokenizer.ParseString5(Quote: Char);
var
  Start: PChar;
begin
  Inc(FCurr);
  Start := FCurr;
  while not IsEof do
  begin
    if FCurr^ = Quote then
    begin
      FValueStart := Start;
      FValueLen := NativeInt(FCurr - Start);
      FTokenType := TJsonToken.Str;
      Inc(FCurr);
      Exit;
    end;
    case FCurr^ of
      '\':
        begin
          Inc(FCurr);
          if IsEof then raise EJsonTokenizerError.CreateFmt('Unterminated escape sequence at line %d, pos %d', [FLine, GetLinePos]);
          case FCurr^ of
            'u':
              begin
                if FEnd - FCurr < 5 then raise EJsonTokenizerError.CreateFmt('Incomplete unicode escape at line %d, pos %d', [FLine, GetLinePos]);
                if not (CharInSet(FCurr[1], ['0'..'9', 'a'..'f', 'A'..'F'])) or not (CharInSet(FCurr[2], ['0'..'9', 'a'..'f', 'A'..'F'])) or not (CharInSet(FCurr[3], ['0'..'9', 'a'..'f', 'A'..'F'])) or not (CharInSet(FCurr[4], ['0'..'9', 'a'..'f', 'A'..'F'])) then raise EJsonTokenizerError.CreateFmt('Invalid unicode escape at line %d, pos %d', [FLine, GetLinePos]);
                Inc(FCurr, 5);
              end;
            'x':
              begin
                if FEnd - FCurr < 3 then raise EJsonTokenizerError.CreateFmt('Incomplete hex escape at line %d, pos %d', [FLine, GetLinePos]);
                if not (CharInSet(FCurr[1], ['0'..'9', 'a'..'f', 'A'..'F'])) or not (CharInSet(FCurr[2], ['0'..'9', 'a'..'f', 'A'..'F'])) then raise EJsonTokenizerError.CreateFmt('Invalid hex escape at line %d, pos %d', [FLine, GetLinePos]);
                Inc(FCurr, 3);
              end;
            '0':
              begin
                Inc(FCurr);
                if not IsEof and (CharInSet(FCurr^, ['0'..'9'])) then raise EJsonTokenizerError.CreateFmt('Invalid escape sequence at line %d, pos %d', [FLine, GetLinePos]);
              end;
            '1'..'9':
              raise EJsonTokenizerError.CreateFmt('Invalid escape sequence at line %d, pos %d', [FLine, GetLinePos]);
            #13:
              begin
                Inc(FCurr);
                if not IsEof and (FCurr^ = #10) then Inc(FCurr);
                Inc(FLine);
                FLineStart := FCurr;
              end;
            #10, #$2028, #$2029:
              begin
                Inc(FCurr);
                Inc(FLine);
                FLineStart := FCurr;
              end;
          else
            Inc(FCurr);
          end;
        end;
      #10, #13: raise EJsonTokenizerError.CreateFmt('Line break in string at line %d, pos %d', [FLine, GetLinePos]);
    else
      Inc(FCurr);
    end;
  end;
  raise EJsonTokenizerError.CreateFmt('Unterminated string at line %d, pos %d', [FLine, GetLinePos]);
end;

procedure TJsonTokenizer.ParseNumber5;
var
  Start, Digits: PChar;
  IsNegative, Modified: Boolean;
  InputValue: UInt64;
  Digit: Integer;
  Sign, IntegerPart, FractionPart, Exponent: string;
begin
  Start := FCurr;
  IsNegative := False;
  Modified := False;
  if CharInSet(FCurr^, ['+', '-']) then
  begin
    IsNegative := FCurr^ = '-';
    Modified := not IsNegative;
    Inc(FCurr);
    if IsEof then raise EJsonTokenizerError.CreateFmt('Invalid number at line %d, pos %d', [FLine, GetLinePos]);
  end;
  if IsNegative then Sign := '-' else Sign := '';

  if MatchWord('Infinity') then
  begin
    FTokenType := TJsonToken.Float;
    SetNormalized(Sign + 'Infinity');
    Exit;
  end;
  if MatchWord('NaN') then
  begin
    FTokenType := TJsonToken.Float;
    SetNormalized('NaN');
    Exit;
  end;

  if (FCurr^ = '0') and (FCurr + 1 < FEnd) and (CharInSet(FCurr[1], ['x', 'X'])) then
  begin
    Inc(FCurr, 2);
    Digits := FCurr;
    InputValue := 0;
    while not IsEof do
    begin
      case FCurr^ of
        '0'..'9': Digit := Ord(FCurr^) - Ord('0');
        'a'..'f': Digit := Ord(FCurr^) - Ord('a') + 10;
        'A'..'F': Digit := Ord(FCurr^) - Ord('A') + 10;
      else
        Break;
      end;
      if InputValue > (High(UInt64) - UInt64(Digit)) div 16 then raise EJsonTokenizerError.CreateFmt('Hexadecimal number too large at line %d, pos %d', [FLine, GetLinePos]);
      InputValue := InputValue * 16 + UInt64(Digit);
      Inc(FCurr);
    end;
    if FCurr = Digits then raise EJsonTokenizerError.CreateFmt('Invalid hexadecimal number at line %d, pos %d', [FLine, GetLinePos]);
    FTokenType := TJsonToken.Integer;
    SetNormalized(Sign + UIntToStr(InputValue));
    Exit;
  end;

  Digits := FCurr;
  if FCurr^ = '0' then
  begin
    Inc(FCurr);
    if not IsEof and (CharInSet(FCurr^, ['0'..'9'])) then raise EJsonTokenizerError.CreateFmt('Leading zero in number at line %d, pos %d', [FLine, GetLinePos]);
  end
  else
    while not IsEof and (CharInSet(FCurr^, ['0'..'9'])) do Inc(FCurr);
  SetString(IntegerPart, Digits, NativeInt(FCurr - Digits));

  FTokenType := TJsonToken.Integer;
  FractionPart := '';
  if not IsEof and (FCurr^ = '.') then
  begin
    FTokenType := TJsonToken.Float;
    Inc(FCurr);
    Digits := FCurr;
    while not IsEof and (CharInSet(FCurr^, ['0'..'9'])) do Inc(FCurr);
    SetString(FractionPart, Digits, NativeInt(FCurr - Digits));
    if (IntegerPart = '') and (FractionPart = '') then raise EJsonTokenizerError.CreateFmt('Invalid number at line %d, pos %d', [FLine, GetLinePos]);
    if FractionPart = '' then
      Modified := True
    else
      FractionPart := '.' + FractionPart;
  end;
  if IntegerPart = '' then
  begin
    if FTokenType <> TJsonToken.Float then raise EJsonTokenizerError.CreateFmt('Invalid number at line %d, pos %d', [FLine, GetLinePos]);
    IntegerPart := '0';
    Modified := True;
  end;

  Exponent := '';
  if not IsEof and (CharInSet(FCurr^, ['e', 'E'])) then
  begin
    FTokenType := TJsonToken.Float;
    Digits := FCurr;
    Inc(FCurr);
    if not IsEof and (CharInSet(FCurr^, ['+', '-'])) then Inc(FCurr);
    if IsEof or not (CharInSet(FCurr^, ['0'..'9'])) then raise EJsonTokenizerError.CreateFmt('Invalid exponent at line %d, pos %d', [FLine, GetLinePos]);
    while not IsEof and (CharInSet(FCurr^, ['0'..'9'])) do Inc(FCurr);
    SetString(Exponent, Digits, NativeInt(FCurr - Digits));
  end;

  if Modified then
    SetNormalized(Sign + IntegerPart + FractionPart + Exponent)
  else
  begin
    FValueStart := Start;
    FValueLen := NativeInt(FCurr - Start);
  end;
end;

procedure TJsonTokenizer.ParseIdentifier5;
var
  Start: PChar;
  AWord: string;
begin
  Start := FCurr;
  Inc(FCurr);
  while not IsEof and IsIdentifierChar(FCurr^) do Inc(FCurr);
  FValueStart := Start;
  FValueLen := NativeInt(FCurr - Start);
  FIsIdentifier := True;
  SetString(AWord, Start, FValueLen);
  if (AWord = 'true') or (AWord = 'false') then FTokenType := TJsonToken.Boolean
  else if AWord = 'null' then FTokenType := TJsonToken.Null
  else if AWord = 'undefined' then FTokenType := TJsonToken.Undefined
  else if (AWord = 'Infinity') or (AWord = 'NaN') then FTokenType := TJsonToken.Float
  else FTokenType := TJsonToken.Str;
end;

procedure TJsonTokenizer.ParseString;
var
  Start: PChar;
  Escaped: Boolean;
begin
  Inc(FCurr);
  Start := FCurr;
  Escaped := False;
  while not IsEof do
  begin
    case FCurr^ of
      '"':
        begin
          FValueStart := Start;
          FValueLen := NativeInt(FCurr - Start);
          FTokenType := TJsonToken.Str;
          Inc(FCurr);
          Exit;
        end;
      '\':
        begin
          Escaped := True;
          Inc(FCurr);
          if IsEof then raise EJsonTokenizerError.CreateFmt('Unterminated escape sequence at line %d, pos %d', [FLine, GetLinePos]);
          case FCurr^ of
            '"', '\', '/', 'b', 'f', 'n', 'r', 't': Inc(FCurr);
            'u':
              begin
                if FEnd - FCurr < 5 then raise EJsonTokenizerError.CreateFmt('Incomplete unicode escape at line %d, pos %d', [FLine, GetLinePos]);
                if not (CharInSet(FCurr[1], ['0'..'9', 'a'..'f', 'A'..'F'])) or not (CharInSet(FCurr[2], ['0'..'9', 'a'..'f', 'A'..'F'])) or not (CharInSet(FCurr[3], ['0'..'9', 'a'..'f', 'A'..'F'])) or not (CharInSet(FCurr[4], ['0'..'9', 'a'..'f', 'A'..'F'])) then raise EJsonTokenizerError.CreateFmt('Invalid unicode escape at line %d, pos %d', [FLine, GetLinePos]);
                Inc(FCurr, 5);
              end;
          else
            raise EJsonTokenizerError.CreateFmt('Invalid escape sequence at line %d, pos %d', [FLine, GetLinePos]);
          end;
        end;
      #0..#31: raise EJsonTokenizerError.CreateFmt('Control character in string at line %d, pos %d', [FLine, GetLinePos]);
    else
      Inc(FCurr);
    end;
  end;
  if Escaped then
    raise EJsonTokenizerError.CreateFmt('Unterminated escaped string at line %d, pos %d', [FLine, GetLinePos])
  else
    raise EJsonTokenizerError.CreateFmt('Unterminated string at line %d, pos %d', [FLine, GetLinePos]);
end;

procedure TJsonTokenizer.ParseNumber;
var
  Start: PChar;
begin
  Start := FCurr;
  if FCurr^ = '-' then
  begin
    Inc(FCurr);
    if IsEof then raise EJsonTokenizerError.CreateFmt('Invalid number at line %d, pos %d', [FLine, GetLinePos]);
  end;
  if FCurr^ = '0' then
  begin
    Inc(FCurr);
    if not IsEof and (CharInSet(FCurr^, ['0'..'9'])) then raise EJsonTokenizerError.CreateFmt('Leading zero in number at line %d, pos %d', [FLine, GetLinePos]);
  end
  else if CharInSet(FCurr^, ['1'..'9']) then
  begin
    repeat Inc(FCurr) until IsEof or not (CharInSet(FCurr^, ['0'..'9']));
  end
  else
    raise EJsonTokenizerError.CreateFmt('Invalid number at line %d, pos %d', [FLine, GetLinePos]);

  FTokenType := TJsonToken.Integer;
  if not IsEof and (FCurr^ = '.') then
  begin
    FTokenType := TJsonToken.Float;
    Inc(FCurr);
    if IsEof or not (CharInSet(FCurr^, ['0'..'9'])) then raise EJsonTokenizerError.CreateFmt('Invalid fraction at line %d, pos %d', [FLine, GetLinePos]);
    repeat Inc(FCurr) until IsEof or not (CharInSet(FCurr^, ['0'..'9']));
  end;

  if not IsEof and (CharInSet(FCurr^, ['e', 'E'])) then
  begin
    FTokenType := TJsonToken.Float;
    Inc(FCurr);
    if not IsEof and (CharInSet(FCurr^, ['+', '-'])) then Inc(FCurr);
    if IsEof or not (CharInSet(FCurr^, ['0'..'9'])) then raise EJsonTokenizerError.CreateFmt('Invalid exponent at line %d, pos %d', [FLine, GetLinePos]);
    repeat Inc(FCurr) until IsEof or not (CharInSet(FCurr^, ['0'..'9']));
  end;

  FValueStart := Start;
  FValueLen := NativeInt(FCurr - Start);
end;

procedure TJsonTokenizer.ParseLiteral(const Literal: string; Token: TJsonToken);
var
  I: Integer;
begin
  if FEnd - FCurr < Length(Literal) then raise EJsonTokenizerError.CreateFmt('Invalid token at line %d, pos %d', [FLine, GetLinePos]);
  for I := 1 to Length(Literal) do
    if FCurr[I - 1] <> Literal[I] then raise EJsonTokenizerError.CreateFmt('Invalid token at line %d, pos %d', [FLine, GetLinePos]);
  FValueStart := FCurr;
  FValueLen := Length(Literal);
  Inc(FCurr, Length(Literal));
  if not IsEof and (CharInSet(FCurr^, ['A'..'Z', 'a'..'z', '0'..'9', '_'])) then raise EJsonTokenizerError.CreateFmt('Invalid token boundary at line %d, pos %d', [FLine, GetLinePos]);
  FTokenType := Token;
end;

procedure TJsonTokenizer.ParseComment;
var
  Start: PChar;
begin
  Inc(FCurr);
  if IsEof then raise EJsonTokenizerError.CreateFmt('Invalid comment at line %d, pos %d', [FLine, GetLinePos]);
  if FCurr^ = '/' then
  begin
    Inc(FCurr);
    Start := FCurr;
    while not IsEof and not (CharInSet(FCurr^, [#10, #13])) do Inc(FCurr);
    FValueStart := Start;
    FValueLen := NativeInt(FCurr - Start);
    FTokenType := TJsonToken.Comment;
    Exit;
  end;
  if FCurr^ <> '*' then raise EJsonTokenizerError.CreateFmt('Invalid comment at line %d, pos %d', [FLine, GetLinePos]);
  Inc(FCurr);
  Start := FCurr;
  while not IsEof do
  begin
    if (FCurr^ = '*') and (FCurr + 1 < FEnd) and (FCurr[1] = '/') then
    begin
      FValueStart := Start;
      FValueLen := NativeInt(FCurr - Start);
      Inc(FCurr, 2);
      FTokenType := TJsonToken.Comment;
      Exit;
    end;
    if FCurr^ = #10 then
    begin
      Inc(FCurr);
      Inc(FLine);
      FLineStart := FCurr;
    end
    else if FCurr^ = #13 then
    begin
      Inc(FCurr);
      if not IsEof and (FCurr^ = #10) then Inc(FCurr);
      Inc(FLine);
      FLineStart := FCurr;
    end
    else
      Inc(FCurr);
  end;
  raise EJsonTokenizerError.CreateFmt('Unterminated comment at line %d, pos %d', [FLine, GetLinePos]);
end;

function TJsonTokenizer.Read: Boolean;
begin
  FTokenType := TJsonToken.None;
  FValueStart := nil;
  FValueLen := 0;
  FIsIdentifier := False;
  SkipWhitespace;
  if IsEof then Exit(False);
  if FJson5 then
  begin
    case FCurr^ of
      '"', '''': begin ParseString5(FCurr^); Exit(True); end;
      '-', '+', '.', '0'..'9': begin ParseNumber5; Exit(True); end;
    else
      if IsIdentifierStart(FCurr^) then
      begin
        ParseIdentifier5;
        Exit(True);
      end;
    end;
  end;
  case FCurr^ of
    '{': begin FTokenType := TJsonToken.StartObject; Inc(FCurr); end;
    '}': begin FTokenType := TJsonToken.EndObject; Inc(FCurr); end;
    '[': begin FTokenType := TJsonToken.StartArray; Inc(FCurr); end;
    ']': begin FTokenType := TJsonToken.EndArray; Inc(FCurr); end;
    ',': begin FTokenType := TJsonToken.Comma; Inc(FCurr); end;
    ':': begin FTokenType := TJsonToken.Colon; Inc(FCurr); end;
    '"': ParseString;
    '-', '0'..'9': ParseNumber;
    't': ParseLiteral('true', TJsonToken.Boolean);
    'f': ParseLiteral('false', TJsonToken.Boolean);
    'n': ParseLiteral('null', TJsonToken.Null);
    'u': ParseLiteral('undefined', TJsonToken.Undefined);
    '/': ParseComment;
  else
    raise EJsonTokenizerError.CreateFmt('Invalid character "%s" at line %d, pos %d', [FCurr^, FLine, GetLinePos]);
  end;
  Result := True;
end;

end.
