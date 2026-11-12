{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_Diff;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  NativeJson.Main,
  NativeJson.Dom.Value,
  NativeJson.Dom.JsonArray,
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

procedure CheckJsonEqual(const ExpectedJson: string; Actual: TJsonValue;
  const MessageText: string);
var
  Expected: TJsonValue;
begin
  Expected := Parse(ExpectedJson);
  try
    Check(Actual <> nil, MessageText + ': actual value is nil');
    Check(TJsonComparer.DeepEquals(Expected, Actual), MessageText +
      '. Expected ' + Expected.ToJson + ', got ' + Actual.ToJson);
  finally
    Expected.Free;
  end;
end;

procedure CheckDiff(const OldJson, NewJson, ExpectedPatchJson,
  MessageText: string);
var
  OldValue, NewValue, Patched: TJsonValue;
  Patch: TJsonArray;
  OldBefore, NewBefore: string;
begin
  OldValue := Parse(OldJson);
  NewValue := Parse(NewJson);
  Patch := nil;
  Patched := nil;
  try
    OldBefore := OldValue.ToJson;
    NewBefore := NewValue.ToJson;

    Patch := TJsonDiff.Compare(OldValue, NewValue);
    CheckJsonEqual(ExpectedPatchJson, Patch, MessageText + ': generated patch');

    Patched := TJsonPatch.Apply(OldValue, Patch);
    Check(TJsonComparer.DeepEquals(NewValue, Patched),
      MessageText + ': generated patch does not recreate target');

    Check(OldValue.ToJson = OldBefore,
      MessageText + ': source document mutated');
    Check(NewValue.ToJson = NewBefore,
      MessageText + ': target document mutated');
  finally
    Patched.Free;
    Patch.Free;
    NewValue.Free;
    OldValue.Free;
  end;
end;

procedure TestNoChanges;
begin
  CheckDiff(
    '{"a":1,"b":2}',
    '{"b":2.0,"a":1e0}',
    '[]',
    'semantic object equality creates empty patch');

  CheckDiff(
    '[{"a":1,"b":2}]',
    '[{"b":2.0,"a":1e0}]',
    '[]',
    'semantic equality inside arrays creates empty patch');
end;

procedure TestRootReplacement;
begin
  CheckDiff(
    '1',
    '2',
    '[{"op":"replace","path":"","value":2}]',
    'scalar root replacement');

  CheckDiff(
    '{"a":1}',
    '[1,2]',
    '[{"op":"replace","path":"","value":[1,2]}]',
    'root type change replacement');

  CheckDiff(
    '[1,2]',
    '[1,3]',
    '[{"op":"replace","path":"","value":[1,3]}]',
    'changed root array replaced whole');
end;

procedure TestObjectChanges;
begin
  CheckDiff(
    '{"name":"Peter","age":30}',
    '{"name":"Peter","age":31,"active":true}',
    '[{"op":"replace","path":"/age","value":31},' +
    '{"op":"add","path":"/active","value":true}]',
    'replace and add object members');

  CheckDiff(
    '{"keep":1,"old":2}',
    '{"keep":1,"new":3}',
    '[{"op":"remove","path":"/old"},' +
    '{"op":"add","path":"/new","value":3}]',
    'remove and add object members');

  CheckDiff(
    '{"customer":{"name":"Peter","age":40},"active":true}',
    '{"customer":{"name":"Anna","age":40},"active":true}',
    '[{"op":"replace","path":"/customer/name","value":"Anna"}]',
    'nested object replacement');

  CheckDiff(
    '{"a":{"x":1,"remove":2}}',
    '{"a":{"x":1,"add":3}}',
    '[{"op":"remove","path":"/a/remove"},' +
    '{"op":"add","path":"/a/add","value":3}]',
    'nested object add and remove');
end;

procedure TestPointerEscaping;
begin
  CheckDiff(
    '{"a/b":1,"m~n":2}',
    '{"a/b":3,"m~n":4}',
    '[{"op":"replace","path":"/a~1b","value":3},' +
    '{"op":"replace","path":"/m~0n","value":4}]',
    'object keys are RFC-6901 escaped');

  CheckDiff(
    '{"":1}',
    '{"":2}',
    '[{"op":"replace","path":"/","value":2}]',
    'empty object member name');

  CheckDiff(
    '{"a/b":{"~x":1}}',
    '{"a/b":{"~x":2}}',
    '[{"op":"replace","path":"/a~1b/~0x","value":2}]',
    'nested pointer escaping');
end;

procedure TestArrayPolicy;
begin
  CheckDiff(
    '{"items":[1,2,3],"name":"x"}',
    '{"items":[1,4,3],"name":"x"}',
    '[{"op":"replace","path":"/items","value":[1,4,3]}]',
    'changed nested array replaced whole');

  CheckDiff(
    '{"items":[{"id":1,"name":"A"}]}',
    '{"items":[{"id":1,"name":"B"}]}',
    '[{"op":"replace","path":"/items","value":' +
    '[{"id":1,"name":"B"}]}]',
    'array object change replaces whole array');
end;

procedure TestExactNumbers;
begin
  CheckDiff(
    '{"n":9007199254740993}',
    '{"n":9007199254740993.0}',
    '[]',
    'large exact equal numbers create no patch');

  CheckDiff(
    '{"n":9007199254740993}',
    '{"n":9007199254740992}',
    '[{"op":"replace","path":"/n","value":9007199254740992}]',
    'large distinct numbers create replace');

  CheckDiff(
    '{"n":-0e100}',
    '{"n":0}',
    '[]',
    'numeric zero representations are equal');
end;

procedure TestDeterministicOrder;
begin
  CheckDiff(
    '{"first":1,"goneA":2,"goneB":3,"last":4}',
    '{"first":10,"last":4,"newA":5,"newB":6}',
    '[{"op":"remove","path":"/goneA"},' +
    '{"op":"remove","path":"/goneB"},' +
    '{"op":"replace","path":"/first","value":10},' +
    '{"op":"add","path":"/newA","value":5},' +
    '{"op":"add","path":"/newB","value":6}]',
    'operation order is deterministic');
end;

procedure TestPatchOwnsValues;
var
  OldValue, NewValue, Patched: TJsonValue;
  Patch: TJsonArray;
begin
  OldValue := Parse('{}');
  NewValue := Parse('{"obj":{"x":1}}');
  Patch := nil;
  Patched := nil;
  try
    Patch := TJsonDiff.Compare(OldValue, NewValue);
    NewValue.Free;
    NewValue := nil;

    Patched := TJsonPatch.Apply(OldValue, Patch);
    CheckJsonEqual('{"obj":{"x":1}}', Patched,
      'generated patch owns cloned target values');
  finally
    Patched.Free;
    Patch.Free;
    NewValue.Free;
    OldValue.Free;
  end;
end;

procedure TestNilRejected;
var
  Value: TJsonValue;
  Patch: TJsonArray;
  RaisedError: Boolean;
begin
  Value := Parse('{}');
  try
    Patch := nil;
    RaisedError := False;
    try
      Patch := TJsonDiff.Compare(nil, Value);
    except
      on E: EJsonDiffError do
        RaisedError := True;
    end;
    Patch.Free;
    Check(RaisedError, 'nil source must be rejected');

    Patch := nil;
    RaisedError := False;
    try
      Patch := TJsonDiff.Compare(Value, nil);
    except
      on E: EJsonDiffError do
        RaisedError := True;
    end;
    Patch.Free;
    Check(RaisedError, 'nil target must be rejected');
  finally
    Value.Free;
  end;
end;

begin
  try
    TestNoChanges;
    TestRootReplacement;
    TestObjectChanges;
    TestPointerEscaping;
    TestArrayPolicy;
    TestExactNumbers;
    TestDeterministicOrder;
    TestPatchOwnsValues;
    TestNilRejected;
    Writeln('NativeJson_Diff: all tests passed.');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
