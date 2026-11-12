{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Linq;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  Generics.Collections,
  Generics.Defaults,
  Rtti,
  TypInfo,
  Math,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Rtti,
  System.TypInfo,
  System.Math,
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.Dom.Value,
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.Primitive;

type
  IJsonQuery = interface;
  IOrderedJsonQuery = interface;

  TJsonPredicate = reference to function(const Item: TJsonValue): Boolean;
  TJsonAction = reference to procedure(const Item: TJsonValue);
  TJsonMapFunc<T> = reference to function(const Item: TJsonValue): T;
  TJsonTransform = reference to function(const Item: TJsonValue): TJsonValue;
  TJsonAccumulator<T> = reference to function(const Acc: T; const Item: TJsonValue): T;

  TJsonValueComparer = class(TInterfacedObject, IComparer<TJsonValue>, IEqualityComparer<TJsonValue>)
  public
    function Compare(const Left, Right: TJsonValue): Integer;
    function Equals(const Left, Right: TJsonValue): Boolean; reintroduce;
    function GetHashCode(const Value: TJsonValue): TJsonHashCode; reintroduce;
    class function Default: IComparer<TJsonValue>; static;
    class function EqualityDefault: IEqualityComparer<TJsonValue>; static;
  end;

  IJsonQuery = interface
    ['{8A59E75B-1A10-4F11-8799-E17E7A150001}']
    function GetList: TList<TJsonValue>;
    function GetCount: Integer;
    function GetItem(Index: Integer): TJsonValue;
    function Children: IJsonQuery;
    function Parents: IJsonQuery;
    function Ancestors: IJsonQuery;
    function Descendants: IJsonQuery;
    function Siblings: IJsonQuery;
    function SelectPath(const Path: string): IJsonQuery;
    function Where(Predicate: TJsonPredicate): IJsonQuery;
    function OfType(JsonType: TJsonType): IJsonQuery;
    function NotNull: IJsonQuery;
    function Select(Selector: TJsonTransform): IJsonQuery;
    function SelectMany(Selector: TJsonTransform): IJsonQuery;
    function Distinct: IJsonQuery;
    function Union(Other: IJsonQuery): IJsonQuery;
    function Intersect(Other: IJsonQuery): IJsonQuery;
    function Exclude(Other: IJsonQuery): IJsonQuery;
    function Concat(Other: IJsonQuery): IJsonQuery;
    function Skip(Count: Integer): IJsonQuery;
    function Take(Count: Integer): IJsonQuery;
    function Reverse: IJsonQuery;
    function OrderBy(KeySelector: TJsonTransform = nil): IOrderedJsonQuery;
    function OrderByDescending(KeySelector: TJsonTransform = nil): IOrderedJsonQuery;
    function Min(Selector: TJsonTransform = nil): TJsonValue;
    function Max(Selector: TJsonTransform = nil): TJsonValue;
    function Sum: Double;
    function Average: Double;
    function Any(Predicate: TJsonPredicate = nil): Boolean;
    function All(Predicate: TJsonPredicate): Boolean;
    function Contains(Value: TJsonValue): Boolean;
    function First: TJsonValue;
    function FirstOrDefault: TJsonValue;
    function Last: TJsonValue;
    function LastOrDefault: TJsonValue;
    function ElementAt(Index: Integer): TJsonValue;
    function Single: TJsonValue;
    function ToList: TList<TJsonValue>;
    function ToArray: TArray<TJsonValue>;
    function ToJsonArray: TJsonArray;
    procedure Remove;
    procedure Replace(NewValue: TJsonValue);
    procedure ForEach(Action: TJsonAction);
    property Count: Integer read GetCount;
    property Items[Index: Integer]: TJsonValue read GetItem; default;
  end;

  IOrderedJsonQuery = interface(IJsonQuery)
    ['{8A59E75B-1A10-4F11-8799-E17E7A150002}']
    function ThenBy(KeySelector: TJsonTransform = nil): IOrderedJsonQuery;
    function ThenByDescending(KeySelector: TJsonTransform = nil): IOrderedJsonQuery;
  end;

  TJsonLinq = record
  private
    FQuery: IJsonQuery;
    function GetQuery: IJsonQuery;
  public
    class operator Implicit(const AValue: TJsonValue): TJsonLinq;
    class operator Implicit(const AList: TList<TJsonValue>): TJsonLinq;
    class operator Implicit(const AQuery: TJsonLinq): IJsonQuery;
    // --- Navigation
    function Children: TJsonLinq;
    function Parents: TJsonLinq;
    function Ancestors: TJsonLinq;
    function Descendants: TJsonLinq;
    function Siblings: TJsonLinq;
    function Select(const Path: string): TJsonLinq;

    // --- Selection and transformation
    function Where(Predicate: TJsonPredicate): TJsonLinq;
    function OfType(JsonType: TJsonType): TJsonLinq;
    function NotNull: TJsonLinq;
    function Transform(Selector: TJsonTransform): TJsonLinq;
    function TransformMany(Selector: TJsonTransform): TJsonLinq;

    // --- Sets
    function Distinct: TJsonLinq;
    function Union(const Other: TJsonLinq): TJsonLinq;
    function Intersect(const Other: TJsonLinq): TJsonLinq;
    function Exclude(const Other: TJsonLinq): TJsonLinq;
    function Concat(const Other: TJsonLinq): TJsonLinq;

    // --- Ordering and slicing
    function OrderBy(KeySelector: TJsonTransform = nil): TJsonLinq;
    function OrderByDescending(KeySelector: TJsonTransform = nil): TJsonLinq;
    function ThenBy(KeySelector: TJsonTransform = nil): TJsonLinq;
    function ThenByDescending(KeySelector: TJsonTransform = nil): TJsonLinq;
    function Reverse: TJsonLinq;
    function Skip(ACount: Integer): TJsonLinq;
    function Take(ACount: Integer): TJsonLinq;

    // --- Single values
    function First: TJsonValue;
    function FirstOrDefault: TJsonValue;
    function Last: TJsonValue;
    function LastOrDefault: TJsonValue;
    function Single: TJsonValue;
    function ElementAt(Index: Integer): TJsonValue;
    function Min(Selector: TJsonTransform = nil): TJsonValue;
    function Max(Selector: TJsonTransform = nil): TJsonValue;

    // --- Checks and aggregates
    function Any(Predicate: TJsonPredicate = nil): Boolean;
    function All(Predicate: TJsonPredicate): Boolean;
    function Contains(Value: TJsonValue): Boolean;
    function Sum: Double;
    function Average: Double;
    function Count: Integer;

    // --- Completion
    function ToArray: TArray<TJsonValue>;
    function ToJsonArray: TJsonArray;
    procedure ForEach(Action: TJsonAction);
    procedure Replace(NewValue: TJsonValue);
    function Aggregate<T>(const Seed: T; Accumulator: TJsonAccumulator<T>): T;
    function Map<T>(Mapper: TJsonMapFunc<T>): TArray<T>;
    function Value<T>: T; overload;
    function Value<T>(const Default: T): T; overload;
    function Values<T>: TArray<T>;
    function ToJson: string;
    procedure Remove;
    property Query: IJsonQuery read GetQuery;
  end;

  TJsonValueLinqHelper = class helper for TJsonValue
  public
    function Q: TJsonLinq;
  end;

implementation

uses
  NativeJson.Deserializer.Core;

type
  TJsonQuery = class(TInterfacedObject, IJsonQuery, IOrderedJsonQuery)
  private
    FList: TList<TJsonValue>;
    FComparer: IComparer<TJsonValue>;
    class function FindObjectKey(Parent: TJsonObject; Child: TJsonValue; out Key: string): Boolean; static;
  public
    constructor Create; overload;
    constructor Create(Source: TJsonValue); overload;
    constructor Create(Collection: TEnumerable<TJsonValue>); overload;
    destructor Destroy; override;
    function GetList: TList<TJsonValue>;
    function GetCount: Integer;
    function GetItem(Index: Integer): TJsonValue;
    function Children: IJsonQuery;
    function Parents: IJsonQuery;
    function Ancestors: IJsonQuery;
    function Descendants: IJsonQuery;
    function Siblings: IJsonQuery;
    function SelectPath(const Path: string): IJsonQuery;
    function Where(Predicate: TJsonPredicate): IJsonQuery;
    function OfType(JsonType: TJsonType): IJsonQuery;
    function NotNull: IJsonQuery;
    function Select(Selector: TJsonTransform): IJsonQuery;
    function SelectMany(Selector: TJsonTransform): IJsonQuery;
    function Distinct: IJsonQuery;
    function Union(Other: IJsonQuery): IJsonQuery;
    function Intersect(Other: IJsonQuery): IJsonQuery;
    function Exclude(Other: IJsonQuery): IJsonQuery;
    function Concat(Other: IJsonQuery): IJsonQuery;
    function Skip(Count: Integer): IJsonQuery;
    function Take(Count: Integer): IJsonQuery;
    function Reverse: IJsonQuery;
    function OrderBy(KeySelector: TJsonTransform): IOrderedJsonQuery;
    function OrderByDescending(KeySelector: TJsonTransform): IOrderedJsonQuery;
    function ThenBy(KeySelector: TJsonTransform): IOrderedJsonQuery;
    function ThenByDescending(KeySelector: TJsonTransform): IOrderedJsonQuery;
    function Min(Selector: TJsonTransform): TJsonValue;
    function Max(Selector: TJsonTransform): TJsonValue;
    function Sum: Double;
    function Average: Double;
    function Aggregate<T>(const Seed: T; Accumulator: TJsonAccumulator<T>): T;
    function Any(Predicate: TJsonPredicate): Boolean;
    function All(Predicate: TJsonPredicate): Boolean;
    function Contains(Value: TJsonValue): Boolean;
    function First: TJsonValue;
    function FirstOrDefault: TJsonValue;
    function Last: TJsonValue;
    function LastOrDefault: TJsonValue;
    function ElementAt(Index: Integer): TJsonValue;
    function Single: TJsonValue;
    function ToList: TList<TJsonValue>;
    function ToArray: TArray<TJsonValue>;
    function ToJsonArray: TJsonArray;
    function Map<T>(Mapper: TJsonMapFunc<T>): TArray<T>;
    procedure Remove;
    procedure Replace(NewValue: TJsonValue);
    procedure ForEach(Action: TJsonAction);
    function Value<T>: T; overload;
    function Value<T>(const Default: T): T; overload;
    function Values<T>: TArray<T>;
  end;

  TJsonKeyComparer = class(TInterfacedObject, IComparer<TJsonValue>)
  private
    FSelector: TJsonTransform;
    FDescending: Boolean;
  public
    constructor Create(Selector: TJsonTransform; Descending: Boolean);
    function Compare(const Left, Right: TJsonValue): Integer;
  end;

  TJsonChainedComparer = class(TInterfacedObject, IComparer<TJsonValue>)
  private
    FPrimary: IComparer<TJsonValue>;
    FSecondary: IComparer<TJsonValue>;
  public
    constructor Create(const Primary, Secondary: IComparer<TJsonValue>);
    function Compare(const Left, Right: TJsonValue): Integer;
  end;

function TJsonValueComparer.Compare(const Left, Right: TJsonValue): Integer;
begin
  if Left = Right then Exit(0);
  if Left = nil then Exit(-1);
  if Right = nil then Exit(1);
  if Left.GetJsonType <> Right.GetJsonType then Exit(Ord(Left.GetJsonType) - Ord(Right.GetJsonType));
  case Left.GetJsonType of
    TJsonType.jtString: Result := CompareStr(Left.AsString, Right.AsString);
    TJsonType.jtInteger: Result := CompareValue(Left.AsInteger, Right.AsInteger);
    TJsonType.jtFloat: Result := CompareValue(Left.AsDouble, Right.AsDouble);
    TJsonType.jtBoolean:
      if Left.AsBoolean = Right.AsBoolean then Result := 0 else if Left.AsBoolean then Result := 1 else Result := -1;
    TJsonType.jtNull: Result := 0;
  else
    Result := CompareStr(Left.ToJson, Right.ToJson);
  end;
end;

function TJsonValueComparer.Equals(const Left, Right: TJsonValue): Boolean;
begin
  Result := Compare(Left, Right) = 0;
end;

function TJsonValueComparer.GetHashCode(const Value: TJsonValue): TJsonHashCode;
begin
  if Value = nil then Exit(0);
  Result := TEqualityComparer<string>.Default.GetHashCode(Value.ToJson);
end;

class function TJsonValueComparer.Default: IComparer<TJsonValue>;
begin
  Result := TJsonValueComparer.Create;
end;

class function TJsonValueComparer.EqualityDefault: IEqualityComparer<TJsonValue>;
begin
  Result := TJsonValueComparer.Create;
end;

constructor TJsonKeyComparer.Create(Selector: TJsonTransform; Descending: Boolean);
begin
  inherited Create;
  FSelector := Selector;
  FDescending := Descending;
end;

function TJsonKeyComparer.Compare(const Left, Right: TJsonValue): Integer;
var
  L, R: TJsonValue;
begin
  if Assigned(FSelector) then
  begin
    L := FSelector(Left);
    R := FSelector(Right);
  end
  else
  begin
    L := Left;
    R := Right;
  end;
  Result := TJsonValueComparer.Default.Compare(L, R);
  if FDescending then Result := -Result;
end;

constructor TJsonChainedComparer.Create(const Primary, Secondary: IComparer<TJsonValue>);
begin
  inherited Create;
  FPrimary := Primary;
  FSecondary := Secondary;
end;

function TJsonChainedComparer.Compare(const Left, Right: TJsonValue): Integer;
begin
  if FPrimary <> nil then Result := FPrimary.Compare(Left, Right) else Result := 0;
  if (Result = 0) and (FSecondary <> nil) then Result := FSecondary.Compare(Left, Right);
end;

constructor TJsonQuery.Create;
begin
  inherited Create;
  FList := TList<TJsonValue>.Create;
end;

constructor TJsonQuery.Create(Source: TJsonValue);
begin
  Create;
  if Source <> nil then FList.Add(Source);
end;

constructor TJsonQuery.Create(Collection: TEnumerable<TJsonValue>);
var
  Item: TJsonValue;
begin
  Create;
  if Collection <> nil then for Item in Collection do FList.Add(Item);
end;

destructor TJsonQuery.Destroy;
begin
  FComparer := nil;
  FList.Free;
  inherited;
end;

function TJsonQuery.GetList: TList<TJsonValue>;
begin
  Result := FList;
end;

function TJsonQuery.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TJsonQuery.GetItem(Index: Integer): TJsonValue;
begin
  Result := FList[Index];
end;

function TJsonQuery.Children: IJsonQuery;
var
  Res: TJsonQuery;
  Item: TJsonValue;
  Pair: TPair<string, TJsonValue>;
  I: Integer;
begin
  Res := TJsonQuery.Create;
  for Item in FList do
    if Item is TJsonObject then
      for Pair in TJsonObject(Item) do Res.FList.Add(Pair.Value)
    else if Item is TJsonArray then
      for I := 0 to TJsonArray(Item).Count - 1 do Res.FList.Add(TJsonArray(Item)[I]);
  Result := Res;
end;

function TJsonQuery.Parents: IJsonQuery;
var
  Res: TJsonQuery;
  Item: TJsonValue;
begin
  Res := TJsonQuery.Create;
  for Item in FList do if (Item.Parent <> nil) and not Res.FList.Contains(Item.Parent) then Res.FList.Add(Item.Parent);
  Result := Res;
end;

function TJsonQuery.Ancestors: IJsonQuery;
var
  Res: TJsonQuery;
  Item, Current: TJsonValue;
begin
  Res := TJsonQuery.Create;
  for Item in FList do
  begin
    Current := Item.Parent;
    while Current <> nil do
    begin
      if not Res.FList.Contains(Current) then Res.FList.Add(Current);
      Current := Current.Parent;
    end;
  end;
  Result := Res;
end;

function TJsonQuery.Descendants: IJsonQuery;
var
  Res: TJsonQuery;
  Item: TJsonValue;
  procedure AddDescendants(Node: TJsonValue);
  var
    Pair: TPair<string, TJsonValue>;
    I: Integer;
    Child: TJsonValue;
  begin
    if Node is TJsonObject then
      for Pair in TJsonObject(Node) do
      begin
        Res.FList.Add(Pair.Value);
        AddDescendants(Pair.Value);
      end
    else if Node is TJsonArray then
      for I := 0 to TJsonArray(Node).Count - 1 do
      begin
        Child := TJsonArray(Node)[I];
        Res.FList.Add(Child);
        AddDescendants(Child);
      end;
  end;
begin
  Res := TJsonQuery.Create;
  for Item in FList do AddDescendants(Item);
  Result := Res;
end;

function TJsonQuery.Siblings: IJsonQuery;
var
  Res: TJsonQuery;
  Item, Parent, Sibling: TJsonValue;
  Pair: TPair<string, TJsonValue>;
  I: Integer;
begin
  Res := TJsonQuery.Create;
  for Item in FList do
  begin
    Parent := Item.Parent;
    if Parent is TJsonArray then
      for I := 0 to TJsonArray(Parent).Count - 1 do
      begin
        Sibling := TJsonArray(Parent)[I];
        if (Sibling <> Item) and not Res.FList.Contains(Sibling) then Res.FList.Add(Sibling);
      end
    else if Parent is TJsonObject then
      for Pair in TJsonObject(Parent) do
      begin
        Sibling := Pair.Value;
        if (Sibling <> Item) and not Res.FList.Contains(Sibling) then Res.FList.Add(Sibling);
      end;
  end;
  Result := Res;
end;

function TJsonQuery.SelectPath(const Path: string): IJsonQuery;
var
  Res: TJsonQuery;
  Item, Found: TJsonValue;
begin
  Res := TJsonQuery.Create;
  for Item in FList do for Found in Item.FindAll(Path) do Res.FList.Add(Found);
  Result := Res;
end;

function TJsonQuery.Where(Predicate: TJsonPredicate): IJsonQuery;
var
  Res: TJsonQuery;
  Item: TJsonValue;
begin
  Res := TJsonQuery.Create;
  if Assigned(Predicate) then for Item in FList do if Predicate(Item) then Res.FList.Add(Item);
  Result := Res;
end;

function TJsonQuery.OfType(JsonType: TJsonType): IJsonQuery;
begin
  Result := Where(function(const Item: TJsonValue): Boolean begin Result := Item.GetJsonType = JsonType end);
end;

function TJsonQuery.NotNull: IJsonQuery;
begin
  Result := Where(function(const Item: TJsonValue): Boolean begin Result := (Item <> nil) and not Item.IsNull end);
end;

function TJsonQuery.Select(Selector: TJsonTransform): IJsonQuery;
var
  Res: TJsonQuery;
  Item, Mapped: TJsonValue;
begin
  Res := TJsonQuery.Create;
  if Assigned(Selector) then
    for Item in FList do
    begin
      Mapped := Selector(Item);
      if Mapped <> nil then Res.FList.Add(Mapped);
    end;
  Result := Res;
end;

function TJsonQuery.SelectMany(Selector: TJsonTransform): IJsonQuery;
var
  Res: TJsonQuery;
  Item, Mapped: TJsonValue;
  Pair: TPair<string, TJsonValue>;
  I: Integer;
begin
  Res := TJsonQuery.Create;
  if Assigned(Selector) then
    for Item in FList do
    begin
      Mapped := Selector(Item);
      if Mapped is TJsonArray then for I := 0 to TJsonArray(Mapped).Count - 1 do Res.FList.Add(TJsonArray(Mapped)[I])
      else if Mapped is TJsonObject then for Pair in TJsonObject(Mapped) do Res.FList.Add(Pair.Value)
      else if Mapped <> nil then Res.FList.Add(Mapped);
    end;
  Result := Res;
end;

function TJsonQuery.Distinct: IJsonQuery;
var
  Res: TJsonQuery;
  Seen: TDictionary<TJsonValue, Byte>;
  Item: TJsonValue;
begin
  Res := TJsonQuery.Create;
  Seen := TDictionary<TJsonValue, Byte>.Create(TJsonValueComparer.EqualityDefault);
  try
    for Item in FList do if not Seen.ContainsKey(Item) then begin Seen.Add(Item, 0); Res.FList.Add(Item) end;
  finally
    Seen.Free;
  end;
  Result := Res;
end;

function TJsonQuery.Union(Other: IJsonQuery): IJsonQuery;
begin
  Result := Concat(Other).Distinct;
end;

function TJsonQuery.Concat(Other: IJsonQuery): IJsonQuery;
var
  Res: TJsonQuery;
  Item: TJsonValue;
begin
  Res := TJsonQuery.Create(FList);
  if Other <> nil then for Item in Other.GetList do Res.FList.Add(Item);
  Result := Res;
end;

function TJsonQuery.Intersect(Other: IJsonQuery): IJsonQuery;
var
  Res: TJsonQuery;
  SetValues: TDictionary<TJsonValue, Byte>;
  Item: TJsonValue;
begin
  Res := TJsonQuery.Create;
  SetValues := TDictionary<TJsonValue, Byte>.Create(TJsonValueComparer.EqualityDefault);
  try
    if Other <> nil then for Item in Other.GetList do SetValues.AddOrSetValue(Item, 0);
    for Item in FList do if SetValues.ContainsKey(Item) then begin Res.FList.Add(Item); SetValues.Remove(Item) end;
  finally
    SetValues.Free;
  end;
  Result := Res;
end;

function TJsonQuery.Exclude(Other: IJsonQuery): IJsonQuery;
var
  Res: TJsonQuery;
  SetValues: TDictionary<TJsonValue, Byte>;
  Item: TJsonValue;
begin
  Res := TJsonQuery.Create;
  SetValues := TDictionary<TJsonValue, Byte>.Create(TJsonValueComparer.EqualityDefault);
  try
    if Other <> nil then for Item in Other.GetList do SetValues.AddOrSetValue(Item, 0);
    for Item in FList do if not SetValues.ContainsKey(Item) then Res.FList.Add(Item);
  finally
    SetValues.Free;
  end;
  Result := Res;
end;

function TJsonQuery.Skip(Count: Integer): IJsonQuery;
var
  Res: TJsonQuery;
  I: Integer;
begin
  Res := TJsonQuery.Create;
  if Count < 0 then Count := 0;
  for I := Count to FList.Count - 1 do Res.FList.Add(FList[I]);
  Result := Res;
end;

function TJsonQuery.Take(Count: Integer): IJsonQuery;
var
  Res: TJsonQuery;
  I, Limit: Integer;
begin
  Res := TJsonQuery.Create;
  if Count < 0 then Count := 0;
  if Count < FList.Count then Limit := Count else Limit := FList.Count;
  for I := 0 to Limit - 1 do Res.FList.Add(FList[I]);
  Result := Res;
end;

function TJsonQuery.Reverse: IJsonQuery;
var
  Res: TJsonQuery;
  I: Integer;
begin
  Res := TJsonQuery.Create;
  for I := FList.Count - 1 downto 0 do Res.FList.Add(FList[I]);
  Result := Res;
end;

function TJsonQuery.OrderBy(KeySelector: TJsonTransform): IOrderedJsonQuery;
var
  Res: TJsonQuery;
begin
  Res := TJsonQuery.Create(FList);
  Res.FComparer := TJsonKeyComparer.Create(KeySelector, False);
  Res.FList.Sort(Res.FComparer);
  Result := Res;
end;

function TJsonQuery.OrderByDescending(KeySelector: TJsonTransform): IOrderedJsonQuery;
var
  Res: TJsonQuery;
begin
  Res := TJsonQuery.Create(FList);
  Res.FComparer := TJsonKeyComparer.Create(KeySelector, True);
  Res.FList.Sort(Res.FComparer);
  Result := Res;
end;

function TJsonQuery.ThenBy(KeySelector: TJsonTransform): IOrderedJsonQuery;
var
  Res: TJsonQuery;
begin
  Res := TJsonQuery.Create(FList);
  Res.FComparer := TJsonChainedComparer.Create(FComparer, TJsonKeyComparer.Create(KeySelector, False));
  Res.FList.Sort(Res.FComparer);
  Result := Res;
end;

function TJsonQuery.ThenByDescending(KeySelector: TJsonTransform): IOrderedJsonQuery;
var
  Res: TJsonQuery;
begin
  Res := TJsonQuery.Create(FList);
  Res.FComparer := TJsonChainedComparer.Create(FComparer, TJsonKeyComparer.Create(KeySelector, True));
  Res.FList.Sort(Res.FComparer);
  Result := Res;
end;

function TJsonQuery.Min(Selector: TJsonTransform): TJsonValue;
var
  Item, Candidate: TJsonValue;
  Comparer: IComparer<TJsonValue>;
begin
  if FList.Count = 0 then Exit(nil);
  Comparer := TJsonValueComparer.Default;
  Result := FList[0];
  for Item in FList do
  begin
    if Assigned(Selector) then Candidate := Selector(Item) else Candidate := Item;
    if Assigned(Selector) then
    begin
      if Comparer.Compare(Candidate, Selector(Result)) < 0 then Result := Item;
    end
    else if Comparer.Compare(Candidate, Result) < 0 then Result := Item;
  end;
end;

function TJsonQuery.Max(Selector: TJsonTransform): TJsonValue;
var
  Item, Candidate: TJsonValue;
  Comparer: IComparer<TJsonValue>;
begin
  if FList.Count = 0 then Exit(nil);
  Comparer := TJsonValueComparer.Default;
  Result := FList[0];
  for Item in FList do
  begin
    if Assigned(Selector) then Candidate := Selector(Item) else Candidate := Item;
    if Assigned(Selector) then
    begin
      if Comparer.Compare(Candidate, Selector(Result)) > 0 then Result := Item;
    end
    else if Comparer.Compare(Candidate, Result) > 0 then Result := Item;
  end;
end;

function TJsonQuery.Sum: Double;
var
  Item: TJsonValue;
begin
  Result := 0;
  for Item in FList do if Item <> nil then Result := Result + Item.AsDouble;
end;

function TJsonQuery.Average: Double;
begin
  if FList.Count = 0 then Exit(0);
  Result := Sum / FList.Count;
end;

function TJsonQuery.Aggregate<T>(const Seed: T; Accumulator: TJsonAccumulator<T>): T;
var
  Item: TJsonValue;
begin
  Result := Seed;
  if not Assigned(Accumulator) then Exit;
  for Item in FList do Result := Accumulator(Result, Item);
end;

function TJsonQuery.Any(Predicate: TJsonPredicate): Boolean;
var
  Item: TJsonValue;
begin
  if not Assigned(Predicate) then Exit(FList.Count > 0);
  for Item in FList do if Predicate(Item) then Exit(True);
  Result := False;
end;

function TJsonQuery.All(Predicate: TJsonPredicate): Boolean;
var
  Item: TJsonValue;
begin
  if not Assigned(Predicate) then Exit(False);
  for Item in FList do if not Predicate(Item) then Exit(False);
  Result := True;
end;

function TJsonQuery.Contains(Value: TJsonValue): Boolean;
begin
  Result := FList.Contains(Value);
end;

function TJsonQuery.First: TJsonValue;
begin
  if FList.Count = 0 then raise EJsonValueError.Create('Sequence contains no elements');
  Result := FList[0];
end;

function TJsonQuery.FirstOrDefault: TJsonValue;
begin
  if FList.Count = 0 then Result := nil else Result := FList[0];
end;

function TJsonQuery.Last: TJsonValue;
begin
  if FList.Count = 0 then raise EJsonValueError.Create('Sequence contains no elements');
  Result := FList[FList.Count - 1];
end;

function TJsonQuery.LastOrDefault: TJsonValue;
begin
  if FList.Count = 0 then Result := nil else Result := FList[FList.Count - 1];
end;

function TJsonQuery.ElementAt(Index: Integer): TJsonValue;
begin
  if (Index < 0) or (Index >= FList.Count) then raise EArgumentOutOfRangeException.Create('Index');
  Result := FList[Index];
end;

function TJsonQuery.Single: TJsonValue;
begin
  if FList.Count <> 1 then raise EJsonValueError.CreateFmt('Sequence contains %d elements', [FList.Count]);
  Result := FList[0];
end;

function TJsonQuery.ToList: TList<TJsonValue>;
begin
  Result := TList<TJsonValue>.Create;
  Result.AddRange(FList);
end;

function TJsonQuery.ToArray: TArray<TJsonValue>;
begin
  Result := FList.ToArray;
end;

function TJsonQuery.ToJsonArray: TJsonArray;
var
  Item: TJsonValue;
begin
  Result := TJsonArray.Create;
  try
    for Item in FList do if Item = nil then Result.Add(TJsonNull.Create) else Result.Add(Item.Clone);
  except
    Result.Free;
    raise;
  end;
end;

function TJsonQuery.Map<T>(Mapper: TJsonMapFunc<T>): TArray<T>;
var
  I: Integer;
begin
  if not Assigned(Mapper) then Exit(nil);
  SetLength(Result, FList.Count);
  for I := 0 to FList.Count - 1 do Result[I] := Mapper(FList[I]);
end;

class function TJsonQuery.FindObjectKey(Parent: TJsonObject; Child: TJsonValue; out Key: string): Boolean;
var
  Pair: TPair<string, TJsonValue>;
begin
  for Pair in Parent do
    if Pair.Value = Child then
    begin
      Key := Pair.Key;
      Exit(True);
    end;
  Key := '';
  Result := False;
end;

procedure TJsonQuery.Remove;
var
  Snapshot: TArray<TJsonValue>;
  Item, Parent: TJsonValue;
  Key: string;
begin
  Snapshot := FList.ToArray;
  FList.Clear;
  for Item in Snapshot do
  begin
    if Item = nil then Continue;
    Parent := Item.Parent;
    if Parent is TJsonArray then TJsonArray(Parent).Remove(Item)
    else if (Parent is TJsonObject) and FindObjectKey(TJsonObject(Parent), Item, Key) then TJsonObject(Parent).Remove(Key);
  end;
end;

procedure TJsonQuery.Replace(NewValue: TJsonValue);
var
  Snapshot: TArray<TJsonValue>;
  Item, Parent, Replacement, Template: TJsonValue;
  Key: string;
  I: Integer;
  OwnTemplate: Boolean;
begin
  OwnTemplate := NewValue = nil;
  if OwnTemplate then Template := TJsonNull.Create else Template := NewValue;
  try
    Snapshot := FList.ToArray;
    FList.Clear;
    for Item in Snapshot do
    begin
      if Item = nil then Continue;
      Parent := Item.Parent;
      Replacement := Template.Clone;
      if Parent is TJsonArray then
      begin
        for I := 0 to TJsonArray(Parent).Count - 1 do
          if TJsonArray(Parent)[I] = Item then
          begin
            TJsonArray(Parent)[I] := Replacement;
            FList.Add(Replacement);
            Replacement := nil;
            Break;
          end;
      end
      else if (Parent is TJsonObject) and FindObjectKey(TJsonObject(Parent), Item, Key) then
      begin
        TJsonObject(Parent).Values[Key] := Replacement;
        FList.Add(Replacement);
        Replacement := nil;
      end;
      Replacement.Free;
    end;
  finally
    if OwnTemplate then Template.Free;
  end;
end;

procedure TJsonQuery.ForEach(Action: TJsonAction);
var
  Item: TJsonValue;
begin
  if Assigned(Action) then for Item in FList do Action(Item);
end;

function TJsonQuery.Value<T>: T;
var
  Deserializer: TJsonDeserializer;
  V: TValue;
begin
  if FList.Count = 0 then raise EJsonValueError.Create('Sequence contains no elements');
  Deserializer := TJsonDeserializer.Create;
  try
    V := Deserializer.Deserialize(FList[0], System.TypeInfo(T));
    if V.IsEmpty then Result := Default(T) else Result := V.AsType<T>;
  finally
    Deserializer.Free;
  end;
end;

function TJsonQuery.Value<T>(const Default: T): T;
begin
  if (FList.Count = 0) or (FList[0] = nil) or FList[0].IsNull then Exit(Default);
  try
    Result := Value<T>;
  except
    Result := Default;
  end;
end;

function TJsonQuery.Values<T>: TArray<T>;
var
  I: Integer;
  Deserializer: TJsonDeserializer;
  V: TValue;
begin
  SetLength(Result, FList.Count);
  Deserializer := TJsonDeserializer.Create;
  try
    for I := 0 to FList.Count - 1 do
    begin
      V := Deserializer.Deserialize(FList[I], System.TypeInfo(T));
      if V.IsEmpty then Result[I] := Default(T) else Result[I] := V.AsType<T>;
    end;
  finally
    Deserializer.Free;
  end;
end;

class operator TJsonLinq.Implicit(const AValue: TJsonValue): TJsonLinq;
begin
  Result.FQuery := TJsonQuery.Create(AValue);
end;

class operator TJsonLinq.Implicit(const AList: TList<TJsonValue>): TJsonLinq;
begin
  Result.FQuery := TJsonQuery.Create(AList);
end;

class operator TJsonLinq.Implicit(const AQuery: TJsonLinq): IJsonQuery;
begin
  Result := AQuery.FQuery;
end;

function TJsonLinq.GetQuery: IJsonQuery;
begin
  Result := FQuery;
end;

function TJsonLinq.Children: TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.Children else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.Descendants: TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.Descendants else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.Select(const Path: string): TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.SelectPath(Path) else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.Where(Predicate: TJsonPredicate): TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.Where(Predicate) else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.First: TJsonValue;
begin
  if FQuery = nil then raise EJsonValueError.Create('Sequence contains no elements');
  Result := FQuery.First;
end;

function TJsonLinq.FirstOrDefault: TJsonValue;
begin
  if FQuery = nil then Result := nil else Result := FQuery.FirstOrDefault;
end;

function TJsonLinq.Count: Integer;
begin
  if FQuery = nil then Result := 0 else Result := FQuery.Count;
end;

function TJsonLinq.Aggregate<T>(const Seed: T; Accumulator: TJsonAccumulator<T>): T;
var
  Item: TJsonValue;
begin
  Result := Seed;
  if (FQuery = nil) or not Assigned(Accumulator) then Exit;
  for Item in FQuery.GetList do Result := Accumulator(Result, Item);
end;

function TJsonLinq.Map<T>(Mapper: TJsonMapFunc<T>): TArray<T>;
var
  I: Integer;
begin
  if (FQuery = nil) or not Assigned(Mapper) then Exit(nil);
  SetLength(Result, FQuery.Count);
  for I := 0 to FQuery.Count - 1 do Result[I] := Mapper(FQuery[I]);
end;

function TJsonLinq.Value<T>: T;
var
  Deserializer: TJsonDeserializer;
  V: TValue;
begin
  if (FQuery = nil) or (FQuery.Count = 0) then raise EJsonValueError.Create('Sequence contains no elements');
  Deserializer := TJsonDeserializer.Create;
  try
    V := Deserializer.Deserialize(FQuery[0], System.TypeInfo(T));
    if V.IsEmpty then Result := Default(T) else Result := V.AsType<T>;
  finally
    Deserializer.Free;
  end;
end;

function TJsonLinq.Value<T>(const Default: T): T;
begin
  if (FQuery = nil) or (FQuery.Count = 0) or (FQuery[0] = nil) or FQuery[0].IsNull then Exit(Default);
  try
    Result := Value<T>;
  except
    Result := Default;
  end;
end;

function TJsonLinq.Values<T>: TArray<T>;
var
  I: Integer;
  Deserializer: TJsonDeserializer;
  V: TValue;
begin
  if FQuery = nil then Exit(nil);
  SetLength(Result, FQuery.Count);
  Deserializer := TJsonDeserializer.Create;
  try
    for I := 0 to FQuery.Count - 1 do
    begin
      V := Deserializer.Deserialize(FQuery[I], System.TypeInfo(T));
      if V.IsEmpty then Result[I] := Default(T) else Result[I] := V.AsType<T>;
    end;
  finally
    Deserializer.Free;
  end;
end;

function TJsonLinq.ToJson: string;
var
  Arr: TJsonArray;
begin
  if (FQuery = nil) or (FQuery.Count = 0) then Exit('null');
  if FQuery.Count = 1 then Exit(FQuery[0].ToJson);
  Arr := FQuery.ToJsonArray;
  try
    Result := Arr.ToJson;
  finally
    Arr.Free;
  end;
end;

procedure TJsonLinq.Remove;
begin
  if FQuery <> nil then FQuery.Remove;
end;


// --- .Q surface: forwarding to IJsonQuery ---------------------------------
//
//   All of the following functions are pure pass-throughs. Their only own
//   contribution is handling FQuery = nil: a TJsonLinq that never came from
//   a value behaves like an empty sequence instead of blowing up.
//   That is why every chain has the same if-then line.

function TJsonLinq.Parents: TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.Parents else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.Ancestors: TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.Ancestors else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.Siblings: TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.Siblings else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.OfType(JsonType: TJsonType): TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.OfType(JsonType) else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.NotNull: TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.NotNull else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.Transform(Selector: TJsonTransform): TJsonLinq;
begin
  // On the interface this is called Select. Here the name is already
  // taken - Select(const Path: string) means something else - and so is Map,
  // through the existing Map<T>. Hence Transform.
  if FQuery <> nil then Result.FQuery := FQuery.Select(Selector) else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.TransformMany(Selector: TJsonTransform): TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.SelectMany(Selector) else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.Distinct: TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.Distinct else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.Union(const Other: TJsonLinq): TJsonLinq;
begin
  if FQuery = nil then Exit(Other);
  if Other.FQuery = nil then Exit(Self);
  Result.FQuery := FQuery.Union(Other.FQuery);
end;

function TJsonLinq.Intersect(const Other: TJsonLinq): TJsonLinq;
begin
  // Intersecting with nothing is nothing - unlike Union, the other side
  // must not be passed through here.
  if (FQuery = nil) or (Other.FQuery = nil) then Result.FQuery := TJsonQuery.Create
  else Result.FQuery := FQuery.Intersect(Other.FQuery);
end;

function TJsonLinq.Exclude(const Other: TJsonLinq): TJsonLinq;
begin
  if FQuery = nil then Result.FQuery := TJsonQuery.Create
  else if Other.FQuery = nil then Result := Self
  else Result.FQuery := FQuery.Exclude(Other.FQuery);
end;

function TJsonLinq.Concat(const Other: TJsonLinq): TJsonLinq;
begin
  if FQuery = nil then Exit(Other);
  if Other.FQuery = nil then Exit(Self);
  Result.FQuery := FQuery.Concat(Other.FQuery);
end;

function TJsonLinq.OrderBy(KeySelector: TJsonTransform): TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.OrderBy(KeySelector) else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.OrderByDescending(KeySelector: TJsonTransform): TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.OrderByDescending(KeySelector) else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.ThenBy(KeySelector: TJsonTransform): TJsonLinq;
var
  Ordered: IOrderedJsonQuery;
begin
  // ThenBy belongs to IOrderedJsonQuery, but the record only holds
  // IJsonQuery - hence the query through Supports. TJsonQuery
  // answers both interfaces, so the query also succeeds without
  // a preceding OrderBy. That is intended: the chained comparer
  // simply skips a missing first key, so ThenBy alone
  // acts like OrderBy instead of failing.
  if (FQuery <> nil) and Supports(FQuery, IOrderedJsonQuery, Ordered) then
    Result.FQuery := Ordered.ThenBy(KeySelector)
  else
    Result := Self;
end;

function TJsonLinq.ThenByDescending(KeySelector: TJsonTransform): TJsonLinq;
var
  Ordered: IOrderedJsonQuery;
begin
  if (FQuery <> nil) and Supports(FQuery, IOrderedJsonQuery, Ordered) then
    Result.FQuery := Ordered.ThenByDescending(KeySelector)
  else
    Result := Self;
end;

function TJsonLinq.Reverse: TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.Reverse else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.Skip(ACount: Integer): TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.Skip(ACount) else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.Take(ACount: Integer): TJsonLinq;
begin
  if FQuery <> nil then Result.FQuery := FQuery.Take(ACount) else Result.FQuery := TJsonQuery.Create;
end;

function TJsonLinq.Last: TJsonValue;
begin
  if FQuery = nil then raise EJsonValueError.Create('Sequence contains no elements');
  Result := FQuery.Last;
end;

function TJsonLinq.LastOrDefault: TJsonValue;
begin
  if FQuery = nil then Result := nil else Result := FQuery.LastOrDefault;
end;

function TJsonLinq.Single: TJsonValue;
begin
  if FQuery = nil then raise EJsonValueError.Create('Sequence contains no elements');
  Result := FQuery.Single;
end;

function TJsonLinq.ElementAt(Index: Integer): TJsonValue;
begin
  if FQuery = nil then raise EJsonValueError.Create('Sequence contains no elements');
  Result := FQuery.ElementAt(Index);
end;

function TJsonLinq.Min(Selector: TJsonTransform): TJsonValue;
begin
  if FQuery = nil then Result := nil else Result := FQuery.Min(Selector);
end;

function TJsonLinq.Max(Selector: TJsonTransform): TJsonValue;
begin
  if FQuery = nil then Result := nil else Result := FQuery.Max(Selector);
end;

function TJsonLinq.Any(Predicate: TJsonPredicate): Boolean;
begin
  Result := (FQuery <> nil) and FQuery.Any(Predicate);
end;

function TJsonLinq.All(Predicate: TJsonPredicate): Boolean;
begin
  // An empty sequence satisfies every condition - that way All is defined
  // everywhere, and the interface follows that.
  if FQuery = nil then Result := True else Result := FQuery.All(Predicate);
end;

function TJsonLinq.Contains(Value: TJsonValue): Boolean;
begin
  Result := (FQuery <> nil) and FQuery.Contains(Value);
end;

function TJsonLinq.Sum: Double;
begin
  if FQuery = nil then Result := 0 else Result := FQuery.Sum;
end;

function TJsonLinq.Average: Double;
begin
  if FQuery = nil then Result := 0 else Result := FQuery.Average;
end;

function TJsonLinq.ToArray: TArray<TJsonValue>;
begin
  if FQuery = nil then Result := nil else Result := FQuery.ToArray;
end;

function TJsonLinq.ToJsonArray: TJsonArray;
begin
  // Always an array, even for an empty sequence - the caller owns it.
  if FQuery = nil then Result := TJsonArray.Create else Result := FQuery.ToJsonArray;
end;

procedure TJsonLinq.ForEach(Action: TJsonAction);
begin
  if FQuery <> nil then FQuery.ForEach(Action);
end;

procedure TJsonLinq.Replace(NewValue: TJsonValue);
begin
  if FQuery <> nil then FQuery.Replace(NewValue);
end;

function TJsonValueLinqHelper.Q: TJsonLinq;
begin
  Result := Self;
end;

end.
