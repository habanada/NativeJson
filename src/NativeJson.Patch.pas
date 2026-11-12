{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Patch;

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
  /// <summary>Error while validating or applying a JSON Patch (RFC 6902).</summary>
  EJsonPatchError = class(EJsonValueError);

  /// <summary>
  ///   RFC 6902 JSON Patch for the NativeJson DOM.
  ///
  ///   Apply works transactionally on a deep copy of the document:
  ///   the given Document is never changed. The caller owns the
  ///   returned result. A successful Remove of the root path can
  ///   return nil (no document left).
  /// </summary>
  TJsonPatch = class abstract
  private
    class function TryParseArrayIndex(const Token: string; out Index: Integer): Boolean; static;
    class function RequiredString(Operation: TJsonValue; const MemberName: string;
      OperationIndex: Integer): string; static;
    class function RequiredValue(Operation: TJsonValue; const MemberName: string;
      OperationIndex: Integer): TJsonValue; static;
    class procedure RaiseOperationError(OperationIndex: Integer;
      const OperationName, Path, MessageText: string); static;
    class function ResolveValue(Document: TJsonValue; const JsonPointer: string;
      OperationIndex: Integer; const OperationName: string): TJsonValue; static;
    class function ResolveParent(Document: TJsonValue; const JsonPointer: string;
      OperationIndex: Integer; const OperationName: string;
      out Token: string): TJsonValue; static;
    class function IsProperPointerPrefix(const Prefix, JsonPointer: string): Boolean; static;
    class procedure AddOwned(var Document: TJsonValue; const Path: string;
      var Value: TJsonValue; OperationIndex: Integer; const OperationName: string); static;
    class procedure RemoveValue(var Document: TJsonValue; const Path: string;
      OperationIndex: Integer; const OperationName: string); static;
    class procedure ReplaceOwned(var Document: TJsonValue; const Path: string;
      var Value: TJsonValue; OperationIndex: Integer; const OperationName: string); static;
    class procedure ApplyOperation(var Document: TJsonValue; Operation: TJsonValue;
      OperationIndex: Integer); static;
  public
    /// <summary>
    ///   Applies an already parsed JSON Patch array and returns a new
    ///   DOM. Document and Patch stay unchanged.
    /// </summary>
    class function Apply(const Document, Patch: TJsonValue): TJsonValue; overload; static;

    /// <summary>
    ///   Parses and applies a JSON Patch document. The caller owns the
    ///   result.
    /// </summary>
    class function Apply(const Document: TJsonValue;
      const PatchJson: string): TJsonValue; overload; static;

    /// <summary>Non-raising variant for an already parsed patch DOM.</summary>
    class function TryApply(const Document, Patch: TJsonValue;
      out Patched: TJsonValue; out ErrorMessage: string): Boolean; overload; static;

    /// <summary>Non-raising variant for JSON Patch text.</summary>
    class function TryApply(const Document: TJsonValue; const PatchJson: string;
      out Patched: TJsonValue; out ErrorMessage: string): Boolean; overload; static;
  end;

implementation

uses
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.Io,
  NativeJson.Pointer,
  NativeJson.Comparer;

class function TJsonPatch.TryParseArrayIndex(const Token: string;
  out Index: Integer): Boolean;
var
  I: Integer;
begin
  Index := -1;
  if Token = '' then Exit(False);

  // RFC 6901 array-index = %x30 / (%x31-39 *(%x30-39)).
  // The RFC 6902 special token "-" is handled separately by the caller.
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

class procedure TJsonPatch.RaiseOperationError(OperationIndex: Integer;
  const OperationName, Path, MessageText: string);
var
  Prefix: string;
begin
  Prefix := Format('JSON Patch operation %d', [OperationIndex]);
  if OperationName <> '' then
    Prefix := Prefix + Format(' (%s)', [OperationName]);
  if Path <> '' then
    Prefix := Prefix + Format(' at "%s"', [Path]);
  raise EJsonPatchError.Create(Prefix + ': ' + MessageText);
end;

class function TJsonPatch.RequiredString(Operation: TJsonValue;
  const MemberName: string; OperationIndex: Integer): string;
var
  Obj: TJsonObject;
  Value: TJsonValue;
begin
  Value := nil;
  Obj := TJsonObject(Operation);
  if not Obj.TryGetValue(MemberName, Value) then
    RaiseOperationError(OperationIndex, '', '',
      Format('required member "%s" is missing', [MemberName]));

  if Value.GetJsonType <> TJsonType.jtString then
    RaiseOperationError(OperationIndex, '', '',
      Format('member "%s" must be a string', [MemberName]));

  Result := Value.AsString;
end;

class function TJsonPatch.RequiredValue(Operation: TJsonValue;
  const MemberName: string; OperationIndex: Integer): TJsonValue;
var
  Obj: TJsonObject;
begin
  Obj := TJsonObject(Operation);
  Result := nil;
  if not Obj.TryGetValue(MemberName, Result) then
    RaiseOperationError(OperationIndex, '', '',
      Format('required member "%s" is missing', [MemberName]));
end;

class function TJsonPatch.ResolveValue(Document: TJsonValue;
  const JsonPointer: string; OperationIndex: Integer;
  const OperationName: string): TJsonValue;
begin
  Result := nil;
  if Document = nil then
    RaiseOperationError(OperationIndex, OperationName, JsonPointer,
      'target document does not exist');

  try
    Result := TJsonPointer.Resolve(Document, JsonPointer);
  except
    on E: EJsonPointerError do
      RaiseOperationError(OperationIndex, OperationName, JsonPointer, E.Message);
  end;
end;

class function TJsonPatch.ResolveParent(Document: TJsonValue;
  const JsonPointer: string; OperationIndex: Integer;
  const OperationName: string; out Token: string): TJsonValue;
begin
  Result := nil;
  Token := '';
  if Document = nil then
    RaiseOperationError(OperationIndex, OperationName, JsonPointer,
      'target document does not exist');

  try
    Result := TJsonPointer.ResolveParent(Document, JsonPointer, Token);
  except
    on E: EJsonPointerError do
      RaiseOperationError(OperationIndex, OperationName, JsonPointer, E.Message);
  end;
end;

class function TJsonPatch.IsProperPointerPrefix(const Prefix,
  JsonPointer: string): Boolean;
begin
  if Prefix = '' then
    Exit(JsonPointer <> '');

  Result :=
    (Length(JsonPointer) > Length(Prefix)) and
    (Copy(JsonPointer, 1, Length(Prefix)) = Prefix) and
    (JsonPointer[Length(Prefix) + 1] = '/');
end;

class procedure TJsonPatch.AddOwned(var Document: TJsonValue;
  const Path: string; var Value: TJsonValue; OperationIndex: Integer;
  const OperationName: string);
var
  Parent, Transferred: TJsonValue;
  Obj: TJsonObject;
  Arr: TJsonArray;
  Token: string;
  Index: Integer;
begin
  if Value = nil then
    RaiseOperationError(OperationIndex, OperationName, Path,
      'internal add value must not be nil');
  if Value.Parent <> nil then
    RaiseOperationError(OperationIndex, OperationName, Path,
      'internal add value must be detached');

  if Path = '' then
  begin
    Document.Free;
    Document := Value;
    Value := nil;
    Exit;
  end;

  Parent := ResolveParent(Document, Path, OperationIndex, OperationName, Token);
  if Parent is TJsonObject then
  begin
    Obj := TJsonObject(Parent);
    // TJsonObject.SetAttribute takes over the value and also frees it on
    // its error path. Hand over ownership visibly before the call, so
    // the caller does not free it twice there.
    Transferred := Value;
    Value := nil;
    Obj.Values[Token] := Transferred;
    Exit;
  end;

  if Parent is TJsonArray then
  begin
    Arr := TJsonArray(Parent);
    if Token = '-' then
    begin
      Arr.Add(Value);
      Value := nil;
      Exit;
    end;

    if not TryParseArrayIndex(Token, Index) then
      RaiseOperationError(OperationIndex, OperationName, Path,
        Format('invalid array index "%s"', [Token]));
    if Index > Arr.Count then
      RaiseOperationError(OperationIndex, OperationName, Path,
        Format('array index %d is greater than the array length %d',
          [Index, Arr.Count]));

    if Index = Arr.Count then
      Arr.Add(Value)
    else
      Arr.Insert(Index, Value);
    Value := nil;
    Exit;
  end;

  RaiseOperationError(OperationIndex, OperationName, Path,
    'target parent must be an object or array');
end;

class procedure TJsonPatch.RemoveValue(var Document: TJsonValue;
  const Path: string; OperationIndex: Integer; const OperationName: string);
var
  Parent: TJsonValue;
  Obj: TJsonObject;
  Arr: TJsonArray;
  Token: string;
  Index: Integer;
begin
  if Path = '' then
  begin
    if Document = nil then
      RaiseOperationError(OperationIndex, OperationName, Path,
        'target document does not exist');
    Document.Free;
    Document := nil;
    Exit;
  end;

  Parent := ResolveParent(Document, Path, OperationIndex, OperationName, Token);
  if Parent is TJsonObject then
  begin
    Obj := TJsonObject(Parent);
    if not Obj.Remove(Token) then
      RaiseOperationError(OperationIndex, OperationName, Path,
        Format('object member "%s" does not exist', [Token]));
    Exit;
  end;

  if Parent is TJsonArray then
  begin
    Arr := TJsonArray(Parent);
    if not TryParseArrayIndex(Token, Index) then
      RaiseOperationError(OperationIndex, OperationName, Path,
        Format('invalid array index "%s"', [Token]));
    if Index >= Arr.Count then
      RaiseOperationError(OperationIndex, OperationName, Path,
        Format('array index %d is out of range', [Index]));
    Arr.Delete(Index);
    Exit;
  end;

  RaiseOperationError(OperationIndex, OperationName, Path,
    'target parent must be an object or array');
end;

class procedure TJsonPatch.ReplaceOwned(var Document: TJsonValue;
  const Path: string; var Value: TJsonValue; OperationIndex: Integer;
  const OperationName: string);
var
  Parent, Transferred: TJsonValue;
  Obj: TJsonObject;
  Arr: TJsonArray;
  Token: string;
  Index: Integer;
begin
  if Value = nil then
    RaiseOperationError(OperationIndex, OperationName, Path,
      'internal replacement value must not be nil');
  if Value.Parent <> nil then
    RaiseOperationError(OperationIndex, OperationName, Path,
      'internal replacement value must be detached');

  if Path = '' then
  begin
    if Document = nil then
      RaiseOperationError(OperationIndex, OperationName, Path,
        'target document does not exist');
    Document.Free;
    Document := Value;
    Value := nil;
    Exit;
  end;

  Parent := ResolveParent(Document, Path, OperationIndex, OperationName, Token);
  if Parent is TJsonObject then
  begin
    Obj := TJsonObject(Parent);
    if not Obj.Contains(Token) then
      RaiseOperationError(OperationIndex, OperationName, Path,
        Format('object member "%s" does not exist', [Token]));
    Transferred := Value;
    Value := nil;
    Obj.Values[Token] := Transferred;
    Exit;
  end;

  if Parent is TJsonArray then
  begin
    Arr := TJsonArray(Parent);
    if not TryParseArrayIndex(Token, Index) then
      RaiseOperationError(OperationIndex, OperationName, Path,
        Format('invalid array index "%s"', [Token]));
    if Index >= Arr.Count then
      RaiseOperationError(OperationIndex, OperationName, Path,
        Format('array index %d is out of range', [Index]));
    Arr[Index] := Value;
    Value := nil;
    Exit;
  end;

  RaiseOperationError(OperationIndex, OperationName, Path,
    'target parent must be an object or array');
end;

class procedure TJsonPatch.ApplyOperation(var Document: TJsonValue;
  Operation: TJsonValue; OperationIndex: Integer);
var
  Obj: TJsonObject;
  OperationName, Path, FromPath: string;
  Value, SourceValue, OwnedValue, ActualValue: TJsonValue;
begin
  if not (Operation is TJsonObject) then
    RaiseOperationError(OperationIndex, '', '', 'operation must be an object');

  Obj := TJsonObject(Operation);
  OperationName := RequiredString(Obj, 'op', OperationIndex);
  Path := RequiredString(Obj, 'path', OperationIndex);

  if OperationName = 'add' then
  begin
    Value := RequiredValue(Obj, 'value', OperationIndex);
    OwnedValue := Value.Clone;
    try
      AddOwned(Document, Path, OwnedValue, OperationIndex, OperationName);
    finally
      OwnedValue.Free;
    end;
    Exit;
  end;

  if OperationName = 'remove' then
  begin
    RemoveValue(Document, Path, OperationIndex, OperationName);
    Exit;
  end;

  if OperationName = 'replace' then
  begin
    Value := RequiredValue(Obj, 'value', OperationIndex);
    OwnedValue := Value.Clone;
    try
      ReplaceOwned(Document, Path, OwnedValue, OperationIndex, OperationName);
    finally
      OwnedValue.Free;
    end;
    Exit;
  end;

  if OperationName = 'move' then
  begin
    FromPath := RequiredString(Obj, 'from', OperationIndex);
    SourceValue := ResolveValue(Document, FromPath, OperationIndex, OperationName);

    // According to the RFC the same location is semantically a no-op. ResolveValue above
    // is deliberately executed before, so that a non-existent "from"
    // still fails correctly.
    if FromPath = Path then Exit;

    if IsProperPointerPrefix(FromPath, Path) then
      RaiseOperationError(OperationIndex, OperationName, Path,
        'the from location must not be a proper prefix of the path location');

    OwnedValue := SourceValue.Clone;
    try
      RemoveValue(Document, FromPath, OperationIndex, OperationName);
      AddOwned(Document, Path, OwnedValue, OperationIndex, OperationName);
    finally
      OwnedValue.Free;
    end;
    Exit;
  end;

  if OperationName = 'copy' then
  begin
    FromPath := RequiredString(Obj, 'from', OperationIndex);
    SourceValue := ResolveValue(Document, FromPath, OperationIndex, OperationName);
    OwnedValue := SourceValue.Clone;
    try
      AddOwned(Document, Path, OwnedValue, OperationIndex, OperationName);
    finally
      OwnedValue.Free;
    end;
    Exit;
  end;

  if OperationName = 'test' then
  begin
    Value := RequiredValue(Obj, 'value', OperationIndex);
    ActualValue := ResolveValue(Document, Path, OperationIndex, OperationName);
    if not TJsonComparer.DeepEquals(ActualValue, Value) then
      RaiseOperationError(OperationIndex, OperationName, Path,
        'test value does not equal the target value');
    Exit;
  end;

  RaiseOperationError(OperationIndex, OperationName, Path,
    Format('unknown operation "%s"', [OperationName]));
end;

class function TJsonPatch.Apply(const Document, Patch: TJsonValue): TJsonValue;
var
  PatchArray: TJsonArray;
  Working: TJsonValue;
  I: Integer;
begin
  if Document = nil then
    raise EJsonPatchError.Create('JSON Patch document target must not be nil');
  if Patch = nil then
    raise EJsonPatchError.Create('JSON Patch must not be nil');
  if not (Patch is TJsonArray) then
    raise EJsonPatchError.Create('JSON Patch document must be an array');

  PatchArray := TJsonArray(Patch);
  Working := Document.Clone;
  try
    for I := 0 to PatchArray.Count - 1 do
      ApplyOperation(Working, PatchArray[I], I);
    Result := Working;
    Working := nil;
  finally
    Working.Free;
  end;
end;

class function TJsonPatch.Apply(const Document: TJsonValue;
  const PatchJson: string): TJsonValue;
var
  Patch: TJsonValue;
begin
  Patch := nil;
  try
    try
      Patch := DomFromText(PatchJson);
    except
      on E: Exception do
        raise EJsonPatchError.CreateFmt('Invalid JSON Patch document: %s',
          [E.Message]);
    end;
    Result := Apply(Document, Patch);
  finally
    Patch.Free;
  end;
end;

class function TJsonPatch.TryApply(const Document, Patch: TJsonValue;
  out Patched: TJsonValue; out ErrorMessage: string): Boolean;
begin
  Patched := nil;
  ErrorMessage := '';
  try
    Patched := Apply(Document, Patch);
    Result := True;
  except
    on E: EJsonPatchError do
    begin
      Patched.Free;
      Patched := nil;
      ErrorMessage := E.Message;
      Result := False;
    end;
  end;
end;

class function TJsonPatch.TryApply(const Document: TJsonValue;
  const PatchJson: string; out Patched: TJsonValue;
  out ErrorMessage: string): Boolean;
begin
  Patched := nil;
  ErrorMessage := '';
  try
    Patched := Apply(Document, PatchJson);
    Result := True;
  except
    on E: EJsonPatchError do
    begin
      Patched.Free;
      Patched := nil;
      ErrorMessage := E.Message;
      Result := False;
    end;
  end;
end;

end.
