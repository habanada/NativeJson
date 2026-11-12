{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_MemoryTest;

{
  MEMORY TEST

  Runs the same sequences very often and checks whether the
  working set grows. Two separate measurements:

    1. ReportMemoryLeaksOnShutdown - on exit reports every block
       that Delphi's memory manager still holds. That pinpoints forgotten
       Free calls.

    2. Working set before and after every round. That finds leaks
       the memory manager does not see, such as held RTTI pools or
       growing caches.

  Important for reading the numbers: a growing value after the FIRST round
  is normal - that is when the RTTI caches of the library fill up, and that is
  intended. It only becomes suspicious when the value keeps rising steadily
  from round to round.

  Usage:  NativeJson_MemoryTest.exe [rounds]
}

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.PsAPI,
  Memory.Model in 'Memory.Model.pas',
  NativeJson.Main,
  NativeJson.Dom.JsonObject,
  NativeJson.Attributes,
  NativeJson.Fluent,
  NativeJson.Dom.Value,
  NativeJson.Rtti.Cache,
  NativeJson.Serializer.Writer;

function WorkingSetKB: Int64;
var
  Counter: TProcessMemoryCounters;
begin
  Counter.cb := SizeOf(Counter);
  if GetProcessMemoryInfo(GetCurrentProcess, @Counter, SizeOf(Counter)) then
    Result := Counter.WorkingSetSize div 1024
  else
    Result := 0;
end;

// ---------------------------------------------------------------------------
// The individual stress probes. Each must clean up its own memory.
// ---------------------------------------------------------------------------

procedure ProbeRoundtrip;
var
  Source, CopyObj: THeavyLoad;
  Settings: TJsonSettings;
  Json: string;
begin
  Source := CreateHeavyLoad(4, 256);
  Settings := TJsonSettings.Create;
  try
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
    Json := JsonConvert.SerializeObject(Source, Settings);

    CopyObj := JsonConvert.DeserializeObject<THeavyLoad>(Json, Settings);
    CopyObj.Free;
  finally
    Settings.Free;
    Source.Free;
  end;
end;

procedure ProbeCycle;
var
  A, B: THeavyLoad;
  Loaded: THeavyLoad;
  Settings: TJsonSettings;
  Json: string;
begin
  A := CreateHeavyLoad(2, 64);
  B := CreateHeavyLoad(2, 64);
  Settings := TJsonSettings.Create;
  try
    A.Designation := 'A';
    B.Designation := 'B';
    A.Neighbor := B;
    B.Neighbor := A;

    Settings.PreserveReferences := TJsonPreserveReferences.Objects;
    Json := JsonConvert.SerializeObject(A, Settings);

    Loaded := JsonConvert.DeserializeObject<THeavyLoad>(Json, Settings);
    try
      // Break the cycle, otherwise the neighbor frees itself.
      // The comparison with Loaded itself prevents a double
      // free in case the reference points to the root object.
      if (Loaded.Neighbor <> nil) and (Loaded.Neighbor <> Loaded) then
      begin
        Loaded.Neighbor.Neighbor := nil;
        Loaded.Neighbor.Free;
        Loaded.Neighbor := nil;
      end;
    finally
      Loaded.Free;
    end;
  finally
    A.Neighbor := nil;
    B.Neighbor := nil;
    B.Free;
    A.Free;
    Settings.Free;
  end;
end;

procedure ProbeFluentSwitch;
var
  Source: THeavyLoad;
  Settings: TJsonSettings;
  I: Integer;
begin
  // A new configuration every round: challenges the RTTI cache,
  // because a new key is created every time.
  Source := CreateHeavyLoad(2, 32);
  try
    for I := 1 to 5 do
    begin
      Settings := TJsonSettings.Create;
      try
        Settings.Fluent.Entity<THeavyLoad>
          .Map('Designation').Name('name_' + IntToStr(I)).EndMember;
        JsonConvert.SerializeObject(Source, Settings);
      finally
        Settings.Free;
      end;
    end;
  finally
    Source.Free;
  end;
end;

procedure ProbeDom;
var
  Source: THeavyLoad;
  Json: string;
  Dom, CopyObj: TJsonValue;
begin
  Source := CreateHeavyLoad(3, 64);
  try
    Json := JsonConvert.SerializeObject(Source);
  finally
    Source.Free;
  end;

  Dom := JsonConvert.DeserializeObject(Json);
  try
    CopyObj := Dom.Clone;
    try
      CopyObj.ToJson;
      Dom.FindAll('$..Name');
    finally
      CopyObj.Free;
    end;
  finally
    Dom.Free;
  end;
end;

procedure ProbeSchema;
var
  Schema: TJsonObject;
begin
  Schema := JsonConvert.GenerateSchema<THeavyLoad>;
  try
    Schema.ToJson;
  finally
    Schema.Free;
  end;
end;

procedure ProbeErrorPaths;
var
  Attempt: Integer;
  Started: THeavyLoad;
begin
  // Aborted operations are the most common leak source: the half
  // built object must still be freed.
  for Attempt := 1 to 3 do
  begin
    Started := nil;
    try
      case Attempt of
        1: Started := JsonConvert.DeserializeObject<THeavyLoad>('{"Designation":"truncated"');
        2: Started := JsonConvert.DeserializeObject<THeavyLoad>('{"Tree":{"$type":"Does.Not.Exist"}}');
        3: Started := JsonConvert.DeserializeObject<THeavyLoad>('not even json');
      end;
    except
      // expected - nothing may be left over here
    end;
    // If something did come back against expectations: clean up
    Started.Free;
  end;
end;

// ---------------------------------------------------------------------------

procedure Pass;
var
  Rounds, I: Integer;
  AfterKB, BaseKB, FirstSampleKB: Int64;
  Growth: Int64;
  CacheAtStart: Integer;
begin
  Rounds := 200;
  if (ParamCount >= 1) and TryStrToInt(ParamStr(1), Rounds) then
    if Rounds < 1 then Rounds := 1;

  Writeln('============================================================');
  Writeln('  NATIVEJSON MEMORY TEST');
  Writeln('============================================================');
  Writeln(Format('Rounds: %d', [Rounds]));
  Writeln;

  // One warm-up round: afterwards the RTTI caches are in place, from here on
  // nothing may grow permanently.
  ProbeRoundtrip;
  ProbeCycle;
  ProbeFluentSwitch;
  ProbeDom;
  ProbeSchema;
  ProbeErrorPaths;

  BaseKB := WorkingSetKB;
  Writeln(Format('After the warm-up round: %d KB', [BaseKB]));
  Writeln;
  Writeln(Format('Entries in the RTTI cache: %d', [TJsonRttiCache.Get.Count]));
  Writeln;
  Writeln('Round     Memory KB       Growth      Cache entries');
  Writeln('------------------------------------------------------------');

  FirstSampleKB := 0;
  CacheAtStart := TJsonRttiCache.Get.Count;

  for I := 1 to Rounds do
  begin
    ProbeRoundtrip;
    ProbeCycle;
    ProbeFluentSwitch;
    ProbeDom;
    ProbeSchema;
    ProbeErrorPaths;

    if (I mod 20 = 0) or (I = Rounds) then
    begin
      AfterKB := WorkingSetKB;
      // The first sample is the reference value. Between the warm-up round and
      // the first sample the memory manager grabs blocks once -
      // that is not a leak and must not distort the rating.
      if FirstSampleKB = 0 then FirstSampleKB := AfterKB;
      Writeln(Format('%5d %14d %12d %15d',
        [I, AfterKB, AfterKB - FirstSampleKB, TJsonRttiCache.Get.Count]));
    end;
  end;

  AfterKB := WorkingSetKB;
  if FirstSampleKB = 0 then FirstSampleKB := BaseKB;
  Growth := AfterKB - FirstSampleKB;

  Writeln;
  Writeln('============================================================');
  Writeln(Format('  One-time base (warm-up round to 1st sample): %d KB',
    [FirstSampleKB - BaseKB]));
  Writeln(Format('  Growth in the long run: %d KB', [Growth]));
  if Rounds > 20 then
    Writeln(Format('  That is %.3f KB per round', [Growth / (Rounds - 20)]));
  Writeln('============================================================');
  Writeln;
  Writeln(Format('  Entries in the RTTI cache: %d at the start, %d at the end',
    [CacheAtStart, TJsonRttiCache.Get.Count]));
  Writeln('============================================================');
  Writeln;
  Writeln('Rating:');
  Writeln('  The one-time base is harmless - the memory manager grabs');
  Writeln('  blocks at the start and keeps them.');
  Writeln('  What matters is the growth in the long run:');
  Writeln('    below 0.1 KB per round -> clean');
  Writeln('    above                  -> something is held, increase the rounds');
  Writeln('                              and read the report on exit');
  Writeln;
  Writeln('The cache count must stay the SAME across rounds. If it grows,');
  Writeln('the RTTI cache keeps entries of dead configurations.');
  Writeln;
  Writeln('On exit the memory manager reports every block it');
  Writeln('still holds. If no window appears, nothing was left over.');
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    Pass;
  except
    on E: Exception do
      Writeln('ABORTED: ', E.ClassName, ': ', E.Message);
  end;
  if ParamCount = 0 then
  begin
    Writeln;
    Writeln('Press Enter ...');
    Readln;
  end;
end.
