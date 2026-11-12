{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Dom.JsonArray;

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
  NativeJson.Dom.Primitive;

type
  TJsonArray = class(TJsonValue)
  private
    FItems: TObjectList<TJsonValue>;
    function GetCount: Integer;
  protected
    function GetItem(Index: Integer): TJsonValue; override;
    procedure SetItem(Index: Integer; const Value: TJsonValue); override;
  public
    constructor Create;
    destructor Destroy; override;
    function GetJsonType: TJsonType; override;
    function Add(const Value: TJsonValue): Integer; overload;
    function Add(const Value: string): Integer; overload;
    function Add(const Value: Integer): Integer; overload;
    function Add(const Value: Int64): Integer; overload;
    function Add(const Value: Double): Integer; overload;
    function Add(const Value: Boolean): Integer; overload;
    procedure Insert(Index: Integer; const Value: TJsonValue);
    procedure Delete(Index: Integer);
    procedure Remove(const Value: TJsonValue);
    procedure Clear;
    function GetEnumerator: TEnumerator<TJsonValue>;
    function Clone: TJsonValue; override;
    function ToJson: string; override;
    property Count: Integer read GetCount;
  end;

implementation

type
  TJsonValueAccess = class(TJsonValue);

constructor TJsonArray.Create;
begin
  inherited Create;
  FItems := TObjectList<TJsonValue>.Create(True);
end;

destructor TJsonArray.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TJsonArray.GetJsonType: TJsonType;
begin
  Result := TJsonType.jtArray;
end;

function TJsonArray.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TJsonArray.GetItem(Index: Integer): TJsonValue;
begin
  Result := FItems[Index];
end;

procedure TJsonArray.SetItem(Index: Integer; const Value: TJsonValue);
var
  Item: TJsonValue;
begin
  if Value = nil then
    Item := TJsonNull.Create
  else
    Item := Value;
  TJsonValueAccess(Item).SetParent(Self);
  FItems[Index] := Item;
end;

function TJsonArray.Add(const Value: TJsonValue): Integer;
var
  Item: TJsonValue;
begin
  if Value = nil then
    Item := TJsonNull.Create
  else
    Item := Value;
  TJsonValueAccess(Item).SetParent(Self);
  Result := FItems.Add(Item);
end;

function TJsonArray.Add(const Value: string): Integer;
begin
  Result := Add(TJsonString.Create(Value));
end;

function TJsonArray.Add(const Value: Integer): Integer;
begin
  Result := Add(TJsonNumber.Create(Value));
end;

function TJsonArray.Add(const Value: Int64): Integer;
begin
  Result := Add(TJsonNumber.Create(Value));
end;

function TJsonArray.Add(const Value: Double): Integer;
begin
  Result := Add(TJsonNumber.Create(Value));
end;

function TJsonArray.Add(const Value: Boolean): Integer;
begin
  Result := Add(TJsonBoolean.Create(Value));
end;

procedure TJsonArray.Insert(Index: Integer; const Value: TJsonValue);
var
  Item: TJsonValue;
begin
  if Value = nil then
    Item := TJsonNull.Create
  else
    Item := Value;
  TJsonValueAccess(Item).SetParent(Self);
  FItems.Insert(Index, Item);
end;

procedure TJsonArray.Delete(Index: Integer);
begin
  FItems.Delete(Index);
end;

procedure TJsonArray.Remove(const Value: TJsonValue);
begin
  FItems.Remove(Value);
end;

procedure TJsonArray.Clear;
begin
  FItems.Clear;
end;

function TJsonArray.GetEnumerator: TEnumerator<TJsonValue>;
begin
  Result := FItems.GetEnumerator;
end;

function TJsonArray.Clone: TJsonValue;
var
  NewArray: TJsonArray;
  I: Integer;
begin
  NewArray := TJsonArray.Create;
  try
    for I := 0 to FItems.Count - 1 do
      NewArray.Add(FItems[I].Clone);
    Result := NewArray;
  except
    NewArray.Free;
    raise;
  end;
end;

function TJsonArray.ToJson: string;
var
  SB: TJsonStringBuilder;
  I: Integer;
begin
  if FItems.Count = 0 then
    Exit('[]');
  SB := TJsonStringBuilder.Create;
  try
    SB.Append('[');
    for I := 0 to FItems.Count - 1 do
    begin
      if I > 0 then
        SB.Append(',');
      SB.Append(FItems[I].ToJson);
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
