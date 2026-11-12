{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.CodeGen.Delphi;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  {$ENDIF}
  NativeJson.Dom.Value,
  NativeJson.Dom.Primitive,
  NativeJson.Dom.Io,
  {$IFDEF FPC}
  Generics.Collections,
  Character,
  {$ELSE}
  System.Generics.Collections,
  System.Character,
  {$ENDIF}
  NativeJson.CodeGen.Options,
  NativeJson.CodeGen.Model,
  NativeJson.CodeGen.Names;

type
  TJsonCodeGenDelphiEmitter = class
  private
    FModel: TJsonCodeGenModel;
    FOptions: TJsonCodeGenOptions;
    FUses: TStringList;
    FNames: TJsonCodeGenNameAllocator;
    FUnsafeEnums: TList<TJsonCodeGenNode>;
    FWarned: TDictionary<string, Boolean>;
    procedure AddUse(const UnitName: string);
    procedure WarnOnce(const Key, Code, Path, Msg: string);
    function EffectiveNode(Node: TJsonCodeGenNode): TJsonCodeGenNode;
    function IsDictionaryNode(Node: TJsonCodeGenNode): Boolean;
    function IsFallbackObjectNode(Node: TJsonCodeGenNode): Boolean;
    function DictionaryValueNode(Node: TJsonCodeGenNode): TJsonCodeGenNode;
    function IsClassNode(Node: TJsonCodeGenNode): Boolean;
    function IsRecordNode(Node: TJsonCodeGenNode): Boolean;
    function DelphiType(Node: TJsonCodeGenNode): string;
    function ScalarType(Node: TJsonCodeGenNode): string;
    function ArrayType(Node: TJsonCodeGenNode): string;
    function UnionType(Node: TJsonCodeGenNode): string;
    function DictionaryType(Node: TJsonCodeGenNode): string;
    function IntegerType(Node: TJsonCodeGenNode): string;
    function StringType(Node: TJsonCodeGenNode): string;
    function SafeEnum(Node: TJsonCodeGenNode): Boolean;
    function EnumBaseType(Node: TJsonCodeGenNode): string;
    function EnumIdentifier(const Raw: string; out Identifier: string): Boolean;
    procedure PrepareMembers;
    procedure WriteForwardDeclarations(B: TStringBuilder);
    procedure WriteNonClassDeclarations(B: TStringBuilder);
    procedure WriteClassDeclarations(B: TStringBuilder);
    procedure WriteEnumConstants(B: TStringBuilder);
    procedure WriteNodeDeclaration(B: TStringBuilder; Node: TJsonCodeGenNode);
    procedure WriteObjectDeclaration(B: TStringBuilder; Node: TJsonCodeGenNode);
    procedure WriteEnumDeclaration(B: TStringBuilder; Node: TJsonCodeGenNode);
    procedure WriteAliasDeclaration(B: TStringBuilder; Node: TJsonCodeGenNode);
    procedure WriteMemberAttributes(B: TStringBuilder; Prop: TJsonCodeGenProperty; Level: Integer);
    procedure WriteTypeAttributes(B: TStringBuilder; Node: TJsonCodeGenNode; Level: Integer);
    procedure WriteClassImplementation(B: TStringBuilder; Node: TJsonCodeGenNode);
    procedure WriteImplementation(B: TStringBuilder);
    procedure WriteEmbeddedSchema(B: TStringBuilder);
    function NeedsConstructor(Node: TJsonCodeGenNode): Boolean;
    function NeedsDestructor(Node: TJsonCodeGenNode): Boolean;
    function MemberNeedsFree(Node: TJsonCodeGenNode): Boolean;
    function MemberNeedsArrayItemFree(Node: TJsonCodeGenNode): Boolean;
    function MemberNeedsDictionaryValueFree(Node: TJsonCodeGenNode): Boolean;
    function DefaultExpression(Node: TJsonCodeGenNode; const Raw: string): string;
    function Indent(Level: Integer): string;
    function UsesClause: string;
    function NonClassNodes: TArray<TJsonCodeGenNode>;
    procedure CollectDependencies(Node: TJsonCodeGenNode; Dependencies: TList<TJsonCodeGenNode>);
    function TopologicalNonClassNodes: TArray<TJsonCodeGenNode>;
    function CanUseInt32(Node: TJsonCodeGenNode): Boolean;
    function JsonStringValue(const Raw: string; out Value: string): Boolean;
    function JsonIntegerValue(const Raw: string; out Value: Int64): Boolean;
    function JsonBooleanValue(const Raw: string; out Value: Boolean): Boolean;
    function JsonNumberValue(const Raw: string): Boolean;
    function PascalFloat(const Raw: string): string;
  public
    constructor Create(Model: TJsonCodeGenModel; const Options: TJsonCodeGenOptions);
    destructor Destroy; override;
    function GenerateTypes: string;
    function GenerateUnit(const UnitName: string): string;
    function RootTypeName: string;
  end;

implementation

uses
  {$IFDEF FPC}
  TypInfo,
  Variants,
  Math;
  {$ELSE}
  System.TypInfo,
  System.Variants,
  System.Math;
  {$ENDIF}

constructor TJsonCodeGenDelphiEmitter.Create(Model: TJsonCodeGenModel; const Options: TJsonCodeGenOptions);
begin
  inherited Create;
  if Model = nil then raise EArgumentNilException.Create('Model');
  FModel := Model;
  FOptions := Options;
  FUses := TStringList.Create;
  FUses.Sorted := True;
  FUses.Duplicates := dupIgnore;
  FNames := TJsonCodeGenNameAllocator.Create;
  FUnsafeEnums := TList<TJsonCodeGenNode>.Create;
  FWarned := TDictionary<string, Boolean>.Create;
  PrepareMembers;
end;

destructor TJsonCodeGenDelphiEmitter.Destroy;
begin
  FWarned.Free;
  FUnsafeEnums.Free;
  FNames.Free;
  FUses.Free;
  inherited;
end;

procedure TJsonCodeGenDelphiEmitter.AddUse(const UnitName: string);
begin
  if UnitName <> '' then FUses.Add(UnitName);
end;

procedure TJsonCodeGenDelphiEmitter.WarnOnce(const Key, Code, Path, Msg: string);
begin
  if FWarned.ContainsKey(Key) then Exit;
  FWarned.Add(Key, True);
  FModel.AddDiagnostic(TJsonCodeGenDiagnosticSeverity.Warning, Code, Path, Msg);
end;

function TJsonCodeGenDelphiEmitter.Indent(Level: Integer): string;
begin
  Result := StringOfChar(' ', Level * FOptions.IndentSize);
end;

function TJsonCodeGenDelphiEmitter.EffectiveNode(Node: TJsonCodeGenNode): TJsonCodeGenNode;
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

function TJsonCodeGenDelphiEmitter.DictionaryValueNode(Node: TJsonCodeGenNode): TJsonCodeGenNode;
var
  N, E: TJsonCodeGenNode;
  I: Integer;
begin
  E := EffectiveNode(Node);
  if E = nil then Exit(nil);
  Result := E.AdditionalPropertiesType;
  if E.AdditionalPropertiesAllowed and (Result = nil) then Exit(nil);
  for I := 0 to E.PatternPropertyTypes.Count - 1 do
  begin
    N := E.PatternPropertyTypes[I];
    if Result = nil then Result := N
    else if EffectiveNode(Result) <> EffectiveNode(N) then Exit(nil);
  end;
end;

function TJsonCodeGenDelphiEmitter.IsDictionaryNode(Node: TJsonCodeGenNode): Boolean;
var
  E: TJsonCodeGenNode;
begin
  E := EffectiveNode(Node);
  Result := (E <> nil) and (E.Kind = TJsonCodeGenNodeKind.ObjectValue) and (E.Properties.Count = 0) and (E.AdditionalPropertiesAllowed or (E.PatternPropertyTypes.Count > 0)) and (FOptions.AdditionalPropertiesKind = TJsonCodeGenAdditionalPropertiesKind.DictionaryWhenPossible);
end;

function TJsonCodeGenDelphiEmitter.IsFallbackObjectNode(Node: TJsonCodeGenNode): Boolean;
var
  E: TJsonCodeGenNode;
begin
  E := EffectiveNode(Node);
  Result := (E <> nil) and (E.Kind = TJsonCodeGenNodeKind.ObjectValue) and (E.Properties.Count = 0) and E.AdditionalPropertiesAllowed and (FOptions.AdditionalPropertiesKind = TJsonCodeGenAdditionalPropertiesKind.FallbackType);
end;

function TJsonCodeGenDelphiEmitter.IsClassNode(Node: TJsonCodeGenNode): Boolean;
var
  E: TJsonCodeGenNode;
begin
  E := EffectiveNode(Node);
  if (E = nil) or (E.Kind <> TJsonCodeGenNodeKind.ObjectValue) or IsDictionaryNode(E) or IsFallbackObjectNode(E) then Exit(False);
  Result := (FOptions.EntityKind = TJsonCodeGenEntityKind.Classes) or E.Recursive;
end;

function TJsonCodeGenDelphiEmitter.IsRecordNode(Node: TJsonCodeGenNode): Boolean;
var
  E: TJsonCodeGenNode;
begin
  E := EffectiveNode(Node);
  Result := (E <> nil) and (E.Kind = TJsonCodeGenNodeKind.ObjectValue) and not IsDictionaryNode(E) and not IsFallbackObjectNode(E) and (FOptions.EntityKind = TJsonCodeGenEntityKind.Records) and not E.Recursive;
end;

function TJsonCodeGenDelphiEmitter.JsonStringValue(const Raw: string; out Value: string): Boolean;
var
  J: TJsonValue;
begin
  // TryDomFromText instead of DomFromText: invalid JSON is an
  // expected case here, not an error. Delphi's ParseJSONValue returned
  // nil for it - here the return value says so.
  Value := '';
  if not TryDomFromText(Raw, J) then Exit(False);
  try
    Result := J is TJsonString;
    if Result then Value := J.AsString else Value := '';
  finally
    J.Free;
  end;
end;

function TJsonCodeGenDelphiEmitter.JsonIntegerValue(const Raw: string; out Value: Int64): Boolean;
var
  J: TJsonValue;
begin
  Value := 0;
  if not TryDomFromText(Raw, J) then Exit(False);
  try
    // Via the raw text, not via AsInteger: 2.7 must not pass as 3 here
    // and 9223372036854775808 must not arrive truncated.
    Result := (J is TJsonNumber) and TryStrToInt64(J.AsRawText, Value);
  finally
    J.Free;
  end;
end;

function TJsonCodeGenDelphiEmitter.JsonBooleanValue(const Raw: string; out Value: Boolean): Boolean;
var
  J: TJsonValue;
begin
  Value := False;
  if not TryDomFromText(Raw, J) then Exit(False);
  try
    Result := J is TJsonBoolean;
    if Result then Value := J.AsBoolean else Value := False;
  finally
    J.Free;
  end;
end;

function TJsonCodeGenDelphiEmitter.JsonNumberValue(const Raw: string): Boolean;
var
  J: TJsonValue;
begin
  if not TryDomFromText(Raw, J) then Exit(False);
  try
    Result := J is TJsonNumber;
  finally
    J.Free;
  end;
end;

function TJsonCodeGenDelphiEmitter.PascalFloat(const Raw: string): string;
begin
  Result := Raw;
  if Pos('.', Result) = 0 then
    if (Pos('e', LowerCase(Result)) = 0) then Result := Result + '.0';
end;

function TJsonCodeGenDelphiEmitter.CanUseInt32(Node: TJsonCodeGenNode): Boolean;
var
  MinV, MaxV: Int64;
begin
  Result := FOptions.PreferInt32WhenSafe and Node.HasMinimum and Node.HasMaximum and TryStrToInt64(Node.MinimumRaw, MinV) and TryStrToInt64(Node.MaximumRaw, MaxV) and (MinV >= Low(Integer)) and (MaxV <= High(Integer));
end;

function TJsonCodeGenDelphiEmitter.IntegerType(Node: TJsonCodeGenNode): string;
var
  MinU, MaxU: UInt64;
  MinRaw, MaxRaw: string;
begin
  if SameText(Node.FormatName, 'int32') then Exit('Integer');
  if SameText(Node.FormatName, 'int64') then Exit('Int64');
  if SameText(Node.FormatName, 'uint32') then Exit('Cardinal');
  if SameText(Node.FormatName, 'uint64') then Exit('UInt64');
  if CanUseInt32(Node) then Exit('Integer');
  MinRaw := '';
  MaxRaw := '';
  if Node.HasMinimum then MinRaw := Node.MinimumRaw else if Node.HasExclusiveMinimum then MinRaw := Node.ExclusiveMinimumRaw;
  if Node.HasMaximum then MaxRaw := Node.MaximumRaw else if Node.HasExclusiveMaximum then MaxRaw := Node.ExclusiveMaximumRaw;
  if (MinRaw <> '') and (MaxRaw <> '') and TryStrToUInt64(MinRaw, MinU) and TryStrToUInt64(MaxRaw, MaxU) and (MaxU > UInt64(High(Int64))) then Exit('UInt64');
  Result := 'Int64';
end;

function TJsonCodeGenDelphiEmitter.StringType(Node: TJsonCodeGenNode): string;
begin
  Result := 'string';
  if FOptions.FormatKind <> TJsonCodeGenFormatKind.NativeTypes then Exit;
  if SameText(Node.FormatName, 'date-time') then Result := 'TDateTime'
  else if SameText(Node.FormatName, 'date') then Result := 'TDate'
  else if SameText(Node.FormatName, 'time') then Result := 'TTime'
  else if SameText(Node.FormatName, 'uuid') then begin AddUse('System.SysUtils'); Result := 'TGUID'; end
  else if SameText(Node.FormatName, 'duration') then begin AddUse('System.TimeSpan'); Result := 'TTimeSpan'; end
  else if SameText(Node.FormatName, 'byte') or SameText(Node.FormatName, 'base64') then begin AddUse('System.SysUtils'); Result := 'TBytes'; end;
end;

function TJsonCodeGenDelphiEmitter.ScalarType(Node: TJsonCodeGenNode): string;
begin
  case Node.Kind of
    TJsonCodeGenNodeKind.NullValue: Result := FOptions.UnknownType;
    TJsonCodeGenNodeKind.BooleanValue: Result := 'Boolean';
    TJsonCodeGenNodeKind.IntegerValue: Result := IntegerType(Node);
    TJsonCodeGenNodeKind.NumberValue:
      if SameText(Node.FormatName, 'float') then Result := 'Single'
      else if FOptions.PreferCurrencyForDecimal and (SameText(Node.FormatName, 'decimal') or Node.HasMultipleOf) then Result := 'Currency'
      else Result := 'Double';
    TJsonCodeGenNodeKind.StringValue: Result := StringType(Node);
  else
    Result := FOptions.UnknownType;
  end;
end;

function TJsonCodeGenDelphiEmitter.EnumIdentifier(const Raw: string; out Identifier: string): Boolean;
var
  S: string;
  I: Integer;
  C: Char;
begin
  Result := JsonStringValue(Raw, S);
  if not Result or (S = '') then Exit(False);
  C := S[1];
  if not (C.IsLetter or (C = '_')) then Exit(False);
  for I := 2 to Length(S) do if not (S[I].IsLetterOrDigit or (S[I] = '_')) then Exit(False);
  Identifier := TJsonCodeGenNameAllocator.DelphiIdentifier(S, False);
  Result := not Identifier.StartsWith('&') and SameText(Identifier, S);
end;

function TJsonCodeGenDelphiEmitter.SafeEnum(Node: TJsonCodeGenNode): Boolean;
var
  Raw, Id: string;
  Used: TDictionary<string, Boolean>;
begin
  Result := (FOptions.EnumKind = TJsonCodeGenEnumKind.SafeDelphiEnum) and (Node.EnumRawValues.Count > 0);
  if not Result then Exit;
  Used := TDictionary<string, Boolean>.Create;
  try
    for Raw in Node.EnumRawValues do
    begin
      if not EnumIdentifier(Raw, Id) or Used.ContainsKey(UpperCase(Id)) then Exit(False);
      Used.Add(UpperCase(Id), True);
    end;
  finally
    Used.Free;
  end;
end;

function TJsonCodeGenDelphiEmitter.EnumBaseType(Node: TJsonCodeGenNode): string;
var
  P: TJsonCodeGenPrimitives;
begin
  P := Node.NonNullPrimitives;
  if P = [TJsonCodeGenPrimitive.StringPrimitive] then Result := 'string'
  else if P = [TJsonCodeGenPrimitive.IntegerPrimitive] then Result := IntegerType(Node)
  else if (P = [TJsonCodeGenPrimitive.NumberPrimitive]) or (P = [TJsonCodeGenPrimitive.IntegerPrimitive, TJsonCodeGenPrimitive.NumberPrimitive]) then Result := 'Double'
  else if P = [TJsonCodeGenPrimitive.BooleanPrimitive] then Result := 'Boolean'
  else Result := FOptions.UnknownType;
end;

function TJsonCodeGenDelphiEmitter.DictionaryType(Node: TJsonCodeGenNode): string;
var
  V: TJsonCodeGenNode;
  ValueType: string;
begin
  AddUse('System.Generics.Collections');
  V := DictionaryValueNode(Node);
  if V = nil then ValueType := FOptions.UnknownType else ValueType := DelphiType(V);
  Result := 'TDictionary<string, ' + ValueType + '>';
end;

function TJsonCodeGenDelphiEmitter.ArrayType(Node: TJsonCodeGenNode): string;
var
  ItemNode: TJsonCodeGenNode;
  ItemType: string;
begin
  ItemNode := Node.ItemType;
  if ItemNode = nil then ItemType := FOptions.UnknownType else ItemType := DelphiType(ItemNode);
  if (FOptions.EntityKind = TJsonCodeGenEntityKind.Records) and (FOptions.ArrayKind <> TJsonCodeGenArrayKind.DynamicArrays) then
  begin
    WarnOnce('record-array-kind', 'CG101', Node.SchemaPath, 'Record generation uses dynamic arrays because generic list instances require object lifetime management');
    Exit('TArray<' + ItemType + '>');
  end;
  case FOptions.ArrayKind of
    TJsonCodeGenArrayKind.DynamicArrays: Result := 'TArray<' + ItemType + '>';
    TJsonCodeGenArrayKind.GenericLists:
      begin AddUse('System.Generics.Collections'); Result := 'TList<' + ItemType + '>'; end;
    TJsonCodeGenArrayKind.ObjectLists:
      begin
        AddUse('System.Generics.Collections');
        if (ItemNode <> nil) and IsClassNode(ItemNode) then Result := 'TObjectList<' + ItemType + '>' else Result := 'TList<' + ItemType + '>';
      end;
  else
    Result := 'TArray<' + ItemType + '>';
  end;
end;

function TJsonCodeGenDelphiEmitter.UnionType(Node: TJsonCodeGenNode): string;
var
  P: TJsonCodeGenPrimitives;
begin
  P := Node.NonNullPrimitives;
  if FOptions.UnionKind = TJsonCodeGenUnionKind.FallbackType then
  begin
    WarnOnce('union-fallback:' + Node.Key, 'CG102', Node.SchemaPath, 'Schema union uses the configured fallback type ' + FOptions.UnknownType);
    Exit(FOptions.UnknownType);
  end;
  if FOptions.UnionKind = TJsonCodeGenUnionKind.VariantForScalars then
  begin
    if (P <= [TJsonCodeGenPrimitive.BooleanPrimitive, TJsonCodeGenPrimitive.IntegerPrimitive, TJsonCodeGenPrimitive.NumberPrimitive, TJsonCodeGenPrimitive.StringPrimitive]) and (P <> []) then begin AddUse('System.Variants'); Exit('Variant'); end;
    WarnOnce('union-fallback:' + Node.Key, 'CG102', Node.SchemaPath, 'Non-scalar schema union uses the configured fallback type ' + FOptions.UnknownType);
    Exit(FOptions.UnknownType);
  end;
  if P = [TJsonCodeGenPrimitive.IntegerPrimitive, TJsonCodeGenPrimitive.NumberPrimitive] then Exit('Double');
  if P = [TJsonCodeGenPrimitive.StringPrimitive] then Exit(StringType(Node));
  if P = [TJsonCodeGenPrimitive.IntegerPrimitive] then Exit(IntegerType(Node));
  if P = [TJsonCodeGenPrimitive.NumberPrimitive] then Exit('Double');
  if P = [TJsonCodeGenPrimitive.BooleanPrimitive] then Exit('Boolean');
  if (P <= [TJsonCodeGenPrimitive.BooleanPrimitive, TJsonCodeGenPrimitive.IntegerPrimitive, TJsonCodeGenPrimitive.NumberPrimitive, TJsonCodeGenPrimitive.StringPrimitive]) and (P <> []) then begin AddUse('System.Variants'); Exit('Variant'); end;
  WarnOnce('union:' + Node.Key, 'CG102', Node.SchemaPath, 'This heterogeneous schema union has no lossless static Delphi representation and uses ' + FOptions.UnknownType);
  Result := FOptions.UnknownType;
end;

function TJsonCodeGenDelphiEmitter.DelphiType(Node: TJsonCodeGenNode): string;
var
  E: TJsonCodeGenNode;
  Base: string;
  NullableScalar: Boolean;
begin
  if Node = nil then Exit(FOptions.UnknownType);
  if Node.AlwaysFalse then Exit(FOptions.UnknownType);
  E := EffectiveNode(Node);
  if E = nil then Exit(FOptions.UnknownType);
  if E <> Node then
  begin
    Base := DelphiType(E);
    NullableScalar := Node.IsNullable and not IsClassNode(E) and (E.Kind <> TJsonCodeGenNodeKind.ArrayValue);
    if NullableScalar then
      case FOptions.NullableKind of
        TJsonCodeGenNullableKind.VariantForScalars: begin AddUse('System.Variants'); Exit('Variant'); end;
        TJsonCodeGenNullableKind.FallbackType: Exit(FOptions.UnknownType);
      end;
    Exit(Base);
  end;
  if E.TypeName <> '' then Base := E.TypeName
  else if IsDictionaryNode(E) then Base := DictionaryType(E)
  else case E.Kind of
    TJsonCodeGenNodeKind.ObjectValue: Base := FOptions.UnknownType;
    TJsonCodeGenNodeKind.ArrayValue: Base := ArrayType(E);
    TJsonCodeGenNodeKind.EnumValue: Base := EnumBaseType(E);
    TJsonCodeGenNodeKind.UnionValue: Base := UnionType(E);
    TJsonCodeGenNodeKind.AnyValue: Base := FOptions.UnknownType;
  else
    Base := ScalarType(E);
  end;
  NullableScalar := E.IsNullable and not IsClassNode(E) and (E.Kind <> TJsonCodeGenNodeKind.ArrayValue) and not IsDictionaryNode(E);
  if NullableScalar then
  begin
    case FOptions.NullableKind of
      TJsonCodeGenNullableKind.VariantForScalars: begin AddUse('System.Variants'); Base := 'Variant'; end;
      TJsonCodeGenNullableKind.FallbackType: Base := FOptions.UnknownType;
      TJsonCodeGenNullableKind.NativeDefaults: WarnOnce('nullable:' + E.Key, 'CG103', E.SchemaPath, 'Nullable scalar uses its native Delphi default; null and the default value are not distinguishable in the generated model');
    end;
  end;
  Result := Base;
end;

procedure TJsonCodeGenDelphiEmitter.PrepareMembers;
var
  N: TJsonCodeGenNode;
  P: TJsonCodeGenProperty;
  Used: TDictionary<string, Boolean>;
begin
  for N in FModel.Nodes do
  begin
    if EffectiveNode(N) <> N then Continue;
    if N.Kind <> TJsonCodeGenNodeKind.ObjectValue then Continue;
    Used := TDictionary<string, Boolean>.Create;
    try
      for P in N.Properties do P.DelphiName := FNames.AllocateMemberName(P.JsonName, Used, IsClassNode(N));
    finally
      Used.Free;
    end;
  end;
end;

procedure TJsonCodeGenDelphiEmitter.WriteTypeAttributes(B: TStringBuilder; Node: TJsonCodeGenNode; Level: Integer);
begin
  if not FOptions.EmitSchemaAttributes then Exit;
  AddUse('NativeJson.Schema.Attributes');
  if Node.Title <> '' then B.Append(Indent(Level)).Append('[JsonTitle(').Append(TJsonCodeGenNameAllocator.DelphiString(Node.Title)).AppendLine(')]');
  if Node.Description <> '' then B.Append(Indent(Level)).Append('[JsonDescription(').Append(TJsonCodeGenNameAllocator.DelphiString(Node.Description)).AppendLine(')]');
  if Node.Deprecated then B.Append(Indent(Level)).AppendLine('[JsonDeprecated]');
end;

procedure TJsonCodeGenDelphiEmitter.WriteMemberAttributes(B: TStringBuilder; Prop: TJsonCodeGenProperty; Level: Integer);
var
  N, A: TJsonCodeGenNode;
  Description, FormatName, Pattern: string;
  ReadOnly, WriteOnly, Deprecated: Boolean;
begin
  N := Prop.Node;
  if FOptions.EmitJsonPropertyAttributes then
  begin
    AddUse('NativeJson.Attributes');
    B.Append(Indent(Level)).Append('[JsonProperty(').Append(TJsonCodeGenNameAllocator.DelphiString(Prop.JsonName)).AppendLine(')]');
  end;
  if not FOptions.EmitSchemaAttributes then Exit;
  AddUse('NativeJson.Schema.Attributes');
  if Prop.Required then B.Append(Indent(Level)).AppendLine('[JsonRequired]');
  if N = nil then Exit;
  A := EffectiveNode(N);
  if A = nil then A := N;
  Description := N.Description;
  if Description = '' then Description := A.Description;
  FormatName := N.FormatName;
  if FormatName = '' then FormatName := A.FormatName;
  Pattern := N.Pattern;
  if Pattern = '' then Pattern := A.Pattern;
  ReadOnly := N.ReadOnly or A.ReadOnly;
  WriteOnly := N.WriteOnly or A.WriteOnly;
  Deprecated := N.Deprecated or A.Deprecated;
  if Description <> '' then B.Append(Indent(Level)).Append('[JsonDescription(').Append(TJsonCodeGenNameAllocator.DelphiString(Description)).AppendLine(')]');
  if FormatName <> '' then B.Append(Indent(Level)).Append('[JsonSchemaFormat(').Append(TJsonCodeGenNameAllocator.DelphiString(FormatName)).AppendLine(')]');
  if Pattern <> '' then B.Append(Indent(Level)).Append('[JsonPattern(').Append(TJsonCodeGenNameAllocator.DelphiString(Pattern)).AppendLine(')]');
  if A.HasMinLength then B.Append(Indent(Level)).Append('[JsonMinLength(').Append(A.MinLength).AppendLine(')]');
  if A.HasMaxLength then B.Append(Indent(Level)).Append('[JsonMaxLength(').Append(A.MaxLength).AppendLine(')]');
  if A.HasMinItems and A.HasMaxItems then B.Append(Indent(Level)).Append('[JsonArrayLength(').Append(A.MinItems).Append(', ').Append(A.MaxItems).AppendLine(')]')
  else if A.HasMinItems or A.HasMaxItems then WarnOnce('array-range:' + A.Key, 'CG104', A.SchemaPath, 'A one-sided array length constraint has no matching NativeJson schema attribute and remains in the embedded schema');
  if A.UniqueItems then B.Append(Indent(Level)).AppendLine('[JsonUniqueItems]');
  if A.HasMinimum and A.HasMaximum and not A.HasExclusiveMinimum and not A.HasExclusiveMaximum then B.Append(Indent(Level)).Append('[JsonRange(').Append(TJsonCodeGenNameAllocator.DelphiString(A.MinimumRaw)).Append(', ').Append(TJsonCodeGenNameAllocator.DelphiString(A.MaximumRaw)).AppendLine(')]')
  else if A.HasExclusiveMinimum and A.HasExclusiveMaximum and not A.HasMinimum and not A.HasMaximum then B.Append(Indent(Level)).Append('[JsonExclusiveRange(').Append(TJsonCodeGenNameAllocator.DelphiString(A.ExclusiveMinimumRaw)).Append(', ').Append(TJsonCodeGenNameAllocator.DelphiString(A.ExclusiveMaximumRaw)).AppendLine(')]')
  else if A.HasMinimum or A.HasMaximum or A.HasExclusiveMinimum or A.HasExclusiveMaximum then WarnOnce('numeric-range:' + A.Key, 'CG105', A.SchemaPath, 'The exact one-sided or mixed inclusive/exclusive numeric range remains in the embedded schema because existing NativeJson attributes cannot express it losslessly');
  if A.HasMultipleOf then B.Append(Indent(Level)).Append('[JsonMultipleOf(').Append(TJsonCodeGenNameAllocator.DelphiString(A.MultipleOfRaw)).AppendLine(')]');
  if ReadOnly then B.Append(Indent(Level)).AppendLine('[JsonReadOnly]');
  if WriteOnly then B.Append(Indent(Level)).AppendLine('[JsonWriteOnly]');
  if Deprecated then B.Append(Indent(Level)).AppendLine('[JsonDeprecated]');
end;

function TJsonCodeGenDelphiEmitter.MemberNeedsArrayItemFree(Node: TJsonCodeGenNode): Boolean;
var
  E, Item: TJsonCodeGenNode;
begin
  Result := False;
  if not FOptions.OwnsGeneratedObjects then Exit;
  E := EffectiveNode(Node);
  if (E = nil) or (E.Kind <> TJsonCodeGenNodeKind.ArrayValue) or (FOptions.ArrayKind <> TJsonCodeGenArrayKind.DynamicArrays) then Exit;
  Item := EffectiveNode(E.ItemType);
  Result := (Item <> nil) and IsClassNode(Item);
end;

function TJsonCodeGenDelphiEmitter.MemberNeedsDictionaryValueFree(Node: TJsonCodeGenNode): Boolean;
var
  E, V: TJsonCodeGenNode;
begin
  Result := False;
  if not FOptions.OwnsGeneratedObjects then Exit;
  E := EffectiveNode(Node);
  if (E = nil) or not IsDictionaryNode(E) then Exit;
  V := EffectiveNode(DictionaryValueNode(E));
  Result := (V <> nil) and IsClassNode(V);
end;

function TJsonCodeGenDelphiEmitter.MemberNeedsFree(Node: TJsonCodeGenNode): Boolean;
var
  E, Item: TJsonCodeGenNode;
begin
  Result := False;
  if not FOptions.OwnsGeneratedObjects then Exit;
  E := EffectiveNode(Node);
  if E = nil then Exit;
  if IsClassNode(E) then Exit(True);
  if IsDictionaryNode(E) then Exit(True);
  if E.Kind = TJsonCodeGenNodeKind.ArrayValue then
  begin
    if FOptions.ArrayKind in [TJsonCodeGenArrayKind.GenericLists, TJsonCodeGenArrayKind.ObjectLists] then Exit(True);
    Item := EffectiveNode(E.ItemType);
    Result := (Item <> nil) and IsClassNode(Item) and MemberNeedsArrayItemFree(E);
  end;
end;

function TJsonCodeGenDelphiEmitter.DefaultExpression(Node: TJsonCodeGenNode; const Raw: string): string;
var
  E: TJsonCodeGenNode;
  S, Id: string;
  I: Int64;
  B: Boolean;
begin
  Result := '';
  E := EffectiveNode(Node);
  if E = nil then Exit;
  if SameText(Raw, 'null') then Exit;
  if E.Kind = TJsonCodeGenNodeKind.EnumValue then
  begin
    if SafeEnum(E) and JsonStringValue(Raw, S) and EnumIdentifier(Raw, Id) then Exit(E.TypeName + '.' + Id);
    if JsonStringValue(Raw, S) then Exit(TJsonCodeGenNameAllocator.DelphiString(S));
  end;
  if E.Kind = TJsonCodeGenNodeKind.StringValue then
  begin
    if not JsonStringValue(Raw, S) then Exit;
    if FOptions.FormatKind = TJsonCodeGenFormatKind.NativeTypes then
    begin
      if SameText(E.FormatName, 'uuid') then Exit('TGUID.Create(' + TJsonCodeGenNameAllocator.DelphiString('{' + S.Trim(['{','}']) + '}') + ')');
      if SameText(E.FormatName, 'date-time') or SameText(E.FormatName, 'date') or SameText(E.FormatName, 'time') then begin AddUse('System.DateUtils'); Exit('ISO8601ToDate(' + TJsonCodeGenNameAllocator.DelphiString(S) + ', False)'); end;
    end;
    Exit(TJsonCodeGenNameAllocator.DelphiString(S));
  end;
  if E.Kind = TJsonCodeGenNodeKind.IntegerValue then if JsonIntegerValue(Raw, I) then Exit(IntToStr(I));
  if E.Kind = TJsonCodeGenNodeKind.NumberValue then Exit(PascalFloat(Raw));
  if E.Kind = TJsonCodeGenNodeKind.BooleanValue then if JsonBooleanValue(Raw, B) then if B then Exit('True') else Exit('False');
  if DelphiType(E) = 'Variant' then
  begin
    AddUse('System.Variants');
    if JsonStringValue(Raw, S) then Exit(TJsonCodeGenNameAllocator.DelphiString(S));
    if JsonIntegerValue(Raw, I) then Exit(IntToStr(I));
    if JsonBooleanValue(Raw, B) then if B then Exit('True') else Exit('False');
  end;
end;

function TJsonCodeGenDelphiEmitter.NeedsConstructor(Node: TJsonCodeGenNode): Boolean;
var
  P: TJsonCodeGenProperty;
begin
  Result := False;
  if not IsClassNode(Node) or not FOptions.EmitDefaults then Exit;
  for P in Node.Properties do
    if (P.Node <> nil) and P.Node.HasDefault then
    begin
      if DefaultExpression(P.Node, P.Node.DefaultRaw) <> '' then Result := True
      else if not SameText(P.Node.DefaultRaw, 'null') then
        WarnOnce('default:' + P.SchemaPath, 'CG110', P.SchemaPath, 'This default value cannot be emitted as a Delphi constructor assignment and remains in the embedded schema');
    end;
end;

function TJsonCodeGenDelphiEmitter.NeedsDestructor(Node: TJsonCodeGenNode): Boolean;
var
  P: TJsonCodeGenProperty;
begin
  Result := False;
  if not IsClassNode(Node) or not FOptions.OwnsGeneratedObjects then Exit;
  for P in Node.Properties do if MemberNeedsFree(P.Node) then Exit(True);
end;

procedure TJsonCodeGenDelphiEmitter.WriteObjectDeclaration(B: TStringBuilder; Node: TJsonCodeGenNode);
var
  P: TJsonCodeGenProperty;
  T: string;
  HasCtor, HasDtor: Boolean;
begin
  if IsDictionaryNode(Node) or IsFallbackObjectNode(Node) then begin WriteAliasDeclaration(B, Node); Exit; end;
  if (Node.Properties.Count > 0) and Node.AdditionalPropertiesAllowed then WarnOnce('additional-properties:' + Node.Key, 'CG111', Node.SchemaPath, 'Additional object properties cannot be retained beside fixed Delphi members and remain enforced only by the embedded schema/runtime validator');
  WriteTypeAttributes(B, Node, 1);
  if IsRecordNode(Node) then
  begin
    B.Append(Indent(1)).Append(Node.TypeName).AppendLine(' = record');
    for P in Node.Properties do
    begin
      WriteMemberAttributes(B, P, 2);
      T := DelphiType(P.Node);
      B.Append(Indent(2)).Append(P.DelphiName).Append(': ').Append(T).AppendLine(';');
    end;
    B.Append(Indent(1)).AppendLine('end;');
    Exit;
  end;
  HasCtor := NeedsConstructor(Node);
  HasDtor := NeedsDestructor(Node);
  B.Append(Indent(1)).Append(Node.TypeName).AppendLine(' = class');
  if Node.Properties.Count > 0 then
  begin
    B.Append(Indent(1)).AppendLine('private');
    for P in Node.Properties do
    begin
      T := DelphiType(P.Node);
      B.Append(Indent(2)).Append('F').Append(StringReplace(P.DelphiName, '&', '', [rfReplaceAll])).Append(': ').Append(T).AppendLine(';');
    end;
  end;
  B.Append(Indent(1)).AppendLine('public');
  if HasCtor then B.Append(Indent(2)).AppendLine('constructor Create;');
  if HasDtor then B.Append(Indent(2)).AppendLine('destructor Destroy; override;');
  for P in Node.Properties do
  begin
    WriteMemberAttributes(B, P, 2);
    T := DelphiType(P.Node);
    B.Append(Indent(2)).Append('property ').Append(P.DelphiName).Append(': ').Append(T).Append(' read F').Append(StringReplace(P.DelphiName, '&', '', [rfReplaceAll])).Append(' write F').Append(StringReplace(P.DelphiName, '&', '', [rfReplaceAll])).AppendLine(';');
  end;
  B.Append(Indent(1)).AppendLine('end;');
end;

procedure TJsonCodeGenDelphiEmitter.WriteEnumDeclaration(B: TStringBuilder; Node: TJsonCodeGenNode);
var
  Raw, Id: string;
  I: Integer;
begin
  if SafeEnum(Node) then
  begin
    B.Append(Indent(1)).Append(Node.TypeName).Append(' = (');
    for I := 0 to Node.EnumRawValues.Count - 1 do
    begin
      Raw := Node.EnumRawValues[I];
      EnumIdentifier(Raw, Id);
      if I > 0 then B.Append(', ');
      B.Append(Id);
    end;
    B.AppendLine(');');
  end
  else
  begin
    B.Append(Indent(1)).Append(Node.TypeName).Append(' = ').Append(EnumBaseType(Node)).AppendLine(';');
    FUnsafeEnums.Add(Node);
  end;
end;

procedure TJsonCodeGenDelphiEmitter.WriteAliasDeclaration(B: TStringBuilder; Node: TJsonCodeGenNode);
var
  SavedName, T: string;
begin
  SavedName := Node.TypeName;
  Node.TypeName := '';
  try
    if Node.Recursive and not IsClassNode(Node) then
    begin
      WarnOnce('recursive-alias:' + Node.Key, 'CG112', Node.SchemaPath, 'Recursive non-object schema cannot be represented as a Delphi alias and uses the configured fallback type ' + FOptions.UnknownType);
      T := FOptions.UnknownType;
    end
    else T := DelphiType(Node);
  finally
    Node.TypeName := SavedName;
  end;
  B.Append(Indent(1)).Append(SavedName).Append(' = ').Append(T).AppendLine(';');
end;

procedure TJsonCodeGenDelphiEmitter.WriteNodeDeclaration(B: TStringBuilder; Node: TJsonCodeGenNode);
begin
  if Node = nil then Exit;
  if Node.Kind = TJsonCodeGenNodeKind.ObjectValue then WriteObjectDeclaration(B, Node)
  else if Node.Kind = TJsonCodeGenNodeKind.EnumValue then WriteEnumDeclaration(B, Node)
  else WriteAliasDeclaration(B, Node);
end;

procedure TJsonCodeGenDelphiEmitter.WriteForwardDeclarations(B: TStringBuilder);
var
  N: TJsonCodeGenNode;
  Wrote: Boolean;
begin
  Wrote := False;
  for N in FModel.Nodes do
    if (EffectiveNode(N) = N) and (N.TypeName <> '') and IsClassNode(N) then
    begin
      Wrote := True;
      B.Append(Indent(1)).Append(N.TypeName).AppendLine(' = class;');
    end;
  if Wrote then B.AppendLine;
end;

procedure TJsonCodeGenDelphiEmitter.CollectDependencies(Node: TJsonCodeGenNode; Dependencies: TList<TJsonCodeGenNode>);
var
  P: TJsonCodeGenProperty;
  N: TJsonCodeGenNode;

  procedure AddDependency(Candidate: TJsonCodeGenNode);
  var
    E: TJsonCodeGenNode;
  begin
    E := EffectiveNode(Candidate);
    if (E <> nil) and (E.TypeName <> '') and not IsClassNode(E) and (Dependencies.IndexOf(E) < 0) then Dependencies.Add(E);
  end;

begin
  if Node = nil then Exit;
  if Node.Kind = TJsonCodeGenNodeKind.ObjectValue then for P in Node.Properties do AddDependency(P.Node);
  if Node.Kind = TJsonCodeGenNodeKind.ArrayValue then AddDependency(Node.ItemType);
  if IsDictionaryNode(Node) then AddDependency(DictionaryValueNode(Node));
  for N in Node.UnionAlternatives do AddDependency(N);
end;

function TJsonCodeGenDelphiEmitter.NonClassNodes: TArray<TJsonCodeGenNode>;
var
  L: TList<TJsonCodeGenNode>;
  N: TJsonCodeGenNode;
begin
  L := TList<TJsonCodeGenNode>.Create;
  try
    for N in FModel.Nodes do if (EffectiveNode(N) = N) and (N.TypeName <> '') and not IsClassNode(N) then L.Add(N);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TJsonCodeGenDelphiEmitter.TopologicalNonClassNodes: TArray<TJsonCodeGenNode>;
var
  Nodes, Output, Deps: TList<TJsonCodeGenNode>;
  InDegree: TDictionary<TJsonCodeGenNode, Integer>;
  N, D: TJsonCodeGenNode;
  I, Degree: Integer;
  Progress: Boolean;
begin
  Nodes := TList<TJsonCodeGenNode>.Create;
  Output := TList<TJsonCodeGenNode>.Create;
  InDegree := TDictionary<TJsonCodeGenNode, Integer>.Create;
  try
    Nodes.AddRange(NonClassNodes);
    for N in Nodes do InDegree.AddOrSetValue(N, 0);
    for N in Nodes do
    begin
      Deps := TList<TJsonCodeGenNode>.Create;
      try
        CollectDependencies(N, Deps);
        for D in Deps do if (D <> N) and InDegree.ContainsKey(D) then InDegree[N] := InDegree[N] + 1;
      finally
        Deps.Free;
      end;
    end;
    while Output.Count < Nodes.Count do
    begin
      Progress := False;
      for I := 0 to Nodes.Count - 1 do
      begin
        N := Nodes[I];
        if Output.Contains(N) or (InDegree[N] <> 0) then Continue;
        Output.Add(N);
        Progress := True;
        for D in Nodes do
        begin
          if Output.Contains(D) then Continue;
          Deps := TList<TJsonCodeGenNode>.Create;
          try
            CollectDependencies(D, Deps);
            if Deps.Contains(N) then begin Degree := InDegree[D]; if Degree > 0 then InDegree[D] := Degree - 1; end;
          finally
            Deps.Free;
          end;
        end;
      end;
      if not Progress then
      begin
        for N in Nodes do if not Output.Contains(N) then begin Output.Add(N); WarnOnce('decl-cycle:' + N.Key, 'CG107', N.SchemaPath, 'A non-class declaration cycle was detected; declaration order is best-effort'); end;
      end;
    end;
    Result := Output.ToArray;
  finally
    InDegree.Free;
    Output.Free;
    Nodes.Free;
  end;
end;

procedure TJsonCodeGenDelphiEmitter.WriteNonClassDeclarations(B: TStringBuilder);
var
  Nodes: TArray<TJsonCodeGenNode>;
  N: TJsonCodeGenNode;
begin
  Nodes := TopologicalNonClassNodes;
  if Length(Nodes) = 0 then Exit;
  for N in Nodes do
  begin
    WriteNodeDeclaration(B, N);
    B.AppendLine;
  end;
end;

procedure TJsonCodeGenDelphiEmitter.WriteClassDeclarations(B: TStringBuilder);
var
  N: TJsonCodeGenNode;
  Any: Boolean;
begin
  Any := False;
  for N in FModel.Nodes do if (EffectiveNode(N) = N) and (N.TypeName <> '') and IsClassNode(N) then begin Any := True; Break; end;
  if not Any then Exit;
  for N in FModel.Nodes do
    if (EffectiveNode(N) = N) and (N.TypeName <> '') and IsClassNode(N) then
    begin
      WriteObjectDeclaration(B, N);
      B.AppendLine;
    end;
end;

procedure TJsonCodeGenDelphiEmitter.WriteEnumConstants(B: TStringBuilder);
var
  N: TJsonCodeGenNode;
  Raw, S, Name, Base, BaseType: string;
  I: Integer;
  IntV: Int64;
  BoolV: Boolean;
  EmittedHeader: Boolean;
begin
  if FUnsafeEnums.Count = 0 then Exit;
  EmittedHeader := False;
  for N in FUnsafeEnums do
  begin
    BaseType := EnumBaseType(N);
    if SameText(BaseType, FOptions.UnknownType) then
    begin
      WarnOnce('enum-constants:' + N.Key, 'CG108', N.SchemaPath, 'Mixed enum values use the fallback Delphi type; typed constants are omitted because Delphi cannot represent every JSON literal as a compile-time constant');
      Continue;
    end;
    Base := N.TypeName;
    if Base.StartsWith('T') and (Length(Base) > 1) then Delete(Base, 1, 1);
    for I := 0 to N.EnumRawValues.Count - 1 do
    begin
      Raw := N.EnumRawValues[I];
      if JsonStringValue(Raw, S) then Name := 'C' + TJsonCodeGenNameAllocator.DelphiIdentifier(Base + ' ' + S, True) + '_' + IntToStr(I + 1)
      else Name := 'C' + TJsonCodeGenNameAllocator.DelphiIdentifier(Base + ' Value', True) + '_' + IntToStr(I + 1);
      if not JsonStringValue(Raw, S) and not JsonIntegerValue(Raw, IntV) and not JsonBooleanValue(Raw, BoolV) and not JsonNumberValue(Raw) then Continue;
      if not EmittedHeader then begin B.AppendLine('const'); EmittedHeader := True; end;
      B.Append(Indent(1)).Append(Name).Append(': ').Append(N.TypeName).Append(' = ');
      if JsonStringValue(Raw, S) then B.Append(TJsonCodeGenNameAllocator.DelphiString(S))
      else if JsonIntegerValue(Raw, IntV) then B.Append(IntToStr(IntV))
      else if JsonBooleanValue(Raw, BoolV) then if BoolV then B.Append('True') else B.Append('False')
      else B.Append(PascalFloat(Raw));
      B.AppendLine(';');
    end;
  end;
  if EmittedHeader then B.AppendLine;
end;

procedure TJsonCodeGenDelphiEmitter.WriteEmbeddedSchema(B: TStringBuilder);
var
  S, Chunk: string;
  P, N: Integer;
begin
  if not FOptions.EmbedSchema or (FModel.OriginalSchema = '') then Exit;
  S := FModel.OriginalSchema;
  B.AppendLine('const');
  B.AppendLine('  CJsonSchema: string =');
  P := 1;
  while P <= Length(S) do
  begin
    N := Min(100, Length(S) - P + 1);
    Chunk := Copy(S, P, N);
    Inc(P, N);
    B.Append(Indent(2)).Append(TJsonCodeGenNameAllocator.DelphiString(Chunk));
    if P <= Length(S) then B.AppendLine(' +') else B.AppendLine(';');
  end;
  if S = '' then B.AppendLine('    '''';');
  B.AppendLine;
end;

procedure TJsonCodeGenDelphiEmitter.WriteClassImplementation(B: TStringBuilder; Node: TJsonCodeGenNode);
var
  P: TJsonCodeGenProperty;
  E, Item, V: TJsonCodeGenNode;
  Expr, Field, LocalName: string;
  HasVars: Boolean;
begin
  if not IsClassNode(Node) then Exit;
  if NeedsConstructor(Node) then
  begin
    B.Append('constructor ').Append(Node.TypeName).AppendLine('.Create;');
    B.AppendLine('begin');
    B.Append(Indent(1)).AppendLine('inherited Create;');
    for P in Node.Properties do
      if (P.Node <> nil) and P.Node.HasDefault then
      begin
        Expr := DefaultExpression(P.Node, P.Node.DefaultRaw);
        if Expr <> '' then
        begin
          Field := 'F' + StringReplace(P.DelphiName, '&', '', [rfReplaceAll]);
          B.Append(Indent(1)).Append(Field).Append(' := ').Append(Expr).AppendLine(';');
        end
        else WarnOnce('default:' + P.SchemaPath, 'CG110', P.SchemaPath, 'This default value cannot be emitted as a Delphi constructor assignment and remains in the embedded schema');
      end;
    B.AppendLine('end;');
    B.AppendLine;
  end;
  if NeedsDestructor(Node) then
  begin
    B.Append('destructor ').Append(Node.TypeName).AppendLine('.Destroy;');
    HasVars := False;
    for P in Node.Properties do if MemberNeedsArrayItemFree(P.Node) or MemberNeedsDictionaryValueFree(P.Node) then begin HasVars := True; Break; end;
    if HasVars then
    begin
      B.AppendLine('var');
      for P in Node.Properties do
      begin
        LocalName := StringReplace(P.DelphiName, '&', '', [rfReplaceAll]);
        if MemberNeedsArrayItemFree(P.Node) then B.Append(Indent(1)).Append('L').Append(LocalName).AppendLine(': Integer;');
        if MemberNeedsDictionaryValueFree(P.Node) then
        begin
          E := EffectiveNode(P.Node);
          V := EffectiveNode(DictionaryValueNode(E));
          B.Append(Indent(1)).Append('L').Append(LocalName).Append('Value: ').Append(DelphiType(V)).AppendLine(';');
        end;
      end;
    end;
    B.AppendLine('begin');
    for P in Node.Properties do
    begin
      if not MemberNeedsFree(P.Node) then Continue;
      LocalName := StringReplace(P.DelphiName, '&', '', [rfReplaceAll]);
      Field := 'F' + LocalName;
      E := EffectiveNode(P.Node);
      if MemberNeedsArrayItemFree(P.Node) then
      begin
        Item := EffectiveNode(E.ItemType);
        if (Item <> nil) and IsClassNode(Item) then B.Append(Indent(1)).Append('for L').Append(LocalName).Append(' := 0 to High(').Append(Field).Append(') do ').Append(Field).Append('[L').Append(LocalName).AppendLine('].Free;');
      end
      else if MemberNeedsDictionaryValueFree(P.Node) then
      begin
        B.Append(Indent(1)).Append('if ').Append(Field).AppendLine(' <> nil then');
        B.Append(Indent(1)).AppendLine('begin');
        B.Append(Indent(2)).Append('for L').Append(LocalName).Append('Value in ').Append(Field).AppendLine('.Values do L' + LocalName + 'Value.Free;');
        B.Append(Indent(2)).Append(Field).AppendLine('.Free;');
        B.Append(Indent(1)).AppendLine('end;');
      end
      else if E.Kind = TJsonCodeGenNodeKind.ArrayValue then
      begin
        if FOptions.ArrayKind = TJsonCodeGenArrayKind.GenericLists then
        begin
          Item := EffectiveNode(E.ItemType);
          if (Item <> nil) and IsClassNode(Item) then
          begin
            B.Append(Indent(1)).Append('while ').Append(Field).Append(' <> nil do begin if ').Append(Field).Append('.Count > 0 then begin ').Append(Field).Append('[').Append(Field).Append('.Count - 1].Free; ').Append(Field).Append('.Delete(').Append(Field).Append('.Count - 1); end else begin ').Append(Field).Append('.Free; ').Append(Field).Append(' := nil; end; end;').AppendLine;
            Continue;
          end;
        end;
        B.Append(Indent(1)).Append(Field).AppendLine('.Free;');
      end
      else B.Append(Indent(1)).Append(Field).AppendLine('.Free;');
    end;
    B.Append(Indent(1)).AppendLine('inherited Destroy;');
    B.AppendLine('end;');
    B.AppendLine;
  end;
end;

procedure TJsonCodeGenDelphiEmitter.WriteImplementation(B: TStringBuilder);
var
  N: TJsonCodeGenNode;
begin
  for N in FModel.Nodes do if (EffectiveNode(N) = N) and IsClassNode(N) then WriteClassImplementation(B, N);
end;

function TJsonCodeGenDelphiEmitter.UsesClause: string;
var
  I: Integer;
  B: TStringBuilder;
begin
  if FUses.Count = 0 then Exit('');
  B := TStringBuilder.Create;
  try
    B.AppendLine('uses');
    for I := 0 to FUses.Count - 1 do
    begin
      B.Append(Indent(1)).Append(FUses[I]);
      if I < FUses.Count - 1 then B.AppendLine(',') else B.AppendLine(';');
    end;
    B.AppendLine;
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

function TJsonCodeGenDelphiEmitter.GenerateTypes: string;
var
  B: TStringBuilder;
  N: TJsonCodeGenNode;
begin
  if FOptions.UnknownTypeUnit <> '' then AddUse(FOptions.UnknownTypeUnit);
  for N in FModel.Nodes do if (EffectiveNode(N) = N) and (N.TypeName <> '') then DelphiType(N);
  B := TStringBuilder.Create;
  try
    if FModel.Nodes.Count > 0 then B.AppendLine('type');
    WriteForwardDeclarations(B);
    WriteNonClassDeclarations(B);
    WriteClassDeclarations(B);
    WriteEnumConstants(B);
    WriteEmbeddedSchema(B);
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

function TJsonCodeGenDelphiEmitter.GenerateUnit(const UnitName: string): string;
var
  B: TStringBuilder;
  Types, Impl: string;
begin
  if Trim(UnitName) = '' then raise EArgumentException.Create('UnitName is required');
  Types := GenerateTypes;
  B := TStringBuilder.Create;
  try
    Impl := '';
    WriteImplementation(B);
    Impl := B.ToString;
    B.Clear;
    B.Append('unit ').Append(UnitName).AppendLine(';');
    B.AppendLine;
    B.AppendLine('interface');
    B.AppendLine;
    B.AppendLine('{$SCOPEDENUMS ON}');
    B.AppendLine;
    B.Append(UsesClause);
    B.Append(Types);
    B.AppendLine('implementation');
    B.AppendLine;
    B.Append(Impl);
    B.AppendLine('end.');
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

function TJsonCodeGenDelphiEmitter.RootTypeName: string;
begin
  if FModel.Root = nil then Exit('');
  Result := DelphiType(FModel.Root);
end;

end.
