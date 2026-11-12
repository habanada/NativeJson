{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Bench.Core;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  System.Diagnostics,
  {$ELSE}
  System.SysUtils,
  System.Diagnostics,
  {$ENDIF}
  Bench.Model,
  NativeJson.Main,
  NativeJson.Settings,
  NativeJson.Serializer.Writer;

type
  TBenchmark = class sealed
  private
    class function CreateBatch(Count: Integer): TLogBatch; static;
  public
    class procedure RunHighPressureTest; static;
  end;

implementation

class function TBenchmark.CreateBatch(Count: Integer): TLogBatch;
var
  I: Integer;
  Event: TLogEvent;
  Error: TLogError;
  Binary: TLogBinary;
begin
  Result := TLogBatch.Create;
  for I := 1 to Count do
  begin
    case I mod 10 of
      0:
        begin
          Binary := TLogBinary.Create(16);
          Binary.Severity := svInfo;
          Result.Entries.Add(Binary);
        end;
      1:
        begin
          Error := TLogError.Create;
          Error.Severity := svError;
          Error.ErrorClass := 'EExample' + IntToStr(I);
          Error.StackTrace.Add('Frame ' + IntToStr(I));
          Error.Meta.Add('Node', 'SRV-' + IntToStr(I mod 32));
          Result.Entries.Add(Error);
        end;
    else
      Event := TLogEvent.Create;
      Event.Severity := TSeverity(I mod 4);
      Event.MessageText := 'Event ' + IntToStr(I);
      Event.Tags.Add('nativejson');
      Event.Tags.Add('benchmark');
      Result.Entries.Add(Event);
    end;
  end;
end;

class procedure TBenchmark.RunHighPressureTest;
const
  ItemCount = 10000;
var
  Batch, Clone: TLogBatch;
  Settings: TJsonSettings;
  Json: string;
  Watch: TStopwatch;
begin
  Batch := CreateBatch(ItemCount);
  Settings := TJsonSettings.Create;
  try
    Settings.Formatting := TJsonFormatting.None;
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
    Watch := TStopwatch.StartNew;
    Json := JsonConvert.SerializeObject(Batch, Settings);
    Watch.Stop;
    Writeln(Format('Serialize: %d items, %d chars, %d ms', [Batch.Entries.Count, Length(Json), Watch.ElapsedMilliseconds]));
    Watch := TStopwatch.StartNew;
    Clone := JsonConvert.DeserializeObject<TLogBatch>(Json, Settings);
    try
      Watch.Stop;
      Writeln(Format('Deserialize: %d items, %d ms', [Clone.Entries.Count, Watch.ElapsedMilliseconds]));
      if Clone.Entries.Count <> Batch.Entries.Count then raise Exception.CreateFmt('Roundtrip count mismatch: %d <> %d', [Clone.Entries.Count, Batch.Entries.Count]);
    finally
      Clone.Free;
    end;
  finally
    Settings.Free;
    Batch.Free;
  end;
end;

end.
