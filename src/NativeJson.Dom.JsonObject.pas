{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Dom.JsonObject;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  Generics.Collections,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.Dom.Value,
  NativeJson.Dom.Primitive,
  NativeJson.Dom.JsonArray;

type
  TJsonObject = class(TJsonValue)
  public
    type
      TPairEnumerator = class
      private
        FObject: TJsonObject;
        FIndex: Integer;
        function GetCurrent: TPair<string, TJsonValue>;
      public
        constructor Create(AObject: TJsonObject);
        function MoveNext: Boolean;
        property Current: TPair<string, TJsonValue> read GetCurrent;
      end;
  private
    FMap: TDictionary<string, TJsonValue>;
    FOrder: TList<string>;
    function GetCount: Integer;
    function EscapeKey(const K: string): string;
    function PrepareValue(const Value: TJsonValue): TJsonValue;
    procedure InternalPut(const Name: string; const Value: TJsonValue);
  protected
    function GetAttribute(const Name: string): TJsonValue; override;
    procedure SetAttribute(const Name: string; const Value: TJsonValue); override;
  public
    constructor Create;
    destructor Destroy; override;
    function GetJsonType: TJsonType; override;
    procedure AddPair(const Name: string; const Value: TJsonValue); overload;
    procedure AddPair(const Name: string; const Value: string); overload;
    procedure AddPair(const Name: string; const Value: Integer); overload;
    procedure AddPair(const Name: string; const Value: Int64); overload;
    procedure AddPair(const Name: string; const Value: Double); overload;
    procedure AddPair(const Name: string; const Value: Boolean); overload;
    function Remove(const Name: string): Boolean;
    function Contains(const Name: string): Boolean;
    function TryGetValue(const Name: string; out Value: TJsonValue): Boolean;
    // Returns nil instead of raising when the key is missing -
    // for code that handles a missing key as a normal case.
    function GetValue(const Name: string): TJsonValue;
    procedure Clear;
    function GetEnumerator: TPairEnumerator;
    function Clone: TJsonValue; override;
    function ToJson: string; override;
    property Count: Integer read GetCount;
  end;

implementation

type
  TJsonValueAccess = class(TJsonValue);

{ TJsonObject.TPairEnumerator }

constructor TJsonObject.TPairEnumerator.Create(AObject: TJsonObject);
begin
  inherited Create;
  FObject := AObject;
  FIndex := -1;
end;

function TJsonObject.TPairEnumerator.MoveNext: Boolean;
begin
  Inc(FIndex);
  Result := FIndex < FObject.FOrder.Count;
end;

function TJsonObject.TPairEnumerator.GetCurrent: TPair<string, TJsonValue>;
var
  Value: TJsonValue;
begin
  Result.Key := FObject.FOrder[FIndex];
  if FObject.FMap.TryGetValue(Result.Key, Value) then Result.Value := Value else Result.Value := nil;
end;

{ TJsonObject }

constructor TJsonObject.Create;
begin
  inherited Create;
  FMap := TDictionary<string, TJsonValue>.Create;
  FOrder := TList<string>.Create;
end;

destructor TJsonObject.Destroy;
begin
  Clear;
  FMap.Free;
  FOrder.Free;
  inherited;
end;

function TJsonObject.GetJsonType: TJsonType;
begin
  Result := TJsonType.jtObject;
end;

function TJsonObject.GetCount: Integer;
begin
  Result := FOrder.Count;
end;

function TJsonObject.GetAttribute(const Name: string): TJsonValue;
begin
  if not FMap.TryGetValue(Name, Result) then raise EJsonValueError.CreateFmt('Property "%s" not found', [Name]);
end;

function TJsonObject.PrepareValue(const Value: TJsonValue): TJsonValue;
var
  Node: TJsonValue;
begin
  if Value = nil then Exit(TJsonNull.Create);
  Node := Self;
  while Node <> nil do
  begin
    if Node = Value then raise EJsonValueError.Create('A JSON value cannot contain itself or one of its ancestors');
    Node := Node.Parent;
  end;
  if Value.Parent <> nil then Result := Value.Clone else Result := Value;
end;

procedure TJsonObject.InternalPut(const Name: string; const Value: TJsonValue);
var
  Old: TJsonValue;
  Existed: Boolean;
begin
  Existed := FMap.TryGetValue(Name, Old);
  if Existed and (Old = Value) then Exit;
  FMap.AddOrSetValue(Name, Value);
  if Existed then Old.Free else FOrder.Add(Name);
end;

procedure TJsonObject.SetAttribute(const Name: string; const Value: TJsonValue);
var
  Existing, NewValue: TJsonValue;
begin
  if FMap.TryGetValue(Name, Existing) and (Existing = Value) then Exit;
  NewValue := PrepareValue(Value);
  TJsonValueAccess(NewValue).SetParent(Self);
  try
    InternalPut(Name, NewValue);
  except
    TJsonValueAccess(NewValue).SetParent(nil);
    NewValue.Free;
    raise;
  end;
end;

procedure TJsonObject.AddPair(const Name: string; const Value: TJsonValue);
var
  Item: TJsonValue;
begin
  if FMap.ContainsKey(Name) then raise EJsonValueError.CreateFmt('Property "%s" already exists', [Name]);
  Item := PrepareValue(Value);
  TJsonValueAccess(Item).SetParent(Self);
  try
    FMap.Add(Name, Item);
    try
      FOrder.Add(Name);
    except
      FMap.Remove(Name);
      raise;
    end;
  except
    TJsonValueAccess(Item).SetParent(nil);
    Item.Free;
    raise;
  end;
end;

procedure TJsonObject.AddPair(const Name: string; const Value: string);
begin
  AddPair(Name, TJsonString.Create(Value));
end;

procedure TJsonObject.AddPair(const Name: string; const Value: Integer);
begin
  AddPair(Name, TJsonNumber.Create(Value));
end;

procedure TJsonObject.AddPair(const Name: string; const Value: Int64);
begin
  AddPair(Name, TJsonNumber.Create(Value));
end;

procedure TJsonObject.AddPair(const Name: string; const Value: Double);
begin
  AddPair(Name, TJsonNumber.Create(Value));
end;

procedure TJsonObject.AddPair(const Name: string; const Value: Boolean);
begin
  AddPair(Name, TJsonBoolean.Create(Value));
end;

function TJsonObject.Remove(const Name: string): Boolean;
var
  Old: TJsonValue;
begin
  Result := FMap.TryGetValue(Name, Old);
  if Result then
  begin
    FMap.Remove(Name);
    FOrder.Remove(Name);
    Old.Free;
  end;
end;

function TJsonObject.Contains(const Name: string): Boolean;
begin
  Result := FMap.ContainsKey(Name);
end;

function TJsonObject.GetValue(const Name: string): TJsonValue;
begin
  if not FMap.TryGetValue(Name, Result) then Result := nil;
end;

function TJsonObject.TryGetValue(const Name: string; out Value: TJsonValue): Boolean;
begin
  Result := FMap.TryGetValue(Name, Value);
end;

procedure TJsonObject.Clear;
var
  Value: TJsonValue;
begin
  for Value in FMap.Values do Value.Free;
  FMap.Clear;
  FOrder.Clear;
end;

function TJsonObject.GetEnumerator: TPairEnumerator;
begin
  Result := TPairEnumerator.Create(Self);
end;

function TJsonObject.Clone: TJsonValue;
var
  NewObj: TJsonObject;
  I: Integer;
  Key: string;
  Value: TJsonValue;
begin
  NewObj := TJsonObject.Create;
  try
    for I := 0 to FOrder.Count - 1 do
    begin
      Key := FOrder[I];
      if FMap.TryGetValue(Key, Value) then NewObj.AddPair(Key, Value.Clone);
    end;
    Result := NewObj;
  except
    NewObj.Free;
    raise;
  end;
end;

function TJsonObject.EscapeKey(const K: string): string;
var
  Temp: TJsonString;
begin
  Temp := TJsonString.Create(K);
  try
    Result := Temp.ToJson;
  finally
    Temp.Free;
  end;
end;

function TJsonObject.ToJson: string;
var
  SB: TJsonStringBuilder;
  I: Integer;
  Key: string;
  Value: TJsonValue;
begin
  if FOrder.Count = 0 then Exit('{}');
  SB := TJsonStringBuilder.Create;
  try
    SB.Append('{');
    for I := 0 to FOrder.Count - 1 do
    begin
      if I > 0 then SB.Append(',');
      Key := FOrder[I];
      SB.Append(EscapeKey(Key));
      SB.Append(':');
      if FMap.TryGetValue(Key, Value) then SB.Append(Value.ToJson) else SB.Append('null');
    end;
    SB.Append('}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
