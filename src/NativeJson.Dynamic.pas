{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Dynamic;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  Rtti,
  TypInfo;
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo;
  {$ENDIF}

type
  /// <summary>
  ///   Abstraction for list iterators (forward-only)
  /// </summary>
  IDynamicIterable = interface
    ['{6A59E75B-3D22-4F11-8799-123456789000}']
    function MoveNext: Boolean;
    function GetCurrent: TValue;
    function GetCount: Integer; // -1 if unknown
    /// <summary>
    ///   The DECLARED element type of the collection, e.g. TBaseItem for
    ///   TObjectList&lt;TBaseItem&gt;. Needed for TypeNameHandling.Auto,
    ///   because the TValue from GetCurrent only carries the runtime class.
    /// </summary>
    function GetElementType: PTypeInfo;
  end;

  /// <summary>
  ///   Abstraction for map/dictionary iterators
  /// </summary>
  IDynamicMapIterable = interface
    ['{7B12E75B-3D22-4F11-8799-987654321000}']
    function MoveNext: Boolean;
    function GetCurrentKey: TValue;
    function GetCurrentValue: TValue;
    function GetCount: Integer;
    /// <summary>The declared value type of the map, e.g. TBaseItem for TDictionary&lt;string, TBaseItem&gt;.</summary>
    function GetValueType: PTypeInfo;
  end;

  TDynamicTypeHelper = class
  public
    /// <summary>
    ///   Checks whether it is a map (Dictionary<K,V>)
    /// </summary>
    class function TryGetMap(AType: TRttiType; AInstance: TValue; out AMap: IDynamicMapIterable): Boolean;
    /// <summary>
    ///   Checks whether it is a list (GetEnumerator pattern)
    /// </summary>
    class function TryGetIterable(AType: TRttiType; AInstance: TValue; out AIterable: IDynamicIterable): Boolean;
  end;

implementation

type
  { TDynamicListWrapper }
  // Wraps any Delphi enumerator (class or record)
  TDynamicListWrapper = class(TInterfacedObject, IDynamicIterable)
  private
    FEnumerator: TValue;
    FMoveNextMethod: TRttiMethod;
    FCurrentProp: TRttiProperty;
    FCountProp: TRttiProperty; // Optional
    FInstance: TValue;
    FEnumeratorIsClass: Boolean;
  public
    constructor Create(AEnumerator: TValue; AMoveNext: TRttiMethod; ACurrent: TRttiProperty; ACount: TRttiProperty; AInstance: TValue);
    destructor Destroy; override;
    function MoveNext: Boolean;
    function GetCurrent: TValue;
    function GetCount: Integer;
    function GetElementType: PTypeInfo;
  end;

  { TDynamicMapWrapper }
  // Special case for dictionaries, where Current is a TPair<K,V>
  TDynamicMapWrapper = class(TInterfacedObject, IDynamicMapIterable)
  private
    FEnumerator: TValue;
    FMoveNextMethod: TRttiMethod;
    FCurrentProp: TRttiProperty;
    FKeyProp: TRttiField;   // TPair.Key is often a field in generics
    FValueProp: TRttiField; // TPair.Value is often a field
    FKeyPropP: TRttiProperty; // Fallback if it is a property
    FValuePropP: TRttiProperty; // Fallback if it is a property
    FCountProp: TRttiProperty;
    FInstance: TValue;
    FEnumeratorIsClass: Boolean;
  public
    constructor Create(AEnumerator: TValue; AMoveNext: TRttiMethod; ACurrent: TRttiProperty; ACount: TRttiProperty; AInstance: TValue);
    destructor Destroy; override;
    function MoveNext: Boolean;
    function GetCurrentKey: TValue;
    function GetCurrentValue: TValue;
    function GetCount: Integer;
    function GetValueType: PTypeInfo;
  end;

{ TDynamicListWrapper }

constructor TDynamicListWrapper.Create(AEnumerator: TValue; AMoveNext: TRttiMethod; ACurrent: TRttiProperty; ACount: TRttiProperty; AInstance: TValue);
begin
  inherited Create;
  FEnumerator := AEnumerator;
  FMoveNextMethod := AMoveNext;
  FCurrentProp := ACurrent;
  FCountProp := ACount;
  FInstance := AInstance;
  FEnumeratorIsClass := FEnumerator.Kind = tkClass;
end;

destructor TDynamicListWrapper.Destroy;
begin
  // An enumerator that is an object must be freed.
  if FEnumeratorIsClass and (FEnumerator.AsObject <> nil) then
  begin
    FEnumerator.AsObject.Free;
  end;
  inherited;
end;

function TDynamicListWrapper.GetCount: Integer;
begin
  if Assigned(FCountProp) and (FInstance.Kind in [tkClass, tkInterface, tkRecord]) then
  begin
    try
      if FInstance.Kind = tkClass then
        Result := FCountProp.GetValue(FInstance.AsObject).AsInteger
      else
        Result := FCountProp.GetValue(FInstance.GetReferenceToRawData).AsInteger;
    except
      Result := -1; // Fallback on error
    end;
  end
  else
    Result := -1;
end;

function TDynamicListWrapper.GetCurrent: TValue;
begin
  if FEnumeratorIsClass then
    Result := FCurrentProp.GetValue(FEnumerator.AsObject)
  else
    Result := FCurrentProp.GetValue(FEnumerator.GetReferenceToRawData);
end;

function TDynamicListWrapper.MoveNext: Boolean;
begin
  Result := FMoveNextMethod.Invoke(FEnumerator, []).AsBoolean;
end;

function TDynamicListWrapper.GetElementType: PTypeInfo;
begin
  if (FCurrentProp <> nil) and (FCurrentProp.PropertyType <> nil) then
    Result := FCurrentProp.PropertyType.Handle
  else
    Result := nil;
end;

{ TDynamicMapWrapper }

constructor TDynamicMapWrapper.Create(AEnumerator: TValue; AMoveNext: TRttiMethod; ACurrent: TRttiProperty; ACount: TRttiProperty; AInstance: TValue);
var
  PairType: TRttiType;
begin
  inherited Create;
  FEnumerator := AEnumerator;
  FMoveNextMethod := AMoveNext;
  FCurrentProp := ACurrent;
  FCountProp := ACount;
  FInstance := AInstance;
  FEnumeratorIsClass := FEnumerator.Kind = tkClass;

  // Analyze the pair type (e.g. TPair<string, Integer>)
  PairType := FCurrentProp.PropertyType;
  
  // Look up Key/Value as field or property
  FKeyProp := PairType.GetField('Key');
  if FKeyProp = nil then FKeyPropP := PairType.GetProperty('Key');
  
  FValueProp := PairType.GetField('Value');
  if FValueProp = nil then FValuePropP := PairType.GetProperty('Value');
end;

destructor TDynamicMapWrapper.Destroy;
begin
  if FEnumeratorIsClass and (FEnumerator.AsObject <> nil) then
    FEnumerator.AsObject.Free;
  inherited;
end;

function TDynamicMapWrapper.GetCount: Integer;
begin
  if Assigned(FCountProp) then
  begin
    if FInstance.Kind = tkClass then
      Result := FCountProp.GetValue(FInstance.AsObject).AsInteger
    else
      Result := -1;
  end
  else
    Result := -1;
end;

function TDynamicMapWrapper.GetCurrentKey: TValue;
var
  Pair: TValue;
begin
  if FEnumeratorIsClass then
    Pair := FCurrentProp.GetValue(FEnumerator.AsObject)
  else
    Pair := FCurrentProp.GetValue(FEnumerator.GetReferenceToRawData);

  if Assigned(FKeyProp) then
    Result := FKeyProp.GetValue(Pair.GetReferenceToRawData)
  else if Assigned(FKeyPropP) then
    Result := FKeyPropP.GetValue(Pair.GetReferenceToRawData)
  else
    Result := TValue.Empty;
end;

function TDynamicMapWrapper.GetCurrentValue: TValue;
var
  Pair: TValue;
begin
  if FEnumeratorIsClass then
    Pair := FCurrentProp.GetValue(FEnumerator.AsObject)
  else
    Pair := FCurrentProp.GetValue(FEnumerator.GetReferenceToRawData);

  if Assigned(FValueProp) then
    Result := FValueProp.GetValue(Pair.GetReferenceToRawData)
  else if Assigned(FValuePropP) then
    Result := FValuePropP.GetValue(Pair.GetReferenceToRawData)
  else
    Result := TValue.Empty;
end;

function TDynamicMapWrapper.MoveNext: Boolean;
begin
  Result := FMoveNextMethod.Invoke(FEnumerator, []).AsBoolean;
end;

function TDynamicMapWrapper.GetValueType: PTypeInfo;
begin
  Result := nil;
  if Assigned(FValueProp) and (FValueProp.FieldType <> nil) then
    Result := FValueProp.FieldType.Handle
  else if Assigned(FValuePropP) and (FValuePropP.PropertyType <> nil) then
    Result := FValuePropP.PropertyType.Handle;
end;

{ TDynamicTypeHelper }

class function TDynamicTypeHelper.TryGetMap(AType: TRttiType; AInstance: TValue; out AMap: IDynamicMapIterable): Boolean;
var
  MethodGetEnumerator: TRttiMethod;
  EnumeratorType: TRttiType;
  MethodMoveNext: TRttiMethod;
  PropCurrent: TRttiProperty;
  PairType: TRttiType;
  PropCount: TRttiProperty;
  EnumeratorVal: TValue;
begin
  Result := False;
  AMap := nil;

  if (AType = nil) or (AType.TypeKind <> tkClass) then Exit;
  if AInstance.IsEmpty or (AInstance.AsObject = nil) then Exit;

  // 1. Look up GetEnumerator
  MethodGetEnumerator := AType.GetMethod('GetEnumerator');
  if (MethodGetEnumerator = nil) or (MethodGetEnumerator.ReturnType = nil) or (Length(MethodGetEnumerator.GetParameters) > 0) then Exit;

  EnumeratorType := MethodGetEnumerator.ReturnType;
  
  // 2. Look up MoveNext (must return Boolean)
  MethodMoveNext := EnumeratorType.GetMethod('MoveNext');
  if (MethodMoveNext = nil) or (Length(MethodMoveNext.GetParameters) > 0) or
     (MethodMoveNext.ReturnType = nil) or (MethodMoveNext.ReturnType.Handle <> System.TypeInfo(Boolean)) then Exit;

  // 3. Look up Current
  PropCurrent := EnumeratorType.GetProperty('Current');
  if PropCurrent = nil then Exit;

  // 4. MAP CHECK: does "Current" have properties named "Key" and "Value"?
  // That is the decisive difference from a list!
  PairType := PropCurrent.PropertyType;
  if PairType = nil then Exit;
  
  // Accept fields (records) or properties (objects)
  if (PairType.GetField('Key') = nil) and (PairType.GetProperty('Key') = nil) then Exit;
  if (PairType.GetField('Value') = nil) and (PairType.GetProperty('Value') = nil) then Exit;

  // Optional: Count
  PropCount := AType.GetProperty('Count');
  if PropCount = nil then PropCount := AType.GetProperty('Size');

  // 5. Get the enumerator
  try
    EnumeratorVal := MethodGetEnumerator.Invoke(AInstance.AsObject, []);
    // The enumerator can be a struct or an object
    if EnumeratorVal.IsEmpty then Exit;
    if (EnumeratorVal.Kind = tkClass) and (EnumeratorVal.AsObject = nil) then Exit;

    AMap := TDynamicMapWrapper.Create(EnumeratorVal, MethodMoveNext, PropCurrent, PropCount, AInstance);
    Result := True;
  except
    // Safe fail on RTTI invoke errors
    Result := False;
  end;
end;

class function TDynamicTypeHelper.TryGetIterable(AType: TRttiType; AInstance: TValue; out AIterable: IDynamicIterable): Boolean;
var
  MethodGetEnumerator: TRttiMethod;
  EnumeratorType: TRttiType;
  MethodMoveNext: TRttiMethod;
  PropCurrent: TRttiProperty;
  PropCount: TRttiProperty;
  EnumeratorVal: TValue;
begin
  Result := False;
  AIterable := nil;

  if (AType = nil) or (AType.TypeKind <> tkClass) then Exit;
  if AInstance.IsEmpty or (AInstance.AsObject = nil) then Exit;

  // 1. Look up GetEnumerator
  MethodGetEnumerator := AType.GetMethod('GetEnumerator');
  if (MethodGetEnumerator = nil) or (MethodGetEnumerator.ReturnType = nil) or (Length(MethodGetEnumerator.GetParameters) > 0) then Exit;

  EnumeratorType := MethodGetEnumerator.ReturnType;

  // 2. Look up MoveNext
  MethodMoveNext := EnumeratorType.GetMethod('MoveNext');
  if (MethodMoveNext = nil) or (Length(MethodMoveNext.GetParameters) > 0) or
     (MethodMoveNext.ReturnType = nil) or (MethodMoveNext.ReturnType.Handle <> System.TypeInfo(Boolean)) then Exit;

  // 3. Look up Current
  PropCurrent := EnumeratorType.GetProperty('Current');
  if PropCurrent = nil then Exit;

  // 4. Count (Optional)
  PropCount := AType.GetProperty('Count');
  if PropCount = nil then PropCount := AType.GetProperty('Length');

  // 5. Get the enumerator
  try
    EnumeratorVal := MethodGetEnumerator.Invoke(AInstance.AsObject, []);
    if EnumeratorVal.IsEmpty then Exit;
    if (EnumeratorVal.Kind = tkClass) and (EnumeratorVal.AsObject = nil) then Exit;

    AIterable := TDynamicListWrapper.Create(EnumeratorVal, MethodMoveNext, PropCurrent, PropCount, AInstance);
    Result := True;
  except
    Result := False;
  end;
end;

end.