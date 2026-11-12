{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Demo.Assert;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Math,
  {$ELSE}
  System.SysUtils,
  System.Math,
  {$ENDIF}
  NativeJson.Compat;

procedure Title(const S: string);
procedure Section(const S: string);
procedure Show(const Name, Val: string);

procedure Check(const Name, Expected, Received: string); overload;
procedure Check(const Name: string; Expected, Received: Integer); overload;
procedure Check(const Name: string; Expected, Received: Double; Tolerance: Double = 0.000001); overload;
procedure Check(const Name: string; Expected, Received: Boolean); overload;
procedure CheckContains(const Name, Part, Text: string);
procedure CheckNotContains(const Name, Part, Text: string);
procedure CheckTrue(const Name: string; Condition: Boolean; const Hint: string = '');
procedure CheckError(const Name: string; Action: TProc);

function Summary: Integer;

implementation

var
  GOk: Integer = 0;
  GFailures: Integer = 0;

function Shorten(const S: string): string;
begin
  if Length(S) > 240 then Result := Copy(S, 1, 240) + ' ...' else Result := S;
end;

procedure Title(const S: string);
begin
  Writeln;
  Writeln('============================================================');
  Writeln('  ' + S);
  Writeln('============================================================');
end;

procedure Section(const S: string);
begin
  Writeln;
  Writeln('-- ' + S + ' ' + StringOfChar('-', Max(3, 56 - Length(S))));
end;

procedure Show(const Name, Val: string);
begin
  Writeln('       ', Name, ': ', Shorten(Val));
end;

procedure Success(const Name, Val: string);
begin
  Inc(GOk);
  if Val = '' then Writeln('[OK]   ', Name)
  else Writeln('[OK]   ', Name, ' = ', Shorten(Val));
end;

procedure Failed(const Name, Expected, Received: string);
begin
  Inc(GFailures);
  Writeln('[FAIL] ', Name);
  Writeln('       expected: ', Shorten(Expected));
  Writeln('       received: ', Shorten(Received));
end;

procedure Check(const Name, Expected, Received: string);
begin
  if Expected = Received then Success(Name, Received)
  else Failed(Name, Expected, Received);
end;

procedure Check(const Name: string; Expected, Received: Integer);
begin
  if Expected = Received then Success(Name, IntToStr(Received))
  else Failed(Name, IntToStr(Expected), IntToStr(Received));
end;

procedure Check(const Name: string; Expected, Received: Double; Tolerance: Double);
var
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Invariant;
  if Abs(Expected - Received) <= Tolerance then Success(Name, FloatToStr(Received, FS))
  else Failed(Name, FloatToStr(Expected, FS), FloatToStr(Received, FS));
end;

procedure Check(const Name: string; Expected, Received: Boolean);
begin
  if Expected = Received then Success(Name, BoolToStr(Received, True))
  else Failed(Name, BoolToStr(Expected, True), BoolToStr(Received, True));
end;

procedure CheckContains(const Name, Part, Text: string);
begin
  if Pos(Part, Text) > 0 then Success(Name, Part)
  else Failed(Name, 'contains ' + Part, Text);
end;

procedure CheckNotContains(const Name, Part, Text: string);
begin
  if Pos(Part, Text) = 0 then Success(Name, 'without ' + Part)
  else Failed(Name, 'without ' + Part, Text);
end;

procedure CheckTrue(const Name: string; Condition: Boolean; const Hint: string);
begin
  if Condition then Success(Name, Hint)
  else Failed(Name, 'True', 'False ' + Hint);
end;

procedure CheckError(const Name: string; Action: TProc);
begin
  try
    Action();
    Failed(Name, 'exception expected', 'no error raised');
  except
    on E: Exception do Success(Name, E.ClassName);
  end;
end;

function Summary: Integer;
begin
  Writeln;
  Writeln('============================================================');
  Writeln(Format('  RESULT: %d passed, %d failed', [GOk, GFailures]));
  Writeln('============================================================');
  if GFailures = 0 then Result := 0 else Result := 1;
end;

end.
