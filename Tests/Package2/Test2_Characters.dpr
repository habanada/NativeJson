{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Test2_Characters;

{$I NativeJson.inc}

// TEST PACKAGE 2 - Strings, escaping, encoding
//
//   The output path escapes while writing into its own byte buffer.
//   Both are about characters. That is exactly why it is tested.

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  Rtti,
  Demo.Assert in '..\..\examples\Demos\Demo.Assert.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Dom.Value,
  NativeJson.Serializer.Writer;

type
  TText = class
  private
    FValue: string;
  public
    property Val: string read FValue write FValue;
  end;

const
  Smiley = #$D83D#$DE00;
  Umlauts = 'Gr' + #$00FC + #$00DF + 'e';
  Euro = #$20AC;
  Chinese = #$4E2D + #$6587;

function RoundTrip(const Input: string; out Json: string): string;
var
  T, K: TText;
begin
  T := TText.Create;
  try
    T.Val := Input;
    Json := JsonConvert.SerializeObject(T);
  finally
    T.Free;
  end;
  K := JsonConvert.DeserializeObject<TText>(Json);
  try
    Result := K.Val;
  finally
    K.Free;
  end;
end;

procedure CheckChars(const Name, Input, ExpectedJsonPart: string);
var
  Json, Back: string;
begin
  Back := RoundTrip(Input, Json);
  if ExpectedJsonPart <> '' then
    CheckContains(Name + ' written', ExpectedJsonPart, Json);
  CheckTrue(Name + ' comes back unchanged', Back = Input,
    Format('%d chars back, %d expected', [Length(Back), Length(Input)]));
end;

// ---------------------------------------------------------------------------

procedure Step1_Escaping;
begin
  Section('1. The seven characters that must be escaped');
  CheckChars('Quote', 'a"b', '"a\"b"');
  CheckChars('Backslash', 'a\b', '"a\\b"');
  CheckChars('Line feed', 'a' + #10 + 'b', '"a\nb"');
  CheckChars('Carriage return', 'a' + #13 + 'b', '"a\rb"');
  CheckChars('Tab', 'a' + #9 + 'b', '"a\tb"');
  CheckChars('Backspace', 'a' + #8 + 'b', '"a\bb"');
  CheckChars('Form feed', 'a' + #12 + 'b', '"a\fb"');
end;

procedure Step2_ControlChars;
begin
  Section('2. Control characters as \u sequence');
  // The hex digits are written in upper case - IntToHex returns upper case letters.
  CheckChars('Null character', 'a' + #0 + 'b', '"a' + '\' + 'u0000b"');
  CheckChars('Control character 1', 'a' + #1 + 'b', '"a' + '\' + 'u0001b"');
  CheckChars('Control character 31', 'a' + #31 + 'b', '"a' + '\' + 'u001Fb"');
  Writeln('       From character 32 on nothing is escaped.');
  CheckChars('Space stays', 'a b', '"a b"');
end;

procedure Step3_Unicode;
var
  Json, Back: string;
begin
  Section('3. Umlauts, CJK and surrogate pairs');
  // The comparison goes through the round trip, not through the console -
  // depending on the code page it shows question marks without anything being broken.
  CheckChars('Umlauts', Umlauts, Umlauts);
  CheckChars('Euro sign', 'Price ' + Euro, Euro);
  CheckChars('CJK', 'CJK: ' + Chinese, Chinese);

  // An emoji is one code point made of two UTF-16 units. This is exactly
  // where the byte buffer stumbled when splitting into chunks.
  Back := RoundTrip(Smiley, Json);
  CheckTrue('Surrogate pair stays intact', Back = Smiley,
    Format('%d units', [Length(Back)]));
  CheckTrue('Emoji is not escaped', Pos('\u', Json) = 0, Json);
end;

// The string route uses a TStringWriter. The own UTF-8 byte buffer
// is only created in the stream constructor - so it is only reached
// via SerializeToBytes. Without this function the long
// strings only test the escaper, not the buffer.
function RoundTripViaBytes(const Input: string; out Bytes: Integer): string;
var
  T, K: TText;
  RawData: TBytes;
begin
  T := TText.Create;
  try
    T.Val := Input;
    RawData := JsonConvert.SerializeToBytes(T);
  finally
    T.Free;
  end;
  Bytes := Length(RawData);
  K := JsonConvert.DeserializeFromBytes<TText>(RawData);
  try
    Result := K.Val;
  finally
    K.Free;
  end;
end;

procedure Step4_LongStrings;
var
  Long, Json, Back: string;
  I: Integer;
  Sb: TStringBuilder;
begin
  Section('4. Length above the chunk limits');
  Writeln('       The escaper collects runs up to 16384 chars, the');
  Writeln('       byte buffer splits at capacity divided by 3. Both limits');
  Writeln('       must be exceeded.');

  Sb := TStringBuilder.Create;
  try
    for I := 1 to 20000 do Sb.Append('x');
    Long := Sb.ToString;
  finally
    Sb.Free;
  end;
  Back := RoundTrip(Long, Json);
  CheckTrue('20000 chars without special characters', Back = Long,
    Format('%d back', [Length(Back)]));

  // Now with emojis across the chunk limits. If a surrogate pair
  // is cut there, question marks come back.
  Sb := TStringBuilder.Create;
  try
    for I := 1 to 9000 do Sb.Append(Smiley);
    Long := Sb.ToString;
  finally
    Sb.Free;
  end;
  Back := RoundTrip(Long, Json);
  CheckTrue('9000 emojis survive the chunk limits', Back = Long,
    Format('%d units back, %d expected', [Length(Back), Length(Long)]));

  // And the same length with escaping needed in the middle.
  Sb := TStringBuilder.Create;
  try
    for I := 1 to 5000 do Sb.Append('ab"cd\ef');
    Long := Sb.ToString;
  finally
    Sb.Free;
  end;
  Back := RoundTrip(Long, Json);
  CheckTrue('40000 chars with escaping', Back = Long,
    Format('%d back, %d expected', [Length(Back), Length(Long)]));
end;

procedure Step4b_ByteBuffer;
var
  Long, Back: string;
  I, Bytes: Integer;
  Sb: TStringBuilder;
begin
  Section('4b. The same text through the UTF-8 byte buffer');
  Writeln('       SerializeObject uses a TStringWriter. Only the');
  Writeln('       byte and stream route goes through TJsonByteOutput.');

  // Odd start length so that the surrogate pairs do NOT sit on even
  // multiples and the chunk limit really falls right into them.
  Sb := TStringBuilder.Create;
  try
    Sb.Append('x');
    for I := 1 to 60000 do Sb.Append(Smiley);
    Long := Sb.ToString;
  finally
    Sb.Free;
  end;

  Back := RoundTripViaBytes(Long, Bytes);
  Show('Output', Format('%d bytes UTF-8', [Bytes]));
  CheckTrue('60000 emojis with odd offset', Back = Long,
    Format('%d units back, %d expected', [Length(Back), Length(Long)]));

  Sb := TStringBuilder.Create;
  try
    for I := 1 to 5000 do Sb.Append('ab"cd' + '\' + 'ef' + Umlauts);
    Long := Sb.ToString;
  finally
    Sb.Free;
  end;
  Back := RoundTripViaBytes(Long, Bytes);
  CheckTrue('Escaping and umlauts through the buffer', Back = Long,
    Format('%d back, %d expected', [Length(Back), Length(Long)]));
end;

procedure Step5_IncomingEscaping;
var
  T: TText;
begin
  Section('5. Incoming \u sequences must be decoded');
  // Deliberately REAL escape sequences in the JSON here, not already
  // decoded characters - otherwise the test does not check the decoder at all.

  T := JsonConvert.DeserializeObject<TText>('{"Val":"a\u0041b"}');
  try
    Check('Upper case hex digits', 'aAb', T.Val);
  finally
    T.Free;
  end;

  T := JsonConvert.DeserializeObject<TText>('{"Val":"a\u00FCb"}');
  try
    Check('Lower case hex digits', 'a' + #$00FC + 'b', T.Val);
  finally
    T.Free;
  end;

  // An emoji as two separate \u sequences - the pair must be
  // put back together.
  T := JsonConvert.DeserializeObject<TText>('{"Val":"\uD83D\uDE00"}');
  try
    CheckTrue('Surrogate pair from two \u sequences', T.Val = Smiley,
      Format('%d units', [Length(T.Val)]));
  finally
    T.Free;
  end;

  T := JsonConvert.DeserializeObject<TText>('{"Val":"Line1\nLine2"}');
  try
    CheckTrue('\n becomes a line feed', Pos(#10, T.Val) > 0,
      IntToStr(Length(T.Val)));
  finally
    T.Free;
  end;

  // The escaped slash is allowed, but not required.
  T := JsonConvert.DeserializeObject<TText>('{"Val":"a\/b"}');
  try
    Check('Escaped slash', 'a/b', T.Val);
  finally
    T.Free;
  end;
end;

procedure Step6_KeysWithSpecialChars;
var
  Dom: TJsonValue;
begin
  Section('6. Special characters in the key name');
  Dom := JsonConvert.DeserializeObject(
    '{"with\"quote":1,"with\\slash":2,"with space":3}');
  try
    CheckTrue('All three keys found',
      (Dom.Values['with"quote'] <> nil) and
      (Dom.Values['with\slash'] <> nil) and
      (Dom.Values['with space'] <> nil), '');
    CheckContains('and escaped again when writing', 'with\"quote', Dom.ToJson);
  finally
    Dom.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('TEST PACKAGE 2 - CHARACTERS AND ESCAPING');

    Step1_Escaping;
    Step2_ControlChars;
    Step3_Unicode;
    Step4_LongStrings;
    Step4b_ByteBuffer;
    Step5_IncomingEscaping;
    Step6_KeysWithSpecialChars;

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
