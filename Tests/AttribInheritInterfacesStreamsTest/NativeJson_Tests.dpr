{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_Tests;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

{$R *.res}

uses
  SysUtils,
  Test.Logistics.Model in 'Test.Logistics.Model.pas',
  Test.Runner in 'Test.Runner.pas',
  
  // Framework units (so the compiler finds them)
  NativeJson.Main in '..\..\src\NativeJson.Main.pas',
  NativeJson.Attributes in '..\..\src\NativeJson.Attributes.pas',
  NativeJson.Schema.Attributes in '..\..\src\NativeJson.Schema.Attributes.pas',
  NativeJson.Fluent in '..\..\src\NativeJson.Fluent.pas',
  NativeJson.Rtti.Cache in '..\..\src\NativeJson.Rtti.Cache.pas',
  NativeJson.Schema.Generator in '..\..\src\NativeJson.Schema.Generator.pas',
  NativeJson.Serializer.Core in '..\..\src\NativeJson.Serializer.Core.pas',
  NativeJson.Deserializer.Core in '..\..\src\NativeJson.Deserializer.Core.pas',
  NativeJson.Dynamic in '..\..\src\NativeJson.Dynamic.pas';

begin
  try
    RunComplexSuite;
    ReadLn;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.