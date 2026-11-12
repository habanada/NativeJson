{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Package3.CodeGen.Helpers;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  System.IOUtils,
  StrUtils,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  {$ENDIF}
  DUnitX.TestFramework,
  NativeJson.CodeGen,
  NativeJson.CodeGen.Options,
  NativeJson.CodeGen.Model;

function TypesOf(const Schema: string): string; overload;
function TypesOf(const Schema: string; const Options: TJsonCodeGenOptions): string; overload;
function UnitOf(const Schema, UnitName: string): string; overload;
function UnitOf(const Schema, UnitName: string; const Options: TJsonCodeGenOptions): string; overload;
function DiagnosticsOf(const Schema: string): TArray<TJsonCodeGenDiagnostic>; overload;
function DiagnosticsOf(const Schema: string; const Options: TJsonCodeGenOptions): TArray<TJsonCodeGenDiagnostic>; overload;
function HasDiagnostic(const Diagnostics: TArray<TJsonCodeGenDiagnostic>; const Code: string): Boolean;
function CountDiagnostic(const Diagnostics: TArray<TJsonCodeGenDiagnostic>; const Code: string): Integer;
function CountText(const Text, Fragment: string): Integer;
function NormalizeText(const Text: string): string;
procedure AssertContains(const Text, Fragment: string; const Msg: string = '');
procedure AssertNotContains(const Text, Fragment: string; const Msg: string = '');
procedure AssertBefore(const Text, FirstFragment, SecondFragment: string; const Msg: string = '');
procedure AssertDiagnostic(const Diagnostics: TArray<TJsonCodeGenDiagnostic>; const Code: string);
procedure AssertNoDiagnostic(const Diagnostics: TArray<TJsonCodeGenDiagnostic>; const Code: string);
function TestDataFile(const FileName: string): string;

implementation

function TypesOf(const Schema: string): string;
begin
  Result := TNativeJsonSchemaCodeGenerator.SchemaToTypes(Schema);
end;

function TypesOf(const Schema: string; const Options: TJsonCodeGenOptions): string;
begin
  Result := TNativeJsonSchemaCodeGenerator.SchemaToTypes(Schema, Options);
end;

function UnitOf(const Schema, UnitName: string): string;
begin
  Result := TNativeJsonSchemaCodeGenerator.SchemaToUnit(Schema, UnitName);
end;

function UnitOf(const Schema, UnitName: string; const Options: TJsonCodeGenOptions): string;
begin
  Result := TNativeJsonSchemaCodeGenerator.SchemaToUnit(Schema, UnitName, Options);
end;

function DiagnosticsOf(const Schema: string): TArray<TJsonCodeGenDiagnostic>;
begin
  Result := DiagnosticsOf(Schema, TJsonCodeGenOptions.Default);
end;

function DiagnosticsOf(const Schema: string; const Options: TJsonCodeGenOptions): TArray<TJsonCodeGenDiagnostic>;
var
  Generator: TNativeJsonSchemaCodeGenerator;
begin
  Generator := TNativeJsonSchemaCodeGenerator.Create(Options);
  try
    Generator.LoadSchema(Schema);
    Generator.GenerateTypes;
    Result := Generator.Diagnostics;
  finally
    Generator.Free;
  end;
end;

function HasDiagnostic(const Diagnostics: TArray<TJsonCodeGenDiagnostic>; const Code: string): Boolean;
var
  Diagnostic: TJsonCodeGenDiagnostic;
begin
  for Diagnostic in Diagnostics do if SameText(Diagnostic.Code, Code) then Exit(True);
  Result := False;
end;

function CountDiagnostic(const Diagnostics: TArray<TJsonCodeGenDiagnostic>; const Code: string): Integer;
var
  Diagnostic: TJsonCodeGenDiagnostic;
begin
  Result := 0;
  for Diagnostic in Diagnostics do if SameText(Diagnostic.Code, Code) then Inc(Result);
end;

function CountText(const Text, Fragment: string): Integer;
var
  P, StartAt: Integer;
begin
  Result := 0;
  if Fragment = '' then Exit;
  StartAt := 1;
  repeat
    P := PosEx(Fragment, Text, StartAt);
    if P = 0 then Break;
    Inc(Result);
    StartAt := P + Length(Fragment);
  until False;
end;

function NormalizeText(const Text: string): string;
begin
  Result := StringReplace(StringReplace(Text, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
end;

procedure AssertContains(const Text, Fragment, Msg: string);
begin
  if Msg = '' then Assert.IsTrue(Pos(Fragment, Text) > 0, 'Missing fragment: ' + Fragment) else Assert.IsTrue(Pos(Fragment, Text) > 0, Msg);
end;

procedure AssertNotContains(const Text, Fragment, Msg: string);
begin
  if Msg = '' then Assert.IsTrue(Pos(Fragment, Text) = 0, 'Unexpected fragment: ' + Fragment) else Assert.IsTrue(Pos(Fragment, Text) = 0, Msg);
end;

procedure AssertBefore(const Text, FirstFragment, SecondFragment, Msg: string);
var
  A, B: Integer;
begin
  A := Pos(FirstFragment, Text);
  B := Pos(SecondFragment, Text);
  if Msg = '' then Assert.IsTrue((A > 0) and (B > 0) and (A < B), FirstFragment + ' must appear before ' + SecondFragment) else Assert.IsTrue((A > 0) and (B > 0) and (A < B), Msg);
end;

procedure AssertDiagnostic(const Diagnostics: TArray<TJsonCodeGenDiagnostic>; const Code: string);
begin
  Assert.IsTrue(HasDiagnostic(Diagnostics, Code), 'Expected diagnostic ' + Code);
end;

procedure AssertNoDiagnostic(const Diagnostics: TArray<TJsonCodeGenDiagnostic>; const Code: string);
begin
  Assert.IsTrue(not HasDiagnostic(Diagnostics, Code), 'Unexpected diagnostic ' + Code);
end;

function TestDataFile(const FileName: string): string;
var
  Dir, Parent: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Result := TPath.Combine(TPath.Combine(Dir, 'Data'), FileName);
  while not TFile.Exists(Result) do
  begin
    Result := TPath.Combine(TPath.Combine(TPath.Combine(TPath.Combine(Dir, 'Tests'), 'Package3'), 'Data'), FileName);
    if TFile.Exists(Result) then Exit;
    Parent := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if (Parent = '') or (Parent = Dir) then Break;
    Dir := Parent;
  end;
end;

end.
