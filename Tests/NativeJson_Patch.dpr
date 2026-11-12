{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_Patch;

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

procedure CheckJsonEqual(const Expected: string; Actual: TJsonValue;
  const MessageText: string);
var
  ExpectedValue: TJsonValue;
begin
  ExpectedValue := Parse(Expected);
  try
    Check(Actual <> nil, MessageText + ': actual value is nil');
    Check(TJsonComparer.DeepEquals(ExpectedValue, Actual), MessageText +
      '. Expected ' + ExpectedValue.ToJson + ', got ' + Actual.ToJson);
  finally
    ExpectedValue.Free;
  end;
end;

procedure CheckPatch(const DocumentJson, PatchJson, ExpectedJson,
  MessageText: string);
var
  Document, Patched: TJsonValue;
  Before: string;
begin
  Document := Parse(DocumentJson);
  try
    Before := Document.ToJson;
    Patched := TJsonPatch.Apply(Document, PatchJson);
    try
      Check(Patched <> nil, MessageText + ': result must exist');
      CheckJsonEqual(ExpectedJson, Patched, MessageText);
      Check(Document.ToJson = Before, MessageText + ': source document mutated');
    finally
      Patched.Free;
    end;
  finally
    Document.Free;
  end;
end;

procedure CheckPatchError(const DocumentJson, PatchJson, MessageText: string);
var
  Document, Patched: TJsonValue;
  ErrorMessage, Before: string;
begin
  Document := Parse(DocumentJson);
  try
    Before := Document.ToJson;
    Patched := nil;
    ErrorMessage := '';
    Check(not TJsonPatch.TryApply(Document, PatchJson, Patched, ErrorMessage),
      MessageText + ': TryApply must fail');
    Check(Patched = nil, MessageText + ': failed TryApply must return nil');
    Check(ErrorMessage <> '', MessageText + ': error message must not be empty');
    Check(Document.ToJson = Before, MessageText + ': failed patch mutated source');
  finally
    Patched.Free;
    Document.Free;
  end;
end;

procedure TestRfcExamples;
begin
  CheckPatch(
    '{"foo":"bar"}',
    '[{"op":"add","path":"/baz","value":"qux"}]',
    '{"baz":"qux","foo":"bar"}',
    'RFC A.1 add object member');

  CheckPatch(
    '{"foo":["bar","baz"]}',
    '[{"op":"add","path":"/foo/1","value":"qux"}]',
    '{"foo":["bar","qux","baz"]}',
    'RFC A.2 add array element');

  CheckPatch(
    '{"baz":"qux","foo":"bar"}',
    '[{"op":"remove","path":"/baz"}]',
    '{"foo":"bar"}',
    'RFC A.3 remove object member');

  CheckPatch(
    '{"foo":["bar","qux","baz"]}',
    '[{"op":"remove","path":"/foo/1"}]',
    '{"foo":["bar","baz"]}',
    'RFC A.4 remove array element');

  CheckPatch(
    '{"baz":"qux","foo":"bar"}',
    '[{"op":"replace","path":"/baz","value":"boo"}]',
    '{"baz":"boo","foo":"bar"}',
    'RFC A.5 replace value');

  CheckPatch(
    '{"foo":{"bar":"baz","waldo":"fred"},"qux":{"corge":"grault"}}',
    '[{"op":"move","from":"/foo/waldo","path":"/qux/thud"}]',
    '{"foo":{"bar":"baz"},"qux":{"corge":"grault","thud":"fred"}}',
    'RFC A.6 move value');

  CheckPatch(
    '{"foo":["all","grass","cows","eat"]}',
    '[{"op":"move","from":"/foo/1","path":"/foo/3"}]',
    '{"foo":["all","cows","eat","grass"]}',
    'RFC A.7 move array element');

  CheckPatch(
    '{"baz":"qux","foo":["a",2,"c"]}',
    '[{"op":"test","path":"/baz","value":"qux"},' +
    '{"op":"test","path":"/foo/1","value":2}]',
    '{"baz":"qux","foo":["a",2,"c"]}',
    'RFC A.8 test success');

  CheckPatchError(
    '{"baz":"qux"}',
    '[{"op":"test","path":"/baz","value":"bar"}]',
    'RFC A.9 test failure');

  CheckPatch(
    '{"foo":"bar"}',
    '[{"op":"add","path":"/child","value":{"grandchild":{}}}]',
    '{"foo":"bar","child":{"grandchild":{}}}',
    'RFC A.10 nested value');

  CheckPatch(
    '{"foo":"bar"}',
    '[{"op":"add","path":"/baz","value":"qux","xyz":123}]',
    '{"foo":"bar","baz":"qux"}',
    'RFC A.11 unknown members ignored');

  CheckPatchError(
    '{"foo":"bar"}',
    '[{"op":"add","path":"/baz/bat","value":"qux"}]',
    'RFC A.12 missing target parent');

  CheckPatch(
    '{"/":9,"~1":10}',
    '[{"op":"test","path":"/~01","value":10}]',
    '{"/":9,"~1":10}',
    'RFC A.14 pointer escape ordering');

  CheckPatchError(
    '{"/":9,"~1":10}',
    '[{"op":"test","path":"/~01","value":"10"}]',
    'RFC A.15 number differs from string');

  CheckPatch(
    '{"foo":["bar"]}',
    '[{"op":"add","path":"/foo/-","value":["abc","def"]}]',
    '{"foo":["bar",["abc","def"]]}',
    'RFC A.16 append array value without flattening');
end;

procedure TestAddSemantics;
begin
  CheckPatch(
    '{"foo":null}',
    '[{"op":"add","path":"/foo","value":1}]',
    '{"foo":1}',
    'add replaces existing object member');

  CheckPatch(
    '[1,2]',
    '[{"op":"add","path":"/2","value":3}]',
    '[1,2,3]',
    'add at array Count appends');

  CheckPatch(
    '[1,2]',
    '[{"op":"add","path":"/-","value":3}]',
    '[1,2,3]',
    'dash appends to array');

  CheckPatch(
    '[1,2,[3,[4,5]]]',
    '[{"op":"add","path":"/2/1/-","value":{"foo":["bar","baz"]}}]',
    '[1,2,[3,[4,5,{"foo":["bar","baz"]}]]]',
    'nested dash append');

  CheckPatchError(
    '[1,2]',
    '[{"op":"add","path":"/3","value":3}]',
    'add index greater than Count fails');

  CheckPatchError(
    '[1,2]',
    '[{"op":"add","path":"/01","value":3}]',
    'add rejects leading-zero array index');

  CheckPatchError(
    '[1,2]',
    '[{"op":"add","path":"/1e0","value":3}]',
    'add rejects non-decimal array index');

  CheckPatch(
    '{}',
    '[{"op":"add","path":"/","value":1}]',
    '{"":1}',
    'slash path addresses empty object member');

  CheckPatch(
    '{"foo":{}}',
    '[{"op":"add","path":"/foo/","value":1}]',
    '{"foo":{"":1}}',
    'trailing slash preserves empty final token');

  CheckPatch(
    '{"foo":"bar"}',
    '[{"op":"add","path":"/FOO","value":"BAR"}]',
    '{"foo":"bar","FOO":"BAR"}',
    'object member names are case-sensitive');

  CheckPatch(
    '{}',
    '[{"op":"add","path":"/-","value":1}]',
    '{"-":1}',
    'dash is an ordinary object member name');
end;

procedure TestRemoveAndReplaceSemantics;
begin
  CheckPatch(
    '[1,2,3,4]',
    '[{"op":"remove","path":"/0"},' +
    '{"op":"remove","path":"/2"}]',
    '[2,3]',
    'sequential array removes use current document');

  CheckPatchError(
    '{"foo":"bar"}',
    '[{"op":"remove","path":"/missing"}]',
    'remove requires existing object member');

  CheckPatchError(
    '[1,2]',
    '[{"op":"remove","path":"/2"}]',
    'remove requires existing array element');

  CheckPatchError(
    '[1,2]',
    '[{"op":"remove","path":"/-"}]',
    'remove does not accept dash');

  CheckPatch(
    '["foo"]',
    '[{"op":"replace","path":"/0","value":{"x":1}}]',
    '[{"x":1}]',
    'replace array item');

  CheckPatchError(
    '{"foo":"bar"}',
    '[{"op":"replace","path":"/missing","value":1}]',
    'replace requires existing target');

  CheckPatchError(
    '[1]',
    '[{"op":"replace","path":"/1e0","value":2}]',
    'replace rejects invalid array index');
end;

procedure TestMoveAndCopySemantics;
begin
  CheckPatch(
    '{"foo":1}',
    '[{"op":"move","from":"/foo","path":"/foo"}]',
    '{"foo":1}',
    'move to same location is no-op');

  CheckPatchError(
    '{"a":{"b":1}}',
    '[{"op":"move","from":"/a","path":"/a/b/c"}]',
    'move cannot move value into its child');

  CheckPatchError(
    '{"a":1}',
    '[{"op":"move","from":"/missing","path":"/b"}]',
    'move from must exist');

  CheckPatchError(
    '{"a":1}',
    '[{"op":"copy","from":"/missing","path":"/b"}]',
    'copy from must exist');

  CheckPatchError(
    '{"a":[1,2]}',
    '[{"op":"move","from":"/a/1e0","path":"/b"}]',
    'move from rejects invalid array index');

  CheckPatchError(
    '{"a":[1,2]}',
    '[{"op":"copy","from":"/a/01","path":"/b"}]',
    'copy from rejects leading-zero array index');

  CheckPatch(
    '{"a":{"x":1}}',
    '[{"op":"copy","from":"/a","path":"/b"},' +
    '{"op":"replace","path":"/a/x","value":2}]',
    '{"a":{"x":2},"b":{"x":1}}',
    'copy creates an independent deep copy');

  CheckPatch(
    '{"foo":null}',
    '[{"op":"move","from":"/foo","path":"/bar"}]',
    '{"bar":null}',
    'move preserves JSON null');

  CheckPatch(
    '{"foo":null}',
    '[{"op":"copy","from":"/foo","path":"/bar"}]',
    '{"foo":null,"bar":null}',
    'copy preserves JSON null');
end;

procedure TestSemanticTestOperation;
begin
  CheckPatch(
    '{"1e0":"foo"}',
    '[{"op":"test","path":"/1e0","value":"foo"}]',
    '{"1e0":"foo"}',
    'numeric-looking token remains valid object member name');

  CheckPatchError(
    '["foo","bar"]',
    '[{"op":"test","path":"/01","value":"bar"}]',
    'test rejects leading-zero array index');

  CheckPatch(
    '{"n":1,"obj":{"a":1,"b":2}}',
    '[{"op":"test","path":"/n","value":1.0},' +
    '{"op":"test","path":"/obj","value":{"b":2.0,"a":1}}]',
    '{"n":1,"obj":{"a":1,"b":2}}',
    'test uses semantic DeepEquals');

  CheckPatch(
    '{"n":9007199254740993}',
    '[{"op":"test","path":"/n","value":9007199254740993.0}]',
    '{"n":9007199254740993}',
    'test keeps exact number precision');

  CheckPatchError(
    '{"n":9007199254740993}',
    '[{"op":"test","path":"/n","value":9007199254740992}]',
    'test distinguishes large exact numbers');

  CheckPatchError(
    '{"a":[1,2]}',
    '[{"op":"test","path":"/a","value":[2,1]}]',
    'test keeps array order significant');
end;

procedure TestRootOperations;
var
  Document, Patched: TJsonValue;
begin
  CheckPatch(
    '"foo"',
    '[{"op":"replace","path":"","value":"bar"}]',
    '"bar"',
    'replace supports scalar root document');

  CheckPatch(
    '[]',
    '[{"op":"add","path":"/-","value":"hi"}]',
    '["hi"]',
    'dash appends to root array document');

  CheckPatch(
    '{"foo":"bar"}',
    '[{"op":"add","path":"","value":{"baz":"qux"}}]',
    '{"baz":"qux"}',
    'add can replace whole document');

  CheckPatch(
    '{"foo":"bar"}',
    '[{"op":"replace","path":"","value":[1,2]}]',
    '[1,2]',
    'replace can replace whole document');

  CheckPatch(
    '{"foo":1}',
    '[{"op":"test","path":"","value":{"foo":1.0}}]',
    '{"foo":1}',
    'test can address whole document');

  CheckPatch(
    '{"foo":1}',
    '[{"op":"remove","path":""},' +
    '{"op":"add","path":"","value":[1,2]}]',
    '[1,2]',
    'root can be removed and then recreated');

  Document := Parse('{"foo":1}');
  try
    Patched := TJsonPatch.Apply(Document, '[{"op":"remove","path":""}]');
    try
      Check(Patched = nil, 'remove root returns nil document');
      CheckJsonEqual('{"foo":1}', Document, 'remove root must not mutate source');
    finally
      Patched.Free;
    end;
  finally
    Document.Free;
  end;
end;

procedure TestValidationAndAtomicity;
var
  Document, PatchDom, Patched: TJsonValue;
  PatchBefore, ErrorMessage: string;
begin
  CheckPatchError('{}', '{}', 'patch document must be array');
  CheckPatchError('{}', '[1]', 'operation must be object');
  CheckPatchError('{}', '[{"path":"/a","value":1}]', 'op is required');
  CheckPatchError('{}', '[{"op":"add","value":1}]', 'path is required');
  CheckPatchError('{}', '[{"op":"add","path":null,"value":1}]',
    'path must be string');
  CheckPatchError('{}', '[{"op":"spam","path":"/a"}]',
    'unknown operation fails');
  CheckPatchError('[]', '[{"op":"add","path":"/-"}]',
    'add requires value');
  CheckPatchError('[1]', '[{"op":"replace","path":"/0"}]',
    'replace requires value');
  CheckPatchError('[null]', '[{"op":"test","path":"/0"}]',
    'test requires value');
  CheckPatchError('[1]', '[{"op":"copy","path":"/-"}]',
    'copy requires from');
  CheckPatchError('{"a":1}', '[{"op":"move","path":"/b"}]',
    'move requires from');
  CheckPatchError('{}', '[{"op":"add","path":"bad","value":1}]',
    'path must be valid JSON Pointer');
  CheckPatchError('{}', '[{"op":"add","path":"/~2","value":1}]',
    'invalid JSON Pointer escape fails');
  CheckPatchError('{}', '[{"op":"Add","path":"/a","value":1}]',
    'operation names are case-sensitive');
  CheckPatchError('{}', '[{"op":null,"path":"/a","value":1}]',
    'op must be string');
  CheckPatchError('{}', '{', 'malformed JSON Patch text fails');
  CheckPatchError('{}',
    '[{"op":"add","op":"remove","path":"/a","value":1}]',
    'duplicate op member is invalid JSON Patch');

  // Unknown members are ignored even if they have types that would be wrong
  // for another operation.
  CheckPatch(
    '{}',
    '[{"op":"add","path":"/a","value":1,"from":42,"ignored":null}]',
    '{"a":1}',
    'irrelevant operation members are ignored');

  Document := Parse('{"a":1}');
  try
    Patched := nil;
    ErrorMessage := '';
    Check(not TJsonPatch.TryApply(Document,
      '[{"op":"replace","path":"/a","value":2},' +
      '{"op":"remove","path":"/missing"}]',
      Patched, ErrorMessage),
      'failed later operation makes whole TryApply fail');
    Check(Patched = nil, 'failed transactional patch returns no partial result');
    CheckJsonEqual('{"a":1}', Document,
      'failed transactional patch leaves source unchanged');
  finally
    Patched.Free;
    Document.Free;
  end;

  Document := Parse('{"a":1}');
  try
    PatchDom := Parse('[{"op":"add","path":"/b","value":{"x":1}}]');
    try
      PatchBefore := PatchDom.ToJson;
      Patched := TJsonPatch.Apply(Document, PatchDom);
      try
        CheckJsonEqual('{"a":1,"b":{"x":1}}', Patched,
          'DOM overload applies patch');
        Check(PatchDom.ToJson = PatchBefore, 'patch DOM must not be mutated');
      finally
        Patched.Free;
      end;
    finally
      PatchDom.Free;
    end;
  finally
    Document.Free;
  end;
end;

procedure TestEmptyPatch;
var
  Document, Patched: TJsonValue;
begin
  Document := Parse('{"a":1}');
  try
    Patched := TJsonPatch.Apply(Document, '[]');
    try
      Check(Patched <> Document, 'empty patch still returns owned clone');
      CheckJsonEqual('{"a":1}', Patched, 'empty patch preserves content');
      CheckJsonEqual('{"a":1}', Document, 'empty patch preserves source');
    finally
      Patched.Free;
    end;
  finally
    Document.Free;
  end;
end;

begin
  try
    TestRfcExamples;
    TestAddSemantics;
    TestRemoveAndReplaceSemantics;
    TestMoveAndCopySemantics;
    TestSemanticTestOperation;
    TestRootOperations;
    TestValidationAndAtomicity;
    TestEmptyPatch;
    Writeln('NativeJson.Patch: ALL TESTS PASSED');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
