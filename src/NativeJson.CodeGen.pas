{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.CodeGen;

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
  NativeJson.Compat,
  NativeJson.Dom.Value,
  NativeJson.CodeGen.Options,
  NativeJson.CodeGen.Model,
  NativeJson.CodeGen.Repository;

type
  EJsonCodeGenError = class(Exception);

  TNativeJsonSchemaCodeGenerator = class
  private
    FOptions: TJsonCodeGenOptions;
    FRepository: TJsonCodeGenRepository;
    FRoot: TJsonCodeGenLocation;
    FSchemaText: string;
    FModel: TJsonCodeGenModel;
    procedure BuildModel;
    function GetDiagnostics: TArray<TJsonCodeGenDiagnostic>;
  public
    constructor Create; overload;
    constructor Create(const Options: TJsonCodeGenOptions); overload;
    destructor Destroy; override;
    procedure LoadSchema(const SchemaJson: string; const SourceUri: string = ''); overload;
    procedure LoadSchema(Schema: TJsonValue; const SourceUri: string = ''); overload;
    procedure LoadSchemaFromFile(const FileName: string; const SourceUri: string = '');
    procedure RegisterSchema(const Uri, SchemaJson: string); overload;
    procedure RegisterSchema(const Uri: string; Schema: TJsonValue); overload;
    procedure RegisterSchemaFromFile(const Uri, FileName: string);
    function GenerateTypes: string;
    function GenerateUnit(const UnitName: string): string;
    procedure SaveUnitToFile(const FileName, UnitName: string; Encoding: TEncoding = nil);
    function RootTypeName: string;
    property Options: TJsonCodeGenOptions read FOptions write FOptions;
    property Diagnostics: TArray<TJsonCodeGenDiagnostic> read GetDiagnostics;
    class function SchemaToTypes(const SchemaJson: string): string; overload; static;
    class function SchemaToTypes(const SchemaJson: string; const Options: TJsonCodeGenOptions): string; overload; static;
    class function SchemaToUnit(const SchemaJson, UnitName: string): string; overload; static;
    class function SchemaToUnit(const SchemaJson, UnitName: string; const Options: TJsonCodeGenOptions): string; overload; static;
  end;

implementation

uses
  System.IOUtils,
  NativeJson.CodeGen.Parser,
  NativeJson.CodeGen.Delphi;

constructor TNativeJsonSchemaCodeGenerator.Create;
begin
  inherited Create;
  FOptions := TJsonCodeGenOptions.Default;
  FRepository := TJsonCodeGenRepository.Create;
  FRoot := TJsonCodeGenLocation.Empty;
end;

constructor TNativeJsonSchemaCodeGenerator.Create(const Options: TJsonCodeGenOptions);
begin
  inherited Create;
  FOptions := Options;
  FRepository := TJsonCodeGenRepository.Create;
  FRoot := TJsonCodeGenLocation.Empty;
end;

destructor TNativeJsonSchemaCodeGenerator.Destroy;
begin
  FModel.Free;
  FRepository.Free;
  inherited;
end;

procedure TNativeJsonSchemaCodeGenerator.LoadSchema(const SchemaJson, SourceUri: string);
begin
  if Trim(SchemaJson) = '' then raise EJsonCodeGenError.Create('Schema JSON is empty');
  FModel.Free;
  FModel := nil;
  FSchemaText := SchemaJson;
  FRoot := FRepository.RegisterSchema(SchemaJson, SourceUri);
end;

procedure TNativeJsonSchemaCodeGenerator.LoadSchema(Schema: TJsonValue; const SourceUri: string);
begin
  if Schema = nil then raise EArgumentNilException.Create('Schema');
  FModel.Free;
  FModel := nil;
  FSchemaText := Schema.ToJSON;
  FRoot := FRepository.RegisterSchema(Schema, SourceUri);
end;

procedure TNativeJsonSchemaCodeGenerator.LoadSchemaFromFile(const FileName, SourceUri: string);
begin
  if Trim(FileName) = '' then raise EArgumentException.Create('FileName is required');
  LoadSchema(TFile.ReadAllText(FileName), SourceUri);
end;

procedure TNativeJsonSchemaCodeGenerator.RegisterSchema(const Uri, SchemaJson: string);
begin
  if Trim(Uri) = '' then raise EArgumentException.Create('Uri is required');
  if Trim(SchemaJson) = '' then raise EArgumentException.Create('SchemaJson is required');
  FRepository.RegisterSchema(SchemaJson, Uri);
  FModel.Free;
  FModel := nil;
end;

procedure TNativeJsonSchemaCodeGenerator.RegisterSchema(const Uri: string; Schema: TJsonValue);
begin
  if Trim(Uri) = '' then raise EArgumentException.Create('Uri is required');
  if Schema = nil then raise EArgumentNilException.Create('Schema');
  FRepository.RegisterSchema(Schema, Uri);
  FModel.Free;
  FModel := nil;
end;

procedure TNativeJsonSchemaCodeGenerator.RegisterSchemaFromFile(const Uri, FileName: string);
begin
  if Trim(FileName) = '' then raise EArgumentException.Create('FileName is required');
  RegisterSchema(Uri, TFile.ReadAllText(FileName));
end;

procedure TNativeJsonSchemaCodeGenerator.BuildModel;
var
  Parser: TJsonSchemaCodeGenParser;
begin
  if FRoot.Value = nil then raise EJsonCodeGenError.Create('No schema loaded');
  FModel.Free;
  FModel := nil;
  Parser := TJsonSchemaCodeGenParser.Create(FRepository, FOptions);
  try
    FModel := Parser.Parse(FRoot, FSchemaText);
  finally
    Parser.Free;
  end;
end;

function TNativeJsonSchemaCodeGenerator.GenerateTypes: string;
var
  Emitter: TJsonCodeGenDelphiEmitter;
begin
  BuildModel;
  Emitter := TJsonCodeGenDelphiEmitter.Create(FModel, FOptions);
  try
    Result := Emitter.GenerateTypes;
  finally
    Emitter.Free;
  end;
end;

function TNativeJsonSchemaCodeGenerator.GenerateUnit(const UnitName: string): string;
var
  Emitter: TJsonCodeGenDelphiEmitter;
begin
  BuildModel;
  Emitter := TJsonCodeGenDelphiEmitter.Create(FModel, FOptions);
  try
    Result := Emitter.GenerateUnit(UnitName);
  finally
    Emitter.Free;
  end;
end;

procedure TNativeJsonSchemaCodeGenerator.SaveUnitToFile(const FileName, UnitName: string; Encoding: TEncoding);
var
  OwnEncoding: Boolean;
  Text: string;
begin
  if Trim(FileName) = '' then raise EArgumentException.Create('FileName is required');
  Text := GenerateUnit(UnitName);
  OwnEncoding := Encoding = nil;
  if OwnEncoding then Encoding := JsonCreateUtf8NoBom;
  try
    TFile.WriteAllText(FileName, Text, Encoding);
  finally
    if OwnEncoding then Encoding.Free;
  end;
end;

function TNativeJsonSchemaCodeGenerator.RootTypeName: string;
var
  Emitter: TJsonCodeGenDelphiEmitter;
begin
  BuildModel;
  Emitter := TJsonCodeGenDelphiEmitter.Create(FModel, FOptions);
  try
    Result := Emitter.RootTypeName;
  finally
    Emitter.Free;
  end;
end;

function TNativeJsonSchemaCodeGenerator.GetDiagnostics: TArray<TJsonCodeGenDiagnostic>;
begin
  if FModel = nil then BuildModel;
  Result := FModel.Diagnostics.ToArray;
end;

class function TNativeJsonSchemaCodeGenerator.SchemaToTypes(const SchemaJson: string): string;
begin
  Result := SchemaToTypes(SchemaJson, TJsonCodeGenOptions.Default);
end;

class function TNativeJsonSchemaCodeGenerator.SchemaToTypes(const SchemaJson: string; const Options: TJsonCodeGenOptions): string;
var
  Generator: TNativeJsonSchemaCodeGenerator;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create(Options);
  try
    Generator.LoadSchema(SchemaJson);
    Result := Generator.GenerateTypes;
  finally
    Generator.Free;
  end;
end;

class function TNativeJsonSchemaCodeGenerator.SchemaToUnit(const SchemaJson, UnitName: string): string;
begin
  Result := SchemaToUnit(SchemaJson, UnitName, TJsonCodeGenOptions.Default);
end;

class function TNativeJsonSchemaCodeGenerator.SchemaToUnit(const SchemaJson, UnitName: string; const Options: TJsonCodeGenOptions): string;
var
  Generator: TNativeJsonSchemaCodeGenerator;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create(Options);
  try
    Generator.LoadSchema(SchemaJson);
    Result := Generator.GenerateUnit(UnitName);
  finally
    Generator.Free;
  end;
end;

end.
