{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program JsonDeathmatch;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  System.TimeSpan,
  System.IOUtils,
  System.Generics.Collections,
  System.JSON,
  Winapi.Windows,
  Winapi.PsAPI,
  
  // Benchmark Entities
  Bench.Entities in 'Bench.Entities.pas',
  
{$IFDEF NATIVEJSON_WITH_NEON}
  Neon.Core.Persistence,
  Neon.Core.Persistence.JSON,
{$ENDIF}
  // NativeJson (our hero)
  NativeJson.Main,
  NativeJson.Serializer.Core,
  NativeJson.Converters.Standard,
  NativeJson.Converters.System,
  NativeJson.Serializer.Writer;

// --- Helper for RAM measurement ---
function GetCurrentMemoryUsage: Int64;
var
  PMC: TProcessMemoryCounters;
begin
  PMC.cb := SizeOf(PMC);
  if GetProcessMemoryInfo(GetCurrentProcess, @PMC, SizeOf(PMC)) then
    Result := PMC.WorkingSetSize
  else
    Result := 0;
end;

function FormatBytes(Bytes: Int64): string;
const
  KB = 1024;
  MB = 1024 * 1024;
  GB = 1024 * 1024 * 1024;
begin
  if Bytes > GB then
    Result := Format('%.2f GB', [Bytes / GB])
  else if Bytes > MB then
    Result := Format('%.2f MB', [Bytes / MB])
  else
    Result := Format('%.2f KB', [Bytes / KB]);
end;

procedure Log(const Msg: string);
begin
  WriteLn(FormatDateTime('hh:nn:ss', Now) + ' | ' + Msg);
end;

// --- Data generator ---
function GenerateMassiveData(ItemCount: Integer; BlobCount: Integer; BlobSizeMB: Integer): TRootContainer;
var
  I: Integer;
  Item: TComplexItem;
  Blob: THeavyBlob;
begin
  Log(Format('Generating data: %d complex items, %d blobs of %d MB...', [ItemCount, BlobCount, BlobSizeMB]));
  Result := TRootContainer.Create;
  Result.Description := 'ULTIMATE JSON BENCHMARK DATASET';
  
  // 1. Many small, complex objects (CPU stress for RTTI)
  for I := 1 to ItemCount do
  begin
    Item := TComplexItem.Create;
    Item.Name := 'Item #' + IntToStr(I) + ' - Enterprise Data ' + GuidToString(Item.ID);
    Item.EntityType := TEntityType(I mod 3);
    
    // Nested Data
    Item.Tags.Add('HighPerformance');
    Item.Tags.Add('NativeJson');
    Item.Tags.Add('Benchmark');
    
    Item.Meta.Add('Index', I);
    Item.Meta.Add('CheckSum', I * 12345);
    
    Result.Items.Add(Item);
  end;
  
  // 2. Memory hogs (RAM stress for string concatenation)
  for I := 1 to BlobCount do
  begin
    Blob := THeavyBlob.Create(BlobSizeMB);
    Result.Items.Add(Blob);
  end;
  
  Log('Data generated. RAM usage: ' + FormatBytes(GetCurrentMemoryUsage));
end;

// --- Tests ---

{$IFDEF NATIVEJSON_WITH_NEON}
procedure RunNeon(Data: TRootContainer);
var
  SW: TStopwatch;
  JsonStr: string;
  MemStart, MemPeak, MemEnd: Int64;
  LNeon: TNeonSerializerJSON;
  LJSON: System.JSON.TJSONValue;
begin
  WriteLn;
  Log('=== START NEON BENCHMARK ===');
  MemStart := GetCurrentMemoryUsage;
  
  SW := TStopwatch.StartNew;
  try
    // Neon step 1: object -> DOM (TJSONValue)
    // This is usually where memory explodes, because TJSONObjects are created for every object
    LNeon := TNeonSerializerJSON.Create(TNeonConfiguration.Default);
    try
      LJSON := LNeon.ObjectToJSON(Data);
    finally
      LNeon.Free;
    end;
    
    MemPeak := GetCurrentMemoryUsage;
    Log('Neon DOM created. RAM: ' + FormatBytes(MemPeak) + ' (Delta: ' + FormatBytes(MemPeak - MemStart) + ')');
    
    // Neon step 2: DOM -> string
    if LJSON <> nil then
    begin
      JsonStr := LJSON.ToJSON; // ToString in older Delphi versions
      LJSON.Free;
    end;
    
    SW.Stop;
    MemEnd := GetCurrentMemoryUsage;
    
    Log('Neon done.');
    Log('Time: ' + SW.Elapsed.ToString);
    Log('JSON length: ' + FormatBytes(Length(JsonStr)));
    Log('RAM peak (estimated via DOM): ' + FormatBytes(MemPeak));
    Log('RAM after cleanup: ' + FormatBytes(MemEnd));
    
  except
    on E: Exception do
      Log('NEON CRASH: ' + E.Message);
  end;
  JsonStr := ''; // free memory
end;

{$ENDIF}

// ---------------------------------------------------------------------------
// Two ways to write the same data.
//
// Route A builds the complete output as a Delphi string in memory.
// It therefore needs as much RAM as the output is large - and because
// Delphi strings are UTF-16, even twice the size of the later file.
// On top of that comes the hard limit of 2^31 characters, because Length and
// TStringBuilder.Capacity are Integer even on Win64.
//
// Route B writes continuously into a stream. The memory requirement stays
// constant, no matter how large the output gets, and the character limit
// disappears, because no string is ever created.
// ---------------------------------------------------------------------------

function WriteAsString(Data: TRootContainer; out Duration: TTimeSpan;
  out Chars: Int64; out RamDelta: Int64): Boolean;
var
  SW: TStopwatch;
  JsonStr: string;
  RamBefore: Int64;
  Writer: TStringWriter;
  NativeWriter: TJsonWriter;
  Serializer: TJsonSerializer;
begin
  Result := False;
  Duration := TTimeSpan.Zero;
  Chars := 0;
  RamBefore := GetCurrentMemoryUsage;
  RamDelta := 0;
  try
    SW := TStopwatch.StartNew;
    // Set to nil first, then create INSIDE the try: this is exactly where
    // EOutOfMemory is to be expected, and then the objects already created
    // still have to be freed.
    Writer := nil;
    NativeWriter := nil;
    Serializer := nil;
    try
      Writer := TStringWriter.Create;
      NativeWriter := TJsonWriter.Create(Writer);
      Serializer := TJsonSerializer.Create;
      Serializer.Formatting := TJsonFormatting.None;
      Serializer.Serialize(NativeWriter, Data);
      JsonStr := Writer.ToString;
      Chars := Length(JsonStr);
      RamDelta := GetCurrentMemoryUsage - RamBefore;
    finally
      Serializer.Free;
      NativeWriter.Free;
      Writer.Free;
    end;
    SW.Stop;
    Duration := SW.Elapsed;
    Result := True;
  except
    on E: Exception do
      Log('  Route A failed: ' + E.ClassName + ': ' + E.Message);
  end;
end;

function WriteAsStream(Data: TRootContainer; const FileName: string;
  out Duration: TTimeSpan; out Bytes: Int64; out RamDelta: Int64): Boolean;
var
  SW: TStopwatch;
  RamBefore: Int64;
  TheFile: TFileStream;
  Serializer: TJsonSerializer;
begin
  Result := False;
  Duration := TTimeSpan.Zero;
  Bytes := 0;
  RamBefore := GetCurrentMemoryUsage;
  RamDelta := 0;
  try
    SW := TStopwatch.StartNew;
    // As with route A: if creating the serializer fails, the file would
    // otherwise stay open - and the subsequent delete would fail on it
    // and abort the whole run.
    TheFile := nil;
    Serializer := nil;
    try
      TheFile := TFileStream.Create(FileName, fmCreate);
      Serializer := TJsonSerializer.Create;
      Serializer.Formatting := TJsonFormatting.None;
      Serializer.Serialize(TheFile, Data);
      Bytes := TheFile.Size;
      RamDelta := GetCurrentMemoryUsage - RamBefore;
    finally
      Serializer.Free;
      TheFile.Free;
    end;
    SW.Stop;
    Duration := SW.Elapsed;
    Result := True;
  except
    on E: Exception do
      Log('  Route B failed: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure RunNativeJson(Data: TRootContainer);
var
  DurationA, DurationB: TTimeSpan;
  CharsA, BytesB: Int64;
  RamA, RamB: Int64;
  OkA, OkB: Boolean;
  TargetFile: string;
begin
  WriteLn;
  Log('=== NATIVEJSON: STRING VS STREAM ===');

  Log('Route A: everything as a string in memory ...');
  OkA := WriteAsString(Data, DurationA, CharsA, RamA);
  if OkA then
    // Characters, not bytes: a Delphi string is UTF-16. If it were passed
    // through FormatBytes, route A would look half as large as route B.
    Log(Format('  done in %d ms, %d chars (UTF-16, so %s in memory), RAM +%s',
      [Round(DurationA.TotalMilliseconds), CharsA, FormatBytes(CharsA * 2), FormatBytes(RamA)]));

  Sleep(1000);

  TargetFile := TPath.Combine(TPath.GetTempPath, 'nativejson_deathmatch.json');
  Log('Route B: continuously into a stream ...');
  OkB := WriteAsStream(Data, TargetFile, DurationB, BytesB, RamB);
  if OkB then
    Log(Format('  done in %d ms, %s file (UTF-8, without BOM), RAM +%s',
      [Round(DurationB.TotalMilliseconds), FormatBytes(BytesB), FormatBytes(RamB)]));

  WriteLn;
  Log('--- Comparison ---');
  if OkA and OkB then
  begin
    Log(Format('  Time:    A %d ms   B %d ms',
      [Round(DurationA.TotalMilliseconds), Round(DurationB.TotalMilliseconds)]));
    Log(Format('  Memory A %s   B %s', [FormatBytes(RamA), FormatBytes(RamB)]));
    if RamB > 0 then
      Log(Format('  The stream needs %.1f times less memory.', [RamA / RamB]))
    else
      Log('  The stream needs practically no additional memory.');
  end
  else if OkB then
    Log('  Route A failed on memory, route B ran through. That is exactly what it is for.')
  else if OkA then
    Log('  Route B failed - that would be a real bug, please report it.')
  else
    Log('  Both routes failed: the amount of data is too large for this process.');

  try
    if TFile.Exists(TargetFile) then TFile.Delete(TargetFile);
  except
    on E: Exception do
      Log('  Temporary file was left behind: ' + TargetFile);
  end;
end;

// --- Main ---

var
  Data: TRootContainer;
  Items, Blobs, BlobMB, Val: Integer;
begin
  try
{$IFDEF WIN64}
    // 64 bit: the address space is practically unlimited, it may hurt here
    Items := 500000; Blobs := 5; BlobMB := 100;
{$ELSE}
    // 32 bit: about 2 GB for the whole process. Route A can never manage
    // more than this, no matter how good the code is.
    Items := 100000; Blobs := 2; BlobMB := 50;
{$ENDIF}

    // TryStrToInt writes a 0 into the out parameter for unusable input.
    // Without an intermediate variable a typo would silently set the
    // default value to zero.
    if (ParamCount >= 1) and TryStrToInt(ParamStr(1), Val) and (Val > 0) then Items := Val;
    if (ParamCount >= 2) and TryStrToInt(ParamStr(2), Val) and (Val >= 0) then Blobs := Val;
    if (ParamCount >= 3) and TryStrToInt(ParamStr(3), Val) and (Val > 0) then BlobMB := Val;

    Log('Initializing benchmark');
{$IFDEF WIN64}
    Log('Platform: Win64');
{$ELSE}
    Log('Platform: Win32 - address space about 2 GB');
{$ENDIF}
{$IFOPT D+}
    Log('WARNING: debug build, the times are not meaningful.');
{$ENDIF}
    Log('Call with your own values: JsonDeathmatch.exe [items] [blobs] [MB per blob]');

    Data := GenerateMassiveData(Items, Blobs, BlobMB);
    try
{$IFDEF NATIVEJSON_WITH_NEON}
      RunNeon(Data);
      Sleep(2000);
{$ENDIF}
      RunNativeJson(Data);
    finally
      Data.Free;
    end;

    WriteLn;
    Log('Benchmark finished.');
    if ParamCount = 0 then
    begin
      Log('Press Enter ...');
      ReadLn;
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
