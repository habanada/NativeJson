{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_Pointer;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  NativeJson.Compat,
  NativeJson.Main,
  NativeJson.Dom.Value,
  NativeJson.Dom.Io;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create('FAILED: ' + MessageText);
end;

procedure CheckText(const Expected, Actual, MessageText: string);
begin
  if Actual <> Expected then
    raise Exception.CreateFmt('FAILED: %s. Expected "%s", got "%s"',
      [MessageText, Expected, Actual]);
end;

procedure CheckInt(Expected, Actual: Int64; const MessageText: string);
begin
  if Actual <> Expected then
    raise Exception.CreateFmt('FAILED: %s. Expected %d, got %d',
      [MessageText, Expected, Actual]);
end;

function RaisesPointerError(const Proc: TProc): Boolean;
begin
  Result := False;
  try
    Proc();
  except
    on E: EJsonPointerError do Result := True;
  end;
end;

procedure TestEscapeAndUnescape;
var
  Decoded: string;
begin
  CheckText('a~1b~0c', TJsonPointer.Escape('a/b~c'), 'Escape order');
  CheckText('a/b~c', TJsonPointer.Unescape('a~1b~0c'), 'Unescape');
  CheckText('~1', TJsonPointer.Unescape('~01'), 'Unescape must decode left-to-right');
  Check(TJsonPointer.TryUnescape('', Decoded), 'Empty token is valid');
  CheckText('', Decoded, 'Empty token stays empty');

  Check(not TJsonPointer.TryUnescape('~', Decoded), 'Dangling tilde is invalid');
  Check(not TJsonPointer.TryUnescape('~2', Decoded), 'Unknown escape is invalid');
  Check(RaisesPointerError(
    procedure
    begin
      TJsonPointer.Unescape('abc~x');
    end), 'Unescape must raise on invalid escape');
end;

procedure TestRfc6901Examples;
var
  Root, Value: TJsonValue;
begin
  Root := DomFromText(
    '{' +
    '"foo":["bar","baz"],' +
    '"":0,' +
    '"a/b":1,' +
    '"c%d":2,' +
    '"e^f":3,' +
    '"g|h":4,' +
    '"i\\j":5,' +
    '"k\"l":6,' +
    '" ":7,' +
    '"m~n":8' +
    '}');
  try
    Check(TJsonPointer.Resolve(Root, '') = Root, 'Empty pointer identifies root');
    CheckText('bar', TJsonPointer.Resolve(Root, '/foo/0').AsString, '/foo/0');
    CheckText('baz', TJsonPointer.Resolve(Root, '/foo/1').AsString, '/foo/1');
    CheckInt(0, TJsonPointer.Resolve(Root, '/').AsInteger, '/');
    CheckInt(1, TJsonPointer.Resolve(Root, '/a~1b').AsInteger, '/a~1b');
    CheckInt(2, TJsonPointer.Resolve(Root, '/c%d').AsInteger, '/c%d');
    CheckInt(3, TJsonPointer.Resolve(Root, '/e^f').AsInteger, '/e^f');
    CheckInt(4, TJsonPointer.Resolve(Root, '/g|h').AsInteger, '/g|h');
    CheckInt(5, TJsonPointer.Resolve(Root, '/i\j').AsInteger, '/i\j');
    CheckInt(6, TJsonPointer.Resolve(Root, '/k"l').AsInteger, '/k"l');
    CheckInt(7, TJsonPointer.Resolve(Root, '/ ').AsInteger, '/ ');
    CheckInt(8, TJsonPointer.Resolve(Root, '/m~0n').AsInteger, '/m~0n');

    Value := Root;
    Check(not TJsonPointer.TryResolve(Root, '/missing', Value),
      'TryResolve returns false for missing member');
    Check(Value = nil, 'TryResolve clears output on failure');
  finally
    Root.Free;
  end;
end;

procedure TestEmptyReferenceTokens;
var
  Root: TJsonValue;
begin
  Root := DomFromText('{"":{"":"deep"}}');
  try
    CheckText('deep', TJsonPointer.Resolve(Root, '//').AsString,
      'Empty reference tokens must not be dropped');
  finally
    Root.Free;
  end;
end;

procedure TestStrictArrayIndices;
var
  Root, ObjectRoot, Value: TJsonValue;
begin
  Root := DomFromText('{"items":[10,20]}');
  try
    CheckInt(10, TJsonPointer.Resolve(Root, '/items/0').AsInteger,
      'Array index zero');
    CheckInt(20, TJsonPointer.Resolve(Root, '/items/1').AsInteger,
      'Array index one');

    Check(not TJsonPointer.TryResolve(Root, '/items/01', Value),
      'Leading zero is not an RFC array index');
    Check(not TJsonPointer.TryResolve(Root, '/items/+1', Value),
      'Plus sign is not an RFC array index');
    Check(not TJsonPointer.TryResolve(Root, '/items/-1', Value),
      'Negative index is not an RFC array index');
    Check(not TJsonPointer.TryResolve(Root, '/items/-', Value),
      'Dash does not identify an existing array value');
    Check(not TJsonPointer.TryResolve(Root, '/items/2', Value),
      'Out-of-range index fails');
  finally
    Root.Free;
  end;

  ObjectRoot := DomFromText('{"01":"legal object key","-":"also legal"}');
  try
    CheckText('legal object key', TJsonPointer.Resolve(ObjectRoot, '/01').AsString,
      'Index-like object key stays legal');
    CheckText('also legal', TJsonPointer.Resolve(ObjectRoot, '/-').AsString,
      'Dash is legal as object member name');
  finally
    ObjectRoot.Free;
  end;
end;

procedure TestParentResolution;
var
  Root, Parent, ExpectedParent: TJsonValue;
  Token: string;
begin
  Root := DomFromText('{"items":[{"name":"A"},{"name":"B"}],"a/b":1}');
  try
    Parent := TJsonPointer.ResolveParent(Root, '/items/1/name', Token);
    ExpectedParent := TJsonPointer.Resolve(Root, '/items/1');
    Check(Parent = ExpectedParent, 'ResolveParent returns direct parent');
    CheckText('name', Token, 'ResolveParent returns decoded final token');

    Parent := TJsonPointer.ResolveParent(Root, '/a~1b', Token);
    Check(Parent = Root, 'Single-token pointer parent is root');
    CheckText('a/b', Token, 'Final token is unescaped');

    Parent := TJsonPointer.ResolveParent(Root, '/', Token);
    Check(Parent = Root, 'Empty member parent is root');
    CheckText('', Token, 'Empty final token is preserved');

    Parent := TJsonPointer.ResolveParent(Root, '/items/-', Token);
    Check(Parent = TJsonPointer.Resolve(Root, '/items'),
      'Dash final token still returns array parent');
    CheckText('-', Token, 'Dash final token is preserved for JSON Patch');

    Parent := Root;
    Token := 'old';
    Check(not TJsonPointer.TryResolveParent(Root, '', Parent, Token),
      'Root pointer has no parent');
    Check(Parent = nil, 'TryResolveParent clears parent on failure');
    CheckText('', Token, 'TryResolveParent clears token on failure');
  finally
    Root.Free;
  end;
end;

procedure TestInvalidPointersAndScalars;
var
  Root, Value, Parent: TJsonValue;
  Token: string;
begin
  Root := DomFromText('{"value":42,"obj":{"~2":"literal"}}');
  try
    Check(not TJsonPointer.TryResolve(Root, 'value', Value),
      'Non-empty pointer needs leading slash');
    Check(not TJsonPointer.TryResolve(Root, '/obj/~2', Value),
      'Invalid escape is rejected even when a similarly named member exists');
    Check(not TJsonPointer.TryResolve(Root, '/value/x', Value),
      'Cannot traverse scalar');
    Check(not TJsonPointer.TryResolveParent(Root, '/value/x', Parent, Token),
      'Scalar cannot be a parent container');

    Check(RaisesPointerError(
      procedure
      begin
        TJsonPointer.Resolve(Root, '/missing');
      end), 'Resolve raises EJsonPointerError');
  finally
    Root.Free;
  end;

  Value := nil;
  Check(not TJsonPointer.TryResolve(nil, '', Value), 'Nil root fails safely');
end;

procedure TestUnicode;
var
  Root: TJsonValue;
begin
  Root := DomFromText('{"ä":"Grüße","東京":"ok"}');
  try
    CheckText('Grüße', TJsonPointer.Resolve(Root, '/ä').AsString,
      'Unicode member name');
    CheckText('ok', TJsonPointer.Resolve(Root, '/東京').AsString,
      'Unicode pointer token');
  finally
    Root.Free;
  end;
end;

begin
  try
    TestEscapeAndUnescape;
    TestRfc6901Examples;
    TestEmptyReferenceTokens;
    TestStrictArrayIndices;
    TestParentResolution;
    TestInvalidPointersAndScalars;
    TestUnicode;
    Writeln('NativeJson.Pointer: ALL TESTS PASSED');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
