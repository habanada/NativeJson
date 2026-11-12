{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Schema.Registry;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Generics.Collections,
  {$ELSE}
  System.SysUtils,
  System.Generics.Collections,
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.Dom.Value,
  NativeJson.Dom.Primitive,
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.JsonArray,
  NativeJson.Schema.Validation;

type
  TJsonSchemaNodeInfo = class
  public
    Schema: TJsonValue;
    SchemaPath: string;
    BaseUri: string;
    ResourceUri: string;
    Dialect: TJsonSchemaDialect;
    RecursiveAnchor: Boolean;
    constructor Create(ASchema: TJsonValue; const ASchemaPath, ABaseUri, AResourceUri: string; ADialect: TJsonSchemaDialect);
  end;

  TJsonSchemaRegistry = class
  private
    FDocuments: TObjectList<TJsonValue>;
    FNodeInfos: TObjectDictionary<TJsonValue, TJsonSchemaNodeInfo>;
    FSchemaOrder: TList<TJsonValue>;
    FResources: TDictionary<string, TJsonValue>;
    FAnchors: TDictionary<string, TJsonValue>;
    FDynamicAnchors: TDictionary<string, TJsonValue>;
    FOptions: TJsonSchemaValidationOptions;
    FRoot: TJsonValue;
    FRootUri: string;
    function GetString(Obj: TJsonObject; const Name: string): string;
    function GetBoolean(Obj: TJsonObject; const Name: string; Default: Boolean = False): Boolean;
    function DetectDialect(Obj: TJsonObject; InheritedDialect: TJsonSchemaDialect): TJsonSchemaDialect;
    function SchemaId(Obj: TJsonObject; Dialect: TJsonSchemaDialect): string;
    procedure AddNodeInfo(Schema: TJsonValue; const Path, BaseUri, ResourceUri: string; Dialect: TJsonSchemaDialect);
    procedure AddResource(const Uri: string; Schema: TJsonValue);
    procedure AddAnchor(const Uri: string; Schema: TJsonValue; Dynamic: Boolean);
    function BelongsToDocument(Value, Document: TJsonValue): Boolean;
    procedure RemoveDocument(Document: TJsonValue);
    procedure IndexSchema(Schema: TJsonValue; const Path, ParentBase, ParentResource: string; InheritedDialect: TJsonSchemaDialect; IsResourceRoot: Boolean);
    procedure IndexDirect(Obj: TJsonObject; const Keyword, Path, BaseUri, ResourceUri: string; Dialect: TJsonSchemaDialect);
    procedure IndexArray(Obj: TJsonObject; const Keyword, Path, BaseUri, ResourceUri: string; Dialect: TJsonSchemaDialect);
    procedure IndexMap(Obj: TJsonObject; const Keyword, Path, BaseUri, ResourceUri: string; Dialect: TJsonSchemaDialect; DependenciesMode: Boolean = False);
    function NavigatePointer(ResourceRoot: TJsonValue; const Fragment: string): TJsonValue;
    function ResolveStatic(const Reference, CurrentBaseUri: string; out TargetUri: string): TJsonValue;
  public
    constructor Create(RootSchema: TJsonValue; Options: TJsonSchemaValidationOptions);
    destructor Destroy; override;
    procedure RegisterSchema(const Uri: string; Schema: TJsonValue);
    procedure UnregisterSchema(const Uri: string);
    function Info(Schema: TJsonValue): TJsonSchemaNodeInfo;
    function Resolve(const Reference: string; CurrentSchema: TJsonValue; out TargetUri: string): TJsonValue;
    function ResolveDynamic(const Reference: string; CurrentSchema: TJsonValue; DynamicScope: TList<string>; out TargetUri: string): TJsonValue;
    function ResolveRecursive(const Reference: string; CurrentSchema: TJsonValue; DynamicScope: TList<string>; out TargetUri: string): TJsonValue;
    function Schemas: TArray<TJsonValue>;
    property Root: TJsonValue read FRoot;
    property RootUri: string read FRootUri;
  end;

function JsonSchemaResolveUri(const BaseUri, Reference: string): string;
function JsonSchemaResourceUri(const Uri: string): string;
function JsonSchemaUriFragment(const Uri: string): string;
function JsonSchemaPercentDecode(const Value: string): string;

implementation

function JsonSchemaPercentDecode(const Value: string): string;
var
  I, N, Count: Integer;
  Bytes: TBytes;
  Builder: TJsonStringBuilder;
begin
  Builder := TJsonStringBuilder.Create;
  try
    I := 1;
    while I <= Length(Value) do
    begin
      if (Value[I] = '%') and (I + 2 <= Length(Value)) and TryStrToInt('$' + Copy(Value, I + 1, 2), N) then
      begin
        SetLength(Bytes, (Length(Value) - I + 1) div 3 + 1);
        Count := 0;
        while (I <= Length(Value)) and (Value[I] = '%') and (I + 2 <= Length(Value)) and TryStrToInt('$' + Copy(Value, I + 1, 2), N) do
        begin
          Bytes[Count] := Byte(N);
          Inc(Count);
          Inc(I, 3);
        end;
        SetLength(Bytes, Count);
        Builder.Append(TEncoding.UTF8.GetString(Bytes));
      end
      else
      begin
        Builder.Append(Value[I]);
        Inc(I);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function JsonSchemaResourceUri(const Uri: string): string;
var
  P: Integer;
begin
  P := Pos('#', Uri);
  if P > 0 then Result := Copy(Uri, 1, P - 1) else Result := Uri;
end;

function JsonSchemaUriFragment(const Uri: string): string;
var
  P: Integer;
begin
  P := Pos('#', Uri);
  if P > 0 then Result := Copy(Uri, P + 1, MaxInt) else Result := '';
end;

function HasScheme(const Uri: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to Length(Uri) do
  begin
    if Uri[I] = ':' then Exit(I > 1);
    if CharInSet(Uri[I], ['/', '?', '#']) then Exit(False);
  end;
end;

function NormalizePath(const Path: string): string;
var
  Parts, Stack: TArray<string>;
  Part: string;
  I, Count: Integer;
  Leading, Trailing: Boolean;
begin
  Leading := Path.StartsWith('/');
  Trailing := (Path <> '') and (Path.EndsWith('/') or Path.EndsWith('/.') or Path.EndsWith('/..') or (Path = '.') or (Path = '..'));
  Parts := Path.Split(['/']);
  SetLength(Stack, Length(Parts));
  Count := 0;
  for Part in Parts do
  begin
    if (Part = '') or (Part = '.') then Continue;
    if Part = '..' then
    begin
      if Count > 0 then Dec(Count);
      Continue;
    end;
    Stack[Count] := Part;
    Inc(Count);
  end;
  Result := '';
  if Leading then Result := '/';
  for I := 0 to Count - 1 do
  begin
    if (Result <> '') and not Result.EndsWith('/') then Result := Result + '/';
    Result := Result + Stack[I];
  end;
  if Trailing and not Result.EndsWith('/') then Result := Result + '/';
  if Leading and (Result = '') then Result := '/';
end;

function JsonSchemaResolveUri(const BaseUri, Reference: string): string;
var
  Base, RefNoFrag, Frag, Scheme, Authority, Path, Query: string;
  P, SchemePos, PathPos, QueryPos, SlashPos: Integer;
begin
  if Reference = '' then Exit(BaseUri);
  if HasScheme(Reference) then Exit(Reference);
  Base := JsonSchemaResourceUri(BaseUri);
  if Reference.StartsWith('#') then Exit(Base + Reference);

  Frag := '';
  P := Pos('#', Reference);
  if P > 0 then
  begin
    Frag := Copy(Reference, P, MaxInt);
    RefNoFrag := Copy(Reference, 1, P - 1);
  end
  else RefNoFrag := Reference;

  SchemePos := Pos('://', Base);
  if RefNoFrag.StartsWith('//') then
  begin
    if SchemePos > 0 then Exit(Copy(Base, 1, SchemePos - 1) + ':' + RefNoFrag + Frag);
    Exit(RefNoFrag + Frag);
  end;

  if SchemePos = 0 then
  begin
    if RefNoFrag = '' then Exit(Base + Frag);
    SlashPos := LastDelimiter('/', Base);
    if RefNoFrag.StartsWith('/') then Result := NormalizePath(RefNoFrag)
    else if SlashPos > 0 then Result := NormalizePath(Copy(Base, 1, SlashPos) + RefNoFrag)
    else Result := RefNoFrag;
    Exit(Result + Frag);
  end;

  Scheme := Copy(Base, 1, SchemePos + 2);
  PathPos := SchemePos + 3;
  P := PathPos;
  while (P <= Length(Base)) and not CharInSet(Base[P], ['/', '?']) do Inc(P);
  Authority := Copy(Base, PathPos, P - PathPos);
  if (P <= Length(Base)) and (Base[P] = '/') then Path := Copy(Base, P, MaxInt) else Path := '/';
  QueryPos := Pos('?', Path);
  if QueryPos > 0 then Path := Copy(Path, 1, QueryPos - 1);

  Query := '';
  QueryPos := Pos('?', RefNoFrag);
  if QueryPos > 0 then
  begin
    Query := Copy(RefNoFrag, QueryPos, MaxInt);
    RefNoFrag := Copy(RefNoFrag, 1, QueryPos - 1);
  end;

  if RefNoFrag = '' then Result := Scheme + Authority + Path + Query + Frag
  else if RefNoFrag.StartsWith('/') then Result := Scheme + Authority + NormalizePath(RefNoFrag) + Query + Frag
  else
  begin
    SlashPos := LastDelimiter('/', Path);
    if SlashPos = 0 then Path := '/' else Path := Copy(Path, 1, SlashPos);
    Result := Scheme + Authority + NormalizePath(Path + RefNoFrag) + Query + Frag;
  end;
end;

constructor TJsonSchemaNodeInfo.Create(ASchema: TJsonValue; const ASchemaPath, ABaseUri, AResourceUri: string; ADialect: TJsonSchemaDialect);
begin
  inherited Create;
  Schema := ASchema;
  SchemaPath := ASchemaPath;
  BaseUri := ABaseUri;
  ResourceUri := AResourceUri;
  Dialect := ADialect;
  RecursiveAnchor := False;
end;

constructor TJsonSchemaRegistry.Create(RootSchema: TJsonValue; Options: TJsonSchemaValidationOptions);
var
  InitialUri: string;
begin
  inherited Create;
  if RootSchema = nil then raise EArgumentNilException.Create('RootSchema');
  if Options = nil then raise EArgumentNilException.Create('Options');
  FOptions := Options;
  FDocuments := TObjectList<TJsonValue>.Create(True);
  FNodeInfos := TObjectDictionary<TJsonValue, TJsonSchemaNodeInfo>.Create([doOwnsValues]);
  FSchemaOrder := TList<TJsonValue>.Create;
  FResources := TDictionary<string, TJsonValue>.Create;
  FAnchors := TDictionary<string, TJsonValue>.Create;
  FDynamicAnchors := TDictionary<string, TJsonValue>.Create;
  FRoot := RootSchema.Clone;
  FDocuments.Add(FRoot);
  InitialUri := FOptions.BaseUri;
  if InitialUri = '' then InitialUri := 'nativejson://schema/root';
  InitialUri := JsonSchemaResourceUri(InitialUri);
  IndexSchema(FRoot, '#', InitialUri, InitialUri, FOptions.Dialect, True);
  FRootUri := Info(FRoot).ResourceUri;
end;

destructor TJsonSchemaRegistry.Destroy;
begin
  FDynamicAnchors.Free;
  FAnchors.Free;
  FResources.Free;
  FSchemaOrder.Free;
  FNodeInfos.Free;
  FDocuments.Free;
  inherited;
end;

function TJsonSchemaRegistry.GetString(Obj: TJsonObject; const Name: string): string;
var
  V: TJsonValue;
begin
  Result := '';
  if Obj.TryGetValue(Name, V) and (V is TJsonString) then Result := V.AsString;
end;

function TJsonSchemaRegistry.GetBoolean(Obj: TJsonObject; const Name: string; Default: Boolean): Boolean;
var
  V: TJsonValue;
begin
  Result := Default;
  if Obj.TryGetValue(Name, V) and (V is TJsonBoolean) then Result := V.AsBoolean;
end;

function TJsonSchemaRegistry.DetectDialect(Obj: TJsonObject; InheritedDialect: TJsonSchemaDialect): TJsonSchemaDialect;
var
  Uri: string;
begin
  if FOptions.Dialect <> TJsonSchemaDialect.Auto then Exit(FOptions.Dialect);
  Uri := LowerCase(GetString(Obj, '$schema'));
  if Uri.EndsWith('#') then Delete(Uri, Length(Uri), 1);
  if (Uri = 'http://json-schema.org/draft-07/schema') or (Uri = 'https://json-schema.org/draft-07/schema') then Exit(TJsonSchemaDialect.Draft07);
  if (Uri = 'http://json-schema.org/draft/2019-09/schema') or (Uri = 'https://json-schema.org/draft/2019-09/schema') then Exit(TJsonSchemaDialect.Draft2019_09);
  if (Uri = 'http://json-schema.org/draft/2020-12/schema') or (Uri = 'https://json-schema.org/draft/2020-12/schema') then Exit(TJsonSchemaDialect.Draft2020_12);
  if Uri <> '' then raise EJsonSchemaException.Create('#/$schema', '$schema', 'Unsupported JSON Schema dialect: ' + Uri);
  if InheritedDialect <> TJsonSchemaDialect.Auto then Exit(InheritedDialect);
  Result := TJsonSchemaDialect.Draft2020_12;
end;

function TJsonSchemaRegistry.SchemaId(Obj: TJsonObject; Dialect: TJsonSchemaDialect): string;
begin
  Result := GetString(Obj, '$id');
end;

procedure TJsonSchemaRegistry.AddNodeInfo(Schema: TJsonValue; const Path, BaseUri, ResourceUri: string; Dialect: TJsonSchemaDialect);
begin
  if FNodeInfos.ContainsKey(Schema) then Exit;
  FNodeInfos.Add(Schema, TJsonSchemaNodeInfo.Create(Schema, Path, BaseUri, ResourceUri, Dialect));
  FSchemaOrder.Add(Schema);
end;

procedure TJsonSchemaRegistry.AddResource(const Uri: string; Schema: TJsonValue);
var
  Key: string;
begin
  Key := JsonSchemaResourceUri(Uri);
  if Key = '' then Exit;
  if FResources.ContainsKey(Key) and (FResources[Key] <> Schema) then raise EJsonSchemaException.Create(Info(Schema).SchemaPath, '$id', 'Duplicate schema resource URI: ' + Key);
  FResources.AddOrSetValue(Key, Schema);
end;

procedure TJsonSchemaRegistry.AddAnchor(const Uri: string; Schema: TJsonValue; Dynamic: Boolean);
var
  Key: string;
begin
  Key := Uri;
  if Dynamic then
  begin
    if FDynamicAnchors.ContainsKey(Key) and (FDynamicAnchors[Key] <> Schema) then raise EJsonSchemaException.Create(Info(Schema).SchemaPath, '$dynamicAnchor', 'Duplicate dynamic anchor: ' + Key);
    FDynamicAnchors.AddOrSetValue(Key, Schema);
  end;
  if FAnchors.ContainsKey(Key) and (FAnchors[Key] <> Schema) then raise EJsonSchemaException.Create(Info(Schema).SchemaPath, '$anchor', 'Duplicate anchor: ' + Key);
  FAnchors.AddOrSetValue(Key, Schema);
end;

function TJsonSchemaRegistry.BelongsToDocument(Value, Document: TJsonValue): Boolean;
begin
  while Value <> nil do
  begin
    if Value = Document then Exit(True);
    Value := Value.Parent;
  end;
  Result := False;
end;

procedure TJsonSchemaRegistry.RemoveDocument(Document: TJsonValue);
var
  ResourcePair, AnchorPair: TPair<string, TJsonValue>;
  NodePair: TPair<TJsonValue, TJsonSchemaNodeInfo>;
begin
  if (Document = nil) or (Document = FRoot) then Exit;
  for AnchorPair in FDynamicAnchors.ToArray do if BelongsToDocument(AnchorPair.Value, Document) then FDynamicAnchors.Remove(AnchorPair.Key);
  for AnchorPair in FAnchors.ToArray do if BelongsToDocument(AnchorPair.Value, Document) then FAnchors.Remove(AnchorPair.Key);
  for ResourcePair in FResources.ToArray do if BelongsToDocument(ResourcePair.Value, Document) then FResources.Remove(ResourcePair.Key);
  for NodePair in FNodeInfos.ToArray do
    if BelongsToDocument(NodePair.Key, Document) then
    begin
      FSchemaOrder.Remove(NodePair.Key);
      FNodeInfos.Remove(NodePair.Key);
    end;
  FDocuments.Remove(Document);
end;

procedure TJsonSchemaRegistry.IndexDirect(Obj: TJsonObject; const Keyword, Path, BaseUri, ResourceUri: string; Dialect: TJsonSchemaDialect);
var
  V: TJsonValue;
begin
  if Obj.TryGetValue(Keyword, V) and ((V is TJsonObject) or (V is TJsonBoolean)) then IndexSchema(V, Path + '/' + JsonPointerEscape(Keyword), BaseUri, ResourceUri, Dialect, False);
end;

procedure TJsonSchemaRegistry.IndexArray(Obj: TJsonObject; const Keyword, Path, BaseUri, ResourceUri: string; Dialect: TJsonSchemaDialect);
var
  V: TJsonValue;
  Arr: TJsonArray;
  I: Integer;
begin
  if not Obj.TryGetValue(Keyword, V) or not (V is TJsonArray) then Exit;
  Arr := TJsonArray(V);
  for I := 0 to Arr.Count - 1 do if (Arr[I] is TJsonObject) or (Arr[I] is TJsonBoolean) then IndexSchema(Arr[I], Path + '/' + JsonPointerEscape(Keyword) + '/' + IntToStr(I), BaseUri, ResourceUri, Dialect, False);
end;

procedure TJsonSchemaRegistry.IndexMap(Obj: TJsonObject; const Keyword, Path, BaseUri, ResourceUri: string; Dialect: TJsonSchemaDialect; DependenciesMode: Boolean);
var
  V: TJsonValue;
  Map: TJsonObject;
  Pair: TPair<string, TJsonValue>;
begin
  if not Obj.TryGetValue(Keyword, V) or not (V is TJsonObject) then Exit;
  Map := TJsonObject(V);
  for Pair in Map do
    if (not DependenciesMode or not (Pair.Value is TJsonArray)) and ((Pair.Value is TJsonObject) or (Pair.Value is TJsonBoolean)) then IndexSchema(Pair.Value, Path + '/' + JsonPointerEscape(Keyword) + '/' + JsonPointerEscape(Pair.Key), BaseUri, ResourceUri, Dialect, False);
end;

procedure TJsonSchemaRegistry.IndexSchema(Schema: TJsonValue; const Path, ParentBase, ParentResource: string; InheritedDialect: TJsonSchemaDialect; IsResourceRoot: Boolean);
var
  Obj: TJsonObject;
  Dialect: TJsonSchemaDialect;
  BaseUri, ResourceUri, IdValue, Anchor, DynamicAnchor, FullId, Fragment: string;
  InfoValue: TJsonSchemaNodeInfo;
  Items: TJsonValue;
begin
  if Schema = nil then Exit;
  Dialect := InheritedDialect;
  if Dialect = TJsonSchemaDialect.Auto then Dialect := TJsonSchemaDialect.Draft2020_12;
  BaseUri := ParentBase;
  ResourceUri := ParentResource;
  Obj := nil;
  if Schema is TJsonObject then
  begin
    Obj := TJsonObject(Schema);
    Dialect := DetectDialect(Obj, InheritedDialect);
    IdValue := SchemaId(Obj, Dialect);
    if IdValue <> '' then
    begin
      FullId := JsonSchemaResolveUri(ParentBase, IdValue);
      Fragment := JsonSchemaUriFragment(FullId);
      BaseUri := JsonSchemaResourceUri(FullId);
      if Fragment = '' then
      begin
        ResourceUri := BaseUri;
        IsResourceRoot := True;
      end;
    end;
  end;

  AddNodeInfo(Schema, Path, BaseUri, ResourceUri, Dialect);
  InfoValue := Info(Schema);
  if IsResourceRoot then AddResource(ResourceUri, Schema);
  if Obj = nil then Exit;

  IdValue := SchemaId(Obj, Dialect);
  if (Dialect = TJsonSchemaDialect.Draft07) and (IdValue <> '') then
  begin
    FullId := JsonSchemaResolveUri(ParentBase, IdValue);
    Fragment := JsonSchemaUriFragment(FullId);
    if Fragment <> '' then AddAnchor(JsonSchemaResourceUri(FullId) + '#' + JsonSchemaPercentDecode(Fragment), Schema, False);
  end;

  if Dialect <> TJsonSchemaDialect.Draft07 then
  begin
    Anchor := GetString(Obj, '$anchor');
    if Anchor <> '' then AddAnchor(ResourceUri + '#' + Anchor, Schema, False);
  end;
  if Dialect = TJsonSchemaDialect.Draft2020_12 then
  begin
    DynamicAnchor := GetString(Obj, '$dynamicAnchor');
    if DynamicAnchor <> '' then AddAnchor(ResourceUri + '#' + DynamicAnchor, Schema, True);
  end;
  if Dialect = TJsonSchemaDialect.Draft2019_09 then InfoValue.RecursiveAnchor := GetBoolean(Obj, '$recursiveAnchor', False);

  IndexDirect(Obj, 'additionalProperties', Path, BaseUri, ResourceUri, Dialect);
  IndexDirect(Obj, 'propertyNames', Path, BaseUri, ResourceUri, Dialect);
  IndexDirect(Obj, 'contains', Path, BaseUri, ResourceUri, Dialect);
  IndexDirect(Obj, 'not', Path, BaseUri, ResourceUri, Dialect);
  IndexDirect(Obj, 'if', Path, BaseUri, ResourceUri, Dialect);
  IndexDirect(Obj, 'then', Path, BaseUri, ResourceUri, Dialect);
  IndexDirect(Obj, 'else', Path, BaseUri, ResourceUri, Dialect);
  if Dialect <> TJsonSchemaDialect.Draft07 then IndexDirect(Obj, 'contentSchema', Path, BaseUri, ResourceUri, Dialect);
  IndexArray(Obj, 'allOf', Path, BaseUri, ResourceUri, Dialect);
  IndexArray(Obj, 'anyOf', Path, BaseUri, ResourceUri, Dialect);
  IndexArray(Obj, 'oneOf', Path, BaseUri, ResourceUri, Dialect);
  IndexMap(Obj, 'properties', Path, BaseUri, ResourceUri, Dialect);
  IndexMap(Obj, 'patternProperties', Path, BaseUri, ResourceUri, Dialect);
  if Dialect = TJsonSchemaDialect.Draft2020_12 then
  begin
    IndexMap(Obj, '$defs', Path, BaseUri, ResourceUri, Dialect);
    IndexMap(Obj, 'definitions', Path, BaseUri, ResourceUri, Dialect);
    IndexDirect(Obj, 'items', Path, BaseUri, ResourceUri, Dialect);
    IndexArray(Obj, 'prefixItems', Path, BaseUri, ResourceUri, Dialect);
    IndexDirect(Obj, 'unevaluatedProperties', Path, BaseUri, ResourceUri, Dialect);
    IndexDirect(Obj, 'unevaluatedItems', Path, BaseUri, ResourceUri, Dialect);
    IndexMap(Obj, 'dependentSchemas', Path, BaseUri, ResourceUri, Dialect);
  end
  else if Dialect = TJsonSchemaDialect.Draft2019_09 then
  begin
    IndexMap(Obj, '$defs', Path, BaseUri, ResourceUri, Dialect);
    IndexMap(Obj, 'definitions', Path, BaseUri, ResourceUri, Dialect);
    if Obj.TryGetValue('items', Items) then
      if Items is TJsonArray then IndexArray(Obj, 'items', Path, BaseUri, ResourceUri, Dialect) else IndexDirect(Obj, 'items', Path, BaseUri, ResourceUri, Dialect);
    IndexDirect(Obj, 'additionalItems', Path, BaseUri, ResourceUri, Dialect);
    IndexDirect(Obj, 'unevaluatedProperties', Path, BaseUri, ResourceUri, Dialect);
    IndexDirect(Obj, 'unevaluatedItems', Path, BaseUri, ResourceUri, Dialect);
    IndexMap(Obj, 'dependentSchemas', Path, BaseUri, ResourceUri, Dialect);
  end
  else
  begin
    IndexMap(Obj, 'definitions', Path, BaseUri, ResourceUri, Dialect);
    if Obj.TryGetValue('items', Items) then
      if Items is TJsonArray then IndexArray(Obj, 'items', Path, BaseUri, ResourceUri, Dialect) else IndexDirect(Obj, 'items', Path, BaseUri, ResourceUri, Dialect);
    IndexDirect(Obj, 'additionalItems', Path, BaseUri, ResourceUri, Dialect);
    IndexMap(Obj, 'dependencies', Path, BaseUri, ResourceUri, Dialect, True);
  end;
end;

procedure TJsonSchemaRegistry.RegisterSchema(const Uri: string; Schema: TJsonValue);
var
  CopySchema: TJsonValue;
  Base: string;
begin
  if Schema = nil then raise EArgumentNilException.Create('Schema');
  if Uri = '' then raise EArgumentException.Create('Uri');
  Base := JsonSchemaResourceUri(Uri);
  if Base = '' then raise EArgumentException.Create('Uri');
  if FResources.ContainsKey(Base) then raise EJsonSchemaException.Create('#', '$id', 'Duplicate schema resource URI: ' + Base);
  CopySchema := Schema.Clone;
  FDocuments.Add(CopySchema);
  try
    IndexSchema(CopySchema, '#', Base, Base, FOptions.Dialect, True);
    if FResources.ContainsKey(Base) and (FResources[Base] <> CopySchema) then raise EJsonSchemaException.Create('#', '$id', 'Duplicate schema resource URI: ' + Base);
    FResources.AddOrSetValue(Base, CopySchema);
  except
    RemoveDocument(CopySchema);
    raise;
  end;
end;

procedure TJsonSchemaRegistry.UnregisterSchema(const Uri: string);
var
  Base: string;
  Document: TJsonValue;
begin
  Base := JsonSchemaResourceUri(Uri);
  if not FResources.TryGetValue(Base, Document) then Exit;
  while (Document.Parent <> nil) do Document := Document.Parent;
  RemoveDocument(Document);
end;

function TJsonSchemaRegistry.Info(Schema: TJsonValue): TJsonSchemaNodeInfo;
begin
  if (Schema = nil) or not FNodeInfos.TryGetValue(Schema, Result) then raise EJsonSchemaException.Create('#', '', 'Schema node is not registered');
end;

function TJsonSchemaRegistry.NavigatePointer(ResourceRoot: TJsonValue; const Fragment: string): TJsonValue;
var
  Segments: TArray<string>;
  Segment, Decoded, RawSegment: string;
  Current, Next: TJsonValue;
  Index: Integer;
begin
  Current := ResourceRoot;
  if Fragment = '' then Exit(Current);
  Decoded := JsonSchemaPercentDecode(Fragment);
  if not Decoded.StartsWith('/') then Exit(nil);
  Segments := Copy(Decoded, 2, MaxInt).Split(['/']);
  for RawSegment in Segments do
  begin
    Segment := JsonPointerUnescape(RawSegment);
    if Current is TJsonObject then
    begin
      if not TJsonObject(Current).TryGetValue(Segment, Next) then Exit(nil);
      Current := Next;
    end
    else if Current is TJsonArray then
    begin
      if (Segment = '') or ((Length(Segment) > 1) and (Segment[1] = '0')) or not TryStrToInt(Segment, Index) or (Index < 0) or (Index >= TJsonArray(Current).Count) then Exit(nil);
      Current := TJsonArray(Current)[Index];
    end
    else Exit(nil);
  end;
  Result := Current;
end;

function TJsonSchemaRegistry.ResolveStatic(const Reference, CurrentBaseUri: string; out TargetUri: string): TJsonValue;
var
  Absolute, ResourceUri, Fragment, DecodedFragment, AnchorKey: string;
  ResourceRoot: TJsonValue;
begin
  Absolute := JsonSchemaResolveUri(CurrentBaseUri, Reference);
  ResourceUri := JsonSchemaResourceUri(Absolute);
  Fragment := JsonSchemaUriFragment(Absolute);
  TargetUri := Absolute;
  if not FResources.TryGetValue(ResourceUri, ResourceRoot) then raise EJsonSchemaException.Create('#', '$ref', 'Schema resource is not registered: ' + ResourceUri);
  if Fragment = '' then Exit(ResourceRoot);
  DecodedFragment := JsonSchemaPercentDecode(Fragment);
  if DecodedFragment.StartsWith('/') then Result := NavigatePointer(ResourceRoot, Fragment)
  else
  begin
    AnchorKey := ResourceUri + '#' + DecodedFragment;
    if not FAnchors.TryGetValue(AnchorKey, Result) then Result := nil;
  end;
  if Result = nil then raise EJsonSchemaException.Create('#', '$ref', 'Schema reference was not found: ' + Absolute);
  if not FNodeInfos.ContainsKey(Result) then raise EJsonSchemaException.Create('#', '$ref', 'Reference target is not a schema: ' + Absolute);
end;

function TJsonSchemaRegistry.Resolve(const Reference: string; CurrentSchema: TJsonValue; out TargetUri: string): TJsonValue;
begin
  Result := ResolveStatic(Reference, Info(CurrentSchema).BaseUri, TargetUri);
end;

function TJsonSchemaRegistry.ResolveDynamic(const Reference: string; CurrentSchema: TJsonValue; DynamicScope: TList<string>; out TargetUri: string): TJsonValue;
var
  StaticTarget: TJsonValue;
  StaticUri, Fragment, Key: string;
  I: Integer;
begin
  StaticTarget := ResolveStatic(Reference, Info(CurrentSchema).BaseUri, StaticUri);
  Fragment := JsonSchemaUriFragment(StaticUri);
  if (Fragment = '') or Fragment.StartsWith('/') or not FDynamicAnchors.ContainsKey(JsonSchemaResourceUri(StaticUri) + '#' + JsonSchemaPercentDecode(Fragment)) then
  begin
    TargetUri := StaticUri;
    Exit(StaticTarget);
  end;
  Fragment := JsonSchemaPercentDecode(Fragment);
  for I := 0 to DynamicScope.Count - 1 do
  begin
    Key := DynamicScope[I] + '#' + Fragment;
    if FDynamicAnchors.TryGetValue(Key, Result) then
    begin
      TargetUri := Key;
      Exit;
    end;
  end;
  TargetUri := StaticUri;
  Result := StaticTarget;
end;

function TJsonSchemaRegistry.ResolveRecursive(const Reference: string; CurrentSchema: TJsonValue; DynamicScope: TList<string>; out TargetUri: string): TJsonValue;
var
  StaticTarget, Candidate: TJsonValue;
  StaticUri: string;
  I: Integer;
begin
  StaticTarget := ResolveStatic(Reference, Info(CurrentSchema).BaseUri, StaticUri);
  if (Reference <> '#') or not Info(StaticTarget).RecursiveAnchor then
  begin
    TargetUri := StaticUri;
    Exit(StaticTarget);
  end;
  for I := 0 to DynamicScope.Count - 1 do
    if FResources.TryGetValue(DynamicScope[I], Candidate) and Info(Candidate).RecursiveAnchor then
    begin
      TargetUri := DynamicScope[I] + '#';
      Exit(Candidate);
    end;
  TargetUri := StaticUri;
  Result := StaticTarget;
end;

function TJsonSchemaRegistry.Schemas: TArray<TJsonValue>;
begin
  Result := FSchemaOrder.ToArray;
end;

end.
