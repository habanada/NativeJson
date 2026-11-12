{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Package3_CodeGen;

{$I NativeJson.inc}

{$IFNDEF TESTINSIGHT}
  {$APPTYPE CONSOLE}
{$ENDIF}

{$STRONGLINKTYPES ON}

uses
  SysUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ELSE}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  {$ENDIF}
  DUnitX.TestFramework,
  Package3.CodeGen.Helpers in 'Source\Package3.CodeGen.Helpers.pas',
  Package3.CodeGen.Types in 'Source\Package3.CodeGen.Types.pas',
  Package3.CodeGen.Naming in 'Source\Package3.CodeGen.Naming.pas',
  Package3.CodeGen.Collections in 'Source\Package3.CodeGen.Collections.pas',
  Package3.CodeGen.References in 'Source\Package3.CodeGen.References.pas',
  Package3.CodeGen.Composition in 'Source\Package3.CodeGen.Composition.pas',
  Package3.CodeGen.OpenApi in 'Source\Package3.CodeGen.OpenApi.pas',
  Package3.CodeGen.Output in 'Source\Package3.CodeGen.Output.pas',
  Package3.CodeGen.Ownership in 'Source\Package3.CodeGen.Ownership.pas',
  Package3.CodeGen.Diagnostics in 'Source\Package3.CodeGen.Diagnostics.pas',
  Package3.CodeGen.RepositoryTests in 'Source\Package3.CodeGen.RepositoryTests.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
  XmlLogger: ITestLogger;
begin
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
  Exit;
{$ENDIF}
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Logger := TDUnitXConsoleLogger.Create(True);
    Runner.AddLogger(Logger);
    XmlLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    Runner.AddLogger(XmlLogger);
    Runner.FailsOnNoAsserts := True;
    Results := Runner.Execute;
    if not Results.AllPassed then System.ExitCode := EXIT_ERRORS;
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
end.
