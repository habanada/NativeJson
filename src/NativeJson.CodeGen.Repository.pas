{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.CodeGen.Repository;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE}
  System.SysUtils,
  {$ENDIF}
  NativeJson.Dom.Value,
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.Primitive,
  NativeJson.Dom.Io,
  {$IFDEF FPC}
  Generics.Collections,
  Character;
  {$ELSE}
  System.Generics.Collections,
  System.Character;
  {$ENDIF}

type
  EJsonCodeGenRepository = class(Exception);

  TJsonCodeGenLocation = record
  public
    Value: TJsonValue;
    BaseUri: string;
    Pointer: string;
    CanonicalUri: string;
    class function Empty: TJsonCodeGenLocation; static;
  end;

  TJsonCodeGenRepository = class
  private
    FDocuments: TObjectList<TJsonValue>;
    FResources: TDictionary<string, TJsonValue>;
    FAnchors: TDictionary<string, TJsonValue>;
    FLocations: TDictionary<Pointer, TJsonCodeGenLocation>;
    FSequence: Integer;
    class function StripFragment(const Uri: string): string; static;
    class function SplitFragment(const Uri: string; out Resource, Fragment: string): Boolean; static;
    class function IsAbsoluteUri(const Uri: string): Boolean; static;
    class function NormalizePath(const Path: string): string; static;
    class function UriOrigin(const Uri: string): string; static;
    class function UriPathStart(const Uri: string): Integer; static;
    class function PointerTokenDecode(const Token: string): string; static;
    function SyntheticUri: string;
    procedure IndexValue(Value: TJsonValue; const InheritedBase, ResourceBase, PointerPath: string; IsResourceRoot: Boolean);
    function ResolvePointer(Root: TJsonValue; const Fragment: string): TJsonValue;
  public
    constructor Create;
    destructor Destroy; override;
    function RegisterSchema(const SchemaJson: string; const SourceUri: string = ''): TJsonCodeGenLocation; overload;
    function RegisterSchema(Schema: TJsonValue; const SourceUri: string = ''): TJsonCodeGenLocation; overload;
    function TryGetLocation(Value: TJsonValue; out Location: TJsonCodeGenLocation): Boolean;
    function Resolve(const Reference, CurrentBaseUri: string; out Location: TJsonCodeGenLocation): Boolean;
    class function ResolveUri(const BaseUri, Reference: string): string; static;
  end;

implementation

uses
  {$IFDEF FPC}
  Classes,
  StrUtils,
  System.NetEncoding;
  {$ELSE}
  System.Classes,
  System.StrUtils,
  System.NetEncoding;
  {$ENDIF}

class function TJsonCodeGenLocation.Empty: TJsonCodeGenLocation;
begin
  Result.Value := nil;
  Result.BaseUri := '';
  Result.Pointer := '';
  Result.CanonicalUri := '';
end;

constructor TJsonCodeGenRepository.Create;
begin
  inherited Create;
  FDocuments := TObjectList<TJsonValue>.Create(True);
  FResources := TDictionary<string, TJsonValue>.Create;
  FAnchors := TDictionary<string, TJsonValue>.Create;
  FLocations := TDictionary<Pointer, TJsonCodeGenLocation>.Create;
end;

destructor TJsonCodeGenRepository.Destroy;
begin
  FLocations.Free;
  FAnchors.Free;
  FResources.Free;
  FDocuments.Free;
  inherited;
end;

function TJsonCodeGenRepository.SyntheticUri: string;
begin
  Inc(FSequence);
  Result := 'nativejson://schema/' + IntToStr(FSequence);
end;

class function TJsonCodeGenRepository.StripFragment(const Uri: string): string;
var
  P: Integer;
begin
  P := Pos('#', Uri);
  if P > 0 then Result := Copy(Uri, 1, P - 1) else Result := Uri;
end;

class function TJsonCodeGenRepository.SplitFragment(const Uri: string; out Resource, Fragment: string): Boolean;
var
  P: Integer;
begin
  P := Pos('#', Uri);
  Result := P > 0;
  if Result then
  begin
    Resource := Copy(Uri, 1, P - 1);
    Fragment := Copy(Uri, P + 1, MaxInt);
  end
  else
  begin
    Resource := Uri;
    Fragment := '';
  end;
end;

class function TJsonCodeGenRepository.IsAbsoluteUri(const Uri: string): Boolean;
var
  I: Integer;
  C: Char;
begin
  Result := False;
  if (Uri = '') or not Uri[1].IsLetter then Exit;
  for I := 2 to Length(Uri) do
  begin
    C := Uri[I];
    if C = ':' then Exit(True);
    if not (C.IsLetterOrDigit or (C = '+') or (C = '-') or (C = '.')) then Exit(False);
  end;
end;

class function TJsonCodeGenRepository.UriOrigin(const Uri: string): string;
var
  Scheme, P: Integer;
begin
  Result := '';
  Scheme := Pos('://', Uri);
  if Scheme = 0 then Exit;
  P := PosEx('/', Uri, Scheme + 3);
  if P = 0 then Result := Uri else Result := Copy(Uri, 1, P - 1);
end;

class function TJsonCodeGenRepository.UriPathStart(const Uri: string): Integer;
var
  Scheme: Integer;
begin
  Scheme := Pos('://', Uri);
  if Scheme = 0 then Exit(1);
  Result := PosEx('/', Uri, Scheme + 3);
  if Result = 0 then Result := Length(Uri) + 1;
end;

class function TJsonCodeGenRepository.NormalizePath(const Path: string): string;
var
  Parts, OutParts: TArray<string>;
  Part: string;
  Count: Integer;
  Leading, Trailing: Boolean;
begin
  if Path = '' then Exit('');
  Leading := Path.StartsWith('/');
  Trailing := Path.EndsWith('/') or Path.EndsWith('/.') or Path.EndsWith('/..');
  Parts := Path.Split(['/']);
  SetLength(OutParts, Length(Parts));
  Count := 0;
  for Part in Parts do
  begin
    if (Part = '') or (Part = '.') then Continue;
    if Part = '..' then
    begin
      if Count > 0 then Dec(Count);
      Continue;
    end;
    OutParts[Count] := Part;
    Inc(Count);
  end;
  SetLength(OutParts, Count);
  Result := string.Join('/', OutParts);
  if Leading then Result := '/' + Result;
  if Trailing and not Result.EndsWith('/') then Result := Result + '/';
  if Leading and (Result = '') then Result := '/';
end;

class function TJsonCodeGenRepository.ResolveUri(const BaseUri, Reference: string): string;
var
  Base, RefResource, Fragment, Origin, BasePath, Combined, Query: string;
  PathStart, P, Q: Integer;
begin
  if Reference = '' then Exit(StripFragment(BaseUri));
  if Reference[1] = '#' then Exit(StripFragment(BaseUri) + Reference);
  if IsAbsoluteUri(Reference) then Exit(Reference);
  Base := StripFragment(BaseUri);
  if Reference[1] = '?' then
  begin
    Q := Pos('?', Base);
    if Q > 0 then Base := Copy(Base, 1, Q - 1);
    Exit(Base + Reference);
  end;
  SplitFragment(Reference, RefResource, Fragment);
  Q := Pos('?', RefResource);
  Query := '';
  if Q > 0 then
  begin
    Query := Copy(RefResource, Q, MaxInt);
    RefResource := Copy(RefResource, 1, Q - 1);
  end;
  Origin := UriOrigin(Base);
  if (RefResource <> '') and RefResource.StartsWith('/') then Combined := Origin + NormalizePath(RefResource)
  else
  begin
    Q := Pos('?', Base);
    if Q > 0 then Base := Copy(Base, 1, Q - 1);
    PathStart := UriPathStart(Base);
    BasePath := Copy(Base, PathStart, MaxInt);
    P := LastDelimiter('/', BasePath);
    if P > 0 then BasePath := Copy(BasePath, 1, P) else BasePath := '/';
    Combined := Origin + NormalizePath(BasePath + RefResource);
    if Origin = '' then Combined := NormalizePath(BasePath + RefResource);
  end;
  Result := Combined + Query;
  if Fragment <> '' then Result := Result + '#' + Fragment else if Reference.EndsWith('#') then Result := Result + '#';
end;

class function TJsonCodeGenRepository.PointerTokenDecode(const Token: string): string;
begin
  Result := StringReplace(StringReplace(Token, '~1', '/', [rfReplaceAll]), '~0', '~', [rfReplaceAll]);
end;

procedure TJsonCodeGenRepository.IndexValue(Value: TJsonValue; const InheritedBase, ResourceBase, PointerPath: string; IsResourceRoot: Boolean);
var
  Obj: TJsonObject;
  Pair: TPair<string, TJsonValue>;
  IdValue, AnchorValue, Child, Components, Schemas: TJsonValue;
  LocalBase, LocalResource, LocalPointer, Canonical, Anchor, IdText: string;
  Location: TJsonCodeGenLocation;
  I: Integer;
  procedure IndexSingle(const Name: string);
  begin
    Child := Obj.GetValue(Name);
    if (Child is TJsonObject) or (Child is TJsonBoolean) then IndexValue(Child, LocalBase, LocalResource, LocalPointer + '/' + StringReplace(StringReplace(Name, '~', '~0', [rfReplaceAll]), '/', '~1', [rfReplaceAll]), False);
  end;
  procedure IndexMap(const Name: string);
  var
    MapValue: TJsonValue;
    MapObj: TJsonObject;
    MapPair: TPair<string, TJsonValue>;
    MapPath: string;
  begin
    MapValue := Obj.GetValue(Name);
    if not (MapValue is TJsonObject) then Exit;
    MapObj := TJsonObject(MapValue);
    MapPath := LocalPointer + '/' + StringReplace(StringReplace(Name, '~', '~0', [rfReplaceAll]), '/', '~1', [rfReplaceAll]);
    for MapPair in MapObj do
      if (MapPair.Value is TJsonObject) or (MapPair.Value is TJsonBoolean) then
        IndexValue(MapPair.Value, LocalBase, LocalResource, MapPath + '/' + StringReplace(StringReplace(MapPair.Key, '~', '~0', [rfReplaceAll]), '/', '~1', [rfReplaceAll]), False);
  end;
  procedure IndexArray(const Name: string);
  var
    ArrayValue: TJsonValue;
    Arr: TJsonArray;
    ArrayPath: string;
    J: Integer;
  begin
    ArrayValue := Obj.GetValue(Name);
    if not (ArrayValue is TJsonArray) then Exit;
    Arr := TJsonArray(ArrayValue);
    ArrayPath := LocalPointer + '/' + StringReplace(StringReplace(Name, '~', '~0', [rfReplaceAll]), '/', '~1', [rfReplaceAll]);
    for J := 0 to Arr.Count - 1 do
      if (Arr.Items[J] is TJsonObject) or (Arr.Items[J] is TJsonBoolean) then IndexValue(Arr.Items[J], LocalBase, LocalResource, ArrayPath + '/' + IntToStr(J), False);
  end;
begin
  if Value = nil then Exit;
  LocalBase := InheritedBase;
  LocalResource := ResourceBase;
  LocalPointer := PointerPath;
  if Value is TJsonObject then
  begin
    Obj := TJsonObject(Value);
    IdValue := Obj.GetValue('$id');
    if IdValue is TJsonString then
    begin
      IdText := IdValue.AsString;
      if IdText <> '' then
      begin
        LocalBase := ResolveUri(InheritedBase, IdText);
        LocalResource := StripFragment(LocalBase);
        LocalPointer := '';
        FResources.AddOrSetValue(LocalResource, Value);
        IsResourceRoot := True;
      end;
    end;
  end;
  if LocalResource = '' then LocalResource := StripFragment(LocalBase);
  if IsResourceRoot then FResources.AddOrSetValue(LocalResource, Value);
  Canonical := LocalResource;
  if LocalPointer <> '' then Canonical := Canonical + '#' + LocalPointer;
  Location.Value := Value;
  Location.BaseUri := StripFragment(LocalBase);
  Location.Pointer := LocalPointer;
  Location.CanonicalUri := Canonical;
  FLocations.AddOrSetValue(Pointer(Value), Location);
  if not (Value is TJsonObject) then Exit;
  Obj := TJsonObject(Value);
  AnchorValue := Obj.GetValue('$anchor');
  if AnchorValue is TJsonString then
  begin
    Anchor := AnchorValue.AsString;
    if Anchor <> '' then FAnchors.AddOrSetValue(LocalResource + '#' + Anchor, Value);
  end;
  AnchorValue := Obj.GetValue('$dynamicAnchor');
  if AnchorValue is TJsonString then
  begin
    Anchor := AnchorValue.AsString;
    if Anchor <> '' then FAnchors.AddOrSetValue(LocalResource + '#' + Anchor, Value);
  end;
  if IsResourceRoot and (Obj.GetValue('openapi') is TJsonString) then
  begin
    Components := Obj.GetValue('components');
    if Components is TJsonObject then
    begin
      Schemas := TJsonObject(Components).GetValue('schemas');
      if Schemas is TJsonObject then
        for Pair in TJsonObject(Schemas) do
          if (Pair.Value is TJsonObject) or (Pair.Value is TJsonBoolean) then
            IndexValue(Pair.Value, LocalBase, LocalResource, LocalPointer + '/components/schemas/' + StringReplace(StringReplace(Pair.Key, '~', '~0', [rfReplaceAll]), '/', '~1', [rfReplaceAll]), False);
    end;
  end;
  IndexMap('$defs');
  IndexMap('definitions');
  IndexMap('properties');
  IndexMap('patternProperties');
  IndexMap('dependentSchemas');
  Child := Obj.GetValue('dependencies');
  if Child is TJsonObject then
    for Pair in TJsonObject(Child) do
      if (Pair.Value is TJsonObject) or (Pair.Value is TJsonBoolean) then
        IndexValue(Pair.Value, LocalBase, LocalResource, LocalPointer + '/dependencies/' + StringReplace(StringReplace(Pair.Key, '~', '~0', [rfReplaceAll]), '/', '~1', [rfReplaceAll]), False);
  IndexArray('allOf');
  IndexArray('anyOf');
  IndexArray('oneOf');
  IndexArray('prefixItems');
  Child := Obj.GetValue('items');
  if Child is TJsonArray then
  begin
    for I := 0 to TJsonArray(Child).Count - 1 do
      if (TJsonArray(Child).Items[I] is TJsonObject) or (TJsonArray(Child).Items[I] is TJsonBoolean) then IndexValue(TJsonArray(Child).Items[I], LocalBase, LocalResource, LocalPointer + '/items/' + IntToStr(I), False);
  end
  else IndexSingle('items');
  IndexSingle('additionalItems');
  IndexSingle('additionalProperties');
  IndexSingle('unevaluatedProperties');
  IndexSingle('propertyNames');
  IndexSingle('contains');
  IndexSingle('unevaluatedItems');
  IndexSingle('not');
  IndexSingle('if');
  IndexSingle('then');
  IndexSingle('else');
  IndexSingle('contentSchema');
end;

function TJsonCodeGenRepository.RegisterSchema(const SchemaJson, SourceUri: string): TJsonCodeGenLocation;
var
  Value: TJsonValue;
begin
  if not TryDomFromText(SchemaJson, Value) then
    raise EJsonCodeGenRepository.Create('Invalid JSON schema text');
  try
    Result := RegisterSchema(Value, SourceUri);
  finally
    Value.Free;
  end;
end;

function TJsonCodeGenRepository.RegisterSchema(Schema: TJsonValue; const SourceUri: string): TJsonCodeGenLocation;
var
  Root: TJsonValue;
  Base: string;
begin
  if Schema = nil then raise EArgumentNilException.Create('Schema');
  Root := Schema.Clone;
  FDocuments.Add(Root);
  Base := SourceUri;
  if Base = '' then Base := SyntheticUri;
  Base := StripFragment(Base);
  FResources.AddOrSetValue(Base, Root);
  IndexValue(Root, Base, Base, '', True);
  if not TryGetLocation(Root, Result) then raise EJsonCodeGenRepository.Create('Could not index schema root');
end;

function TJsonCodeGenRepository.TryGetLocation(Value: TJsonValue; out Location: TJsonCodeGenLocation): Boolean;
begin
  Result := (Value <> nil) and FLocations.TryGetValue(Pointer(Value), Location);
  if not Result then Location := TJsonCodeGenLocation.Empty;
end;

function TJsonCodeGenRepository.ResolvePointer(Root: TJsonValue; const Fragment: string): TJsonValue;
var
  Decoded, Token: string;
  Parts: TArray<string>;
  Current: TJsonValue;
  I, Index: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Fragment = '' then Exit(Root);
  Decoded := TNetEncoding.URL.Decode(Fragment);
  if not Decoded.StartsWith('/') then Exit;
  Parts := Copy(Decoded, 2, MaxInt).Split(['/']);
  Current := Root;
  for I := 0 to High(Parts) do
  begin
    Token := PointerTokenDecode(Parts[I]);
    if Current is TJsonObject then Current := TJsonObject(Current).GetValue(Token)
    else if Current is TJsonArray then
    begin
      if not TryStrToInt(Token, Index) or (Index < 0) or (Index >= TJsonArray(Current).Count) then Exit(nil);
      Current := TJsonArray(Current).Items[Index];
    end
    else Exit(nil);
    if Current = nil then Exit(nil);
  end;
  Result := Current;
end;

function TJsonCodeGenRepository.Resolve(const Reference, CurrentBaseUri: string; out Location: TJsonCodeGenLocation): Boolean;
var
  Absolute, Resource, Fragment: string;
  Root, Value: TJsonValue;
begin
  Location := TJsonCodeGenLocation.Empty;
  Absolute := ResolveUri(CurrentBaseUri, Reference);
  SplitFragment(Absolute, Resource, Fragment);
  Resource := StripFragment(Resource);
  if not FResources.TryGetValue(Resource, Root) then Exit(False);
  if Fragment = '' then Value := Root
  else if Fragment.StartsWith('/') then Value := ResolvePointer(Root, Fragment)
  else if not FAnchors.TryGetValue(Resource + '#' + Fragment, Value) then Exit(False);
  if Value = nil then Exit(False);
  Result := TryGetLocation(Value, Location);
  if Result and (Fragment <> '') then Location.CanonicalUri := Resource + '#' + Fragment;
end;

end.
