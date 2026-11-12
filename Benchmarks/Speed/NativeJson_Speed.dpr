{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program NativeJson_Speed;

{$I NativeJson.inc}

{$APPTYPE CONSOLE}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  System.Diagnostics,
  fpjson,
  jsonparser,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  System.Generics.Collections,
  System.JSON,
  {$ENDIF}
  NativeJson.Dom.Value,
  NativeJson.Dom.Io,
  NativeJson.Main,
  NativeJson.Settings,
  Speed.Model in 'Speed.Model.pas';

const
  Runs = 5;
  RecordCount = 40000;
  NumberCount = 400000;
  StringCount = 200000;

type
  TAction = reference to procedure;
  TNativeValue = NativeJson.Dom.Value.TJsonValue;
  {$IFDEF FPC}
  TRefValue = TJSONData;
  {$ELSE}
  TRefValue = System.JSON.TJSONValue;
  {$ENDIF}

var
  FS: TFormatSettings;
  Sink: string;

function Fmt(Value: Double): string;
begin
  Result := FloatToStrF(Value, ffGeneral, 17, 0, FS);
end;

function BuildRecords: string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{"Items":[');
    for I := 1 to RecordCount do
    begin
      if I > 1 then SB.Append(',');
      SB.Append('{"Id":').Append(I);
      SB.Append(',"Name":"User ').Append(I).Append('"');
      SB.Append(',"Email":"user_').Append(I).Append('@example.org"');
      if I mod 3 = 0 then SB.Append(',"Active":true') else SB.Append(',"Active":false');
      SB.Append(',"Score":').Append(Fmt(I * 0.37 + 1 / (I + 3)));
      SB.Append(',"Amount":').Append(I * 7).Append('.').Append(10 + I mod 90);
      SB.Append(',"Tags":["alpha","beta","gamma"]');
      SB.Append(',"Address":{"City":"Exampletown","Zip":"12345","Note":null}');
      SB.Append(',"Text":"Line one\nLine \"two\" with äöü and some more words to fill the row"}');
    end;
    SB.Append(']}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function BuildNumbers: string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  RandSeed := 12345;
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for I := 1 to NumberCount do
    begin
      if I > 1 then SB.Append(',');
      SB.Append(Fmt((Random - 0.5) * 1.0E6));
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function BuildStrings: string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for I := 1 to StringCount do
    begin
      if I > 1 then SB.Append(',');
      SB.Append('"item ').Append(I).Append(' with a few words, a tab\t, a quote \" and umlauts üß"');
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure Measure(const Title: string; Bytes: Integer; const Action: TAction);
var
  Times: array[0..Runs - 1] of Double;
  I, J: Integer;
  Watch: TStopwatch;
  Swap, Best, Median: Double;
begin
  Action();
  for I := 0 to Runs - 1 do
  begin
    Watch := TStopwatch.StartNew;
    Action();
    Watch.Stop;
    Times[I] := Watch.Elapsed.TotalMilliseconds;
  end;
  for I := 0 to Runs - 2 do
    for J := I + 1 to Runs - 1 do
      if Times[J] < Times[I] then
      begin
        Swap := Times[I];
        Times[I] := Times[J];
        Times[J] := Swap;
      end;
  Best := Times[0];
  Median := Times[Runs div 2];
  Writeln(Format('  %-26s best %8.1f ms   median %8.1f ms   %7.1f MB/s',
    [Title, Best, Median, Bytes / 1.0E6 / (Best / 1000)], FS));
end;

procedure RunDocument(const Name, Text: string);
var
  Bytes: Integer;
  Keep: TNativeValue;
  RefKeep: TRefValue;
  {$IFDEF FPC}
  Utf8: UTF8String;
  {$ENDIF}
begin
  Bytes := Length(Text);
  Writeln;
  Writeln(Format('%s (%.1f MB of text)', [Name, Bytes / 1.0E6], FS));

  Measure('NativeJson parse', Bytes,
    procedure
    var
      Dom: TNativeValue;
    begin
      Dom := DomFromText(Text);
      Dom.Free;
    end);
  Keep := DomFromText(Text);
  try
    Measure('NativeJson write', Bytes,
      procedure
      begin
        Sink := DomToText(Keep);
      end);
  finally
    Keep.Free;
  end;

  {$IFDEF FPC}
  Utf8 := UTF8Encode(Text);
  Measure('fpjson parse', Bytes,
    procedure
    var
      Ref: TRefValue;
    begin
      Ref := GetJSON(Utf8);
      Ref.Free;
    end);
  RefKeep := GetJSON(Utf8);
  try
    Measure('fpjson write', Bytes,
      procedure
      begin
        Sink := string(RefKeep.AsJSON);
      end);
  finally
    RefKeep.Free;
  end;
  {$ELSE}
  Measure('System.JSON parse', Bytes,
    procedure
    var
      Ref: TRefValue;
    begin
      Ref := TJSONObject.ParseJSONValue(Text);
      Ref.Free;
    end);
  RefKeep := TJSONObject.ParseJSONValue(Text);
  try
    Measure('System.JSON write', Bytes,
      procedure
      begin
        Sink := RefKeep.ToJSON;
      end);
  finally
    RefKeep.Free;
  end;
  {$ENDIF}
end;

procedure RunMapping(const Text: string);
var
  Bytes: Integer;
  Batch: TSpeedBatch;
begin
  Bytes := Length(Text);
  Writeln;
  Writeln('Object mapping, the records as classes');
  Batch := JsonConvert.DeserializeObject<TSpeedBatch>(Text);
  try
    if Batch.Items.Count <> RecordCount then
      raise Exception.CreateFmt('Expected %d records, got %d', [RecordCount, Batch.Items.Count]);
    Measure('NativeJson deserialize', Bytes,
      procedure
      var
        Copy: TSpeedBatch;
      begin
        Copy := JsonConvert.DeserializeObject<TSpeedBatch>(Text);
        Copy.Free;
      end);
    Measure('NativeJson serialize', Bytes,
      procedure
      begin
        Sink := JsonConvert.SerializeObject(Batch);
      end);
    if Length(Sink) < Bytes div 2 then
      raise Exception.Create('Serialized text is unexpectedly short');
  finally
    Batch.Free;
  end;
end;

var
  Records, Numbers, Strings: string;

begin
  FS := TFormatSettings.Invariant;
  try
    {$IFDEF FPC}
    Writeln('NativeJson speed test, FPC ', {$I %FPCVERSION%}, ', reference: fpjson');
    {$ELSE}
    Writeln('NativeJson speed test, reference: System.JSON');
    {$ENDIF}
    Writeln(Format('Best and median of %d runs after one warm-up; the text is parsed from a string in memory.', [Runs]));
    Records := BuildRecords;
    Numbers := BuildNumbers;
    Strings := BuildStrings;
    RunDocument('Records', Records);
    RunDocument('Numbers (doubles with 15 to 17 digits)', Numbers);
    RunDocument('Strings with escapes', Strings);
    RunMapping(Records);
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
