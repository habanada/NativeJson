{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Test.Logistics.Model;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils, Classes, Generics.Collections,
  {$ELSE}
  System.SysUtils, System.Classes, System.Generics.Collections,
  {$ENDIF}
  NativeJson.Attributes, NativeJson.Schema.Attributes;

type
  TParcel = class;
  TPallet = class;

  // Enum with an explicit schema name
  [JsonDescription('The status of the shipment')]
  TShipmentStatus = (ssCreated, ssInTransit, ssDelivered, ssLost);

  // Base class for polymorphism
  [JsonKnownType('TPallet')]
  [JsonKnownType('TParcel')]
  [JsonDescription('Base class for all cargo items')]
  TCargoItem = class
  private
    FTrackingCode: string;
    FWeight: Double;
  public
    [JsonRequired]
    property TrackingCode: string read FTrackingCode write FTrackingCode;
    
    [JsonRange('0.1', '10000.0')]
    property Weight: Double read FWeight write FWeight;
  end;

  // Child class 1
  [JsonDescription('A standard parcel')]
  TParcel = class(TCargoItem)
  private
    FIsFragile: Boolean;
  public
    property IsFragile: Boolean read FIsFragile write FIsFragile;
  end;

  // Child class 2
  [JsonDescription('A pallet with goods')]
  TPallet = class(TCargoItem)
  private
    FLayerCount: Integer;
    FMaterial: string;
  public
    [JsonRange('1', '10')]
    property LayerCount: Integer read FLayerCount write FLayerCount;
    property Material: string read FMaterial write FMaterial;
  end;

  // A custom list that is NOT a TList (for the duck typing test)
  // Simulates a "legacy" list from an old library
  TCargoList = class
  private
    FItems: TObjectList<TCargoItem>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(Item: TCargoItem);
    function GetEnumerator: TEnumerator<TCargoItem>; // the decisive feature!
    property InternalList: TObjectList<TCargoItem> read FItems;
  end;

  // The main object (root)
  [JsonTitle('Logistics Order')]
  TShipmentOrder = class
  private
    FID: TGUID;
    FDate: TDateTime;
    FStatus: TShipmentStatus;
    FItems: TCargoList; // our custom list!
    FMetadata: TDictionary<string, Variant>; // generics with Variant
    FDocument: TMemoryStream; // binary data
    FSecretNote: string; // should be ignored by default
  public
    constructor Create;
    destructor Destroy; override;

    property ID: TGUID read FID write FID;
    property Date: TDateTime read FDate write FDate;
    property Status: TShipmentStatus read FStatus write FStatus;
    
    // Custom list -> must be detected as an array via duck typing
    property Cargo: TCargoList read FItems; 
    
    // Dictionary -> must be detected as a JSON object
    property Meta: TDictionary<string, Variant> read FMetadata;
    
    // Stream -> must be detected as Base64
    property Document: TMemoryStream read FDocument;

    [JsonIgnore] // ignored by default, enabled later via fluent!
    property SecretNote: string read FSecretNote write FSecretNote;
  end;

implementation

{ TCargoList }

constructor TCargoList.Create;
begin
  FItems := TObjectList<TCargoItem>.Create(True); // Owns Objects
end;

destructor TCargoList.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TCargoList.Add(Item: TCargoItem);
begin
  FItems.Add(Item);
end;

function TCargoList.GetEnumerator: TEnumerator<TCargoItem>;
begin
  Result := FItems.GetEnumerator;
end;

{ TShipmentOrder }

constructor TShipmentOrder.Create;
begin
  FItems := TCargoList.Create;
  FMetadata := TDictionary<string, Variant>.Create;
  FDocument := TMemoryStream.Create;
  CreateGUID(FID);
  FDate := Now;
end;

destructor TShipmentOrder.Destroy;
begin
  FItems.Free;
  FMetadata.Free;
  FDocument.Free;
  inherited;
end;

initialization
  JsonKeepTypes([TCargoItem, TParcel, TPallet]);

end.
