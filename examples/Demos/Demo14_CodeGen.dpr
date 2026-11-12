{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo14_CodeGen;

{$I NativeJson.inc}

// DEMO 14 - GENERATING DELPHI CODE FROM A JSON SCHEMA
//
//   Test package 3 covers the generator with 188 cases, but needs
//   DUnitX for that. This demo runs without anything and answers the one
//   question you ask first: does compilable code come out at all,
//   and are the types right?
//
//   If this demo is green, the route
//   schema -> model -> Delphi source works in principle.

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Demo.Assert in 'Demo.Assert.pas',
  NativeJson.CodeGen,
  NativeJson.CodeGen.Options,
  NativeJson.CodeGen.Model;

const
  Body = '{"type":"object","additionalProperties":false,"properties":{';
  Finish = '}}';

function TypeList(const Schema: string): string; overload;
begin
  Result := TNativeJsonSchemaCodeGenerator.SchemaToTypes(Schema);
end;

function TypeList(const Schema: string; const Opts: TJsonCodeGenOptions): string; overload;
begin
  Result := TNativeJsonSchemaCodeGenerator.SchemaToTypes(Schema, Opts);
end;

function Fld(const Prop: string): string;
begin
  Result := TypeList(Body + Prop + Finish);
end;

function Messages(const Schema: string): TArray<TJsonCodeGenDiagnostic>;
var
  Gen: TNativeJsonSchemaCodeGenerator;
begin
  Gen := TNativeJsonSchemaCodeGenerator.Create;
  try
    Gen.LoadSchema(Schema);
    Gen.GenerateTypes;
    Result := Gen.Diagnostics;
  finally
    Gen.Free;
  end;
end;

function HasMessage(const Schema, Code: string): Boolean;
var
  D: TJsonCodeGenDiagnostic;
begin
  for D in Messages(Schema) do
    if SameText(D.Code, Code) then Exit(True);
  Result := False;
end;

// ---------------------------------------------------------------------------

procedure Step1_SimpleTypes;
begin
  Section('1. A schema field becomes a Delphi field');
  CheckContains('string', 'FValue: string;', Fld('"value":{"type":"string"}'));
  CheckContains('boolean', 'FValue: Boolean;', Fld('"value":{"type":"boolean"}'));
  CheckContains('number', 'FValue: Double;', Fld('"value":{"type":"number"}'));
end;

procedure Step2_IntegersByRange;
begin
  Section('2. The integer width follows the bounds in the schema');
  Writeln('       Without bounds it has to be Int64 - a JSON integer has');
  Writeln('       no upper limit. Only when the schema narrows the range');
  Writeln('       may it be Integer.');

  CheckContains('without bounds: Int64', 'FValue: Int64;',
    Fld('"value":{"type":"integer"}'));
  CheckContains('with bounds: Integer', 'FValue: Integer;',
    Fld('"value":{"type":"integer","minimum":0,"maximum":100}'));
  CheckContains('format int32', 'FValue: Integer;',
    Fld('"value":{"type":"integer","format":"int32"}'));
  CheckContains('format int64', 'FValue: Int64;',
    Fld('"value":{"type":"integer","format":"int64"}'));
end;

procedure Step3_Formats;
var
  Opts: TJsonCodeGenOptions;
begin
  Section('3. format becomes a real Delphi type');
  CheckContains('date-time', 'FValue: TDateTime;',
    Fld('"value":{"type":"string","format":"date-time"}'));
  CheckContains('date', 'FValue: TDate;',
    Fld('"value":{"type":"string","format":"date"}'));
  CheckContains('uuid', 'FValue: TGUID;',
    Fld('"value":{"type":"string","format":"uuid"}'));

  // Whoever wants the raw form switches the formats off.
  Opts := TJsonCodeGenOptions.Default.SetFormatKind(TJsonCodeGenFormatKind.StringsOnly);
  CheckContains('switched off everything stays string', 'FValue: string;',
    TypeList(Body + '"value":{"type":"string","format":"date-time"}' + Finish, Opts));
end;

procedure Step4_ListsAndReferences;
var
  Code: string;
begin
  Section('4. Lists and $ref');
  CheckContains('List of text', 'FTags: TArray<string>;',
    Fld('"tags":{"type":"array","items":{"type":"string"}}'));

  Code := TypeList('{"$defs":{"Address":{"type":"object","properties":' +
    '{"city":{"type":"string"}}}},"type":"object","properties":' +
    '{"home":{"$ref":"#/$defs/Address"}}}');
  Show('Output', StringReplace(Code, sLineBreak, ' | ', [rfReplaceAll]));
  CheckContains('The definition becomes its own type', 'TAddress', Code);
  CheckContains('and is used as the field type', 'FHome: TAddress;', Code);
  // A class is forward-declared before any member refers to it,
  // otherwise the generated code does not compile.
  CheckTrue('TAddress is declared before its first use',
    Pos('TAddress = class;', Code) < Pos('FHome: TAddress', Code),
    Format('%d before %d', [Pos('TAddress = class;', Code), Pos('FHome: TAddress', Code)]));
end;

procedure Step5_Enumeration;
var
  Code: string;
begin
  Section('5. enum becomes a Delphi enumeration');
  Code := Fld('"state":{"type":"string","enum":["open","closed"]}');
  Show('Output', StringReplace(Code, sLineBreak, ' | ', [rfReplaceAll]));
  CheckContains('Enumeration type is created', ' = (', Code);
  // The values keep the spelling from the schema: the generator
  // calls DelphiIdentifier here without PascalCase, so that the code
  // shows recognizably what was in the JSON.
  CheckContains('with the first value', 'open', Code);
  CheckContains('and the second', 'closed', Code);
end;

procedure Step6_Names;
begin
  Section('6. JSON names that do not work in Delphi');
  Writeln('       A reserved word or a hyphen must not make the');
  Writeln('       generated code uncompilable.');

  CheckContains('Hyphen is joined', 'FTypeName: string;',
    Fld('"type-name":{"type":"string"}'));
  CheckContains('The JSON name is kept in the attribute', 'type-name',
    Fld('"type-name":{"type":"string"}'));
  // 'type' is a reserved word. The generator has to defuse it,
  // otherwise the generated code does not compile.
  CheckContains('reserved word is escaped', '&Type',
    Fld('"type":{"type":"string"}'));
end;

procedure Step7_WholeUnit;
var
  Code: string;
begin
  Section('7. A complete unit');
  Code := TNativeJsonSchemaCodeGenerator.SchemaToUnit(
    Body + '"name":{"type":"string"},"age":{"type":"integer","minimum":0,"maximum":150}' + Finish,
    'Demo.Models');
  Writeln;
  Writeln(Code);
  Writeln;
  CheckContains('Unit header', 'unit Demo.Models;', Code);
  CheckContains('interface', 'interface', Code);
  CheckContains('implementation', 'implementation', Code);
  CheckContains('End', 'end.', Code);
  CheckContains('Name as string', 'FName: string;', Code);
  CheckContains('Age as Integer', 'FAge: Integer;', Code);
end;

procedure Step8_MessagesInsteadOfSilence;
begin
  Section('8. What the generator cannot represent, it says');
  Writeln('       A schema can express more than a Delphi type.');
  Writeln('       The difference must not disappear silently.');

  CheckTrue('nullable without an equivalent is reported',
    HasMessage('{"type":["string","null"]}', 'CG103'), '');
  CheckTrue('a valid simple schema reports nothing of the kind',
    not HasMessage(Body + '"value":{"type":"string"}' + Finish, 'CG103'), '');
end;

procedure Step9_InvalidFailsLoudly;
begin
  Section('9. Invalid JSON must be noticed');
  CheckError('truncated schema',
    procedure
    begin
      TNativeJsonSchemaCodeGenerator.SchemaToTypes('{"type":"object","properties":');
    end);
  CheckError('no JSON at all',
    procedure
    begin
      TNativeJsonSchemaCodeGenerator.SchemaToTypes('{broken');
    end);
  CheckError('empty schema',
    procedure
    begin
      TNativeJsonSchemaCodeGenerator.SchemaToTypes('');
    end);
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 14 - JSON SCHEMA TO DELPHI CODE');

    Step1_SimpleTypes;
    Step2_IntegersByRange;
    Step3_Formats;
    Step4_ListsAndReferences;
    Step5_Enumeration;
    Step6_Names;
    Step7_WholeUnit;
    Step8_MessagesInsteadOfSilence;
    Step9_InvalidFailsLoudly;

    ExitCode := Summary;
  except
    on E: Exception do
    begin
      Writeln('ABORTED: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
  if ParamCount = 0 then
  begin
    Writeln;
    Writeln('Press Enter ...');
    Readln;
  end;
end.
