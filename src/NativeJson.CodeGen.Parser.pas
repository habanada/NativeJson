{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.CodeGen.Parser;

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
  {$ELSE}
  System.Generics.Collections,
  {$ENDIF}
  NativeJson.CodeGen.Options,
  NativeJson.CodeGen.Model,
  NativeJson.CodeGen.Repository,
  NativeJson.CodeGen.Names;

type
  TJsonSchemaCodeGenParser = class
  private
    FRepository: TJsonCodeGenRepository;
    FOptions: TJsonCodeGenOptions;
    FModel: TJsonCodeGenModel;
    FNodeMap: TDictionary<string, TJsonCodeGenNode>;
    FIntersectionPairs: TDictionary<string, TJsonCodeGenNode>;
    FNames: TJsonCodeGenNameAllocator;
    FSyntheticId: Integer;
    function ParseNode(Schema: TJsonValue; const Hint, Path: string; ForceDeclaration, FromDefinition: Boolean): TJsonCodeGenNode;
    procedure ParseObjectNode(Node: TJsonCodeGenNode; Obj: TJsonObject; const Path: string);
    procedure ParseArrayNode(Node: TJsonCodeGenNode; Obj: TJsonObject; const Path: string);
    procedure ParseDefinitions(Obj: TJsonObject; const Path: string);
    procedure ParseAnnotations(Node: TJsonCodeGenNode; Obj: TJsonObject);
    procedure ParseConstraints(Node: TJsonCodeGenNode; Obj: TJsonObject);
    procedure ParseTypeKeyword(Node: TJsonCodeGenNode; Obj: TJsonObject);
    procedure ParseEnumAndConst(Node: TJsonCodeGenNode; Obj: TJsonObject);
    procedure ReportRuntimeOnlyKeywords(Obj: TJsonObject; const Path: string);
    procedure ParseCompositions(Node: TJsonCodeGenNode; Obj: TJsonObject; const Path: string);
    procedure ParseReference(Node: TJsonCodeGenNode; Obj: TJsonObject; const Hint, Path: string; out StopParsing: Boolean);
    procedure MergeAllOf(Node, Source: TJsonCodeGenNode; const Path: string);
    procedure MergeObjectUnion(Node: TJsonCodeGenNode; const Alternatives: TArray<TJsonCodeGenNode>; const Path: string);
    function CommonNode(Left, Right: TJsonCodeGenNode; const Hint, Path: string): TJsonCodeGenNode;
    function IntersectionNode(Left, Right: TJsonCodeGenNode; const Hint, Path: string): TJsonCodeGenNode;
    function NewSyntheticNode(const Hint, Path: string): TJsonCodeGenNode;
    function EffectiveNode(Node: TJsonCodeGenNode): TJsonCodeGenNode;
    procedure InferKind(Node: TJsonCodeGenNode);
    procedure AssignNames;
    procedure DetectRecursion;
    procedure DetectRecursionFrom(Node: TJsonCodeGenNode; Visiting, Visited: TDictionary<TJsonCodeGenNode, Boolean>; Stack: TList<TJsonCodeGenNode>);
    procedure AddDependencies(Node: TJsonCodeGenNode; List: TList<TJsonCodeGenNode>);
    function DetectVersion(Root: TJsonValue): TJsonCodeGenSchemaVersion;
    function ParseOpenApi(Root: TJsonObject; const Path: string): Boolean;
    function HasStructuralRefSibling(Obj: TJsonObject): Boolean;
    function ReferenceHint(const Ref: string; const Fallback: string): string;
    function NeedsDeclaration(Node: TJsonCodeGenNode): Boolean;
    function PrimitiveOf(Value: TJsonValue): TJsonCodeGenPrimitive;
    procedure AddPrimitiveFromTypeName(Node: TJsonCodeGenNode; const TypeName, Path: string);
    procedure AddDiagnostic(Severity: TJsonCodeGenDiagnosticSeverity; const Code, Path, Msg: string);
    class function GetString(Obj: TJsonObject; const Name: string; out Value: string): Boolean; static;
    class function GetBoolean(Obj: TJsonObject; const Name: string; out Value: Boolean): Boolean; static;
    class function GetInteger(Obj: TJsonObject; const Name: string; out Value: Integer): Boolean; static;
    class function GetNumberRaw(Obj: TJsonObject; const Name: string; out Value: string): Boolean; static;
    class function IsSchemaValue(Value: TJsonValue): Boolean; static;
  public
    constructor Create(Repository: TJsonCodeGenRepository; const Options: TJsonCodeGenOptions);
    destructor Destroy; override;
    function Parse(const Root: TJsonCodeGenLocation; const OriginalSchema: string): TJsonCodeGenModel;
  end;

implementation

uses
  {$IFDEF FPC}
  StrUtils,
  Math;
  {$ELSE}
  System.StrUtils,
  System.Math;
  {$ENDIF}

constructor TJsonSchemaCodeGenParser.Create(Repository: TJsonCodeGenRepository; const Options: TJsonCodeGenOptions);
begin
  inherited Create;
  if Repository = nil then raise EArgumentNilException.Create('Repository');
  FRepository := Repository;
  FOptions := Options;
  FNodeMap := TDictionary<string, TJsonCodeGenNode>.Create;
  FIntersectionPairs := TDictionary<string, TJsonCodeGenNode>.Create;
  FNames := TJsonCodeGenNameAllocator.Create;
end;

destructor TJsonSchemaCodeGenParser.Destroy;
begin
  FNames.Free;
  FIntersectionPairs.Free;
  FNodeMap.Free;
  inherited;
end;

procedure TJsonSchemaCodeGenParser.AddDiagnostic(Severity: TJsonCodeGenDiagnosticSeverity; const Code, Path, Msg: string);
begin
  FModel.AddDiagnostic(Severity, Code, Path, Msg);
end;

class function TJsonSchemaCodeGenParser.GetString(Obj: TJsonObject; const Name: string; out Value: string): Boolean;
var
  V: TJsonValue;
begin
  V := Obj.GetValue(Name);
  Result := V is TJsonString;
  if Result then Value := V.AsString else Value := '';
end;

class function TJsonSchemaCodeGenParser.GetBoolean(Obj: TJsonObject; const Name: string; out Value: Boolean): Boolean;
var
  V: TJsonValue;
begin
  V := Obj.GetValue(Name);
  Result := V is TJsonBoolean;
  if Result then Value := V.AsBoolean else Value := False;
end;

class function TJsonSchemaCodeGenParser.GetInteger(Obj: TJsonObject; const Name: string; out Value: Integer): Boolean;
var
  V: TJsonValue;
begin
  V := Obj.GetValue(Name);
  // Via the raw text: AsInteger rounds silently (2.7 would become 3) and
  // truncates an Int64 to Integer. Both would be wrong here -
  // minLength and maxItems must be whole numbers in the Integer range.
  Value := 0;
  Result := (V is TJsonNumber) and TryStrToInt(V.AsRawText, Value);
end;

class function TJsonSchemaCodeGenParser.GetNumberRaw(Obj: TJsonObject; const Name: string; out Value: string): Boolean;
var
  V: TJsonValue;
begin
  V := Obj.GetValue(Name);
  Result := V is TJsonNumber;
  if Result then Value := V.AsRawText else Value := '';
end;

class function TJsonSchemaCodeGenParser.IsSchemaValue(Value: TJsonValue): Boolean;
begin
  Result := (Value is TJsonObject) or (Value is TJsonBoolean);
end;

function TJsonSchemaCodeGenParser.PrimitiveOf(Value: TJsonValue): TJsonCodeGenPrimitive;
var
  S: string;
begin
  if Value is TJsonNull then Exit(TJsonCodeGenPrimitive.NullPrimitive);
  if Value is TJsonBoolean then Exit(TJsonCodeGenPrimitive.BooleanPrimitive);
  if Value is TJsonNumber then
  begin
    S := Value.ToJSON;
    if (Pos('.', S) = 0) and (Pos('e', LowerCase(S)) = 0) then Exit(TJsonCodeGenPrimitive.IntegerPrimitive);
    Exit(TJsonCodeGenPrimitive.NumberPrimitive);
  end;
  if Value is TJsonString then Exit(TJsonCodeGenPrimitive.StringPrimitive);
  if Value is TJsonObject then Exit(TJsonCodeGenPrimitive.ObjectPrimitive);
  if Value is TJsonArray then Exit(TJsonCodeGenPrimitive.ArrayPrimitive);
  Result := TJsonCodeGenPrimitive.StringPrimitive;
end;

procedure TJsonSchemaCodeGenParser.AddPrimitiveFromTypeName(Node: TJsonCodeGenNode; const TypeName, Path: string);
begin
  if SameText(TypeName, 'null') then Include(Node.Primitives, TJsonCodeGenPrimitive.NullPrimitive)
  else if SameText(TypeName, 'boolean') then Include(Node.Primitives, TJsonCodeGenPrimitive.BooleanPrimitive)
  else if SameText(TypeName, 'integer') then Include(Node.Primitives, TJsonCodeGenPrimitive.IntegerPrimitive)
  else if SameText(TypeName, 'number') then Include(Node.Primitives, TJsonCodeGenPrimitive.NumberPrimitive)
  else if SameText(TypeName, 'string') then Include(Node.Primitives, TJsonCodeGenPrimitive.StringPrimitive)
  else if SameText(TypeName, 'object') then Include(Node.Primitives, TJsonCodeGenPrimitive.ObjectPrimitive)
  else if SameText(TypeName, 'array') then Include(Node.Primitives, TJsonCodeGenPrimitive.ArrayPrimitive)
  else AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Warning, 'CG001', Path, 'Unknown schema type "' + TypeName + '"');
end;

function TJsonSchemaCodeGenParser.DetectVersion(Root: TJsonValue): TJsonCodeGenSchemaVersion;
var
  Obj: TJsonObject;
  S: string;
begin
  Result := TJsonCodeGenSchemaVersion.Unknown;
  if not (Root is TJsonObject) then Exit;
  Obj := TJsonObject(Root);
  if FOptions.DetectOpenApi and GetString(Obj, 'openapi', S) then
  begin
    if S.StartsWith('3.0') then Exit(TJsonCodeGenSchemaVersion.OpenApi30);
    if S.StartsWith('3.1') then Exit(TJsonCodeGenSchemaVersion.OpenApi31);
  end;
  if not GetString(Obj, '$schema', S) then Exit;
  S := LowerCase(S);
  if Pos('draft-07', S) > 0 then Result := TJsonCodeGenSchemaVersion.Draft07
  else if Pos('2019-09', S) > 0 then Result := TJsonCodeGenSchemaVersion.Draft2019_09
  else if Pos('2020-12', S) > 0 then Result := TJsonCodeGenSchemaVersion.Draft2020_12;
end;

function TJsonSchemaCodeGenParser.ReferenceHint(const Ref, Fallback: string): string;
var
  S, Extension: string;
  P: Integer;
begin
  S := Ref;
  P := LastDelimiter('/#', S);
  if P > 0 then S := Copy(S, P + 1, MaxInt);
  S := StringReplace(StringReplace(S, '~1', '/', [rfReplaceAll]), '~0', '~', [rfReplaceAll]);
  if Pos('#', Ref) = 0 then
    for Extension in ['.schema.json', '.json', '.yaml', '.yml'] do
      if (Length(S) > Length(Extension)) and SameText(Copy(S, Length(S) - Length(Extension) + 1, MaxInt), Extension) then
      begin
        S := Copy(S, 1, Length(S) - Length(Extension));
        Break;
      end;
  if S = '' then Result := Fallback else Result := S;
end;

function TJsonSchemaCodeGenParser.HasStructuralRefSibling(Obj: TJsonObject): Boolean;
var
  P: TPair<string, TJsonValue>;
  N: string;
begin
  for P in Obj do
  begin
    N := P.Key;
    if (N = '$ref') or (N = '$dynamicRef') or (N = '$recursiveRef') or (N = '$id') or (N = 'id') or (N = '$schema') or (N = '$comment') or (N = 'title') or (N = 'description') or (N = 'default') or (N = 'examples') or (N = 'readOnly') or (N = 'writeOnly') or (N = 'deprecated') then Continue;
    Exit(True);
  end;
  Result := False;
end;

function TJsonSchemaCodeGenParser.EffectiveNode(Node: TJsonCodeGenNode): TJsonCodeGenNode;
var
  Seen: TDictionary<TJsonCodeGenNode, Boolean>;
begin
  Result := Node;
  Seen := TDictionary<TJsonCodeGenNode, Boolean>.Create;
  try
    while (Result <> nil) and Result.IsPureReference and (Result.RefTarget <> nil) and not Seen.ContainsKey(Result) do
    begin
      Seen.Add(Result, True);
      Result := Result.RefTarget;
    end;
  finally
    Seen.Free;
  end;
end;

function TJsonSchemaCodeGenParser.NewSyntheticNode(const Hint, Path: string): TJsonCodeGenNode;
begin
  Inc(FSyntheticId);
  Result := TJsonCodeGenNode.Create('synthetic:' + IntToStr(FSyntheticId), Path, '', Hint);
  FModel.Nodes.Add(Result);
end;

function TJsonSchemaCodeGenParser.CommonNode(Left, Right: TJsonCodeGenNode; const Hint, Path: string): TJsonCodeGenNode;
var
  L, R: TJsonCodeGenNode;
  LTypes, RTypes: TJsonCodeGenPrimitives;
begin
  if Left = nil then Exit(Right);
  if Right = nil then Exit(Left);
  L := EffectiveNode(Left);
  R := EffectiveNode(Right);
  if L = R then Exit(Left);
  LTypes := L.NonNullPrimitives;
  RTypes := R.NonNullPrimitives;
  if (LTypes = [TJsonCodeGenPrimitive.IntegerPrimitive]) and (RTypes = [TJsonCodeGenPrimitive.NumberPrimitive]) then Exit(Right);
  if (RTypes = [TJsonCodeGenPrimitive.IntegerPrimitive]) and (LTypes = [TJsonCodeGenPrimitive.NumberPrimitive]) then Exit(Left);
  Result := NewSyntheticNode(Hint, Path);
  Result.Kind := TJsonCodeGenNodeKind.UnionValue;
  Result.Primitives := L.Primitives + R.Primitives;
  Result.UnionAlternatives.Add(Left);
  Result.UnionAlternatives.Add(Right);
end;

function TJsonSchemaCodeGenParser.IntersectionNode(Left, Right: TJsonCodeGenNode; const Hint, Path: string): TJsonCodeGenNode;
var
  L, R: TJsonCodeGenNode;
  Types: TJsonCodeGenPrimitives;
  PairKey: string;
begin
  if Left = nil then Exit(Right);
  if Right = nil then Exit(Left);
  L := EffectiveNode(Left);
  R := EffectiveNode(Right);
  if L = R then Exit(Left);
  PairKey := L.Key + #1 + R.Key;
  if FIntersectionPairs.TryGetValue(PairKey, Result) then Exit;
  Types := L.Primitives * R.Primitives;
  if (TJsonCodeGenPrimitive.IntegerPrimitive in L.Primitives) and (TJsonCodeGenPrimitive.NumberPrimitive in R.Primitives) then Include(Types, TJsonCodeGenPrimitive.IntegerPrimitive);
  if (TJsonCodeGenPrimitive.NumberPrimitive in L.Primitives) and (TJsonCodeGenPrimitive.IntegerPrimitive in R.Primitives) then Include(Types, TJsonCodeGenPrimitive.IntegerPrimitive);
  if Types = [] then
  begin
    Result := NewSyntheticNode(Hint, Path);
    Result.AlwaysFalse := True;
    FIntersectionPairs.Add(PairKey, Result);
    FIntersectionPairs.AddOrSetValue(R.Key + #1 + L.Key, Result);
    AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Warning, 'CG015', Path, 'allOf intersection has incompatible static types and cannot be represented as a normal Delphi value');
    Exit;
  end;
  Result := NewSyntheticNode(Hint, Path);
  Result.Primitives := Types;
  FIntersectionPairs.Add(PairKey, Result);
  FIntersectionPairs.AddOrSetValue(R.Key + #1 + L.Key, Result);
  MergeAllOf(Result, L, Path);
  MergeAllOf(Result, R, Path);
  InferKind(Result);
  if Result.Kind in [TJsonCodeGenNodeKind.ObjectValue, TJsonCodeGenNodeKind.EnumValue] then Result.ForceDeclaration := True;
end;

procedure TJsonSchemaCodeGenParser.ParseAnnotations(Node: TJsonCodeGenNode; Obj: TJsonObject);
var
  B: Boolean;
begin
  GetString(Obj, 'title', Node.Title);
  GetString(Obj, 'description', Node.Description);
  GetString(Obj, 'format', Node.FormatName);
  GetString(Obj, 'pattern', Node.Pattern);
  if GetBoolean(Obj, 'readOnly', B) then Node.ReadOnly := B;
  if GetBoolean(Obj, 'writeOnly', B) then Node.WriteOnly := B;
  if GetBoolean(Obj, 'deprecated', B) then Node.Deprecated := B;
  if Obj.GetValue('default') <> nil then
  begin
    Node.HasDefault := True;
    Node.DefaultRaw := Obj.GetValue('default').ToJSON;
  end;
end;

procedure TJsonSchemaCodeGenParser.ParseConstraints(Node: TJsonCodeGenNode; Obj: TJsonObject);
var
  I: Integer;
  B: Boolean;
begin
  if GetInteger(Obj, 'minLength', I) then begin Node.HasMinLength := True; Node.MinLength := I; end;
  if GetInteger(Obj, 'maxLength', I) then begin Node.HasMaxLength := True; Node.MaxLength := I; end;
  if GetInteger(Obj, 'minItems', I) then begin Node.HasMinItems := True; Node.MinItems := I; end;
  if GetInteger(Obj, 'maxItems', I) then begin Node.HasMaxItems := True; Node.MaxItems := I; end;
  if GetBoolean(Obj, 'uniqueItems', B) then Node.UniqueItems := B;
  Node.HasMinimum := GetNumberRaw(Obj, 'minimum', Node.MinimumRaw);
  Node.HasMaximum := GetNumberRaw(Obj, 'maximum', Node.MaximumRaw);
  Node.HasExclusiveMinimum := GetNumberRaw(Obj, 'exclusiveMinimum', Node.ExclusiveMinimumRaw);
  Node.HasExclusiveMaximum := GetNumberRaw(Obj, 'exclusiveMaximum', Node.ExclusiveMaximumRaw);
  Node.HasMultipleOf := GetNumberRaw(Obj, 'multipleOf', Node.MultipleOfRaw);
  if FModel.Version in [TJsonCodeGenSchemaVersion.Draft07, TJsonCodeGenSchemaVersion.OpenApi30] then
  begin
    if not Node.HasExclusiveMinimum and GetBoolean(Obj, 'exclusiveMinimum', B) and B and Node.HasMinimum then begin Node.HasExclusiveMinimum := True; Node.ExclusiveMinimumRaw := Node.MinimumRaw; Node.HasMinimum := False; end;
    if not Node.HasExclusiveMaximum and GetBoolean(Obj, 'exclusiveMaximum', B) and B and Node.HasMaximum then begin Node.HasExclusiveMaximum := True; Node.ExclusiveMaximumRaw := Node.MaximumRaw; Node.HasMaximum := False; end;
  end;
end;

procedure TJsonSchemaCodeGenParser.ParseTypeKeyword(Node: TJsonCodeGenNode; Obj: TJsonObject);
var
  V, Item: TJsonValue;
  A: TJsonArray;
  S: string;
  I: Integer;
  B: Boolean;
begin
  V := Obj.GetValue('type');
  if V is TJsonString then AddPrimitiveFromTypeName(Node, V.AsString, Node.SchemaPath + '/type')
  else if V is TJsonArray then
  begin
    A := TJsonArray(V);
    for I := 0 to A.Count - 1 do
    begin
      Item := A.Items[I];
      if Item is TJsonString then AddPrimitiveFromTypeName(Node, Item.AsString, Node.SchemaPath + '/type/' + IntToStr(I))
      else AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Warning, 'CG002', Node.SchemaPath + '/type/' + IntToStr(I), 'Type array contains a non-string entry');
    end;
  end;
  if GetBoolean(Obj, 'nullable', B) and B then Include(Node.Primitives, TJsonCodeGenPrimitive.NullPrimitive);
  if (Node.Primitives = []) and GetString(Obj, 'format', S) and (FModel.Version in [TJsonCodeGenSchemaVersion.OpenApi30, TJsonCodeGenSchemaVersion.OpenApi31]) then
  begin
    if SameText(S, 'int32') or SameText(S, 'int64') then Include(Node.Primitives, TJsonCodeGenPrimitive.IntegerPrimitive)
    else if SameText(S, 'float') or SameText(S, 'double') or SameText(S, 'decimal') then Include(Node.Primitives, TJsonCodeGenPrimitive.NumberPrimitive);
  end;
end;

procedure TJsonSchemaCodeGenParser.ParseEnumAndConst(Node: TJsonCodeGenNode; Obj: TJsonObject);
var
  V: TJsonValue;
  A: TJsonArray;
  I: Integer;
  InferTypes: Boolean;
begin
  V := Obj.GetValue('enum');
  if V is TJsonArray then
  begin
    A := TJsonArray(V);
    InferTypes := Node.Primitives = [];
    for I := 0 to A.Count - 1 do
    begin
      V := A.Items[I];
      Node.EnumRawValues.Add(V.ToJSON);
      if InferTypes then Include(Node.Primitives, PrimitiveOf(V));
    end;
    if A.Count > 0 then Node.ForceDeclaration := True;
  end;
  V := Obj.GetValue('const');
  if V <> nil then
  begin
    Node.HasConst := True;
    Node.ConstRaw := V.ToJSON;
    if Node.Primitives = [] then Include(Node.Primitives, PrimitiveOf(V));
  end;
end;

procedure TJsonSchemaCodeGenParser.ReportRuntimeOnlyKeywords(Obj: TJsonObject; const Path: string);
  procedure Report(const Name: string);
  begin
    if Obj.GetValue(Name) <> nil then AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Info, 'CG013', Path + '/' + TJsonCodeGenNameAllocator.JsonPointerToken(Name), 'Keyword "' + Name + '" affects schema semantics but has no lossless static Delphi representation; retain the schema for runtime validation');
  end;
begin
  Report('const');
  Report('not');
  Report('if');
  Report('then');
  Report('else');
  Report('dependentRequired');
  Report('dependentSchemas');
  Report('dependencies');
  Report('propertyNames');
  Report('minProperties');
  Report('maxProperties');
  Report('contains');
  Report('minContains');
  Report('maxContains');
  Report('unevaluatedProperties');
  Report('unevaluatedItems');
  Report('contentEncoding');
  Report('contentMediaType');
  Report('contentSchema');
  Report('discriminator');
end;

procedure TJsonSchemaCodeGenParser.MergeAllOf(Node, Source: TJsonCodeGenNode; const Path: string);
var
  S: TJsonCodeGenNode;
  P: TJsonCodeGenProperty;
  Existing: TJsonCodeGenProperty;
  Intersect: TJsonCodeGenPrimitives;
begin
  if Source = nil then Exit;
  S := EffectiveNode(Source);
  if S = nil then Exit;
  if Node.Primitives = [] then Node.Primitives := S.Primitives
  else if S.Primitives <> [] then
  begin
    Intersect := Node.Primitives * S.Primitives;
    if (Intersect = []) and (TJsonCodeGenPrimitive.IntegerPrimitive in Node.Primitives) and (TJsonCodeGenPrimitive.NumberPrimitive in S.Primitives) then Intersect := [TJsonCodeGenPrimitive.IntegerPrimitive]
    else if (Intersect = []) and (TJsonCodeGenPrimitive.NumberPrimitive in Node.Primitives) and (TJsonCodeGenPrimitive.IntegerPrimitive in S.Primitives) then Intersect := [TJsonCodeGenPrimitive.IntegerPrimitive];
    if Intersect <> [] then Node.Primitives := Intersect else AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Warning, 'CG003', Path, 'allOf contains incompatible static types');
  end;
  for P in S.Properties do
  begin
    Existing := Node.FindProperty(P.JsonName);
    if Existing = nil then Node.AddOrMergeProperty(TJsonCodeGenProperty.Create(P.JsonName, P.SchemaPath, P.Node, P.Required))
    else
    begin
      Existing.Required := Existing.Required or P.Required;
      Existing.Node := IntersectionNode(Existing.Node, P.Node, Existing.JsonName, Path + '/properties/' + TJsonCodeGenNameAllocator.JsonPointerToken(Existing.JsonName));
    end;
  end;
  if S.ItemType <> nil then Node.ItemType := IntersectionNode(Node.ItemType, S.ItemType, Node.NameHint + 'Item', Path + '/items');
  if S.AdditionalPropertiesSpecified then
  begin
    Node.AdditionalPropertiesSpecified := True;
    Node.AdditionalPropertiesAllowed := Node.AdditionalPropertiesAllowed and S.AdditionalPropertiesAllowed;
    if S.AdditionalPropertiesType <> nil then Node.AdditionalPropertiesType := IntersectionNode(Node.AdditionalPropertiesType, S.AdditionalPropertiesType, Node.NameHint + 'Value', Path + '/additionalProperties');
  end;
  if S.HasMinLength and (not Node.HasMinLength or (S.MinLength > Node.MinLength)) then begin Node.HasMinLength := True; Node.MinLength := S.MinLength; end;
  if S.HasMaxLength and (not Node.HasMaxLength or (S.MaxLength < Node.MaxLength)) then begin Node.HasMaxLength := True; Node.MaxLength := S.MaxLength; end;
  if S.HasMinItems and (not Node.HasMinItems or (S.MinItems > Node.MinItems)) then begin Node.HasMinItems := True; Node.MinItems := S.MinItems; end;
  if S.HasMaxItems and (not Node.HasMaxItems or (S.MaxItems < Node.MaxItems)) then begin Node.HasMaxItems := True; Node.MaxItems := S.MaxItems; end;
  Node.UniqueItems := Node.UniqueItems or S.UniqueItems;
  if not Node.HasMinimum and S.HasMinimum then begin Node.HasMinimum := True; Node.MinimumRaw := S.MinimumRaw; end;
  if not Node.HasMaximum and S.HasMaximum then begin Node.HasMaximum := True; Node.MaximumRaw := S.MaximumRaw; end;
  if not Node.HasExclusiveMinimum and S.HasExclusiveMinimum then begin Node.HasExclusiveMinimum := True; Node.ExclusiveMinimumRaw := S.ExclusiveMinimumRaw; end;
  if not Node.HasExclusiveMaximum and S.HasExclusiveMaximum then begin Node.HasExclusiveMaximum := True; Node.ExclusiveMaximumRaw := S.ExclusiveMaximumRaw; end;
  if not Node.HasMultipleOf and S.HasMultipleOf then begin Node.HasMultipleOf := True; Node.MultipleOfRaw := S.MultipleOfRaw; end;
  if (Node.FormatName = '') then Node.FormatName := S.FormatName;
  if (Node.Pattern = '') then Node.Pattern := S.Pattern;
end;

procedure TJsonSchemaCodeGenParser.MergeObjectUnion(Node: TJsonCodeGenNode; const Alternatives: TArray<TJsonCodeGenNode>; const Path: string);
var
  Counts, RequiredCounts: TDictionary<string, Integer>;
  A, E: TJsonCodeGenNode;
  P, Existing: TJsonCodeGenProperty;
  N, C: Integer;
  Pair: TPair<string, Integer>;
begin
  Counts := TDictionary<string, Integer>.Create;
  RequiredCounts := TDictionary<string, Integer>.Create;
  try
    Include(Node.Primitives, TJsonCodeGenPrimitive.ObjectPrimitive);
    Node.Kind := TJsonCodeGenNodeKind.ObjectValue;
    Node.AdditionalPropertiesAllowed := False;
    for A in Alternatives do
    begin
      E := EffectiveNode(A);
      if E = nil then Continue;
      Node.AdditionalPropertiesSpecified := Node.AdditionalPropertiesSpecified or E.AdditionalPropertiesSpecified;
      if E.AdditionalPropertiesAllowed then
      begin
        Node.AdditionalPropertiesAllowed := True;
        Node.AdditionalPropertiesType := CommonNode(Node.AdditionalPropertiesType, E.AdditionalPropertiesType, Node.NameHint + ' Value', Path + '/additionalProperties');
      end;
      for P in E.Properties do
      begin
        if Counts.TryGetValue(P.JsonName, C) then Counts[P.JsonName] := C + 1 else Counts.Add(P.JsonName, 1);
        if P.Required then
          if RequiredCounts.TryGetValue(P.JsonName, C) then RequiredCounts[P.JsonName] := C + 1 else RequiredCounts.Add(P.JsonName, 1);
        Existing := Node.FindProperty(P.JsonName);
        if Existing = nil then Node.AddOrMergeProperty(TJsonCodeGenProperty.Create(P.JsonName, P.SchemaPath, P.Node, False))
        else Existing.Node := CommonNode(Existing.Node, P.Node, Existing.JsonName, Path + '/properties/' + TJsonCodeGenNameAllocator.JsonPointerToken(P.JsonName));
      end;
    end;
    N := Length(Alternatives);
    for Pair in RequiredCounts do
      if (Pair.Value = N) and (Node.FindProperty(Pair.Key) <> nil) then Node.FindProperty(Pair.Key).Required := True;
    Node.ForceDeclaration := True;
  finally
    RequiredCounts.Free;
    Counts.Free;
  end;
end;

procedure TJsonSchemaCodeGenParser.ParseCompositions(Node: TJsonCodeGenNode; Obj: TJsonObject; const Path: string);
var
  V: TJsonValue;
  A: TJsonArray;
  Alt: TJsonCodeGenNode;
  Alternatives: TArray<TJsonCodeGenNode>;
  AllObjects, AllArrays: Boolean;
  I: Integer;
  E: TJsonCodeGenNode;
begin
  V := Obj.GetValue('allOf');
  if V is TJsonArray then
  begin
    A := TJsonArray(V);
    for I := 0 to A.Count - 1 do
      if IsSchemaValue(A.Items[I]) then
      begin
        Alt := ParseNode(A.Items[I], Node.NameHint, Path + '/allOf/' + IntToStr(I), False, False);
        MergeAllOf(Node, Alt, Path + '/allOf/' + IntToStr(I));
      end;
  end;
  V := Obj.GetValue('oneOf');
  if not (V is TJsonArray) then V := Obj.GetValue('anyOf');
  if V is TJsonArray then
  begin
    A := TJsonArray(V);
    SetLength(Alternatives, 0);
    for I := 0 to A.Count - 1 do
      if IsSchemaValue(A.Items[I]) then
      begin
        Alt := ParseNode(A.Items[I], Node.NameHint + 'Option' + IntToStr(I + 1), Path + '/' + IfThen(Obj.GetValue('oneOf') = V, 'oneOf', 'anyOf') + '/' + IntToStr(I), False, False);
        SetLength(Alternatives, Length(Alternatives) + 1);
        Alternatives[High(Alternatives)] := Alt;
        Node.UnionAlternatives.Add(Alt);
      end;
    if Length(Alternatives) > 0 then
    begin
      AllObjects := True;
      AllArrays := True;
      for Alt in Alternatives do
      begin
        E := EffectiveNode(Alt);
        AllObjects := AllObjects and (E <> nil) and ((E.Kind = TJsonCodeGenNodeKind.ObjectValue) or (TJsonCodeGenPrimitive.ObjectPrimitive in E.Primitives));
        AllArrays := AllArrays and (E <> nil) and ((E.Kind = TJsonCodeGenNodeKind.ArrayValue) or (TJsonCodeGenPrimitive.ArrayPrimitive in E.Primitives));
      end;
      if AllObjects then
      begin
        MergeObjectUnion(Node, Alternatives, Path);
        for Alt in Alternatives do
          if Alt.Kind = TJsonCodeGenNodeKind.ObjectValue then Alt.Omitted := True;
        Node.UnionAlternatives.Clear;
      end
      else if AllArrays then
      begin
        Include(Node.Primitives, TJsonCodeGenPrimitive.ArrayPrimitive);
        Node.Kind := TJsonCodeGenNodeKind.ArrayValue;
        for Alt in Alternatives do begin E := EffectiveNode(Alt); Node.ItemType := CommonNode(Node.ItemType, E.ItemType, Node.NameHint + 'Item', Path + '/items'); end;
      end
      else
      begin
        Node.Kind := TJsonCodeGenNodeKind.UnionValue;
        for Alt in Alternatives do begin E := EffectiveNode(Alt); if E <> nil then Node.Primitives := Node.Primitives + E.Primitives; end;
      end;
    end;
  end;
end;

procedure TJsonSchemaCodeGenParser.ParseReference(Node: TJsonCodeGenNode; Obj: TJsonObject; const Hint, Path: string; out StopParsing: Boolean);
var
  Ref, RefKeyword: string;
  Location: TJsonCodeGenLocation;
  Target: TJsonCodeGenNode;
  Legacy: Boolean;
begin
  StopParsing := False;
  RefKeyword := '$ref';
  if not GetString(Obj, RefKeyword, Ref) then begin RefKeyword := '$dynamicRef'; if not GetString(Obj, RefKeyword, Ref) then begin RefKeyword := '$recursiveRef'; if not GetString(Obj, RefKeyword, Ref) then Exit; end; end;
  if not FRepository.Resolve(Ref, Node.BaseUri, Location) then
  begin
    AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Error, 'CG004', Path + '/' + RefKeyword, 'Unresolved reference "' + Ref + '"');
    Exit;
  end;
  Target := ParseNode(Location.Value, ReferenceHint(Ref, Hint), Location.Pointer, True, False);
  Node.RefTarget := Target;
  if Target.Parsing then begin Target.Recursive := True; Node.Recursive := True; end;
  Legacy := FModel.Version in [TJsonCodeGenSchemaVersion.Draft07, TJsonCodeGenSchemaVersion.OpenApi30];
  if Legacy or not HasStructuralRefSibling(Obj) then
  begin
    Node.Kind := TJsonCodeGenNodeKind.ReferenceValue;
    Node.Primitives := Target.Primitives;
    if Legacy and HasStructuralRefSibling(Obj) then AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Info, 'CG005', Path, 'Structural siblings of ' + RefKeyword + ' are ignored by this dialect');
    StopParsing := True;
  end
  else MergeAllOf(Node, Target, Path + '/' + RefKeyword);
  if RefKeyword <> '$ref' then AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Info, 'CG006', Path + '/' + RefKeyword, RefKeyword + ' is resolved to its statically reachable target for code generation');
end;

procedure TJsonSchemaCodeGenParser.ParseDefinitions(Obj: TJsonObject; const Path: string);
var
  Container: TJsonValue;
  Defs: TJsonObject;
  P: TPair<string, TJsonValue>;
  Key, ContainerName: string;

  procedure ParseContainer(const Name: string);
  var
    P: TPair<string, TJsonValue>;
  begin
    Container := Obj.GetValue(Name);
    if not (Container is TJsonObject) then Exit;
    ContainerName := Name;
    Defs := TJsonObject(Container);
    for P in Defs do
      if IsSchemaValue(P.Value) then
      begin
        Key := P.Key;
        ParseNode(P.Value, Key, Path + '/' + ContainerName + '/' + TJsonCodeGenNameAllocator.JsonPointerToken(Key), True, True);
      end;
  end;

begin
  if not FOptions.GenerateUnusedDefinitions then Exit;
  ParseContainer('$defs');
  ParseContainer('definitions');
end;

procedure TJsonSchemaCodeGenParser.ParseObjectNode(Node: TJsonCodeGenNode; Obj: TJsonObject; const Path: string);
var
  Props, Patterns: TJsonValue;
  PropObj: TJsonObject;
  P: TPair<string, TJsonValue>;
  RequiredValue: TJsonValue;
  RequiredArray: TJsonArray;
  Required: TDictionary<string, Boolean>;
  Child: TJsonCodeGenNode;
  Name: string;
  I: Integer;
  Additional: TJsonValue;
  RequiredPair: TPair<string, Boolean>;
  B: Boolean;
begin
  Props := Obj.GetValue('properties');
  Patterns := Obj.GetValue('patternProperties');
  if (Props is TJsonObject) or (Patterns is TJsonObject) or (Obj.GetValue('additionalProperties') <> nil) or (TJsonCodeGenPrimitive.ObjectPrimitive in Node.Primitives) then
  begin
    Include(Node.Primitives, TJsonCodeGenPrimitive.ObjectPrimitive);
    if Node.Kind = TJsonCodeGenNodeKind.AnyValue then Node.Kind := TJsonCodeGenNodeKind.ObjectValue;
  end;
  Required := TDictionary<string, Boolean>.Create;
  try
    RequiredValue := Obj.GetValue('required');
    if RequiredValue is TJsonArray then
    begin
      RequiredArray := TJsonArray(RequiredValue);
      for I := 0 to RequiredArray.Count - 1 do if RequiredArray.Items[I] is TJsonString then Required.AddOrSetValue(RequiredArray.Items[I].AsString, True);
    end;
    if Props is TJsonObject then
    begin
      PropObj := TJsonObject(Props);
      for P in PropObj do
        if IsSchemaValue(P.Value) then
        begin
          Name := P.Key;
          Child := ParseNode(P.Value, Node.NameHint + ' ' + Name, Path + '/properties/' + TJsonCodeGenNameAllocator.JsonPointerToken(Name), False, False);
          Node.AddOrMergeProperty(TJsonCodeGenProperty.Create(Name, Path + '/properties/' + TJsonCodeGenNameAllocator.JsonPointerToken(Name), Child, Required.ContainsKey(Name)));
        end;
    end;
    for RequiredPair in Required do
      if Node.FindProperty(RequiredPair.Key) = nil then
      begin
        Node.AddOrMergeProperty(TJsonCodeGenProperty.Create(RequiredPair.Key, Path + '/required', nil, True));
        AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Info, 'CG014', Path + '/required', 'Required property "' + RequiredPair.Key + '" has no properties schema and is generated with the configured fallback type');
      end;
  finally
    Required.Free;
  end;
  Additional := Obj.GetValue('additionalProperties');
  if Additional <> nil then
  begin
    Node.AdditionalPropertiesSpecified := True;
    if Additional is TJsonBoolean then Node.AdditionalPropertiesAllowed := Additional.AsBoolean
    else if IsSchemaValue(Additional) then
    begin
      Node.AdditionalPropertiesAllowed := True;
      Node.AdditionalPropertiesType := ParseNode(Additional, Node.NameHint + ' Value', Path + '/additionalProperties', False, False);
    end;
  end;
  if Patterns is TJsonObject then
  begin
    for P in TJsonObject(Patterns) do
      if IsSchemaValue(P.Value) then
      begin
        Node.PatternPropertyPatterns.Add(P.Key);
        Node.PatternPropertyTypes.Add(ParseNode(P.Value, Node.NameHint + ' Pattern Value', Path + '/patternProperties/' + TJsonCodeGenNameAllocator.JsonPointerToken(P.Key), False, False));
      end;
    if (Node.Properties.Count > 0) then AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Warning, 'CG007', Path + '/patternProperties', 'Pattern properties cannot be represented as normal Delphi properties; the embedded schema still preserves the constraint');
  end;
  if GetBoolean(Obj, 'unevaluatedProperties', B) and not B and Node.AdditionalPropertiesSpecified and Node.AdditionalPropertiesAllowed then AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Info, 'CG008', Path + '/unevaluatedProperties', 'unevaluatedProperties affects runtime validation but not the generated static shape');
  if Node.Properties.Count > 0 then Node.ForceDeclaration := True;
end;

procedure TJsonSchemaCodeGenParser.ParseArrayNode(Node: TJsonCodeGenNode; Obj: TJsonObject; const Path: string);
var
  V, Items: TJsonValue;
  A: TJsonArray;
  I: Integer;
begin
  V := Obj.GetValue('prefixItems');
  Items := Obj.GetValue('items');
  if (V <> nil) or (Items <> nil) or (Obj.GetValue('contains') <> nil) or (TJsonCodeGenPrimitive.ArrayPrimitive in Node.Primitives) then
  begin
    Include(Node.Primitives, TJsonCodeGenPrimitive.ArrayPrimitive);
    if Node.Kind = TJsonCodeGenNodeKind.AnyValue then Node.Kind := TJsonCodeGenNodeKind.ArrayValue;
  end;
  if V is TJsonArray then
  begin
    A := TJsonArray(V);
    for I := 0 to A.Count - 1 do if IsSchemaValue(A.Items[I]) then Node.PrefixItems.Add(ParseNode(A.Items[I], Node.NameHint + ' Item' + IntToStr(I + 1), Path + '/prefixItems/' + IntToStr(I), False, False));
  end
  else if Items is TJsonArray then
  begin
    A := TJsonArray(Items);
    for I := 0 to A.Count - 1 do if IsSchemaValue(A.Items[I]) then Node.PrefixItems.Add(ParseNode(A.Items[I], Node.NameHint + ' Item' + IntToStr(I + 1), Path + '/items/' + IntToStr(I), False, False));
    Items := Obj.GetValue('additionalItems');
  end;
  if Items is TJsonBoolean then
  begin
    if Items.AsBoolean then Node.ItemType := ParseNode(Items, Node.NameHint + ' Item', Path + '/items', False, False) else Node.ItemType := nil;
  end
  else if IsSchemaValue(Items) then Node.ItemType := ParseNode(Items, Node.NameHint + ' Item', Path + '/items', False, False);
  if Node.PrefixItems.Count > 0 then
  begin
    for I := 0 to Node.PrefixItems.Count - 1 do Node.ItemType := CommonNode(Node.ItemType, Node.PrefixItems[I], Node.NameHint + ' Item', Path + '/items');
    if (Node.ItemType <> nil) and (Node.ItemType.Kind = TJsonCodeGenNodeKind.UnionValue) then AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Info, 'CG009', Path, 'Heterogeneous tuple items are represented by their best common static type');
  end;
end;

procedure TJsonSchemaCodeGenParser.InferKind(Node: TJsonCodeGenNode);
var
  Types: TJsonCodeGenPrimitives;
  Count: Integer;
  P: TJsonCodeGenPrimitive;
begin
  if Node.Kind = TJsonCodeGenNodeKind.ReferenceValue then Exit;
  if (Node.EnumRawValues.Count > 0) and not (TJsonCodeGenPrimitive.ObjectPrimitive in Node.Primitives) and not (TJsonCodeGenPrimitive.ArrayPrimitive in Node.Primitives) then
  begin
    Node.Kind := TJsonCodeGenNodeKind.EnumValue;
    Exit;
  end;
  Types := Node.NonNullPrimitives;
  if Types = [] then
  begin
    if Node.Properties.Count > 0 then begin Include(Node.Primitives, TJsonCodeGenPrimitive.ObjectPrimitive); Node.Kind := TJsonCodeGenNodeKind.ObjectValue; Exit; end;
    if (Node.ItemType <> nil) or (Node.PrefixItems.Count > 0) then begin Include(Node.Primitives, TJsonCodeGenPrimitive.ArrayPrimitive); Node.Kind := TJsonCodeGenNodeKind.ArrayValue; Exit; end;
    if Node.UnionAlternatives.Count > 0 then begin Node.Kind := TJsonCodeGenNodeKind.UnionValue; Exit; end;
    if Node.IsNullable then Node.Kind := TJsonCodeGenNodeKind.NullValue else Node.Kind := TJsonCodeGenNodeKind.AnyValue;
    Exit;
  end;
  if (Types = [TJsonCodeGenPrimitive.IntegerPrimitive, TJsonCodeGenPrimitive.NumberPrimitive]) then begin Node.Kind := TJsonCodeGenNodeKind.NumberValue; Exit; end;
  Count := 0;
  for P := Low(TJsonCodeGenPrimitive) to High(TJsonCodeGenPrimitive) do if P in Types then Inc(Count);
  if Count > 1 then begin Node.Kind := TJsonCodeGenNodeKind.UnionValue; Exit; end;
  if TJsonCodeGenPrimitive.BooleanPrimitive in Types then Node.Kind := TJsonCodeGenNodeKind.BooleanValue
  else if TJsonCodeGenPrimitive.IntegerPrimitive in Types then Node.Kind := TJsonCodeGenNodeKind.IntegerValue
  else if TJsonCodeGenPrimitive.NumberPrimitive in Types then Node.Kind := TJsonCodeGenNodeKind.NumberValue
  else if TJsonCodeGenPrimitive.StringPrimitive in Types then Node.Kind := TJsonCodeGenNodeKind.StringValue
  else if TJsonCodeGenPrimitive.ObjectPrimitive in Types then Node.Kind := TJsonCodeGenNodeKind.ObjectValue
  else if TJsonCodeGenPrimitive.ArrayPrimitive in Types then Node.Kind := TJsonCodeGenNodeKind.ArrayValue;
end;

function TJsonSchemaCodeGenParser.ParseNode(Schema: TJsonValue; const Hint, Path: string; ForceDeclaration, FromDefinition: Boolean): TJsonCodeGenNode;
var
  Location: TJsonCodeGenLocation;
  Key: string;
  Obj: TJsonObject;
  StopParsing: Boolean;
  B: Boolean;
begin
  if Schema = nil then Exit(nil);
  Location := TJsonCodeGenLocation.Empty;
  if FRepository.TryGetLocation(Schema, Location) then Key := Location.CanonicalUri else Key := 'inline:' + Path;
  if FNodeMap.TryGetValue(Key, Result) then
  begin
    Result.ForceDeclaration := Result.ForceDeclaration or ForceDeclaration;
    Result.FromDefinition := Result.FromDefinition or FromDefinition;
    if Result.Parsing then Result.Recursive := True;
    Exit;
  end;
  Result := TJsonCodeGenNode.Create(Key, Path, Location.BaseUri, Hint);
  Result.SourceSchema := Schema;
  Result.ForceDeclaration := ForceDeclaration;
  Result.FromDefinition := FromDefinition;
  FModel.Nodes.Add(Result);
  FNodeMap.Add(Key, Result);
  Result.Parsing := True;
  if Schema is TJsonBoolean then
  begin
    if not Schema.AsBoolean then
    begin
      Result.AlwaysFalse := True;
      AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Warning, 'CG010', Path, 'False schema accepts no value; generated code can only expose a placeholder type');
    end;
    Result.Kind := TJsonCodeGenNodeKind.AnyValue;
    Result.Parsing := False;
    Result.Parsed := True;
    Exit;
  end;
  if not (Schema is TJsonObject) then
  begin
    AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Error, 'CG011', Path, 'Schema must be an object or boolean');
    Result.Parsing := False;
    Result.Parsed := True;
    Exit;
  end;
  Obj := TJsonObject(Schema);
  ParseAnnotations(Result, Obj);
  ParseConstraints(Result, Obj);
  ParseTypeKeyword(Result, Obj);
  ParseEnumAndConst(Result, Obj);
  ParseReference(Result, Obj, Hint, Path, StopParsing);
  if not StopParsing then
  begin
    ParseCompositions(Result, Obj, Path);
    ParseObjectNode(Result, Obj, Path);
    ParseArrayNode(Result, Obj, Path);
    if Result.Primitives = [] then
    begin
      if Obj.GetValue('properties') <> nil then Include(Result.Primitives, TJsonCodeGenPrimitive.ObjectPrimitive)
      else if Obj.GetValue('items') <> nil then Include(Result.Primitives, TJsonCodeGenPrimitive.ArrayPrimitive)
      else if (Obj.GetValue('minLength') <> nil) or (Obj.GetValue('maxLength') <> nil) or (Obj.GetValue('pattern') <> nil) then Include(Result.Primitives, TJsonCodeGenPrimitive.StringPrimitive)
      else if (Obj.GetValue('minimum') <> nil) or (Obj.GetValue('maximum') <> nil) or (Obj.GetValue('multipleOf') <> nil) then Include(Result.Primitives, TJsonCodeGenPrimitive.NumberPrimitive);
    end;
    if GetBoolean(Obj, 'nullable', B) and B then Include(Result.Primitives, TJsonCodeGenPrimitive.NullPrimitive);
    ReportRuntimeOnlyKeywords(Obj, Path);
    ParseDefinitions(Obj, Path);
    InferKind(Result);
  end;
  Result.Parsing := False;
  Result.Parsed := True;
end;

function TJsonSchemaCodeGenParser.ParseOpenApi(Root: TJsonObject; const Path: string): Boolean;
var
  Components, Schemas: TJsonValue;
  P: TPair<string, TJsonValue>;
  First: TJsonCodeGenNode;
  Count: Integer;
begin
  Result := False;
  Components := Root.GetValue('components');
  if not (Components is TJsonObject) then Exit;
  Schemas := TJsonObject(Components).GetValue('schemas');
  if not (Schemas is TJsonObject) then Exit;
  First := nil;
  Count := 0;
  for P in TJsonObject(Schemas) do
    if IsSchemaValue(P.Value) then
    begin
      Inc(Count);
      if First = nil then First := ParseNode(P.Value, P.Key, Path + '/components/schemas/' + TJsonCodeGenNameAllocator.JsonPointerToken(P.Key), True, True)
      else ParseNode(P.Value, P.Key, Path + '/components/schemas/' + TJsonCodeGenNameAllocator.JsonPointerToken(P.Key), True, True);
    end;
  if Count = 1 then FModel.Root := First
  else if Count > 1 then AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Info, 'CG012', Path, 'OpenAPI document contains multiple component schemas; all components are generated and no artificial root DTO is created');
  Result := Count > 0;
end;

function TJsonSchemaCodeGenParser.NeedsDeclaration(Node: TJsonCodeGenNode): Boolean;
var
  E: TJsonCodeGenNode;
begin
  if Node = nil then Exit(False);
  if Node.IsPureReference or Node.Omitted then Exit(False);
  E := EffectiveNode(Node);
  if E = nil then Exit(False);
  Result := Node.ForceDeclaration or (Node.Kind = TJsonCodeGenNodeKind.ObjectValue) or (Node.Kind = TJsonCodeGenNodeKind.EnumValue);
end;

procedure TJsonSchemaCodeGenParser.AssignNames;
var
  N: TJsonCodeGenNode;
  Hint: string;
begin
  if (FModel.Root <> nil) and not FModel.IsOpenApiDocument and NeedsDeclaration(FModel.Root) then FModel.Root.TypeName := FNames.AllocateTypeName(FOptions.RootTypeName, FOptions.TypePrefix);
  for N in FModel.Nodes do
    if NeedsDeclaration(N) and (N.TypeName = '') then
    begin
      Hint := N.NameHint;
      if FOptions.UseTitlesForTypeNames and (N.Title <> '') then Hint := N.Title;
      if Hint = '' then Hint := 'Value';
      N.TypeName := FNames.AllocateTypeName(Hint, FOptions.TypePrefix);
    end;
end;

procedure TJsonSchemaCodeGenParser.AddDependencies(Node: TJsonCodeGenNode; List: TList<TJsonCodeGenNode>);
var
  P: TJsonCodeGenProperty;
  N: TJsonCodeGenNode;
begin
  if Node = nil then Exit;
  if Node.RefTarget <> nil then List.Add(EffectiveNode(Node.RefTarget));
  for P in Node.Properties do if P.Node <> nil then List.Add(EffectiveNode(P.Node));
  if Node.ItemType <> nil then List.Add(EffectiveNode(Node.ItemType));
  if Node.AdditionalPropertiesType <> nil then List.Add(EffectiveNode(Node.AdditionalPropertiesType));
  for N in Node.PrefixItems do List.Add(EffectiveNode(N));
  for N in Node.UnionAlternatives do List.Add(EffectiveNode(N));
end;

procedure TJsonSchemaCodeGenParser.DetectRecursionFrom(Node: TJsonCodeGenNode; Visiting, Visited: TDictionary<TJsonCodeGenNode, Boolean>; Stack: TList<TJsonCodeGenNode>);
var
  Dependencies: TList<TJsonCodeGenNode>;
  D: TJsonCodeGenNode;
  I: Integer;
begin
  if (Node = nil) or Visited.ContainsKey(Node) then Exit;
  if Visiting.ContainsKey(Node) then
  begin
    I := Stack.IndexOf(Node);
    if I < 0 then I := 0;
    while I < Stack.Count do begin Stack[I].Recursive := True; Inc(I); end;
    Node.Recursive := True;
    Exit;
  end;
  Visiting.Add(Node, True);
  Stack.Add(Node);
  Dependencies := TList<TJsonCodeGenNode>.Create;
  try
    AddDependencies(Node, Dependencies);
    for D in Dependencies do DetectRecursionFrom(D, Visiting, Visited, Stack);
  finally
    Dependencies.Free;
  end;
  Stack.Delete(Stack.Count - 1);
  Visiting.Remove(Node);
  Visited.AddOrSetValue(Node, True);
end;

procedure TJsonSchemaCodeGenParser.DetectRecursion;
var
  Visiting, Visited: TDictionary<TJsonCodeGenNode, Boolean>;
  Stack: TList<TJsonCodeGenNode>;
  N: TJsonCodeGenNode;
begin
  Visiting := TDictionary<TJsonCodeGenNode, Boolean>.Create;
  Visited := TDictionary<TJsonCodeGenNode, Boolean>.Create;
  Stack := TList<TJsonCodeGenNode>.Create;
  try
    for N in FModel.Nodes do DetectRecursionFrom(N, Visiting, Visited, Stack);
  finally
    Stack.Free;
    Visited.Free;
    Visiting.Free;
  end;
end;

function TJsonSchemaCodeGenParser.Parse(const Root: TJsonCodeGenLocation; const OriginalSchema: string): TJsonCodeGenModel;
begin
  if Root.Value = nil then raise EArgumentNilException.Create('Root');
  FModel := TJsonCodeGenModel.Create;
  try
    FModel.OriginalSchema := OriginalSchema;
    FModel.Version := DetectVersion(Root.Value);
    FModel.IsOpenApiDocument := FModel.Version in [TJsonCodeGenSchemaVersion.OpenApi30, TJsonCodeGenSchemaVersion.OpenApi31];
    if FModel.IsOpenApiDocument and (Root.Value is TJsonObject) and ParseOpenApi(TJsonObject(Root.Value), '') then
    begin
    end
    else FModel.Root := ParseNode(Root.Value, FOptions.RootTypeName, '', True, False);
    DetectRecursion;
    AssignNames;
    Result := FModel;
    FModel := nil;
  except
    FModel.Free;
    FModel := nil;
    raise;
  end;
end;

end.
