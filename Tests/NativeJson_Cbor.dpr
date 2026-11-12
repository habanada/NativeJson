{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_Cbor;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  NativeJson.Compat,
  Demo.Assert in '..\examples\Demos\Demo.Assert.pas',
  NativeJson.Dom.Value,
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.Primitive,
  NativeJson.Dom.Io,
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.FloatText,
  NativeJson.Cbor,
  NativeJson.Cbor.Convert;

type
  TUser = class
  private
    FName: string;
    FAge: Integer;
    FBalance: Currency;
    FPhoto: TBytes;
  public
    [JsonProperty('full_name')]
    property Name: string read FName write FName;
    property Age: Integer read FAge write FAge;
    property Balance: Currency read FBalance write FBalance;
    property Photo: TBytes read FPhoto write FPhoto;
  end;

function Normalized(const Json: string): string;
var
  Dom: TJsonValue;
begin
  Dom := DomFromText(Json);
  try
    Result := DomToText(Dom);
  finally
    Dom.Free;
  end;
end;

function Dec(const Hex: string; Options: TJsonCborOptions = nil): string;
begin
  Result := CborToJson(CborFromHex(Hex), Options);
end;

function Enc(const Json: string; Options: TJsonCborOptions = nil): string;
begin
  Result := CborToHex(JsonToCbor(Json, Options));
end;

function DecodedDouble(const Hex: string): Double;
var
  Dom: TJsonValue;
begin
  Dom := CborToDom(CborFromHex(Hex));
  try
    Result := Dom.AsDouble;
  finally
    Dom.Free;
  end;
end;

function EncodeError(const Json: string; Options: TJsonCborOptions): string;
begin
  Result := '';
  try
    Enc(Json, Options);
  except
    on E: EJsonCborError do Result := E.Message;
  end;
end;

function ErrorOf(const Hex: string; Options: TJsonCborOptions = nil): string;
begin
  Result := '';
  try
    Dec(Hex, Options);
  except
    on E: EJsonCborError do Result := E.Message;
  end;
end;

procedure Step1_Integers;
begin
  Section('1. Integers (RFC 8949 Appendix A)');
  Check('0', '0', Dec('00'));
  Check('1', '1', Dec('01'));
  Check('10', '10', Dec('0a'));
  Check('23', '23', Dec('17'));
  Check('24', '24', Dec('1818'));
  Check('25', '25', Dec('1819'));
  Check('100', '100', Dec('1864'));
  Check('1000', '1000', Dec('1903e8'));
  Check('1000000', '1000000', Dec('1a000f4240'));
  Check('10^12', '1000000000000', Dec('1b000000e8d4a51000'));
  Check('2^64-1', '18446744073709551615', Dec('1bffffffffffffffff'));
  Check('2^64 as bignum', '18446744073709551616', Dec('c249010000000000000000'));
  Check('-2^64', '-18446744073709551616', Dec('3bffffffffffffffff'));
  Check('-2^64-1 as bignum', '-18446744073709551617', Dec('c349010000000000000000'));
  Check('-1', '-1', Dec('20'));
  Check('-10', '-10', Dec('29'));
  Check('-100', '-100', Dec('3863'));
  Check('-1000', '-1000', Dec('3903e7'));
  Check('Empty bignum is 0', '0', Dec('c240'));
  Check('Empty negative bignum is -1', '-1', Dec('c340'));

  Check('Encode 0', '00', Enc('0'));
  Check('Encode 23', '17', Enc('23'));
  Check('Encode 24', '1818', Enc('24'));
  Check('Encode 255', '18ff', Enc('255'));
  Check('Encode 256', '190100', Enc('256'));
  Check('Encode 65536', '1a00010000', Enc('65536'));
  Check('Encode 10^12', '1b000000e8d4a51000', Enc('1000000000000'));
  Check('Encode 2^64-1', '1bffffffffffffffff', Enc('18446744073709551615'));
  Check('Encode 2^64 as bignum', 'c249010000000000000000', Enc('18446744073709551616'));
  Check('Encode -1', '20', Enc('-1'));
  Check('Encode -1000', '3903e7', Enc('-1000'));
  Check('Encode -2^64', '3bffffffffffffffff', Enc('-18446744073709551616'));
  Check('Encode -2^64-1 as bignum', 'c349010000000000000000', Enc('-18446744073709551617'));
  Check('Encode 100 digits', Dec(Enc('1' + StringOfChar('0', 99))), '1' + StringOfChar('0', 99));
end;

procedure Step2_Floats;
begin
  Section('2. Floats and preferred serialization');
  Check('0.0', '0.0', Dec('f90000'));
  Check('-0.0', '-0.0', Dec('f98000'));
  Check('1.0', '1.0', Dec('f93c00'));
  Check('1.5', '1.5', Dec('f93e00'));
  Check('65504.0', '65504.0', Dec('f97bff'));
  Check('Half precision subnormal', 5.9604644775390625E-8, DecodedDouble('f90001'), 0);
  Check('Shortest text, 16 digits', '-8.584287591200702E-15', Dec('fbbd03548140000000'));
  Check('Shortest text at a power of two', '5.960464477539063E-' + {$IFDEF FPC}'8'{$ELSE}'08'{$ENDIF}, Dec('fb3e70000000000000'));
  Check('Shortest text, smallest subnormal', '5E-324', Dec('fb0000000000000001'));
  Check('Shortest text, 16 digits fraction', '0.8907681278553053', Dec('fb3fec812c292ea557'));
  Check('Half precision smallest normal', 0.00006103515625, DecodedDouble('f90400'), 0);
  Check('-4.0', '-4.0', Dec('f9c400'));
  Check('1.1', '1.1', Dec('fb3ff199999999999a'));
  Check('-4.1', '-4.1', Dec('fbc010666666666666'));
  Check('Single 100000.0', '100000.0', Dec('fa47c35000'));
  Check('Single maximum', 3.4028234663852886E38, DecodedDouble('fa7f7fffff'), 0);
  Check('Double 1.0e300', 1.0E300, DecodedDouble('fb7e37e43c8800759c'), 0);
  Check('Single keeps its exact value', 0.10000000149011612, DecodedDouble('fa3dcccccd'), 0);

  Check('Encode 1.5 as half', 'f93e00', Enc('1.5'));
  Check('Encode 0.0 as half', 'f90000', Enc('0.0'));
  Check('Encode -0.0 as half', 'f98000', Enc('-0.0'));
  Check('Encode 1.0 stays a float', 'f93c00', Enc('1.0'));
  Check('Encode 65504.0 as half', 'f97bff', Enc('65504.0'));
  Check('Encode 100000.0 as single', 'fa47c35000', Enc('100000.0'));
  Check('Encode 5.960464477539063e-8 as half', 'f90001', Enc('5.960464477539063e-8'));
  Check('Encode 0.00006103515625 as half', 'f90400', Enc('0.00006103515625'));
  Check('Encode 1.1 as double', 'fb3ff199999999999a', Enc('1.1'));
  Check('Encode -4.1 as double', 'fbc010666666666666', Enc('-4.1'));
  Check('Encode 3.4028234663852886e38 as single', 'fa7f7fffff', Enc('3.4028234663852886e38'));
  Check('Encode 1.0e300 as double', 'fb7e37e43c8800759c', Enc('1.0e300'));
  Check('Encode 0.1 as double', 'fb3fb999999999999a', Enc('0.1'));

  Check('Double text survives a round trip', '0.30000000000000004', Dec(Enc('0.30000000000000004')));
  Check('Integer and float stay different',
    '[1,1.0]', Dec(Enc('[1,1.0]')));
end;

procedure Step3_SimpleAndStrings;
begin
  Section('3. Simple values, strings, bytes');
  Check('false', 'false', Dec('f4'));
  Check('true', 'true', Dec('f5'));
  Check('null', 'null', Dec('f6'));
  Check('undefined becomes null', 'null', Dec('f7'));
  Check('Encode false', 'f4', Enc('false'));
  Check('Encode true', 'f5', Enc('true'));
  Check('Encode null', 'f6', Enc('null'));

  Check('Empty string', '""', Dec('60'));
  Check('a', '"a"', Dec('6161'));
  Check('IETF', '"IETF"', Dec('6449455446'));
  Check('Quote and backslash', '"\"\\"', Dec('62225c'));
  Check('U+00FC', '"' + #$FC + '"', Dec('62c3bc'));
  Check('U+6C34', '"' + Char($6C34) + '"', Dec('63e6b0b4'));
  Check('U+10151 as surrogate pair', '"' + Char($D800) + Char($DD51) + '"', Dec('64f0908591'));
  Check('Encode IETF', '6449455446', Enc('"IETF"'));
  Check('Encode U+00FC', '62c3bc', Enc('"' + #$FC + '"'));
  Check('Encode U+10151', '64f0908591', Enc('"' + Char($D800) + Char($DD51) + '"'));
  Check('Encode empty string', '60', Enc('""'));
  Check('Long string head', '7818', Copy(Enc('"' + StringOfChar('x', 24) + '"'), 1, 4));

  Check('Empty byte string', '""', Dec('40'));
  Check('Bytes as Base64Url', '"AQIDBA"', Dec('4401020304'));
  Check('Bytes with url-unsafe alphabet', '"-_8"', Dec('42fbff'));
end;

procedure Step4_Containers;
begin
  Section('4. Arrays and maps');
  Check('Empty array', '[]', Dec('80'));
  Check('[1,2,3]', '[1,2,3]', Dec('83010203'));
  Check('Nested', '[1,[2,3],[4,5]]', Dec('8301820203820405'));
  Check('25 items', '[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]',
    Dec('98190102030405060708090a0b0c0d0e0f101112131415161718181819'));
  Check('Empty map', '{}', Dec('a0'));
  Check('Integer keys become text', '{"1":2,"3":4}', Dec('a201020304'));
  Check('{"a":1,"b":[2,3]}', '{"a":1,"b":[2,3]}', Dec('a26161016162820203'));
  Check('["a",{"b":"c"}]', '["a",{"b":"c"}]', Dec('826161a161626163'));
  Check('Five entries', '{"a":"A","b":"B","c":"C","d":"D","e":"E"}',
    Dec('a56161614161626142616361436164614461656145'));
  Check('Boolean key', '{"true":1}', Dec('a1f501'));
  Check('Null key', '{"null":1}', Dec('a1f601'));
  Check('Float key', '{"1.5":1}', Dec('a1f93e0001'));
  Check('Byte string key', '{"AQI":1}', Dec('a1420102' + '01'));

  Check('Encode array', '83010203', Enc('[1,2,3]'));
  Check('Encode nested', '8301820203820405', Enc('[1,[2,3],[4,5]]'));
  Check('Encode map', 'a26161016162820203', Enc('{"a":1,"b":[2,3]}'));
  Check('Encode empty containers', '82a080', Enc('[{},[]]'));
  Check('Round trip keeps member order', '{"z":1,"a":2,"m":3}', Dec(Enc('{"z":1,"a":2,"m":3}')));
end;

procedure Step5_Indefinite;
begin
  Section('5. Indefinite lengths');
  Check('Byte string chunks', '"AQIDBAU"', Dec('5f42010243030405ff'));
  Check('Text string chunks', '"streaming"', Dec('7f657374726561646d696e67ff'));
  Check('Empty array', '[]', Dec('9fff'));
  Check('Nested indefinite arrays', '[1,[2,3],[4,5]]', Dec('9f018202039f0405ffff'));
  Check('Mixed definite and indefinite', '[1,[2,3],[4,5]]', Dec('83018202039f0405ff'));
  Check('Mixed, other position', '[1,[2,3],[4,5]]', Dec('83019f0203ff820405'));
  Check('Indefinite map', '{"a":1,"b":[2,3]}', Dec('bf61610161629f0203ffff'));
  Check('Map inside array', '["a",{"b":"c"}]', Dec('826161bf61626163ff'));
  Check('Fun and Amt', '{"Fun":true,"Amt":-2}', Dec('bf6346756ef563416d7421ff'));
  Check('Indefinite 25 items',
    '[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]',
    Dec('9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff'));
end;

procedure Step6_Tags;
var
  Options: TJsonCborOptions;
begin
  Section('6. Tags, decimal fractions, bigfloats');
  Check('Tag 0 is dropped', '"2013-03-21T20:04:00Z"', Dec('c074323031332d30332d32315432303a30343a30305a'));
  Check('Tag 1 integer', '1363896240', Dec('c11a514b67b0'));
  Check('Tag 1 float', 1363896240.5, DecodedDouble('c1fb41d452d9ec200000'), 0);
  Check('Tag 23 on bytes', '"AQIDBA"', Dec('d74401020304'));
  Check('Tag 24 on bytes', '"ZElFVEY"', Dec('d818456449455446'));
  Check('Tag 32 on text', '"http://www.example.com"', Dec('d82076687474703a2f2f7777772e6578616d706c652e636f6d'));
  Check('Self-describe tag', '[1]', Dec('d9d9f78101'));
  Check('Decimal fraction 273.15', '273.15', Dec('c48221196ab3'));
  Check('Decimal fraction with large exponent', '1E1000', Dec('c482' + '1903e8' + '01'));
  Check('Decimal fraction negative mantissa', '-0.05', Dec('c4822124'));
  Check('Decimal fraction positive exponent', '1200', Dec('c482020c'));
  Check('Bigfloat 1.5', '1.5', Dec('c5822003'));
  Check('Bigfloat 12', '12', Dec('c5820203'));
  Check('Bigfloat 0.125', '0.125', Dec('c5822201'));
  Check('Decimal fraction with bignum mantissa', '1.00000000000000000001',
    Dec('c482' + '33' + 'c249056bc75e2d63100001'));

  Check('Exact decimal needs a decimal fraction', 'c482' + '33' + 'c249056bc75e2d63100001',
    Enc('1.00000000000000000001'));
  Check('Tag 4 round trip', '1.00000000000000000001', Dec(Enc('1.00000000000000000001')));
  Check('Huge exponent is kept exactly', 'c4821903e801', Enc('1e1000'));
  Check('Negative exact decimal', 'c482' + '33' + 'c349056bc75e2d63100000', Enc('-1.00000000000000000001'));

  Options := TJsonCborOptions.Create;
  try
    Options.ExactDecimals := False;
    Check('Without ExactDecimals the digits are rounded', 'f93c00', Enc('1.00000000000000000001', Options));
    CheckContains('Without ExactDecimals an overflow is an error', 'outside the range', EncodeError('1e1000', Options));
  finally
    Options.Free;
  end;

  Options := TJsonCborOptions.Create;
  try
    Options.TagMode := ctmWrap;
    Check('Tag wrapped',
      '{"@tag":32,"@value":"http://www.example.com"}',
      Dec('d82076687474703a2f2f7777772e6578616d706c652e636f6d', Options));
    Check('Wrapped tag round trip',
      'd82076687474703a2f2f7777772e6578616d706c652e636f6d',
      Enc('{"@tag":32,"@value":"http://www.example.com"}', Options));
    Check('Tag 4 is still a number in wrap mode', '273.15', Dec('c48221196ab3', Options));
    Options.TagKey := 't';
    Options.ValueKey := 'v';
    Check('Custom tag keys', '{"t":1,"v":5}', Dec('c105', Options));
  finally
    Options.Free;
  end;
end;

procedure Step7_BytesModes;
var
  Options: TJsonCborOptions;
  Dom, Clone: TJsonValue;
begin
  Section('7. Byte string representation');
  Options := TJsonCborOptions.Create;
  try
    Options.BytesMode := cbmBase64;
    Check('Base64 with padding', '"AQIDBA=="', Dec('4401020304', Options));
    Check('Base64 uses the standard alphabet', '"+/8="', Dec('42fbff', Options));
    Options.BytesMode := cbmHex;
    Check('Hex', '"01020304"', Dec('4401020304', Options));
    Options.BytesMode := cbmWrapped;
    Check('Wrapped', '{"@bytes":"AQIDBA"}', Dec('4401020304', Options));
    Check('Wrapped encodes back to a byte string', '4401020304', Enc('{"@bytes":"AQIDBA"}', Options));
    Check('Wrapped empty', '40', Enc('{"@bytes":""}', Options));
    Check('Wrapped bytes inside a structure', '{"k":{"@bytes":"AQI"}}', Dec(Enc('{"k":{"@bytes":"AQI"}}', Options), Options));
    Options.BytesKey := '$b';
    Check('Custom key', '4401020304', Enc('{"$b":"AQIDBA"}', Options));
  finally
    Options.Free;
  end;
  Dom := CborToDom(CborFromHex('a1614b4401020304'));
  try
    CheckTrue('A byte string becomes a TJsonBytes node', Dom.Values['K'] is TJsonBytes, '');
    Check('The node keeps the bytes', 4, Length(TJsonBytes(Dom.Values['K']).Bytes));
    Check('A byte string survives the DOM without options', 'a1614b4401020304', CborToHex(DomToCbor(Dom)));
    Clone := Dom.Clone;
    try
      Check('A clone is still a byte string', 'a1614b4401020304', CborToHex(DomToCbor(Clone)));
    finally
      Clone.Free;
    end;
  finally
    Dom.Free;
  end;
  Options := TJsonCborOptions.Create;
  try
    Options.BytesMode := cbmHex;
    Dom := CborToDom(CborFromHex('4401020304'), Options);
    try
      Check('The text form follows BytesMode', '"01020304"', DomToText(Dom));
      Check('The bytes are the same in every mode', '4401020304', CborToHex(DomToCbor(Dom)));
    finally
      Dom.Free;
    end;
  finally
    Options.Free;
  end;
  Check('Wrapper is recognized with default options too', '4401020304', Enc('{"@bytes":"AQIDBA"}'));
  Check('Wrapper with other members is a map', 'a2', Copy(Enc('{"@bytes":"","a":1}'), 1, 2));
end;

procedure Step8_Deterministic;
var
  Options: TJsonCborOptions;
begin
  Section('8. Deterministic encoding (RFC 8949 4.2)');
  Options := TJsonCborOptions.Create;
  try
    Options.Deterministic := True;
    Check('Keys are sorted by their encoding', 'a4600461610261620162616103', Enc('{"b":1,"a":2,"aa":3,"":4}', Options));
    Check('Nested maps are sorted too', 'a1616182a261610161620280', Enc('{"a":[{"b":2,"a":1},[]]}', Options));
    Check('Same data, same bytes', Enc('{"x":1,"y":2}', Options), Enc('{"y":2,"x":1}', Options));
    Options.KeyMode := ckmInteger;
    Check('Bytewise order puts 256 before a', 'a21901000261610' + '1', Enc('{"a":1,"256":2}', Options));
    Options.KeyOrder := ckoLengthFirst;
    Check('Length first order puts a before 256', 'a26161011901000' + '2', Enc('{"a":1,"256":2}', Options));
    Check('Length first order, mixed keys', 'a50a032004616102626262016361616105', Enc('{"bb":1,"a":2,"10":3,"-1":4,"aaa":5}', Options));
  finally
    Options.Free;
  end;
  Check('Without the option the order is kept', 'a2616201616102', Enc('{"b":1,"a":2}'));
end;

procedure Step9_Malformed;
var
  Options: TJsonCborOptions;
  Deep: string;
  I: Integer;
begin
  Section('9. Malformed and hostile input');
  CheckContains('Empty input', 'Unexpected end', ErrorOf(''));
  CheckContains('Truncated integer', 'Unexpected end', ErrorOf('19ff'));
  CheckContains('Truncated array', 'exceeds', ErrorOf('8301'));
  CheckContains('Truncated string', 'exceeds', ErrorOf('6461'));
  CheckContains('Trailing data', 'unexpected byte', ErrorOf('0000'));
  CheckContains('Reserved additional information', 'Reserved', ErrorOf('1c'));
  CheckContains('Reserved in major 7', 'Reserved', ErrorOf('fc'));
  CheckContains('Stray break', 'Unexpected break', ErrorOf('ff'));
  CheckContains('Break inside a definite array', 'Unexpected break', ErrorOf('8301ff00'));
  CheckContains('Indefinite integer', 'Indefinite', ErrorOf('1f'));
  CheckContains('Indefinite tag', 'Indefinite', ErrorOf('df'));
  CheckContains('Invalid UTF-8 byte', 'UTF-8', ErrorOf('62c328'));
  CheckContains('Overlong UTF-8', 'UTF-8', ErrorOf('62c080'));
  CheckContains('Surrogate in UTF-8', 'UTF-8', ErrorOf('63eda080'));
  CheckContains('Above U+10FFFF', 'UTF-8', ErrorOf('64f4908080'));
  CheckContains('Truncated UTF-8', 'UTF-8', ErrorOf('62e6b0'));
  CheckContains('Chunk of the wrong type', 'chunk', ErrorOf('5f6161ff'));
  CheckContains('Nested indefinite chunk', 'chunk', ErrorOf('5f5fffff'));
  CheckContains('Split UTF-8 across chunks', 'UTF-8', ErrorOf('7f62e6b062b0b4ff'));
  CheckContains('Huge array length', 'exceeds', ErrorOf('9bffffffffffffffff'));
  CheckContains('Huge map length', 'exceeds', ErrorOf('bb7fffffffffffffff'));
  CheckContains('Huge string length', 'exceeds', ErrorOf('7bffffffffffffffff'));
  CheckContains('Duplicate map key', 'Duplicate', ErrorOf('a20101' + '0102'));
  CheckContains('Odd map in an indefinite map', 'Unexpected break', ErrorOf('bf01ff'));
  CheckContains('Bignum without bytes', 'byte string', ErrorOf('c201'));
  CheckContains('Decimal fraction of wrong shape', 'two integers', ErrorOf('c40102'));
  CheckContains('Decimal fraction with float', 'two integers', ErrorOf('c482f93c0001'));
  CheckContains('Unassigned simple value', 'simple value', ErrorOf('f0'));
  CheckContains('Two-byte simple value', 'simple value', ErrorOf('f820'));
  CheckContains('NaN', 'NaN', ErrorOf('f97e00'));
  CheckContains('Infinity', 'Infinity', ErrorOf('fa7f800000'));
  CheckContains('Negative infinity', 'Infinity', ErrorOf('fbfff0000000000000'));
  CheckContains('Bigfloat exponent too large', 'too large', ErrorOf('c5821a3b9aca0001'));

  Deep := '';
  for I := 1 to 300 do Deep := Deep + '81';
  CheckContains('Nesting beyond MaxDepth', 'MaxDepth', ErrorOf(Deep + '00'));
  Deep := '';
  for I := 1 to 200 do Deep := Deep + '81';
  Check('Nesting within MaxDepth', '', ErrorOf(Deep + '00'));
  Deep := '';
  for I := 1 to 100000 do Deep := Deep + 'c1';
  CheckContains('Tag chains are bounded', 'MaxDepth', ErrorOf(Deep + '00'));

  Options := TJsonCborOptions.Create;
  try
    Options.MaxDepth := 2;
    Check('Depth 2 fits', '[[1]]', Dec('818101', Options));
    CheckContains('Depth 3 does not', 'MaxDepth', ErrorOf('81818101', Options));
    Options.MaxDepth := 256;

    Options.NonFinite := cnfNull;
    Check('NaN as null', '[null,null,null]', Dec('83f97e00f97c00f9fc00', Options));
    Options.NonFinite := cnfText;
    Check('NaN as text', '["NaN","Infinity","-Infinity"]', Dec('83f97e00f97c00f9fc00', Options));
    Options.NonFinite := cnfError;

    Options.UndefinedAsNull := False;
    CheckContains('undefined rejected', 'undefined', ErrorOf('f7', Options));
    Options.UndefinedAsNull := True;

    Options.KeyMode := ckmText;
    CheckContains('Integer key rejected in text mode', 'text string', ErrorOf('a10102', Options));
    Check('Text keys accepted in text mode', '{"a":1}', Dec('a1616101', Options));
    Options.KeyMode := ckmStringify;

    Check('COSE-style integer keys read as text', '{"1":2,"3":-7,"-1":1}', Dec('a30102032620' + '01', Options));
    Check('Integer-looking keys are text by default', 'a3613102613326622d3101', Enc('{"1":2,"3":-7,"-1":1}', Options));
    Options.KeyMode := ckmInteger;
    Check('Integer keys round trip byte for byte', 'a30102032620' + '01', Enc(Dec('a30102032620' + '01', Options), Options));
    Check('Large integer keys', 'a21bffffffffffffffff013bffffffffffffffff02',
      Enc('{"18446744073709551615":1,"-18446744073709551616":2}', Options));
    Check('Non canonical keys stay text', 'a4000162' + '2d3002' + '62' + '303103' + '62' + '2b3104',
      Enc('{"0":1,"-0":2,"01":3,"+1":4}', Options));
    Check('Out of range key stays text', 'a174313834343637343430373337303935353136313601',
      Enc('{"18446744073709551616":1}', Options));
    Options.Deterministic := True;
    Check('Deterministic order with integer keys', 'a3020220036162' + '01',
      Enc('{"b":1,"2":2,"-1":3}', Options));
    Options.Deterministic := False;
    Options.KeyMode := ckmStringify;

    Options.DuplicateKeys := cdkFirstWins;
    Check('First duplicate wins', '{"a":1}', Dec('a2616101616102', Options));
    Options.DuplicateKeys := cdkLastWins;
    Check('Last duplicate wins', '{"a":2}', Dec('a2616101616102', Options));
    Options.DuplicateKeys := cdkError;
    CheckContains('Integer and text key collide', 'Duplicate', ErrorOf('a2' + '01' + '01' + '6131' + '02', Options));
  finally
    Options.Free;
  end;

  CheckError('Array and map keys are rejected', procedure begin Dec('a18101' + '01'); end);
  CheckError('Lone surrogate cannot be encoded', procedure
    var
      Node: TJsonString;
    begin
      Node := TJsonString.Create(#$D800);
      try
        DomToCbor(Node);
      finally
        Node.Free;
      end;
    end);
  CheckError('Invalid Base64 in a bytes wrapper', procedure begin Enc('{"@bytes":"***"}'); end);
  CheckError('Encoding beyond MaxDepth', procedure
    var
      Json: string;
      K: Integer;
    begin
      Json := '';
      for K := 1 to 300 do Json := Json + '[';
      for K := 1 to 300 do Json := Json + ']';
      Enc(Json);
    end);
end;

procedure Step10_Sequences;
var
  Data: TBytes;
  Position: Integer;
  Item: TJsonValue;
begin
  Section('10. Sequences and files');
  Data := CborFromHex('01826161f5a0');
  Position := 0;
  Item := CborToDomAt(Data, Position);
  try
    Check('First item', '1', DomToText(Item));
  finally
    Item.Free;
  end;
  Check('Position after the first item', 1, Position);
  Item := CborToDomAt(Data, Position);
  try
    Check('Second item', '["a",true]', DomToText(Item));
  finally
    Item.Free;
  end;
  Item := CborToDomAt(Data, Position);
  try
    Check('Third item', '{}', DomToText(Item));
  finally
    Item.Free;
  end;
  Check('Consumed everything', Length(Data), Position);
  CheckError('Position beyond the data', procedure
    var
      P: Integer;
    begin
      P := 7;
      CborToDomAt(Data, P).Free;
    end);
  Check('Hex helper ignores white space', '01020304', CborToHex(CborFromHex('01 02' + #13#10 + '03' + #9 + '04')));
  CheckError('Odd hex', procedure begin CborFromHex('abc'); end);
  CheckError('Bad hex digit', procedure begin CborFromHex('zz'); end);
end;

procedure Step11_Objects;
var
  User, Back: TUser;
  Data: TBytes;
begin
  Section('11. Delphi objects');
  User := TUser.Create;
  try
    User.Name := 'Anna';
    User.Age := 34;
    User.Balance := StrToCurr('1234567890123.4567', TFormatSettings.Invariant);
    Data := CborConvert.SerializeObject(User);
    Check('Four members', 'a4', Copy(CborToHex(Data), 1, 2));
    CheckContains('Member name from the attribute', '6966756c6c5f6e616d65', CborToHex(Data));
    Back := CborConvert.DeserializeObject<TUser>(Data);
    try
      Check('Name', 'Anna', Back.Name);
      Check('Age', 34, Back.Age);
      CheckTrue('Currency stays exact', Back.Balance = User.Balance, CurrToStr(Back.Balance));
    finally
      Back.Free;
    end;
    CheckContains('Currency uses a decimal fraction', 'c482', CborToHex(Data));
    CheckContains('A nil TBytes stays null', '6550686f746ff6', CborToHex(Data));
    User.Photo := TBytes.Create(1, 2, 3, 255);
    Data := CborConvert.SerializeObject(User);
    CheckContains('TBytes is a CBOR byte string', '6550686f746f4401' + '0203ff', CborToHex(Data));
    Back := CborConvert.DeserializeObject<TUser>(Data);
    try
      Check('TBytes comes back', 4, Length(Back.Photo));
      Check('Last byte', 255, Integer(Back.Photo[3]));
    finally
      Back.Free;
    end;
    CheckContains('JsonConvert still writes Base64 text', '"Photo":"AQID/w=="', JsonConvert.SerializeObject(User));
    Back := JsonConvert.DeserializeObject<TUser>('{"Photo":{"@bytes":"AQID_w"}}');
    try
      Check('JsonConvert reads the byte wrapper', 4, Length(Back.Photo));
    finally
      Back.Free;
    end;
  finally
    User.Free;
  end;
end;

function RandomText: string;
var
  I, N, Kind: Integer;
begin
  N := Random(8);
  Result := '';
  for I := 1 to N do
  begin
    Kind := Random(6);
    case Kind of
      0: Result := Result + Char(Ord('a') + Random(26));
      1: Result := Result + Char($E0 + Random($1F));
      2: Result := Result + Char($4E00 + Random($1000));
      3: Result := Result + Char($D800) + Char($DC00 + Random($400));
      4: Result := Result + '\\"';
    else
      Result := Result + Char(32 + Random(90));
    end;
  end;
end;

function JsonQuote(const S: string): string;
var
  Node: TJsonString;
begin
  Node := TJsonString.Create(S);
  try
    Result := Node.ToJson;
  finally
    Node.Free;
  end;
end;

function RandomNumber: string;
var
  Kind: Integer;
  D: Double;
begin
  Kind := Random(7);
  case Kind of
    0: Result := IntToStr(Random(300) - 100);
    1: Result := IntToStr(Int64(Random(MaxInt)) * Random(MaxInt));
    2: Result := '-' + IntToStr(Int64(Random(MaxInt)) * Random(MaxInt));
    3: Result := '1' + StringOfChar('0', 20 + Random(40));
    4:
      begin
        D := (Random - 0.5) * 1000;
        Result := JsonDoubleToText(D);
      end;
    5:
      begin
        D := (Random - 0.5) * 1E30;
        Result := JsonDoubleToText(D);
      end;
  else
    Result := IntToStr(Random(1000)) + '.' + IntToStr(Random(100)) + '25';
  end;
end;

function RandomJson(Depth: Integer): string;
var
  I, N, Kind: Integer;
begin
  if Depth > 0 then Kind := Random(7) else Kind := Random(5);
  case Kind of
    0: Result := 'null';
    1: Result := 'true';
    2: Result := 'false';
    3: Result := RandomNumber;
    4: Result := JsonQuote(RandomText);
    5:
      begin
        N := Random(5);
        Result := '[';
        for I := 0 to N - 1 do
        begin
          if I > 0 then Result := Result + ',';
          Result := Result + RandomJson(Depth - 1);
        end;
        Result := Result + ']';
      end;
  else
    N := Random(5);
    Result := '{';
    for I := 0 to N - 1 do
    begin
      if I > 0 then Result := Result + ',';
      Result := Result + JsonQuote('k' + IntToStr(I) + RandomText) + ':' + RandomJson(Depth - 1);
    end;
    Result := Result + '}';
  end;
end;

procedure Step12_Fuzz;
var
  I, J, Failures, Rejected, Accepted: Integer;
  Json, Back: string;
  Data, Mutated: TBytes;
  Dom: TJsonValue;
begin
  Section('12. Round trip and mutation fuzzing');
  RandSeed := 20260101;
  Failures := 0;
  for I := 1 to 3000 do
  begin
    Json := RandomJson(4);
    Dom := DomFromText(Json);
    try
      Data := DomToCbor(Dom);
    finally
      Dom.Free;
    end;
    Back := CborToJson(Data);
    if Normalized(Back) <> Normalized(Json) then
    begin
      Inc(Failures);
      if Failures <= 3 then Show('Mismatch', Copy(Json, 1, 80) + ' -> ' + Copy(Back, 1, 80));
    end;
  end;
  Check('3000 random documents survive JSON -> CBOR -> JSON', 0, Failures);

  Failures := 0;
  Rejected := 0;
  Accepted := 0;
  for I := 1 to 4000 do
  begin
    Json := RandomJson(4);
    Dom := DomFromText(Json);
    try
      Data := DomToCbor(Dom);
    finally
      Dom.Free;
    end;
    Mutated := Copy(Data, 0, Length(Data));
    case Random(3) of
      0: if Length(Mutated) > 0 then Mutated[Random(Length(Mutated))] := Byte(Random(256));
      1: if Length(Mutated) > 1 then SetLength(Mutated, Random(Length(Mutated)));
    else
      for J := 1 to 3 do if Length(Mutated) > 0 then Mutated[Random(Length(Mutated))] := Byte(Random(256));
    end;
    try
      Dom := CborToDom(Mutated);
      Dom.Free;
      Inc(Accepted);
    except
      on EJsonCborError do Inc(Rejected);
      on E: Exception do
      begin
        Inc(Failures);
        if Failures <= 3 then Show('Unexpected exception', E.ClassName + ': ' + E.Message + ' for ' + CborToHex(Mutated));
      end;
    end;
  end;
  Show('Mutated inputs', IntToStr(Accepted) + ' accepted, ' + IntToStr(Rejected) + ' rejected');
  Check('Mutated input only ever raises EJsonCborError', 0, Failures);
end;

begin
  {$IFNDEF FPC}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
  try
    Title('NATIVEJSON - CBOR');
    Step1_Integers;
    Step2_Floats;
    Step3_SimpleAndStrings;
    Step4_Containers;
    Step5_Indefinite;
    Step6_Tags;
    Step7_BytesModes;
    Step8_Deterministic;
    Step9_Malformed;
    Step10_Sequences;
    Step11_Objects;
    Step12_Fuzz;
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
