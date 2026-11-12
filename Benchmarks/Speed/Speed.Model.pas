{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Speed.Model;

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
  NativeJson.Attributes;

type
  TSpeedAddress = class
  private
    FCity: string;
    FZip: string;
    FNote: string;
  public
    property City: string read FCity write FCity;
    property Zip: string read FZip write FZip;
    property Note: string read FNote write FNote;
  end;

  TSpeedRecord = class
  private
    FId: Integer;
    FName: string;
    FEmail: string;
    FActive: Boolean;
    FScore: Double;
    FAmount: Currency;
    FTags: TArray<string>;
    FAddress: TSpeedAddress;
    FText: string;
  public
    constructor Create;
    destructor Destroy; override;
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    property Email: string read FEmail write FEmail;
    property Active: Boolean read FActive write FActive;
    property Score: Double read FScore write FScore;
    property Amount: Currency read FAmount write FAmount;
    property Tags: TArray<string> read FTags write FTags;
    property Address: TSpeedAddress read FAddress write FAddress;
    property Text: string read FText write FText;
  end;

  TSpeedBatch = class
  private
    FItems: TObjectList<TSpeedRecord>;
  public
    constructor Create;
    destructor Destroy; override;
    property Items: TObjectList<TSpeedRecord> read FItems;
  end;

implementation

constructor TSpeedRecord.Create;
begin
  inherited Create;
  FAddress := TSpeedAddress.Create;
end;

destructor TSpeedRecord.Destroy;
begin
  FAddress.Free;
  inherited Destroy;
end;

constructor TSpeedBatch.Create;
begin
  inherited Create;
  FItems := TObjectList<TSpeedRecord>.Create(True);
end;

destructor TSpeedBatch.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

end.
