{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Deserializer.Generics;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Rtti,
  TypInfo;
  {$ELSE}
  System.SysUtils,
  System.Rtti,
  System.TypInfo;
  {$ENDIF}

type
  EJsonGenericsError = class(Exception);
  TCollectionAddProc = reference to procedure(Instance: TObject; const Item: TValue);

  TJsonGenericsHelper = record
  private
    class function GetMethod(RType: TRttiType; const Name: string; ParamCount: Integer): TRttiMethod; static;
    class function FindAddMethod(RType: TRttiType): TRttiMethod; static;
  public
    class function IsCollection(RType: TRttiType): Boolean; static;
    class function GetCollectionElementType(RType: TRttiType): TRttiType; static;
    class procedure AddToCollection(RType: TRttiType; const Instance, Item: TValue); static;
    class function IsDictionary(RType: TRttiType): Boolean; static;
    class procedure GetDictionaryKeyValueTypes(RType: TRttiType; out KeyType, ValueType: TRttiType); static;
    class procedure AddToDictionary(RType: TRttiType; const Instance, Key, Value: TValue); static;
  end;

implementation

class function TJsonGenericsHelper.GetMethod(RType: TRttiType; const Name: string; ParamCount: Integer): TRttiMethod;
var
  Method: TRttiMethod;
begin
  Result := nil;
  if RType = nil then Exit;
  for Method in RType.GetMethods do
    if SameText(Method.Name, Name) and (Length(Method.GetParameters) = ParamCount) then Exit(Method);
end;

class function TJsonGenericsHelper.FindAddMethod(RType: TRttiType): TRttiMethod;
begin
  Result := GetMethod(RType, 'Add', 1);
  if Result = nil then Result := GetMethod(RType, 'Push', 1);
  if Result = nil then Result := GetMethod(RType, 'Enqueue', 1);
end;

class function TJsonGenericsHelper.IsCollection(RType: TRttiType): Boolean;
begin
  Result := (RType <> nil) and (RType.TypeKind in [tkClass, tkInterface]) and (FindAddMethod(RType) <> nil) and not IsDictionary(RType);
end;

class function TJsonGenericsHelper.GetCollectionElementType(RType: TRttiType): TRttiType;
var
  Method: TRttiMethod;
begin
  Method := FindAddMethod(RType);
  if Method = nil then raise EJsonGenericsError.CreateFmt('Type %s is not a supported collection', [RType.Name]);
  Result := Method.GetParameters[0].ParamType;
end;

class procedure TJsonGenericsHelper.AddToCollection(RType: TRttiType; const Instance, Item: TValue);
var
  Method: TRttiMethod;
begin
  Method := FindAddMethod(RType);
  if Method = nil then raise EJsonGenericsError.CreateFmt('Cannot find Add/Push/Enqueue on %s', [RType.Name]);
  Method.Invoke(Instance, [Item]);
end;

class function TJsonGenericsHelper.IsDictionary(RType: TRttiType): Boolean;
begin
  Result := (RType <> nil) and (RType.TypeKind in [tkClass, tkInterface]) and (GetMethod(RType, 'Add', 2) <> nil);
end;

class procedure TJsonGenericsHelper.GetDictionaryKeyValueTypes(RType: TRttiType; out KeyType, ValueType: TRttiType);
var
  Method: TRttiMethod;
  Params: TArray<TRttiParameter>;
begin
  Method := GetMethod(RType, 'Add', 2);
  if Method = nil then raise EJsonGenericsError.CreateFmt('Type %s is not a supported dictionary', [RType.Name]);
  Params := Method.GetParameters;
  KeyType := Params[0].ParamType;
  ValueType := Params[1].ParamType;
end;

class procedure TJsonGenericsHelper.AddToDictionary(RType: TRttiType; const Instance, Key, Value: TValue);
var
  Method: TRttiMethod;
begin
  Method := GetMethod(RType, 'Add', 2);
  if Method = nil then raise EJsonGenericsError.CreateFmt('Cannot find Add on %s', [RType.Name]);
  Method.Invoke(Instance, [Key, Value]);
end;

end.
