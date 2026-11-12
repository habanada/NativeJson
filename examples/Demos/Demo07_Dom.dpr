{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo07_Dom;

{$I NativeJson.inc}

{
  DEMO 7 - Working without classes: the DOM

  Sometimes you do not want an object at all, you just want to pull something
  out of a foreign message quickly or build a small JSON.

  Shows: building a DOM, parsing, navigating, path queries (SelectToken,
         FindAll), convenience getters with a default value, filtering by
         condition, writing paths and the query chain (Q).
}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Demo.Assert in 'Demo.Assert.pas',
  NativeJson.Main,
  NativeJson.Dom.Value,
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.Primitive,
  NativeJson.Linq;

const
  Notice =
    '{' +
    '"invoice_no":"P-77001",' +
    '"customer":{"nr":"K-4711","name":"Sample Corp","city":"Bremen"},' +
    '"lineItems":[' +
    '{"pos":10,"article":"ART-400-24","quantity":3,"price":129.5},' +
    '{"pos":20,"article":"ART-2X1.5","quantity":50,"price":1.25},' +
    '{"pos":30,"article":"ART-M4","quantity":200,"price":0.08}' +
    ']}';

// ---------------------------------------------------------------------------

procedure Step1_BuildDom;
var
  Root, Customer: TJsonObject;
  LineItems: TJsonArray;
  Pos1: TJsonObject;
begin
  Section('1. Building a JSON by hand');
  Root := TJsonObject.Create;
  try
    Root.AddPair('invoice_no', 'B-1');

    Customer := TJsonObject.Create;
    Customer.AddPair('nr', 'K-1');
    Customer.AddPair('name', 'Sample Corp');
    Root.AddPair('customer', Customer); // from now on Customer belongs to Root

    LineItems := TJsonArray.Create;
    Pos1 := TJsonObject.Create;
    Pos1.AddPair('pos', 10);
    Pos1.AddPair('quantity', 2.5);
    LineItems.Add(Pos1);
    Root.AddPair('lineItems', LineItems);

    Show('JSON', Root.ToJson);

    // The DOM keeps the insertion order - unlike the
    // RTTI-based serialization of objects.
    Check('Exact output',
      '{"invoice_no":"B-1","customer":{"nr":"K-1","name":"Sample Corp"},' +
      '"lineItems":[{"pos":10,"quantity":2.5}]}',
      Root.ToJson);

    Check('Number of top-level keys', 3, Root.Count);
  finally
    Root.Free; // frees the whole tree
  end;
end;

procedure Step2_Navigate;
var
  Dom: TJsonValue;
  LineItems: TJsonValue;
begin
  Section('2. Parsing and navigating');
  Dom := JsonConvert.DeserializeObject(Notice);
  try
    CheckTrue('Root is an object', Dom.GetJsonType = TJsonType.jtObject);

    Check('Invoice number', 'P-77001', Dom.Values['invoice_no'].AsString);
    Check('Customer name', 'Sample Corp', Dom.Values['customer'].Values['name'].AsString);

    LineItems := Dom.Values['lineItems'];
    CheckTrue('Line items are an array', LineItems.GetJsonType = TJsonType.jtArray);
    Check('Line item count', 3, TJsonArray(LineItems).Count);
    Check('Article of the first line item', 'ART-400-24',
      LineItems[0].Values['article'].AsString);
    Check('Quantity of the second line item', 50, Integer(LineItems[1].Values['quantity'].AsInteger));

    // Cross-check: a missing key is an error, not nil
    CheckError('Missing key raises an exception',
      procedure
      var
        Unknown: TJsonValue;
      begin
        Unknown := Dom.Values['missing'];
        if Unknown <> nil then Writeln('unreachable');
      end);
  finally
    Dom.Free;
  end;
end;

procedure Step3_Paths;
var
  Dom: TJsonValue;
  Hits: TJsonValue;
begin
  Section('3. Path queries with SelectToken');
  Dom := JsonConvert.DeserializeObject(Notice);
  try
    Hits := Dom.SelectToken('customer.city');
    CheckTrue('Path found', Hits <> nil);
    if Hits <> nil then
      Check('customer.city', 'Bremen', Hits.AsString);

    Hits := Dom.SelectToken('lineItems[2].article');
    CheckTrue('Index in the path', Hits <> nil);
    if Hits <> nil then
      Check('lineItems[2].article', 'ART-M4', Hits.AsString);

    Hits := Dom.SelectToken('does.not.exist');
    CheckTrue('Unknown path returns nil', Hits = nil);

    CheckTrue('TrySelectToken reports False',
      not Dom.TrySelectToken('customer.phone', Hits));
  finally
    Dom.Free;
  end;
end;

procedure Step4_ConvenienceGetters;
var
  Dom: TJsonValue;
begin
  Section('4. Convenience getters with a default value');
  Dom := JsonConvert.DeserializeObject(Notice);
  try
    Check('Existing text', 'Sample Corp', Dom.GetStringPath('customer.name'));
    Check('Missing text -> default', 'unknown',
      Dom.GetStringPath('customer.phone', 'unknown'));
    Check('Existing number', 10, Integer(Dom.GetIntegerPath('lineItems[0].pos')));
    Check('Missing number -> default', -1,
      Integer(Dom.GetIntegerPath('lineItems[0].discount', -1)));

    Writeln('       Benefit: no try/except needed for optional fields.');
  finally
    Dom.Free;
  end;
end;

procedure Step5_MultipleMatches;
var
  Dom: TJsonValue;
  Hits: TArray<TJsonValue>;
  I: Integer;
  Total: Double;
begin
  Section('5. Multiple hits (wildcard and deep search)');
  Dom := JsonConvert.DeserializeObject(Notice);
  try
    Hits := Dom.FindAll('lineItems[*].article');
    Check('All article numbers', 3, Length(Hits));
    if Length(Hits) = 3 then
    begin
      Check('First', 'ART-400-24', Hits[0].AsString);
      Check('Last', 'ART-M4', Hits[2].AsString);
    end;

    Hits := Dom.FindAll('lineItems[*].quantity');
    Total := 0;
    for I := 0 to High(Hits) do Total := Total + Hits[I].AsDouble;
    Check('Sum of all quantities', 253.0, Total);

    Hits := Dom.FindAll('$..article');
    Check('Deep search finds the same nodes', 3, Length(Hits));
  finally
    Dom.Free;
  end;
end;

procedure Step6_Filter;
var
  Dom: TJsonValue;
  Big: TArray<TJsonValue>;
begin
  Section('6. Filtering with a condition');
  Dom := JsonConvert.DeserializeObject(Notice);
  try
    // Note: Values['x'] raises an exception when the key is missing.
    // Always use TryGetValue for optional fields.
    Big := Dom.Find('lineItems[*]',
      function(const Val: TJsonValue): Boolean
      var
        Quantity: TJsonValue;
      begin
        Result := (Val is TJsonObject) and
                  TJsonObject(Val).TryGetValue('quantity', Quantity) and
                  (Quantity.AsDouble >= 50);
      end);

    Check('Line items with quantity >= 50', 2, Length(Big));
    if Length(Big) > 0 then
      Check('First hit', 'ART-2X1.5', Big[0].Values['article'].AsString);
  finally
    Dom.Free;
  end;
end;

procedure Step7_WritingPaths;
var
  Root: TJsonObject;
  Target: TJsonValue;
begin
  Section('7. Creating paths and setting values');
  Root := TJsonObject.Create;
  try
    Target := Root.EnsureObjectPath('delivery.address');
    CheckTrue('Intermediate levels were created', Target <> nil);
    if Target is TJsonObject then
      TJsonObject(Target).AddPair('city', 'Exampletown');

    Show('JSON', Root.ToJson);
    Check('Outcome', '{"delivery":{"address":{"city":"Exampletown"}}}', Root.ToJson);
    Check('Readable again via the path', 'Exampletown',
      Root.GetStringPath('delivery.address.city'));
  finally
    Root.Free;
  end;
end;

procedure Step8_Copy;
var
  Dom, CopyObj: TJsonValue;
begin
  Section('8. Clone - an independent copy');
  Dom := JsonConvert.DeserializeObject(Notice);
  try
    CopyObj := Dom.Clone;
    try
      Check('Copy has the same content', Dom.ToJson, CopyObj.ToJson);

      // Change the original, the copy must stay unchanged.
      // AddPair creates NEW entries and raises for an existing key.
      // To overwrite, Values[...] is the right way - the old
      // value is freed and the position in the order stays.
      Dom.Values['invoice_no'] := TJsonString.Create('CHANGED');
      Check('Original changed', 'CHANGED', Dom.GetStringPath('invoice_no'));
      Check('Copy unchanged', 'P-77001', CopyObj.GetStringPath('invoice_no'));

      CheckError('AddPair on an existing key raises',
        procedure
        begin
          TJsonObject(CopyObj).AddPair('invoice_no', 'again');
        end);
    finally
      CopyObj.Free;
    end;
  finally
    Dom.Free;
  end;
end;

procedure Step9_QueryChain;
var
  Dom: TJsonValue;
  ItemCount: Integer;
begin
  Section('9. Query chain (Q) in LINQ style');
  Dom := JsonConvert.DeserializeObject(Notice);
  try
    ItemCount := Dom.Q.Select('lineItems').Children.Where(
      function(const Val: TJsonValue): Boolean
      var
        Price: TJsonValue;
      begin
        Result := (Val is TJsonObject) and
                  TJsonObject(Val).TryGetValue('price', Price) and
                  (Price.AsDouble > 1);
      end).Count;

    Check('Line items with price > 1', 2, ItemCount);

    ItemCount := Dom.Q.Select('lineItems').Children.Count;
    Check('All line items', 3, ItemCount);
  finally
    Dom.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 7 - THE DOM: JSON WITHOUT CLASSES');

    Step1_BuildDom;
    Step2_Navigate;
    Step3_Paths;
    Step4_ConvenienceGetters;
    Step5_MultipleMatches;
    Step6_Filter;
    Step7_WritingPaths;
    Step8_Copy;
    Step9_QueryChain;

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
