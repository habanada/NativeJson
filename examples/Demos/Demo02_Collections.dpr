{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo02_Collections;

{$I NativeJson.inc}

{
  DEMO 2 - Lists, arrays and dictionaries

  Shows: TArray<T>, TList<T>, TObjectList<T>, TDictionary<K,V>,
         nested lists, custom list classes (duck typing)
         and filling lists that already exist.
}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Rtti,
  Generics.Collections,
  Demo.Assert in 'Demo.Assert.pas',
  Demo.Model in 'Demo.Model.pas',
  NativeJson.Main,
  NativeJson.Attributes;

type
  TNumbers = TArray<Integer>;
  TTexts = TArray<string>;
  TNumberList = TList<Integer>;
  TAddressList = TObjectList<TAddress>;

procedure Step1_DynamicArray;
var
  Source, Target: TArray<string>;
  Json: string;
begin
  Section('1. TArray<string>');
  Source := ['ART-400-24', 'ART-2X1.5', 'ART-M4'];

  Json := JsonConvert.SerializeObject(TValue.From<TTexts>(Source));
  Check('JSON', '["ART-400-24","ART-2X1.5","ART-M4"]', Json);

  Target := JsonConvert.DeserializeObject<TTexts>(Json);
  Check('Count after round trip', 3, Length(Target));
  Check('First element', 'ART-400-24', Target[0]);
  Check('Last element', 'ART-M4', Target[2]);
end;

procedure Step2_NumberArray;
var
  Source, Target: TArray<Integer>;
  Json: string;
begin
  Section('2. TArray<Integer>');
  Source := [10, 20, 30];

  Json := JsonConvert.SerializeObject(TValue.From<TNumbers>(Source));
  Check('JSON', '[10,20,30]', Json);

  Target := JsonConvert.DeserializeObject<TNumbers>(Json);
  Check('ItemCount', 3, Length(Target));
  Check('Total', 60, Target[0] + Target[1] + Target[2]);
end;

procedure Step3_ListOfNumbers;
var
  TheList, CopyObj: TList<Integer>;
  Json: string;
begin
  Section('3. TList<Integer>');
  TheList := TList<Integer>.Create;
  try
    TheList.Add(1);
    TheList.Add(2);
    TheList.Add(3);

    Json := JsonConvert.SerializeObject(TheList);
    Check('JSON', '[1,2,3]', Json);

    CopyObj := JsonConvert.DeserializeObject<TNumberList>(Json);
    try
      Check('ItemCount', 3, CopyObj.Count);
      Check('Second element', 2, CopyObj[1]);
    finally
      CopyObj.Free;
    end;
  finally
    TheList.Free;
  end;
end;

procedure Step4_ObjectList;
var
  TheList, CopyObj: TObjectList<TAddress>;
  A: TAddress;
  Json: string;
begin
  Section('4. TObjectList<TAddress>');
  TheList := TObjectList<TAddress>.Create(True);
  try
    A := TAddress.Create; A.City := 'Exampletown'; A.ZipCode := '12345'; TheList.Add(A);
    A := TAddress.Create; A.City := 'Bremen'; A.ZipCode := '28195'; TheList.Add(A);

    Json := JsonConvert.SerializeObject(TheList);
    Show('JSON', Json);

    CheckTrue('JSON starts with [', (Json <> '') and (Json[1] = '['), Copy(Json, 1, 1));
    CheckContains('First city', '"City":"Exampletown"', Json);
    CheckContains('Second city', '"City":"Bremen"', Json);

    CopyObj := JsonConvert.DeserializeObject<TAddressList>(Json);
    try
      // Practical note: the activator finds the parameterless
      // TList<T>.Create - OwnsObjects is False then. Whoever frees
      // the list should set it beforehand, otherwise the
      // elements stay in memory.
      CopyObj.OwnsObjects := True;

      Check('ItemCount', 2, CopyObj.Count);
      Check('City [0]', 'Exampletown', CopyObj[0].City);
      Check('City [1]', 'Bremen', CopyObj[1].City);
      Check('ZipCode [1]', '28195', CopyObj[1].ZipCode);
    finally
      CopyObj.Free;
    end;
  finally
    TheList.Free;
  end;
end;

procedure Step5_Dictionary;
var
  Warehouse: TDictionary<string, Integer>;
  Json: string;
begin
  Section('5. TDictionary<string, Integer> -> JSON object');
  Warehouse := TDictionary<string, Integer>.Create;
  try
    Warehouse.Add('ART-400-24', 17);
    Warehouse.Add('ART-2X1.5', 240);

    Json := JsonConvert.SerializeObject(Warehouse);
    Show('JSON', Json);

    // The order in a dictionary is not guaranteed -> only check the content
    CheckContains('First key', '"ART-400-24":17', Json);
    CheckContains('Second key', '"ART-2X1.5":240', Json);
    CheckTrue('Result is a JSON object', (Json <> '') and (Json[1] = '{'), Copy(Json, 1, 1));
  finally
    Warehouse.Free;
  end;
end;

procedure Step5b_ReadDictionary;
var
  Warehouse, CopyObj: TInventory;
  Json: string;
  Quantity: Integer;
begin
  Section('5b. Reading a dictionary - wrapped as a read-only property');
  Warehouse := TInventory.Create;
  try
    Warehouse.StorageLocation := 'Hall 3';
    Warehouse.Stock.Add('ART-400-24', 17);
    Warehouse.Stock.Add('ART-2X1.5', 240);

    Json := JsonConvert.SerializeObject(Warehouse);
    Show('JSON', Json);
    CheckContains('StorageLocation', '"StorageLocation":"Hall 3"', Json);
    CheckContains('Stock as sub-object', '"Stock":{', Json);

    CopyObj := JsonConvert.DeserializeObject<TInventory>(Json);
    try
      Check('StorageLocation after round trip', 'Hall 3', CopyObj.StorageLocation);
      Check('Number of entries', 2, CopyObj.Stock.Count);
      CheckTrue('Key found', CopyObj.Stock.TryGetValue('ART-400-24', Quantity));
      Check('Stock', 17, Quantity);
    finally
      CopyObj.Free;
    end;
  finally
    Warehouse.Free;
  end;
end;

procedure Step6_DictionaryWithObjects;
var
  Locations: TObjectDictionary<string, TAddress>;
  A: TAddress;
  Json: string;
begin
  Section('6. TObjectDictionary<string, TAddress>');
  Locations := TObjectDictionary<string, TAddress>.Create([doOwnsValues]);
  try
    A := TAddress.Create; A.City := 'Exampletown'; A.Country := 'DE';
    Locations.Add('Plant1', A);

    Json := JsonConvert.SerializeObject(Locations);
    Show('JSON', Json);

    CheckContains('Key as object name', '"Plant1":{', Json);
    CheckContains('Value as object', '"City":"Exampletown"', Json);
  finally
    Locations.Free;
  end;
end;

procedure Step7_DuckTyping;
var
  TheList, CopyObj: TArticleNumberList;
  Json: string;
begin
  Section('7. Custom list class without TList ancestry (duck typing)');
  TheList := TArticleNumberList.Create;
  try
    TheList.Add('A-1');
    TheList.Add('A-2');

    // It is recognized by GetEnumerator (writing) and Add (reading)
    Json := JsonConvert.SerializeObject(TheList);
    Check('JSON', '["A-1","A-2"]', Json);

    CopyObj := JsonConvert.DeserializeObject<TArticleNumberList>(Json);
    try
      Check('Count after round trip', 2, CopyObj.Count);
    finally
      CopyObj.Free;
    end;
  finally
    TheList.Free;
  end;
end;

procedure Step8_NestedList;
var
  Order, CopyObj: TOrder;
  Json: string;
begin
  Section('8. List as read-only property in the order');
  Order := CreateSampleOrder;
  try
    Json := JsonConvert.SerializeObject(Order);
    Show('JSON', Json);

    Check('Line items in the original', 3, Order.LineItems.Count);
    CheckContains('Line item array present', '"LineItems":[', Json);

    CopyObj := JsonConvert.DeserializeObject<TOrder>(Json);
    try
      // Note: without TypeNameHandling all line items are created as
      // the base class TLineItem - the count is still correct.
      Check('Line items after round trip', 3, CopyObj.LineItems.Count);
      Check('LineNo of the first line item', 10, CopyObj.LineItems[0].LineNo);
      Check('Order number', 'B-2026-0815', CopyObj.OrderNo);
      Check('Customer name', 'Example Trading GmbH', CopyObj.Customer.Name);
      Check('Customer city', 'Exampletown', CopyObj.Customer.Address.City);
    finally
      CopyObj.Free;
    end;
  finally
    Order.Free;
  end;
end;

procedure Step9_FillExistingList;
var
  Order: TOrder;
  Json: string;
begin
  Section('9. PopulateObject replaces the content of existing lists');
  Order := CreateSampleOrder;
  try
    Check('Before', 3, Order.LineItems.Count);

    Json := '{"OrderNo":"B-NEW","LineItems":[{"LineNo":99}]}';
    JsonConvert.PopulateObject(Order, Json);

    Check('OrderNo updated', 'B-NEW', Order.OrderNo);
    Check('List was cleared and refilled', 1, Order.LineItems.Count);
    Check('New LineNo', 99, Order.LineItems[0].LineNo);
    Check('Customer stayed untouched', 'K-10042', Order.Customer.Number);
  finally
    Order.Free;
  end;
end;

procedure Step10_EmptyLists;
var
  TheList: TObjectList<TAddress>;
  Json: string;
  CopyObj: TObjectList<TAddress>;
begin
  Section('10. Empty lists');
  TheList := TObjectList<TAddress>.Create(True);
  try
    Json := JsonConvert.SerializeObject(TheList);
    Check('Empty list', '[]', Json);

    CopyObj := JsonConvert.DeserializeObject<TAddressList>('[]');
    try
      CopyObj.OwnsObjects := True;
      Check('Empty array read', 0, CopyObj.Count);
    finally
      CopyObj.Free;
    end;
  finally
    TheList.Free;
  end;
end;

begin
  try
    Title('DEMO 2 - LISTS, ARRAYS AND DICTIONARIES');

    Step1_DynamicArray;
    Step2_NumberArray;
    Step3_ListOfNumbers;
    Step4_ObjectList;
    Step5_Dictionary;
    Step5b_ReadDictionary;
    Step6_DictionaryWithObjects;
    Step7_DuckTyping;
    Step8_NestedList;
    Step9_FillExistingList;
    Step10_EmptyLists;

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
