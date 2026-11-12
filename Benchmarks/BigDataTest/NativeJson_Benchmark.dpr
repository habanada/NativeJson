{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_Benchmark;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

{$R *.res}

uses
  SysUtils,
  Bench.Model in 'Bench.Model.pas',
  Bench.Core in 'Bench.Core.pas',
  NativeJson.Main in '..\..\src\NativeJson.Main.pas',
  NativeJson.Attributes in '..\..\src\NativeJson.Attributes.pas',
  NativeJson.Serializer.Core in '..\..\src\NativeJson.Serializer.Core.pas',
  NativeJson.Serializer.Writer in '..\..\src\NativeJson.Serializer.Writer.pas',
  NativeJson.Deserializer.Core in '..\..\src\NativeJson.Deserializer.Core.pas',
  NativeJson.Rtti.Cache in '..\..\src\NativeJson.Rtti.Cache.pas',
  NativeJson.Fluent in '..\..\src\NativeJson.Fluent.pas',
  NativeJson.Settings in '..\..\src\NativeJson.Settings.pas';

begin
  try
    TBenchmark.RunHighPressureTest;
    Writeln;
    Writeln('Benchmark complete. Press Enter.');
    ReadLn;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.