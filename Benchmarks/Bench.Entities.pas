{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Bench.Entities;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, 
  NativeJson.Attributes;

type
  TEntityType = (etUser, etSystem, etExternal);

  // Base class with attributes for both frameworks
  [JsonObject(TJsonMemberSerialization.OptOut)]
  TBaseEntity = class
  private
    FID: TGUID;
    FCreatedAt: TDateTime;
    FInternalCache: Integer; // should be ignored
  public
    constructor Create;
    property ID: TGUID read FID write FID;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;

  // Complex child with dictionary and list
  TComplexItem = class(TBaseEntity)
  private
    FName: string;
    FTags: TList<string>;
    FMeta: TDictionary<string, Integer>;
    FType: TEntityType;
  public
    constructor Create;
    destructor Destroy; override;
    
    [JsonProperty('display_name')]
    property Name: string read FName write FName;
    
    property Tags: TList<string> read FTags;
    property Meta: TDictionary<string, Integer> read FMeta;
    property EntityType: TEntityType read FType write FType;
  end;

  // The memory hog (simulates images/files)
  THeavyBlob = class(TBaseEntity)
  private
    FData: TBytes;
    FSizeInfo: string;
  public
    constructor Create(SizeMB: Integer);
    
    // Neon automatically uses Base64 for TBytes here
    property Data: TBytes read FData write FData;
    
    property SizeInfo: string read FSizeInfo;
  end;

  // The root container
  TRootContainer = class
  private
    FItems: TObjectList<TBaseEntity>;
    FDescription: string;
  public
    constructor Create;
    destructor Destroy; override;
    
    // Polymorphic list! Contains items and blobs mixed.
    property Items: TObjectList<TBaseEntity> read FItems;
    property Description: string read FDescription write FDescription;
  end;

implementation

{ TBaseEntity }

constructor TBaseEntity.Create;
begin
  CreateGUID(FID);
  FCreatedAt := Now;
end;

{ TComplexItem }

constructor TComplexItem.Create;
begin
  inherited;
  FTags := TList<string>.Create;
  FMeta := TDictionary<string, Integer>.Create;
end;

destructor TComplexItem.Destroy;
begin
  FTags.Free;
  FMeta.Free;
  inherited;
end;

{ THeavyBlob }

constructor THeavyBlob.Create(SizeMB: Integer);
begin
  inherited Create;
  SetLength(FData, SizeMB * 1024 * 1024); // allocate MB
  FillChar(FData[0], Length(FData), $FF); // fill data so it is not optimized away
  FSizeInfo := Format('%d MB Blob Data', [SizeMB]);
end;

{ TRootContainer }

constructor TRootContainer.Create;
begin
  FItems := TObjectList<TBaseEntity>.Create(True);
end;

destructor TRootContainer.Destroy;
begin
  FItems.Free;
  inherited;
end;

end.