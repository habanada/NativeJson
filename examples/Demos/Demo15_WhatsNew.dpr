{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo15_WhatsNew;

{$I NativeJson.inc}

// DEMO 15 - QUERY SURFACE, SEQUENTIAL READING, FLUENT POLYMORPHISM
//
//   1. The .Q surface offers everything IJsonQuery offers.
//   2. An array can be processed element by element instead of
//      loading it into memory as a whole.
//   3. Polymorphism can be configured via fluent - with a
//      custom discriminator field instead of $type.

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  Generics.Collections,
  Demo.Assert in 'Demo.Assert.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Fluent,
  NativeJson.Linq,
  NativeJson.Sequence,
  NativeJson.Settings,
  NativeJson.Dom.Value,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.Io;

type
  TEntryItem = class
  private
    FNumber: Integer;
    FAmount: Currency;
  published
    property Number: Integer read FNumber write FNumber;
    property Amount: Currency read FAmount write FAmount;
  end;

  // Polymorphism via a custom field, not via $type.
  TAnimal = class
  private
    FName: string;
  published
    property Name: string read FName write FName;
  end;

  TDog = class(TAnimal)
  private
    FBreed: string;
  published
    property Breed: string read FBreed write FBreed;
  end;

  TCat = class(TAnimal)
  private
    FInside: Boolean;
  published
    property Inside: Boolean read FInside write FInside;
  end;

  TEnclosure = class
  private
    FResident: TAnimal;
  public
    destructor Destroy; override;
  published
    property Resident: TAnimal read FResident write FResident;
  end;

destructor TEnclosure.Destroy;
begin
  FResident.Free;
  inherited;
end;

const
  Data =
    '{"article":[' +
    '{"name":"Widget","price":120,"warehouse":5},' +
    '{"name":"Gadget","price":15,"warehouse":0},' +
    '{"name":"Gizmo","price":45,"warehouse":12},' +
    '{"name":"Sprocket","price":3,"warehouse":40},' +
    '{"name":"Widget","price":120,"warehouse":5}]}';

function Price(const Item: TJsonValue): TJsonValue;
begin
  Result := Item.Values['price'];
end;

function Warehouse(const Item: TJsonValue): TJsonValue;
begin
  Result := Item.Values['warehouse'];
end;

// ---------------------------------------------------------------------------

procedure Step1_SelectionAndOrder;
var
  Dom: TJsonValue;
  Names: TArray<TJsonValue>;
  W: TJsonValue;
  Text: string;
begin
  Section('1. .Q: OrderBy, Take, Skip');
  Dom := DomFromText(Data);
  try
    // Most expensive first, take the top two.
    Names := Dom.Q.Select('article').Children.OrderByDescending(Price).Take(2)
      .Transform(function(const Item: TJsonValue): TJsonValue
        begin
          Result := Item.Values['name'];
        end).ToArray;
    Text := '';
    for W in Names do Text := Text + W.AsString + ' ';
    Show('two most expensive', Text);
    Check('two hits', 2, Length(Names));
    Check('the most expensive', 'Widget', Names[0].AsString);

    Check('Skip leaves out the first two', 3,
      Dom.Q.Select('article').Children.Skip(2).Count);
    Check('Take limits', 2,
      Dom.Q.Select('article').Children.Take(2).Count);
    // Taking more than there is must not blow up.
    Check('Take beyond the end', 5,
      Dom.Q.Select('article').Children.Take(99).Count);
  finally
    Dom.Free;
  end;
end;

procedure Step2_SetsAndChecks;
var
  Dom: TJsonValue;
  AllItems, EmptyItem, Expensive, Cheap: TJsonLinq;
begin
  Section('2. .Q: Distinct, Any, All, Single, Last, Union, Intersect');
  Dom := DomFromText(Data);
  try
    AllItems := Dom.Q.Select('article').Children;
    Check('five entries', 5, AllItems.Count);
    // The widget is in there twice, with identical content.
    Check('four distinct', 4, AllItems.Distinct.Count);

    CheckTrue('something is sold out',
      AllItems.Any(function(const I: TJsonValue): Boolean
        begin
          Result := I.Values['warehouse'].AsInteger = 0;
        end), '');
    CheckTrue('not everything is sold out',
      not AllItems.All(function(const I: TJsonValue): Boolean
        begin
          Result := I.Values['warehouse'].AsInteger = 0;
        end), '');
    CheckTrue('all have a price',
      AllItems.All(function(const I: TJsonValue): Boolean
        begin
          Result := I.Values['price'].AsDouble > 0;
        end), '');

    Expensive := AllItems.Where(function(const I: TJsonValue): Boolean
      begin
        Result := I.Values['price'].AsDouble > 100;
      end);
    Cheap := AllItems.Where(function(const I: TJsonValue): Boolean
      begin
        Result := I.Values['price'].AsDouble < 20;
      end);
    Check('two above 100', 2, Expensive.Count);
    Check('two below 20', 2, Cheap.Count);
    Check('expensive and cheap do not overlap', 0,
      Expensive.Intersect(Cheap).Count);
    // Union and Intersect are set operations, they remove duplicates. The
    // two expensive entries are the same widget, so intersecting
    // with itself leaves exactly one - not two.
    Check('Intersect with itself removes duplicates', 1, Expensive.Intersect(Expensive).Count);
    Check('Union with itself likewise', 4, AllItems.Union(AllItems).Count);
    // Concat does NOT remove duplicates - that is the difference.
    Check('Concat only appends', 10, AllItems.Concat(AllItems).Count);

    Check('Last', 'Widget', AllItems.Last.Values['name'].AsString);
    Check('Single on exactly one hit', 'Sprocket',
      AllItems.Where(function(const I: TJsonValue): Boolean
        begin
          Result := I.Values['warehouse'].AsInteger = 40;
        end).Single.Values['name'].AsString);

    Check('Sum of prices', 303.0, AllItems.Transform(Price).Sum);
    Check('Sum of stock levels', 62.0, AllItems.Transform(Warehouse).Sum);

    // An empty chain must not blow up - that is the most common
    // mistake with a surface like this.
    EmptyItem := Dom.Q.Select('missing').Children;
    Check('empty chain counts zero', 0, EmptyItem.Count);
    CheckTrue('Any on empty is False', not EmptyItem.Any, '');
    CheckTrue('All on empty is True',
      EmptyItem.All(function(const I: TJsonValue): Boolean
        begin
          Result := False;
        end), 'that way All is defined everywhere');
    Check('Sum on empty is zero', 0.0, EmptyItem.Sum);
    Check('Take on empty stays empty', 0, EmptyItem.Take(5).Count);
  finally
    Dom.Free;
  end;
end;

procedure Step3_ReadSequence;
var
  Text: string;
  Sb: TStringBuilder;
  I, ItemCount: Integer;
  NumberSum: Int64;
  AmountSum: Currency;
  ElementSeq: TJsonElementSequence;
  Element: TJsonValue;
  Counted: Integer;
begin
  Section('3. An array element by element');
  Writeln('       The handler gets every object individually. The node');
  Writeln('       behind it is already gone before the next one');
  Writeln('       is built.');

  Sb := TStringBuilder.Create;
  try
    Sb.Append('[');
    for I := 1 to 1000 do
    begin
      if I > 1 then Sb.Append(',');
      Sb.Append('{"Number":').Append(I).Append(',"Amount":').Append(I).Append('.25}');
    end;
    Sb.Append(']');
    Text := Sb.ToString;
  finally
    Sb.Free;
  end;

  NumberSum := 0;
  AmountSum := 0;
  ItemCount := JsonConvert.DeserializeSequence<TEntryItem>(Text,
    procedure(P: TEntryItem)
    begin
      try
        NumberSum := NumberSum + P.Number;
        AmountSum := AmountSum + P.Amount;
      finally
        // The handler is the owner. Without this Free the
        // saved memory would be back immediately.
        P.Free;
      end;
    end);

  Check('a thousand elements', 1000, ItemCount);
  CheckTrue('Sum of the numbers', NumberSum = 500500, IntToStr(NumberSum));
  CheckTrue('Sum of the amounts', AmountSum = 500750.00,
    CurrToStr(AmountSum));

  // The raw route, if you want to stop halfway.
  Counted := 0;
  ElementSeq := TJsonElementSequence.Create(Text);
  try
    while ElementSeq.NextItem(Element) do
    try
      Inc(Counted);
      if Counted >= 3 then Break;
    finally
      Element.Free;
    end;
  finally
    ElementSeq.Free;
  end;
  Check('stopped early', 3, Counted);

  // An empty array is not an error.
  Check('empty array', 0, JsonConvert.DeserializeSequence<TEntryItem>('[]',
    procedure(P: TEntryItem)
    begin
      P.Free;
    end));

  // Anything other than an array must be rejected cleanly.
  CheckError('an object at the top is not an array',
    procedure
    begin
      JsonConvert.DeserializeSequence<TEntryItem>('{"a":1}',
        procedure(P: TEntryItem)
        begin
          P.Free;
        end);
    end);
  CheckError('truncated array',
    procedure
    begin
      JsonConvert.DeserializeSequence<TEntryItem>('[{"Number":1}',
        procedure(P: TEntryItem)
        begin
          P.Free;
        end);
    end);
end;

procedure Step4_FluentPolymorphism;
var
  Settings: TJsonSettings;
  G: TEnclosure;
  Json: string;
begin
  Section('4. Polymorphism via a custom field');
  Writeln('       Foreign JSON writes "kind":"dog", not');
  Writeln('       "$type":"Unit.TDog". That is exactly what this is for.');

  Settings := TJsonSettings.Create;
  try
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
    Settings.Fluent.Entity<TAnimal>
      .Discriminator('kind')
      .SubType('dog', TDog)
      .SubType('cat', TCat);

    // --- Reading
    G := JsonConvert.DeserializeObject<TEnclosure>(
      '{"Resident":{"kind":"dog","Name":"Rex","Breed":"Shepherd"}}', Settings);
    try
      CheckTrue('the subclass was recognized', G.Resident is TDog,
        G.Resident.ClassName);
      Check('Base field arrived', 'Rex', G.Resident.Name);
      Check('own field of the subclass', 'Shepherd',
        TDog(G.Resident).Breed);
    finally
      G.Free;
    end;

    G := JsonConvert.DeserializeObject<TEnclosure>(
      '{"Resident":{"kind":"cat","Name":"Mimi","Inside":true}}', Settings);
    try
      CheckTrue('the other subclass likewise', G.Resident is TCat,
        G.Resident.ClassName);
      CheckTrue('its field too', TCat(G.Resident).Inside, '');
    finally
      G.Free;
    end;

    // --- Writing
    G := TEnclosure.Create;
    try
      G.Resident := TDog.Create;
      G.Resident.Name := 'Bello';
      TDog(G.Resident).Breed := 'Dachshund';
      Json := JsonConvert.SerializeObject(G, Settings);
      Show('written', Json);
      CheckContains('the custom field is in it', '"kind":"dog"', Json);
      CheckNotContains('and $type is not', '$type', Json);
    finally
      G.Free;
    end;

    // --- Round trip
    G := JsonConvert.DeserializeObject<TEnclosure>(Json, Settings);
    try
      CheckTrue('Round trip keeps the class', G.Resident is TDog,
        G.Resident.ClassName);
      Check('and the content', 'Dachshund', TDog(G.Resident).Breed);
    finally
      G.Free;
    end;

    // --- An unknown value must blow up, not stay silent
    CheckError('unknown kind',
      procedure
      var
        X: TEnclosure;
      begin
        X := JsonConvert.DeserializeObject<TEnclosure>(
          '{"Resident":{"kind":"bird","Name":"Piep"}}', Settings);
        X.Free;
      end);
  finally
    Settings.Free;
  end;
end;

procedure Step5_ExistingUntouched;
var
  Settings: TJsonSettings;
  G: TEnclosure;
  Json: string;
begin
  Section('5. Without configuration everything stays as before');
  Writeln('       This is the most important check of this demo: the');
  Writeln('       built-in $type route must not have changed.');

  Settings := TJsonSettings.Create;
  try
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
    // NO discriminator configured.
    G := TEnclosure.Create;
    try
      G.Resident := TDog.Create;
      G.Resident.Name := 'Rex';
      Json := JsonConvert.SerializeObject(G, Settings);
      Show('written', Json);
      CheckContains('$type is in it again', '$type', Json);
      CheckNotContains('and no kind', '"kind"', Json);
    finally
      G.Free;
    end;

    G := JsonConvert.DeserializeObject<TEnclosure>(Json, Settings);
    try
      CheckTrue('and the round trip via $type still works',
        G.Resident is TDog, G.Resident.ClassName);
    finally
      G.Free;
    end;
  finally
    Settings.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    JsonKeepTypes([TDog, TCat]);
    Title('DEMO 15 - Q SURFACE, SEQUENCE READER, FLUENT POLYMORPHISM');

    Step1_SelectionAndOrder;
    Step2_SetsAndChecks;
    Step3_ReadSequence;
    Step4_FluentPolymorphism;
    Step5_ExistingUntouched;

    ExitCode := Summary;
  except
    on E: Exception do
    begin
      Writeln('ABORTED: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
  if ParamCount = 0 then
  begin
    Writeln;
    Writeln('Press Enter ...');
    Readln;
  end;
end.
