{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Dom.Value;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  TypInfo,
  Generics.Collections;
  {$ELSE}
  System.SysUtils,
  System.TypInfo,
  System.Generics.Collections;
  {$ENDIF}

type
  // Forward declaration (important for the predicate)
  TJsonValue = class;

  EJsonValueError = class(Exception);
  EJsonPathError = class(EJsonValueError);

  TJsonType = (
    jtNone,
    jtObject,
    jtArray,
    jtString,
    jtInteger,
    jtFloat,
    jtBoolean,
    jtNull,
    jtDate,
    jtBytes
  );

  TJsonValuePredicate = reference to function(const Value: TJsonValue): Boolean;

  TJsonValue = class abstract
  private
    FParent: TJsonValue;
  protected
    function GetItem(Index: Integer): TJsonValue; virtual;
    procedure SetItem(Index: Integer; const Value: TJsonValue); virtual;
    function GetAttribute(const Name: string): TJsonValue; virtual;
    procedure SetAttribute(const Name: string; const Value: TJsonValue); virtual;
    procedure SetParent(const Value: TJsonValue);
  public
    // Type information
    function GetJsonType: TJsonType; virtual; abstract;
    function IsContainer: Boolean;
    
    // Hierarchy
    property Parent: TJsonValue read FParent;
    
    // Container Access
    property Items[Index: Integer]: TJsonValue read GetItem write SetItem; default;
    property Values[const Name: string]: TJsonValue read GetAttribute write SetAttribute;
    
    // Value Accessors
    function AsString: string; virtual;
    function AsInteger: Int64; virtual;
    function AsDouble: Double; virtual;
    function AsCurrency: Currency; virtual;
    function AsRawText: string; virtual;
    function AsBoolean: Boolean; virtual;
    function IsNull: Boolean; virtual;
    
    // Output / Manipulation
    function Clone: TJsonValue; virtual; abstract;
    function ToJson: string; virtual; abstract;

    // --- NAVIGATION & PATH (Modern API) ---
    
    // 1. Single value (first match) - the classic
    function SelectToken(const Path: string): TJsonValue;
    function TrySelectToken(const Path: string; out Value: TJsonValue): Boolean;
    
    // 2. Multiple values (wildcards *, recursion ..)
    function FindAll(const Path: string): TArray<TJsonValue>;

    // 3. Filter with a callback
    // Example: Dom.Find('Users', function(V) Result := V['Age'].AsInt > 18 end)
    function Find(const Path: string; const Predicate: TJsonValuePredicate): TArray<TJsonValue>; overload;
    
    // Overload without a path (searches in the current element)
    function Find(const Predicate: TJsonValuePredicate): TArray<TJsonValue>; overload;
    
    // 4. Writing
    // Since NativeJson.Dom.JsonObject must not be in the interface here (circular),
    // TJsonValue has to be returned, but the name clearly says "ObjectPath".
    function EnsureObjectPath(const Path: string): TJsonValue;
    
    // 5. Convenience getters
    function GetStringPath(const Path: string; const Default: string = ''): string;
    function GetIntegerPath(const Path: string; Default: Int64 = 0): Int64;
  end;

implementation

uses
  {$IFDEF FPC}
  Character,
  SyncObjs,
  {$ELSE}
  System.Character,
  System.SyncObjs,
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.JsonArray;

// =============================================================================
// INTERNAL TYPES (hidden from the user)
// =============================================================================

type
  TJsonPathSegmentKind = (
    psProperty,  // .Name or ['Name']
    psIndex,     // [1]
    psWildcard,  // * or [*]
    psRecursive  // .. (Deep Scan)
  );

  TJsonPathSegment = record
    Kind: TJsonPathSegmentKind;
    Name: string;
    Index: Integer;
  end;

// =============================================================================
// PARSER LOGIC
// =============================================================================

function ParsePath(const Path: string): TArray<TJsonPathSegment>;
var
  P: PChar;
  Segs: TList<TJsonPathSegment>;
  Seg: TJsonPathSegment;
  Start: PChar;
  NumStr: string;
  
  procedure SkipWhitespace;
  begin
    while (P^ <> #0) and (P^ <= ' ') do Inc(P);
  end;
  
  function ParseName: string;
  var LocalStart: PChar;
  begin
    LocalStart := P;
    while (P^ <> #0) and (P^ <> '.') and (P^ <> '[') and (P^ <> ']') and (P^ > ' ') do Inc(P);
    SetString(Result, LocalStart, P - LocalStart);
  end;
  
  function ParseQuoted(Quote: Char): string;
  var
    SB: TJsonStringBuilder;
    C: Char;
  begin
    Inc(P); 
    SB := TJsonStringBuilder.Create;
    try
      while P^ <> #0 do
      begin
        C := P^;
        Inc(P);
        if C = Quote then 
        begin
          Result := SB.ToString;
          Exit; 
        end;
        
        if C = '\' then
        begin
          if P^ = #0 then 
             raise EJsonPathError.Create('Unterminated escape sequence in path');
          C := P^; 
          Inc(P);
        end;
        
        SB.Append(C);
      end;
      raise EJsonPathError.Create('Unterminated quoted name in path');
    finally
      SB.Free;
    end;
  end;

begin
  Segs := TList<TJsonPathSegment>.Create;
  try
    P := PChar(Path);
    
    SkipWhitespace;
    if P^ = '$' then Inc(P); 
    
    while P^ <> #0 do
    begin
      SkipWhitespace;
      
      // --- RECURSION (..) ---
      if (P^ = '.') and ((P+1)^ = '.') then
      begin
        Inc(P, 2); 
        Seg.Kind := psRecursive;
        Segs.Add(Seg);
        Continue; 
      end;

      // --- PROPERTY (.) ---
      if P^ = '.' then
      begin
        Inc(P);
        SkipWhitespace;
        
        if P^ = '*' then
        begin
          Inc(P);
          Seg.Kind := psWildcard;
          Segs.Add(Seg);
        end
        else
        begin
          Seg.Kind := psProperty;
          Seg.Name := ParseName;
          if Seg.Name = '' then raise EJsonPathError.Create('Empty property name in path');
          Segs.Add(Seg);
        end;
      end
      // --- INDEXER ([) ---
      else if P^ = '[' then
      begin
        Inc(P);
        SkipWhitespace;
        
        if P^ = '*' then
        begin
          Inc(P);
          Seg.Kind := psWildcard;
        end
        else if (P^ = '''') or (P^ = '"') then
        begin
          Seg.Kind := psProperty;
          Seg.Name := ParseQuoted(P^); 
        end
        else
        begin
          Start := P;
          while (P^ >= '0') and (P^ <= '9') do Inc(P);
          SetString(NumStr, Start, P - Start);
          if NumStr = '' then raise EJsonPathError.Create('Invalid index in path');
          Seg.Kind := psIndex;
          Seg.Index := StrToInt(NumStr);
        end;
        
        SkipWhitespace;
        if P^ <> ']' then raise EJsonPathError.Create('Expected "]"');
        Inc(P);
        Segs.Add(Seg);
      end
      // --- START IDENTIFIER OR AFTER RECURSION ---
      else if (Segs.Count = 0) or 
              ((Segs.Count > 0) and (Segs.Last.Kind = psRecursive)) then
      begin
        Seg.Kind := psProperty;
        Seg.Name := ParseName;
        
        if Seg.Name <> '' then 
          Segs.Add(Seg)
        else if (Segs.Count > 0) and (Segs.Last.Kind = psRecursive) then
        begin
           // Case: "..[...]" -> OK
        end
        else
           raise EJsonPathError.Create('Unexpected character or empty property in path');
      end
      else
        raise EJsonPathError.Create('Unexpected character in path');
    end;
    
    Result := Segs.ToArray;
  finally
    Segs.Free;
  end;
end;

// =============================================================================
// CACHE
// =============================================================================

type
  TJsonPathCache = class
  private
    class var FCache: TDictionary<string, TArray<TJsonPathSegment>>;
    class var FLock: TCriticalSection;
    class constructor Create;
    class destructor Destroy;
  public
    class function GetSegments(const Path: string): TArray<TJsonPathSegment>;
    class procedure Clear; // New: for debugging/tests
  end;

class constructor TJsonPathCache.Create;
begin
  FCache := TDictionary<string, TArray<TJsonPathSegment>>.Create;
  FLock := TCriticalSection.Create;
end;

class destructor TJsonPathCache.Destroy;
begin
  FCache.Free;
  FLock.Free;
end;

class function TJsonPathCache.GetSegments(const Path: string): TArray<TJsonPathSegment>;
begin
  FLock.Enter;
  try
    if not FCache.TryGetValue(Path, Result) then
    begin
      Result := ParsePath(Path);
      FCache.Add(Path, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

class procedure TJsonPathCache.Clear;
begin
  FLock.Enter;
  try
    FCache.Clear;
  finally
    FLock.Leave;
  end;
end;

// =============================================================================
// TJsonValue Implementation
// =============================================================================

procedure CollectSelfAndDescendants(Root: TJsonValue; List: TList<TJsonValue>);
var
  Pair: TPair<string, TJsonValue>;
  Item: TJsonValue;
begin
  List.Add(Root);
  
  if Root is TJsonObject then
  begin
    for Pair in TJsonObject(Root) do
      CollectSelfAndDescendants(Pair.Value, List);
  end
  else if Root is TJsonArray then
  begin
    for Item in TJsonArray(Root) do
      CollectSelfAndDescendants(Item, List);
  end;
end;

function TJsonValue.FindAll(const Path: string): TArray<TJsonValue>;
var
  Segments: TArray<TJsonPathSegment>;
  CurrentNodes, NextNodes, TempList: TList<TJsonValue>;
  I: Integer;
  Seg: TJsonPathSegment;
  Node, ChildNode: TJsonValue;
  Pair: TPair<string, TJsonValue>;
  Arr: TJsonArray;
begin
  if Path = '' then 
    Exit(TArray<TJsonValue>.Create(Self));
    
  Segments := TJsonPathCache.GetSegments(Path);
  
  CurrentNodes := TList<TJsonValue>.Create;
  CurrentNodes.Add(Self);
  
  NextNodes := TList<TJsonValue>.Create;
  
  try
    for I := 0 to High(Segments) do
    begin
      Seg := Segments[I];
      NextNodes.Clear;
      
      for Node in CurrentNodes do
      begin
        case Seg.Kind of
          psProperty:
            begin
              if Node is TJsonObject then
              begin
                if TJsonObject(Node).TryGetValue(Seg.Name, ChildNode) then
                  NextNodes.Add(ChildNode);
              end;
            end;
            
          psIndex:
            begin
              if Node is TJsonArray then
              begin
                Arr := TJsonArray(Node);
                if (Seg.Index >= 0) and (Seg.Index < Arr.Count) then
                  NextNodes.Add(Arr[Seg.Index]);
              end;
            end;
            
          psWildcard:
            begin
              if Node is TJsonObject then
              begin
                for Pair in TJsonObject(Node) do
                  NextNodes.Add(Pair.Value);
              end
              else if Node is TJsonArray then
              begin
                for ChildNode in TJsonArray(Node) do
                  NextNodes.Add(ChildNode);
              end;
            end;
            
          psRecursive:
            begin
              CollectSelfAndDescendants(Node, NextNodes);
            end;
        end;
      end;
      
      // Swap Lists
      TempList := CurrentNodes;
      CurrentNodes := NextNodes;
      NextNodes := TempList;
      
      if CurrentNodes.Count = 0 then Break;
    end;
    
    Result := CurrentNodes.ToArray;
  finally
    CurrentNodes.Free;
    NextNodes.Free;
  end;
end;

function TJsonValue.Find(const Path: string; const Predicate: TJsonValuePredicate): TArray<TJsonValue>;
var
  Candidates: TArray<TJsonValue>;
  ResultList: TList<TJsonValue>;
  Node: TJsonValue;
begin
  Candidates := FindAll(Path);
  
  if Length(Candidates) = 0 then Exit(nil);
  if not Assigned(Predicate) then Exit(Candidates);

  ResultList := TList<TJsonValue>.Create;
  try
    for Node in Candidates do
    begin
      if Predicate(Node) then
        ResultList.Add(Node);
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TJsonValue.Find(const Predicate: TJsonValuePredicate): TArray<TJsonValue>;
begin
  // Overload for searching in the current context (Path = '')
  Result := Find('', Predicate);
end;

function TJsonValue.SelectToken(const Path: string): TJsonValue;
var
  Results: TArray<TJsonValue>;
begin
  Results := FindAll(Path);
  if Length(Results) > 0 then
    Result := Results[0]
  else
    Result := nil;
end;

function TJsonValue.TrySelectToken(const Path: string; out Value: TJsonValue): Boolean;
begin
  try
    Value := SelectToken(Path);
    Result := Value <> nil;
  except
    on EJsonPathError do
    begin
      Value := nil;
      Result := False;
    end;
  end;
end;

function TJsonValue.EnsureObjectPath(const Path: string): TJsonValue;
var
  Segments: TArray<TJsonPathSegment>;
  Seg: TJsonPathSegment;
  Curr: TJsonValue;
  I: Integer;
  NextObj: TJsonObject;
  Obj: TJsonObject;
begin
  Segments := TJsonPathCache.GetSegments(Path);
  Curr := Self;
  
  for I := 0 to High(Segments) do
  begin
    Seg := Segments[I];
    
    case Seg.Kind of
      psProperty:
        begin
          if not (Curr is TJsonObject) then
            raise EJsonPathError.Create('EnsureObjectPath failed: Intermediate node is not an object');
            
          Obj := TJsonObject(Curr);
          if not Obj.TryGetValue(Seg.Name, Curr) then
          begin
            NextObj := TJsonObject.Create;
            Obj.AddPair(Seg.Name, NextObj);
            Curr := NextObj;
          end;
        end;
        
      psIndex, psWildcard, psRecursive:
        raise EJsonPathError.Create('EnsureObjectPath only supports explicit properties'); 
    end;
  end;
  
  // Check at the end (safety)
  if not (Curr is TJsonObject) then
     raise EJsonPathError.Create('EnsureObjectPath did not result in an object');

  Result := Curr;
end;

function TJsonValue.GetStringPath(const Path: string; const Default: string): string;
var
  V: TJsonValue;
begin
  if TrySelectToken(Path, V) and (V <> nil) and (V.GetJsonType = TJsonType.jtString) then
    Result := V.AsString
  else
    Result := Default;
end;

function TJsonValue.GetIntegerPath(const Path: string; Default: Int64): Int64;
var
  V: TJsonValue;
begin
  if TrySelectToken(Path, V) and (V <> nil) and (V.GetJsonType in [TJsonType.jtInteger, TJsonType.jtFloat]) then
    Result := V.AsInteger
  else
    Result := Default;
end;

// --- Standard implementations ---

procedure TJsonValue.SetParent(const Value: TJsonValue);
begin
  FParent := Value;
end;

function TJsonValue.IsContainer: Boolean;
begin
  Result := GetJsonType in [TJsonType.jtObject, TJsonType.jtArray];
end;

function TJsonValue.GetItem(Index: Integer): TJsonValue;
begin
  raise EJsonValueError.CreateFmt('Cannot access index [%d] on %s', [Index, GetEnumName(System.TypeInfo(TJsonType), Ord(GetJsonType))]);
end;

procedure TJsonValue.SetItem(Index: Integer; const Value: TJsonValue);
begin
  raise EJsonValueError.CreateFmt('Cannot set index [%d] on %s', [Index, GetEnumName(System.TypeInfo(TJsonType), Ord(GetJsonType))]);
end;

function TJsonValue.GetAttribute(const Name: string): TJsonValue;
begin
  raise EJsonValueError.CreateFmt('Cannot access property "%s" on %s', [Name, GetEnumName(System.TypeInfo(TJsonType), Ord(GetJsonType))]);
end;

procedure TJsonValue.SetAttribute(const Name: string; const Value: TJsonValue);
begin
  raise EJsonValueError.CreateFmt('Cannot set property "%s" on %s', [Name, GetEnumName(System.TypeInfo(TJsonType), Ord(GetJsonType))]);
end;

function TJsonValue.AsString: string;
begin
  raise EJsonValueError.CreateFmt('Cannot convert %s to String', [GetEnumName(System.TypeInfo(TJsonType), Ord(GetJsonType))]);
end;

function TJsonValue.AsInteger: Int64;
begin
  raise EJsonValueError.CreateFmt('Cannot convert %s to Integer', [GetEnumName(System.TypeInfo(TJsonType), Ord(GetJsonType))]);
end;

function TJsonValue.AsDouble: Double;
begin
  raise EJsonValueError.CreateFmt('Cannot convert %s to Double', [GetEnumName(System.TypeInfo(TJsonType), Ord(GetJsonType))]);
end;

function TJsonValue.AsCurrency: Currency;
begin
  Result := AsDouble;
end;

function TJsonValue.AsRawText: string;
begin
  // The text as it appeared in the JSON. Only numbers differ from it when
  // they were passed through Int64 or Double - there the raw text
  // is the only lossless source.
  Result := AsString;
end;

function TJsonValue.AsBoolean: Boolean;
begin
  raise EJsonValueError.CreateFmt('Cannot convert %s to Boolean', [GetEnumName(System.TypeInfo(TJsonType), Ord(GetJsonType))]);
end;

function TJsonValue.IsNull: Boolean;
begin
  Result := False;
end;

end.