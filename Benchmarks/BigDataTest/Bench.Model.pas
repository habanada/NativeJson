{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Bench.Model;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  Generics.Collections,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  {$ENDIF}
  NativeJson.Attributes,
  NativeJson.Schema.Attributes;

type
  TLogEvent = class;
  TLogBinary = class;
  TLogError = class;

  TSeverity = (svInfo, svWarning, svError, svCritical);

  [JsonKnownType('TLogEvent')]
  [JsonKnownType('TLogBinary')]
  [JsonKnownType('TLogError')]
  TLogEntry = class
  private
    FID: TGUID;
    FTimeStamp: TDateTime;
    FMachine: string;
    FSeverity: TSeverity;
  public
    constructor Create;
    property ID: TGUID read FID write FID;
    property TimeStamp: TDateTime read FTimeStamp write FTimeStamp;
    property Machine: string read FMachine write FMachine;
    property Severity: TSeverity read FSeverity write FSeverity;
  end;

  TLogEvent = class(TLogEntry)
  private
    FMessage: string;
    FTags: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    property MessageText: string read FMessage write FMessage;
    property Tags: TList<string> read FTags;
  end;

  TLogBinary = class(TLogEntry)
  private
    FPayload: TBytes;
    FCheckSum: Int64;
  public
    constructor Create; overload;
    constructor Create(SizeKB: Integer); overload;
    property Payload: TBytes read FPayload write FPayload;
    property CheckSum: Int64 read FCheckSum write FCheckSum;
  end;

  TLogError = class(TLogEntry)
  private
    FErrorClass: string;
    FStackTrace: TStrings;
    FMeta: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    property ErrorClass: string read FErrorClass write FErrorClass;
    property StackTrace: TStrings read FStackTrace;
    property Meta: TDictionary<string, string> read FMeta;
  end;

  TLogBatch = class
  private
    FBatchID: string;
    FEntries: TObjectList<TLogEntry>;
  public
    constructor Create;
    destructor Destroy; override;
    property BatchID: string read FBatchID write FBatchID;
    property Entries: TObjectList<TLogEntry> read FEntries;
  end;

implementation

constructor TLogEntry.Create;
begin
  CreateGUID(FID);
  FTimeStamp := Now;
  FMachine := 'SRV-NODE-' + IntToStr(Random(100));
  FSeverity := TSeverity(Random(4));
end;

constructor TLogEvent.Create;
begin
  inherited;
  FTags := TList<string>.Create;
end;

destructor TLogEvent.Destroy;
begin
  FTags.Free;
  inherited;
end;

constructor TLogBinary.Create;
begin
  inherited Create;
end;

constructor TLogBinary.Create(SizeKB: Integer);
begin
  inherited Create;
  SetLength(FPayload, SizeKB * 1024);
  FillChar(FPayload[0], Length(FPayload), Random(255));
  FCheckSum := Random(MaxInt);
end;

constructor TLogError.Create;
begin
  inherited;
  FStackTrace := TStringList.Create;
  FMeta := TDictionary<string, string>.Create;
end;

destructor TLogError.Destroy;
begin
  FStackTrace.Free;
  FMeta.Free;
  inherited;
end;

constructor TLogBatch.Create;
begin
  FEntries := TObjectList<TLogEntry>.Create(True);
  FBatchID := TGUID.NewGuid.ToString;
end;

destructor TLogBatch.Destroy;
begin
  FEntries.Free;
  inherited;
end;

end.