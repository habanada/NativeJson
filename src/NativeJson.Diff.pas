{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Diff;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE}
  System.SysUtils,
  {$ENDIF}
  NativeJson.Dom.Value,
  NativeJson.Dom.JsonArray;

type
  /// <summary>Raised when a JSON diff cannot be created.</summary>
  EJsonDiffError = class(EJsonValueError);

  /// <summary>
  ///   Creates an RFC-6902 JSON Patch that transforms one NativeJson DOM
  ///   document into another. Version 1 compares objects recursively and
  ///   replaces changed arrays as a whole.
  /// </summary>
  TJsonDiff = class abstract
  private
    class function AppendPath(const BasePath, Token: string): string; static;
    class procedure AddOperation(Patch: TJsonArray; const OperationName,
      Path: string; Value: TJsonValue); static;
    class procedure CompareValue(const OldValue, NewValue: TJsonValue;
      const Path: string; Patch: TJsonArray); static;
  public
    /// <summary>
    ///   Returns a newly allocated RFC-6902 patch array. OldValue and NewValue
    ///   remain unchanged. The caller owns the returned array.
    /// </summary>
    class function Compare(const OldValue, NewValue: TJsonValue): TJsonArray; static;
  end;

implementation

uses
  {$IFDEF FPC}
  Generics.Collections,
  {$ELSE}
  System.Generics.Collections,
  {$ENDIF}
  NativeJson.Dom.JsonObject,
  NativeJson.Pointer,
  NativeJson.Comparer;

class function TJsonDiff.AppendPath(const BasePath, Token: string): string;
begin
  Result := BasePath + '/' + TJsonPointer.Escape(Token);
end;

class procedure TJsonDiff.AddOperation(Patch: TJsonArray;
  const OperationName, Path: string; Value: TJsonValue);
var
  OperationObject: TJsonObject;
  ValueClone, Transferred: TJsonValue;
begin
  OperationObject := TJsonObject.Create;
  try
    OperationObject.AddPair('op', OperationName);
    OperationObject.AddPair('path', Path);

    if Value <> nil then
    begin
      ValueClone := Value.Clone;
      // TJsonObject.AddPair owns the value, including its exception path.
      // Relinquish the local reference before calling it to avoid double-free.
      try
        Transferred := ValueClone;
        ValueClone := nil;
        OperationObject.AddPair('value', Transferred);
      finally
        ValueClone.Free;
      end;
    end;

    Patch.Add(OperationObject);
    OperationObject := nil;
  finally
    OperationObject.Free;
  end;
end;

class procedure TJsonDiff.CompareValue(const OldValue, NewValue: TJsonValue;
  const Path: string; Patch: TJsonArray);
var
  OldObject, NewObject: TJsonObject;
  Pair: TPair<string, TJsonValue>;
  OldChild: TJsonValue;
  ChildPath: string;
begin
  if TJsonComparer.DeepEquals(OldValue, NewValue) then
    Exit;

  if (OldValue is TJsonObject) and (NewValue is TJsonObject) then
  begin
    OldObject := TJsonObject(OldValue);
    NewObject := TJsonObject(NewValue);

    // Remove members that no longer exist. Iteration follows the old DOM
    // order, making the generated patch deterministic.
    for Pair in OldObject do
      if not NewObject.Contains(Pair.Key) then
      begin
        ChildPath := AppendPath(Path, Pair.Key);
        AddOperation(Patch, 'remove', ChildPath, nil);
      end;

    // Add new members and recursively compare shared members in the new DOM
    // order. This is deterministic and keeps object member order irrelevant.
    for Pair in NewObject do
    begin
      ChildPath := AppendPath(Path, Pair.Key);
      OldChild := nil;
      if OldObject.TryGetValue(Pair.Key, OldChild) then
        CompareValue(OldChild, Pair.Value, ChildPath, Patch)
      else
        AddOperation(Patch, 'add', ChildPath, Pair.Value);
    end;
    Exit;
  end;

  // Version 1 intentionally replaces changed arrays as one value. This is
  // always correct and avoids fragile index-shift/LCS/move heuristics. The
  // same replacement rule also handles scalars and JSON type changes.
  AddOperation(Patch, 'replace', Path, NewValue);
end;

class function TJsonDiff.Compare(const OldValue,
  NewValue: TJsonValue): TJsonArray;
begin
  if OldValue = nil then
    raise EJsonDiffError.Create('JSON diff source must not be nil');
  if NewValue = nil then
    raise EJsonDiffError.Create('JSON diff target must not be nil');

  Result := TJsonArray.Create;
  try
    CompareValue(OldValue, NewValue, '', Result);
  except
    Result.Free;
    raise;
  end;
end;

end.
