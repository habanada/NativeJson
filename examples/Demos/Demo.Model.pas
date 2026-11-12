{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Demo.Model;

{
  Shared data model for all demo programs.

  Why is the model in a unit and not in the .dpr?
  Classes that are to be rebuilt via TypeNameHandling ($type)
  must be declared in the interface section of a unit. TRttiContext.FindType
  only finds such types. Classes declared in the program (.dpr)
  cannot be found through RTTI -> deserialization then raises
  "Unknown runtime type".
}

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
  TSalutation = (saMr, saMs, saCompany);
  TOrderStatus = (bsNew, bsConfirmed, bsDelivered, bsCancelled);

  // Forward declaration: the base class refers to these types by string
  TOrderLine = class;
  TTextLine = class;

  // ---------------------------------------------------------------------
  // Address - simple value object
  // ---------------------------------------------------------------------
  TAddress = class
  private
    FStreet: string;
    FZipCode: string;
    FCity: string;
    FCountry: string;
  public
    property Street: string read FStreet write FStreet;
    property ZipCode: string read FZipCode write FZipCode;
    property City: string read FCity write FCity;
    property Country: string read FCountry write FCountry;
  end;

  // ---------------------------------------------------------------------
  // Customer - holds an address as a READ-ONLY property.
  // The deserializer does not create a new address here, it fills
  // the instance created by the constructor.
  // ---------------------------------------------------------------------
  TCustomer = class
  private
    FNumber: string;
    FName: string;
    FSalutation: TSalutation;
    FEmail: string;
    FAddress: TAddress;
    FInternalNote: string;
  public
    constructor Create;
    destructor Destroy; override;

    property Number: string read FNumber write FNumber;
    property Name: string read FName write FName;
    property Salutation: TSalutation read FSalutation write FSalutation;
    property Email: string read FEmail write FEmail;
    property Address: TAddress read FAddress;

    // NOT serialized by default
    [JsonIgnore]
    property InternalNote: string read FInternalNote write FInternalNote;
  end;

  // ---------------------------------------------------------------------
  // Line items - polymorphic hierarchy
  // ---------------------------------------------------------------------
  [JsonKnownType('TOrderLine')]
  [JsonKnownType('TTextLine')]
  TLineItem = class
  private
    FLineNo: Integer;
  public
    property LineNo: Integer read FLineNo write FLineNo;
  end;

  TOrderLine = class(TLineItem)
  private
    FArticleNo: string;
    FQuantity: Double;
    FUnitPrice: Double;
  public
    function TotalPrice: Double;
    property ArticleNo: string read FArticleNo write FArticleNo;
    property Quantity: Double read FQuantity write FQuantity;
    property UnitPrice: Double read FUnitPrice write FUnitPrice;
  end;

  TTextLine = class(TLineItem)
  private
    FHint: string;
  public
    property Hint: string read FHint write FHint;
  end;

  // ---------------------------------------------------------------------
  // Order - the typical ERP document: header + line items
  // ---------------------------------------------------------------------
  TOrder = class
  private
    FOrderNo: string;
    FDate: TDateTime;
    FStatus: TOrderStatus;
    FCustomer: TCustomer;
    FLineItems: TObjectList<TLineItem>;
  public
    constructor Create;
    destructor Destroy; override;

    function Total: Double;

    property OrderNo: string read FOrderNo write FOrderNo;
    property Date: TDateTime read FDate write FDate;
    property Status: TOrderStatus read FStatus write FStatus;
    property Customer: TCustomer read FCustomer;
    property LineItems: TObjectList<TLineItem> read FLineItems;
  end;

  // ---------------------------------------------------------------------
  // Employee - for the cycle test ($id / $ref)
  // ---------------------------------------------------------------------
  TEmployee = class
  private
    FName: string;
    FSupervisor: TEmployee;
  public
    property Name: string read FName write FName;
    property Supervisor: TEmployee read FSupervisor write FSupervisor;
  end;

  // ---------------------------------------------------------------------
  // Record - records are serialized through their FIELDS
  // ---------------------------------------------------------------------
  TGeoPoint = record
    Width: Double;
    Len: Double;
  end;

  // ---------------------------------------------------------------------
  // Class without properties - only public fields.
  // Without MemberSelection the result here is {}!
  // ---------------------------------------------------------------------
  TMeterReading = class
  public
    Designation: string;
    Val: Integer;
  end;

  // ---------------------------------------------------------------------
  // Wrapper around a dictionary.
  // Practical tip: a TDictionary as the ROOT can be written,
  // but when reading the activator needs a parameterless
  // constructor - TDictionary does not have one. So it is wrapped in
  // a class and exposed as a read-only property: then the
  // existing instance is filled.
  // ---------------------------------------------------------------------
  TInventory = class
  private
    FStock: TDictionary<string, Integer>;
    FStorageLocation: string;
  public
    constructor Create;
    destructor Destroy; override;
    property StorageLocation: string read FStorageLocation write FStorageLocation;
    property Stock: TDictionary<string, Integer> read FStock;
  end;

  // ---------------------------------------------------------------------
  // Custom list without TList ancestry, but with GetEnumerator (duck typing)
  // ---------------------------------------------------------------------
  TArticleNumberList = class
  private
    FItems: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const S: string);
    function Count: Integer;
    function GetEnumerator: TEnumerator<string>;
  end;

  // ---------------------------------------------------------------------
  // For the schema demo: validation rules as attributes
  // ---------------------------------------------------------------------
  [JsonTitle('Supplier')]
  [JsonDescription('A supplier in the ERP master data')]
  TSupplier = class
  private
    FName: string;
    FEmail: string;
    FRating: Integer;
    FDiscount: Double;
  public
    [JsonRequired]
    [JsonMinLength(2)]
    property Name: string read FName write FName;

    [JsonRequired]
    [JsonPattern('^.+@.+\..+$')]
    [JsonSchemaFormat('email')]
    property Email: string read FEmail write FEmail;

    [JsonRange('0', '100')]
    [JsonDescription('Rating from 0 to 100')]
    property Rating: Integer read FRating write FRating;

    [JsonRange('0.0', '0.5')]
    property Discount: Double read FDiscount write FDiscount;
  end;

// Helper functions for building test data
function CreateSampleOrder: TOrder;

implementation

{ TCustomer }

constructor TCustomer.Create;
begin
  inherited Create;
  FAddress := TAddress.Create;
end;

destructor TCustomer.Destroy;
begin
  FAddress.Free;
  inherited;
end;

{ TOrderLine }

function TOrderLine.TotalPrice: Double;
begin
  Result := FQuantity * FUnitPrice;
end;

{ TOrder }

constructor TOrder.Create;
begin
  inherited Create;
  FCustomer := TCustomer.Create;
  FLineItems := TObjectList<TLineItem>.Create(True);
end;

destructor TOrder.Destroy;
begin
  FLineItems.Free;
  FCustomer.Free;
  inherited;
end;

function TOrder.Total: Double;
var
  Entry: TLineItem;
begin
  Result := 0;
  for Entry in FLineItems do
    if Entry is TOrderLine then
      Result := Result + TOrderLine(Entry).TotalPrice;
end;

{ TInventory }

constructor TInventory.Create;
begin
  inherited Create;
  FStock := TDictionary<string, Integer>.Create;
end;

destructor TInventory.Destroy;
begin
  FStock.Free;
  inherited;
end;

{ TArticleNumberList }

constructor TArticleNumberList.Create;
begin
  inherited Create;
  FItems := TList<string>.Create;
end;

destructor TArticleNumberList.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TArticleNumberList.Add(const S: string);
begin
  FItems.Add(S);
end;

function TArticleNumberList.Count: Integer;
begin
  Result := FItems.Count;
end;

function TArticleNumberList.GetEnumerator: TEnumerator<string>;
begin
  Result := FItems.GetEnumerator;
end;

{ Test data }

function CreateSampleOrder: TOrder;
var
  A1, A2: TOrderLine;
  T1: TTextLine;
begin
  Result := TOrder.Create;
  Result.OrderNo := 'B-2026-0815';
  Result.Date := EncodeDate(2026, 3, 15);
  Result.Status := bsConfirmed;

  Result.Customer.Number := 'K-10042';
  Result.Customer.Name := 'Example Trading GmbH';
  Result.Customer.Salutation := saCompany;
  Result.Customer.Email := 'purchasing@example.org';
  Result.Customer.InternalNote := 'Always pays on time';
  Result.Customer.Address.Street := 'Example Street 1';
  Result.Customer.Address.ZipCode := '12345';
  Result.Customer.Address.City := 'Exampletown';
  Result.Customer.Address.Country := 'DE';

  A1 := TOrderLine.Create;
  A1.LineNo := 10;
  A1.ArticleNo := 'ART-400-24';
  A1.Quantity := 5;
  A1.UnitPrice := 129.5;
  Result.LineItems.Add(A1);

  A2 := TOrderLine.Create;
  A2.LineNo := 20;
  A2.ArticleNo := 'ART-2X1.5';
  A2.Quantity := 100;
  A2.UnitPrice := 1.25;
  Result.LineItems.Add(A2);

  T1 := TTextLine.Create;
  T1.LineNo := 30;
  T1.Hint := 'Please deliver to ramp 2';
  Result.LineItems.Add(T1);
end;

initialization
  // Without this line the linker removes TOrderLine and TTextLine
  // from every program that does not create both itself - for example
  // from Demo08_Schema, which only generates a schema. The class names
  // appear there only as a string in the [JsonKnownType] attribute,
  // and a string is not a reference for the linker. The result would be
  // an empty "oneOf" in the schema or "Unknown runtime type" when reading.
  JsonKeepTypes([TLineItem, TOrderLine, TTextLine]);

end.
