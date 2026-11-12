{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Pointer;

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
  /// <summary>Error in the syntax or resolution of a JSON Pointer (RFC 6901).</summary>
  EJsonPointerError = class(EJsonValueError);

  /// <summary>
  ///   RFC 6901 JSON Pointer for the NativeJson DOM.
  ///   The methods work with the string representation ("/a/0/b"),
  ///   not with the URI fragment representation ("#/a/0/b").
  /// </summary>
  TJsonPointer = class abstract
  private
    class function TryDecodeToken(const Encoded: string; out Decoded: string): Boolean; static;
    class function TryParseArrayIndex(const Token: string; out Index: Integer): Boolean; static;
    class function TryResolveCore(Root: TJsonValue; const JsonPointer: string;
      StopBeforeLast: Boolean; out Value: TJsonValue; out LastToken,
      ErrorMessage: string): Boolean; static;
  public
    /// <summary>Escapes exactly one reference token: "~" -> "~0", "/" -> "~1".</summary>
    class function Escape(const Value: string): string; static;

    /// <summary>
    ///   Decodes exactly one reference token. Invalid "~" sequences
    ///   raise EJsonPointerError.
    /// </summary>
    class function Unescape(const Value: string): string; static;

    /// <summary>Non-raising variant of Unescape.</summary>
    class function TryUnescape(const Value: string; out Decoded: string): Boolean; static;

    /// <summary>
    ///   Resolves a JSON Pointer against Root. The empty pointer denotes Root.
    ///   On errors EJsonPointerError is raised.
    /// </summary>
    class function Resolve(Root: TJsonValue; const JsonPointer: string): TJsonValue; static;

    /// <summary>
    ///   Non-raising variant of Resolve. On error Value = nil.
    /// </summary>
    class function TryResolve(Root: TJsonValue; const JsonPointer: string;
      out Value: TJsonValue): Boolean; static;

    /// <summary>
    ///   Resolves the parent value of the last token and returns the last token
    ///   already RFC 6901 decoded. The empty pointer has no parent.
    ///   The last token itself is not resolved; that way e.g. "/items/-"
    ///   can be used correctly for later JSON Patch operations.
    /// </summary>
    class function ResolveParent(Root: TJsonValue; const JsonPointer: string;
      out Token: string): TJsonValue; static;

    /// <summary>Non-raising variant of ResolveParent.</summary>
    class function TryResolveParent(Root: TJsonValue; const JsonPointer: string;
      out Parent: TJsonValue; out Token: string): Boolean; static;
  end;

implementation

uses
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.JsonArray;

class function TJsonPointer.Escape(const Value: string): string;
begin
  Result := StringReplace(Value, '~', '~0', [rfReplaceAll]);
  Result := StringReplace(Result, '/', '~1', [rfReplaceAll]);
end;

class function TJsonPointer.TryDecodeToken(const Encoded: string;
  out Decoded: string): Boolean;
var
  I, StartPos: Integer;
  Builder: TStringBuilder;
begin
  Decoded := '';
  I := Pos('~', Encoded);
  if I = 0 then
  begin
    Decoded := Encoded;
    Exit(True);
  end;

  Result := False;
  Builder := TStringBuilder.Create;
  try
    StartPos := 1;
    I := 1;
    while I <= Length(Encoded) do
    begin
      if Encoded[I] <> '~' then
      begin
        Inc(I);
        Continue;
      end;

      Builder.Append(Copy(Encoded, StartPos, I - StartPos));
      if I = Length(Encoded) then Exit;

      case Encoded[I + 1] of
        '0': Builder.Append('~');
        '1': Builder.Append('/');
      else
        Exit;
      end;

      Inc(I, 2);
      StartPos := I;
    end;

    Builder.Append(Copy(Encoded, StartPos, MaxInt));
    Decoded := Builder.ToString;
    Result := True;
  finally
    Builder.Free;
  end;
end;

class function TJsonPointer.TryUnescape(const Value: string;
  out Decoded: string): Boolean;
begin
  Result := TryDecodeToken(Value, Decoded);
end;

class function TJsonPointer.Unescape(const Value: string): string;
begin
  if not TryDecodeToken(Value, Result) then
    raise EJsonPointerError.CreateFmt(
      'Invalid JSON Pointer escape sequence in token "%s"', [Value]);
end;

class function TJsonPointer.TryParseArrayIndex(const Token: string;
  out Index: Integer): Boolean;
var
  I: Integer;
begin
  Index := -1;
  if Token = '' then Exit(False);

  // RFC 6901: array-index = %x30 / (%x31-39 *(%x30-39))
  if Token = '0' then
  begin
    Index := 0;
    Exit(True);
  end;

  if Token[1] = '0' then Exit(False);
  for I := 1 to Length(Token) do
    if not CharInSet(Token[I], ['0'..'9']) then Exit(False);

  Result := TryStrToInt(Token, Index);
  if not Result then Index := -1;
end;

class function TJsonPointer.TryResolveCore(Root: TJsonValue;
  const JsonPointer: string; StopBeforeLast: Boolean; out Value: TJsonValue;
  out LastToken, ErrorMessage: string): Boolean;
var
  Current, Next: TJsonValue;
  EncodedToken, Token: string;
  SegmentStart, SegmentEnd, SegmentIndex, ArrayIndex: Integer;
  IsLast: Boolean;
begin
  Result := False;
  Value := nil;
  LastToken := '';
  ErrorMessage := '';

  if Root = nil then
  begin
    ErrorMessage := 'JSON Pointer root must not be nil';
    Exit;
  end;

  if JsonPointer = '' then
  begin
    if StopBeforeLast then
    begin
      ErrorMessage := 'The empty JSON Pointer identifies the root and has no parent';
      Exit;
    end;
    Value := Root;
    Exit(True);
  end;

  if JsonPointer[1] <> '/' then
  begin
    ErrorMessage := 'A non-empty JSON Pointer must start with "/"';
    Exit;
  end;

  Current := Root;
  SegmentStart := 2;
  SegmentIndex := 0;

  // <= Length + 1 is intentional: for "/" and for a trailing
  // slash there is an empty reference token that must not get lost.
  while SegmentStart <= Length(JsonPointer) + 1 do
  begin
    SegmentEnd := SegmentStart;
    while (SegmentEnd <= Length(JsonPointer)) and
      (JsonPointer[SegmentEnd] <> '/') do
      Inc(SegmentEnd);

    EncodedToken := Copy(JsonPointer, SegmentStart, SegmentEnd - SegmentStart);
    if not TryDecodeToken(EncodedToken, Token) then
    begin
      ErrorMessage := Format('Invalid JSON Pointer escape sequence at token %d',
        [SegmentIndex]);
      Exit;
    end;

    IsLast := SegmentEnd > Length(JsonPointer);
    if StopBeforeLast and IsLast then
    begin
      if not ((Current is TJsonObject) or (Current is TJsonArray)) then
      begin
        ErrorMessage := Format(
          'JSON Pointer parent at token %d is not an object or array',
          [SegmentIndex]);
        Exit;
      end;
      Value := Current;
      LastToken := Token;
      Exit(True);
    end;

    if Current is TJsonObject then
    begin
      if not TJsonObject(Current).TryGetValue(Token, Next) then
      begin
        ErrorMessage := Format(
          'JSON Pointer member "%s" was not found at token %d',
          [Token, SegmentIndex]);
        Exit;
      end;
      Current := Next;
    end
    else if Current is TJsonArray then
    begin
      if Token = '-' then
      begin
        ErrorMessage := Format(
          'JSON Pointer token "-" does not identify an existing array element at token %d',
          [SegmentIndex]);
        Exit;
      end;

      if not TryParseArrayIndex(Token, ArrayIndex) then
      begin
        ErrorMessage := Format(
          'Invalid JSON Pointer array index "%s" at token %d',
          [Token, SegmentIndex]);
        Exit;
      end;

      if ArrayIndex >= TJsonArray(Current).Count then
      begin
        ErrorMessage := Format(
          'JSON Pointer array index %d is out of range at token %d',
          [ArrayIndex, SegmentIndex]);
        Exit;
      end;

      Current := TJsonArray(Current)[ArrayIndex];
    end
    else
    begin
      ErrorMessage := Format(
        'JSON Pointer cannot traverse a scalar value at token %d',
        [SegmentIndex]);
      Exit;
    end;

    Inc(SegmentIndex);
    SegmentStart := SegmentEnd + 1;
  end;

  Value := Current;
  Result := True;
end;

class function TJsonPointer.TryResolve(Root: TJsonValue;
  const JsonPointer: string; out Value: TJsonValue): Boolean;
var
  LastToken, ErrorMessage: string;
begin
  Result := TryResolveCore(Root, JsonPointer, False, Value, LastToken,
    ErrorMessage);
  if not Result then Value := nil;
end;

class function TJsonPointer.Resolve(Root: TJsonValue;
  const JsonPointer: string): TJsonValue;
var
  LastToken, ErrorMessage: string;
begin
  if not TryResolveCore(Root, JsonPointer, False, Result, LastToken,
    ErrorMessage) then
    raise EJsonPointerError.Create(ErrorMessage);
end;

class function TJsonPointer.TryResolveParent(Root: TJsonValue;
  const JsonPointer: string; out Parent: TJsonValue; out Token: string): Boolean;
var
  ErrorMessage: string;
begin
  Result := TryResolveCore(Root, JsonPointer, True, Parent, Token,
    ErrorMessage);
  if not Result then
  begin
    Parent := nil;
    Token := '';
  end;
end;

class function TJsonPointer.ResolveParent(Root: TJsonValue;
  const JsonPointer: string; out Token: string): TJsonValue;
var
  ErrorMessage: string;
begin
  if not TryResolveCore(Root, JsonPointer, True, Result, Token,
    ErrorMessage) then
    raise EJsonPointerError.Create(ErrorMessage);
end;

end.
