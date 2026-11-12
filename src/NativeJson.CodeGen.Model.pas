{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.CodeGen.Model;

interface

{$I NativeJson.inc}

{$SCOPEDENUMS ON}

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE}
  System.SysUtils,
  {$ENDIF}
  NativeJson.Dom.Value,
  {$IFDEF FPC}
  Generics.Collections;
  {$ELSE}
  System.Generics.Collections;
  {$ENDIF}

type
  TJsonCodeGenSchemaVersion = (Unknown, Draft07, Draft2019_09, Draft2020_12, OpenApi30, OpenApi31);
  TJsonCodeGenDiagnosticSeverity = (Info, Warning, Error);
  TJsonCodeGenNodeKind = (AnyValue, NullValue, BooleanValue, IntegerValue, NumberValue, StringValue, ObjectValue, ArrayValue, EnumValue, UnionValue, ReferenceValue);
  TJsonCodeGenPrimitive = (NullPrimitive, BooleanPrimitive, IntegerPrimitive, NumberPrimitive, StringPrimitive, ObjectPrimitive, ArrayPrimitive);
  TJsonCodeGenPrimitives = set of TJsonCodeGenPrimitive;

  TJsonCodeGenDiagnostic = record
  public
    Severity: TJsonCodeGenDiagnosticSeverity;
    Code: string;
    SchemaPath: string;
    MessageText: string;
    class function Create(ASeverity: TJsonCodeGenDiagnosticSeverity; const ACode, APath, AMessage: string): TJsonCodeGenDiagnostic; static;
  end;

  TJsonCodeGenNode = class;

  TJsonCodeGenProperty = class
  public
    JsonName: string;
    DelphiName: string;
    Node: TJsonCodeGenNode;
    Required: Boolean;
    SchemaPath: string;
    constructor Create(const AJsonName, APath: string; ANode: TJsonCodeGenNode; ARequired: Boolean);
  end;

  TJsonCodeGenNode = class
  public
    Key: string;
    SchemaPath: string;
    BaseUri: string;
    NameHint: string;
    TypeName: string;
    Kind: TJsonCodeGenNodeKind;
    Primitives: TJsonCodeGenPrimitives;
    RefTarget: TJsonCodeGenNode;
    Properties: TObjectList<TJsonCodeGenProperty>;
    PropertyMap: TDictionary<string, TJsonCodeGenProperty>;
    PrefixItems: TList<TJsonCodeGenNode>;
    UnionAlternatives: TList<TJsonCodeGenNode>;
    ItemType: TJsonCodeGenNode;
    AdditionalPropertiesType: TJsonCodeGenNode;
    AdditionalPropertiesAllowed: Boolean;
    AdditionalPropertiesSpecified: Boolean;
    PatternPropertyTypes: TList<TJsonCodeGenNode>;
    PatternPropertyPatterns: TList<string>;
    AlwaysFalse: Boolean;
    ForceDeclaration: Boolean;
    Omitted: Boolean;
    FromDefinition: Boolean;
    Recursive: Boolean;
    Parsing: Boolean;
    Parsed: Boolean;
    Title: string;
    Description: string;
    FormatName: string;
    Pattern: string;
    HasMinLength: Boolean;
    HasMaxLength: Boolean;
    MinLength: Integer;
    MaxLength: Integer;
    HasMinItems: Boolean;
    HasMaxItems: Boolean;
    MinItems: Integer;
    MaxItems: Integer;
    UniqueItems: Boolean;
    HasMinimum: Boolean;
    HasMaximum: Boolean;
    HasExclusiveMinimum: Boolean;
    HasExclusiveMaximum: Boolean;
    MinimumRaw: string;
    MaximumRaw: string;
    ExclusiveMinimumRaw: string;
    ExclusiveMaximumRaw: string;
    MultipleOfRaw: string;
    HasMultipleOf: Boolean;
    HasDefault: Boolean;
    DefaultRaw: string;
    HasConst: Boolean;
    ConstRaw: string;
    ReadOnly: Boolean;
    WriteOnly: Boolean;
    Deprecated: Boolean;
    EnumRawValues: TList<string>;
    SourceSchema: TJsonValue;
    constructor Create(const AKey, APath, ABaseUri, AHint: string);
    destructor Destroy; override;
    function IsNullable: Boolean;
    function NonNullPrimitives: TJsonCodeGenPrimitives;
    function IsPureReference: Boolean;
    function FindProperty(const Name: string): TJsonCodeGenProperty;
    procedure AddOrMergeProperty(AProperty: TJsonCodeGenProperty);
  end;

  TJsonCodeGenModel = class
  public
    Version: TJsonCodeGenSchemaVersion;
    Root: TJsonCodeGenNode;
    Nodes: TObjectList<TJsonCodeGenNode>;
    Diagnostics: TList<TJsonCodeGenDiagnostic>;
    OriginalSchema: string;
    IsOpenApiDocument: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure AddDiagnostic(Severity: TJsonCodeGenDiagnosticSeverity; const Code, Path, Msg: string);
    function HasErrors: Boolean;
  end;

implementation

class function TJsonCodeGenDiagnostic.Create(ASeverity: TJsonCodeGenDiagnosticSeverity; const ACode, APath, AMessage: string): TJsonCodeGenDiagnostic;
begin
  Result.Severity := ASeverity;
  Result.Code := ACode;
  Result.SchemaPath := APath;
  Result.MessageText := AMessage;
end;

constructor TJsonCodeGenProperty.Create(const AJsonName, APath: string; ANode: TJsonCodeGenNode; ARequired: Boolean);
begin
  inherited Create;
  JsonName := AJsonName;
  SchemaPath := APath;
  Node := ANode;
  Required := ARequired;
end;

constructor TJsonCodeGenNode.Create(const AKey, APath, ABaseUri, AHint: string);
begin
  inherited Create;
  Key := AKey;
  SchemaPath := APath;
  BaseUri := ABaseUri;
  NameHint := AHint;
  Kind := TJsonCodeGenNodeKind.AnyValue;
  Primitives := [];
  AdditionalPropertiesAllowed := True;
  Properties := TObjectList<TJsonCodeGenProperty>.Create(True);
  PropertyMap := TDictionary<string, TJsonCodeGenProperty>.Create;
  PrefixItems := TList<TJsonCodeGenNode>.Create;
  PatternPropertyTypes := TList<TJsonCodeGenNode>.Create;
  PatternPropertyPatterns := TList<string>.Create;
  UnionAlternatives := TList<TJsonCodeGenNode>.Create;
  EnumRawValues := TList<string>.Create;
end;

destructor TJsonCodeGenNode.Destroy;
begin
  EnumRawValues.Free;
  UnionAlternatives.Free;
  PatternPropertyPatterns.Free;
  PatternPropertyTypes.Free;
  PrefixItems.Free;
  PropertyMap.Free;
  Properties.Free;
  inherited;
end;

function TJsonCodeGenNode.IsNullable: Boolean;
begin
  Result := TJsonCodeGenPrimitive.NullPrimitive in Primitives;
end;

function TJsonCodeGenNode.NonNullPrimitives: TJsonCodeGenPrimitives;
begin
  Result := Primitives - [TJsonCodeGenPrimitive.NullPrimitive];
end;

function TJsonCodeGenNode.IsPureReference: Boolean;
begin
  Result := (RefTarget <> nil) and (Kind = TJsonCodeGenNodeKind.ReferenceValue);
end;

function TJsonCodeGenNode.FindProperty(const Name: string): TJsonCodeGenProperty;
begin
  if not PropertyMap.TryGetValue(Name, Result) then Result := nil;
end;

procedure TJsonCodeGenNode.AddOrMergeProperty(AProperty: TJsonCodeGenProperty);
var
  Existing: TJsonCodeGenProperty;
begin
  if AProperty = nil then Exit;
  if PropertyMap.TryGetValue(AProperty.JsonName, Existing) then
  begin
    Existing.Required := Existing.Required or AProperty.Required;
    if (Existing.Node = nil) and (AProperty.Node <> nil) then Existing.Node := AProperty.Node;
    AProperty.Free;
    Exit;
  end;
  Properties.Add(AProperty);
  PropertyMap.Add(AProperty.JsonName, AProperty);
end;

constructor TJsonCodeGenModel.Create;
begin
  inherited Create;
  Version := TJsonCodeGenSchemaVersion.Unknown;
  Nodes := TObjectList<TJsonCodeGenNode>.Create(True);
  Diagnostics := TList<TJsonCodeGenDiagnostic>.Create;
end;

destructor TJsonCodeGenModel.Destroy;
begin
  Diagnostics.Free;
  Nodes.Free;
  inherited;
end;

procedure TJsonCodeGenModel.AddDiagnostic(Severity: TJsonCodeGenDiagnosticSeverity; const Code, Path, Msg: string);
begin
  Diagnostics.Add(TJsonCodeGenDiagnostic.Create(Severity, Code, Path, Msg));
end;

function TJsonCodeGenModel.HasErrors: Boolean;
var
  D: TJsonCodeGenDiagnostic;
begin
  for D in Diagnostics do if D.Severity = TJsonCodeGenDiagnosticSeverity.Error then Exit(True);
  Result := False;
end;

end.
