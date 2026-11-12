{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_DeepEquals;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  NativeJson.Main,
  NativeJson.Dom.Value,
  NativeJson.Dom.Io;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create('FAILED: ' + MessageText);
end;

function Parse(const Json: string): TJsonValue;
begin
  Result := DomFromText(Json);
end;

procedure CheckJsonEqual(const LeftJson, RightJson, MessageText: string);
var
  Left, Right: TJsonValue;
begin
  Left := Parse(LeftJson);
  try
    Right := Parse(RightJson);
    try
      Check(TJsonComparer.DeepEquals(Left, Right), MessageText);
      Check(TJsonComparer.DeepEquals(Right, Left), MessageText + ' (symmetric)');
    finally
      Right.Free;
    end;
  finally
    Left.Free;
  end;
end;

procedure CheckJsonNotEqual(const LeftJson, RightJson, MessageText: string);
var
  Left, Right: TJsonValue;
begin
  Left := Parse(LeftJson);
  try
    Right := Parse(RightJson);
    try
      Check(not TJsonComparer.DeepEquals(Left, Right), MessageText);
      Check(not TJsonComparer.DeepEquals(Right, Left), MessageText + ' (symmetric)');
    finally
      Right.Free;
    end;
  finally
    Left.Free;
  end;
end;

procedure TestNilAndIdentity;
var
  Value: TJsonValue;
begin
  Check(TJsonComparer.DeepEquals(nil, nil), 'nil equals nil');

  Value := Parse('{"a":1}');
  try
    Check(TJsonComparer.DeepEquals(Value, Value), 'same instance equals itself');
    Check(not TJsonComparer.DeepEquals(Value, nil), 'value differs from nil');
    Check(not TJsonComparer.DeepEquals(nil, Value), 'nil differs from value');
  finally
    Value.Free;
  end;
end;

procedure TestPrimitiveValues;
begin
  CheckJsonEqual('null', 'null', 'null equality');
  CheckJsonEqual('true', 'true', 'boolean equality');
  CheckJsonNotEqual('true', 'false', 'boolean inequality');
  CheckJsonEqual('"NativeJson"', '"NativeJson"', 'string equality');
  CheckJsonNotEqual('"NativeJson"', '"nativejson"', 'strings are case-sensitive');
  CheckJsonNotEqual('"1"', '1', 'string and number differ');
end;

procedure TestExactNumbers;
begin
  CheckJsonEqual('1', '1.0', 'integer and decimal represent the same JSON number');
  CheckJsonEqual('1', '1e0', 'integer and exponent represent the same JSON number');
  CheckJsonEqual('1.000e+0', '1', 'trailing zeroes do not change numeric value');
  CheckJsonEqual('-0', '0.0', 'negative zero equals zero numerically');
  CheckJsonEqual('1000', '1e3', 'exponent comparison is exact');
  CheckJsonEqual('1e1000', '10e999', 'very large exponents compare without Double');

  CheckJsonNotEqual('1', '1.0000000000000000000000000000000001',
    'tiny exact numeric difference is preserved');
  CheckJsonNotEqual('9007199254740993', '9007199254740992',
    'integers above Double precision remain distinct');
  CheckJsonNotEqual('1e1000', '1e999',
    'large exponent difference remains distinct');
end;

procedure TestArrays;
begin
  CheckJsonEqual('[1,"x",true,null]', '[1.0,"x",true,null]',
    'array elements use deep numeric equality');
  CheckJsonEqual('[{"a":1,"b":2}]', '[{"b":2,"a":1.0}]',
    'nested objects are compared deeply');
  CheckJsonNotEqual('[1,2,3]', '[3,2,1]', 'array order is significant');
  CheckJsonNotEqual('[1,2]', '[1,2,3]', 'array length is significant');
end;

procedure TestObjects;
begin
  CheckJsonEqual('{"a":1,"b":2}', '{"b":2.0,"a":1e0}',
    'object member order is irrelevant');
  CheckJsonEqual(
    '{"customer":{"name":"Anna","flags":[true,false]},"id":9007199254740993}',
    '{"id":9007199254740993.0,"customer":{"flags":[true,false],"name":"Anna"}}',
    'deep nested object equality');

  CheckJsonNotEqual('{"name":"Anna"}', '{"name":"ANNA"}',
    'object string values remain case-sensitive');
  CheckJsonNotEqual('{"a":1}', '{"A":1}', 'object member names are case-sensitive');
  CheckJsonNotEqual('{"a":1}', '{"a":2}', 'object member value difference');
  CheckJsonNotEqual('{"a":1}', '{"a":1,"b":2}', 'extra object member differs');
end;

procedure TestDoesNotMutate;
var
  Left, Right: TJsonValue;
  LeftBefore, RightBefore: string;
begin
  Left := Parse('{"b":[2,1],"a":{"y":2,"x":1}}');
  try
    Right := Parse('{"a":{"x":1.0,"y":2},"b":[2.0,1e0]}');
    try
      LeftBefore := Left.ToJson;
      RightBefore := Right.ToJson;
      Check(TJsonComparer.DeepEquals(Left, Right), 'comparison baseline');
      Check(Left.ToJson = LeftBefore, 'DeepEquals must not mutate left value');
      Check(Right.ToJson = RightBefore, 'DeepEquals must not mutate right value');
    finally
      Right.Free;
    end;
  finally
    Left.Free;
  end;
end;

procedure TestClone;
var
  Original, CopyValue: TJsonValue;
begin
  Original := Parse('{"a":[1,2,{"x":"y"}],"b":true}');
  try
    CopyValue := Original.Clone;
    try
      Check(TJsonComparer.DeepEquals(Original, CopyValue), 'clone is deeply equal');
      Check(Original <> CopyValue, 'clone is a different instance');
    finally
      CopyValue.Free;
    end;
  finally
    Original.Free;
  end;
end;

begin
  try
    TestNilAndIdentity;
    TestPrimitiveValues;
    TestExactNumbers;
    TestArrays;
    TestObjects;
    TestDoesNotMutate;
    TestClone;
    Writeln('NativeJson.Comparer DeepEquals: ALL TESTS PASSED');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
