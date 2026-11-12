{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo04_Polymorphism;

{$I NativeJson.inc}

{
  DEMO 4 - Polymorphism and object graphs

  Shows: $type for derived classes, the difference with and without
         TypeNameHandling, and $id/$ref for cyclic references.

  All classes that are rebuilt via $type
  live in Demo.Model.pas. Classes declared in the .dpr are not found
  by RTTI - deserialization then fails.
}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Generics.Collections,
  Demo.Assert in 'Demo.Assert.pas',
  Demo.Model in 'Demo.Model.pas',
  NativeJson.Main,
  NativeJson.Serializer.Writer;

type
  TLineItemList = TObjectList<TLineItem>;

function CreateLineItemList: TObjectList<TLineItem>;
var
  A: TOrderLine;
  T: TTextLine;
begin
  Result := TObjectList<TLineItem>.Create(True);

  A := TOrderLine.Create;
  A.LineNo := 10;
  A.ArticleNo := 'ART-400-24';
  A.Quantity := 5;
  A.UnitPrice := 129.5;
  Result.Add(A);

  T := TTextLine.Create;
  T.LineNo := 20;
  T.Hint := 'Deliver to ramp 2';
  Result.Add(T);
end;

// ---------------------------------------------------------------------------

procedure Step1_WithoutTypeInfo;
var
  TheList: TObjectList<TLineItem>;
  Json: string;
begin
  Section('1. Without TypeNameHandling the class is lost');
  TheList := CreateLineItemList;
  try
    Json := JsonConvert.SerializeObject(TheList);
    Show('JSON', Json);

    // The real data of the subclasses is still written
    CheckContains('Article number is included', 'ART-400-24', Json);
    CheckNotContains('No $type marker', '$type', Json);
    Writeln('       Note: when reading, plain TLineItem objects are created from this.');
  finally
    TheList.Free;
  end;
end;

procedure Step2_WithTypeInfo;
var
  TheList: TObjectList<TLineItem>;
  Settings: TJsonSettings;
  Json: string;
begin
  Section('2. With TypeNameHandling.Auto $type is written');
  TheList := CreateLineItemList;
  Settings := TJsonSettings.Create;
  try
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
    Settings.Formatting := TJsonFormatting.Indented;

    Json := JsonConvert.SerializeObject(TheList, Settings);
    Writeln(Json);

    CheckContains('Marker present', '"$type"', Json);
    CheckContains('Fully qualified name of the order line',
      'Demo.Model.TOrderLine', Json);
    CheckContains('Fully qualified name of the text line',
      'Demo.Model.TTextLine', Json);
  finally
    TheList.Free;
    Settings.Free;
  end;
end;

procedure Step3_PolymorphicRoundTrip;
var
  TheList, CopyObj: TObjectList<TLineItem>;
  Settings: TJsonSettings;
  Json: string;
begin
  Section('3. Round trip: subclasses come back as subclasses');
  TheList := CreateLineItemList;
  Settings := TJsonSettings.Create;
  try
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
    Json := JsonConvert.SerializeObject(TheList, Settings);

    CopyObj := JsonConvert.DeserializeObject<TLineItemList>(Json, Settings);
    try
      CopyObj.OwnsObjects := True;

      Check('ItemCount', 2, CopyObj.Count);
      CheckTrue('Element 0 is TOrderLine',
        CopyObj[0] is TOrderLine, CopyObj[0].ClassName);
      CheckTrue('Element 1 is TTextLine',
        CopyObj[1] is TTextLine, CopyObj[1].ClassName);

      if CopyObj[0] is TOrderLine then
      begin
        Check('Article number', 'ART-400-24', TOrderLine(CopyObj[0]).ArticleNo);
        Check('Quantity', 5.0, TOrderLine(CopyObj[0]).Quantity);
        Check('TotalPrice', 647.5, TOrderLine(CopyObj[0]).TotalPrice, 0.001);
      end;

      if CopyObj[1] is TTextLine then
        Check('Hint text', 'Deliver to ramp 2', TTextLine(CopyObj[1]).Hint);
    finally
      CopyObj.Free;
    end;
  finally
    TheList.Free;
    Settings.Free;
  end;
end;

procedure Step4_CompleteInvoice;
var
  Order, CopyObj: TOrder;
  Settings: TJsonSettings;
  Json: string;
begin
  Section('4. Complete order with mixed line items');
  Order := CreateSampleOrder;
  Settings := TJsonSettings.Create;
  try
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
    Json := JsonConvert.SerializeObject(Order, Settings);
    Show('JSON', Json);

    CopyObj := JsonConvert.DeserializeObject<TOrder>(Json, Settings);
    try
      Check('Order number', 'B-2026-0815', CopyObj.OrderNo);
      Check('Line item count', 3, CopyObj.LineItems.Count);
      CheckTrue('Line item 1 is an article', CopyObj.LineItems[0] is TOrderLine,
        CopyObj.LineItems[0].ClassName);
      CheckTrue('Line item 3 is text', CopyObj.LineItems[2] is TTextLine,
        CopyObj.LineItems[2].ClassName);
      Check('Order total', Order.Total, CopyObj.Total, 0.001);
      Check('Customer city', 'Exampletown', CopyObj.Customer.Address.City);
    finally
      CopyObj.Free;
    end;
  finally
    Order.Free;
    Settings.Free;
  end;
end;

procedure Step5_Cycles;
var
  Boss, Employee, Loaded: TEmployee;
  Settings: TJsonSettings;
  Json: string;
begin
  Section('5. Cyclic references with $id / $ref');
  Boss := TEmployee.Create;
  Employee := TEmployee.Create;
  Settings := TJsonSettings.Create;
  try
    Boss.Name := 'Ms Meier';
    Employee.Name := 'Mr Schmidt';
    Employee.Supervisor := Boss;
    Boss.Supervisor := Employee; // deliberate cycle

    Settings.PreserveReferences := TJsonPreserveReferences.Objects;
    Settings.Formatting := TJsonFormatting.Indented;

    Json := JsonConvert.SerializeObject(Employee, Settings);
    Writeln(Json);

    CheckContains('Object ids are assigned', '"$id"', Json);
    CheckContains('Back reference instead of an endless loop', '"$ref"', Json);

    Loaded := JsonConvert.DeserializeObject<TEmployee>(Json, Settings);
    try
      Check('Name', 'Mr Schmidt', Loaded.Name);
      CheckTrue('Supervisor loaded', Loaded.Supervisor <> nil);
      if Loaded.Supervisor <> nil then
      begin
        Check('Name of the supervisor', 'Ms Meier', Loaded.Supervisor.Name);
        CheckTrue('Cycle points to the same instance',
          Loaded.Supervisor.Supervisor = Loaded,
          'Identity restored');
      end;
    finally
      // Break the cycle before freeing
      if Loaded.Supervisor <> nil then
      begin
        Loaded.Supervisor.Supervisor := nil;
        Loaded.Supervisor.Free;
      end;
      Loaded.Free;
    end;
  finally
    Boss.Supervisor := nil;
    Employee.Supervisor := nil;
    Boss.Free;
    Employee.Free;
    Settings.Free;
  end;
end;

procedure Step6_ErrorOnUnknownType;
var
  Settings: TJsonSettings;
begin
  Section('6. Cross-check: unknown type in $type');
  Settings := TJsonSettings.Create;
  try
    Settings.TypeNameHandling := TJsonTypeNameHandling.Auto;
    CheckError('Unknown $type raises an exception',
      procedure
      var
        TheList: TObjectList<TLineItem>;
      begin
        TheList := JsonConvert.DeserializeObject<TLineItemList>(
          '[{"$type":"Does.Not.Exist.TSomething","LineNo":1}]', Settings);
        TheList.Free;
      end);
  finally
    Settings.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 4 - POLYMORPHISM AND OBJECT GRAPHS');

    Step1_WithoutTypeInfo;
    Step2_WithTypeInfo;
    Step3_PolymorphicRoundTrip;
    Step4_CompleteInvoice;
    Step5_Cycles;
    Step6_ErrorOnUnknownType;

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
