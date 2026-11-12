{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo08_Schema;

{$I NativeJson.inc}

{
  DEMO 8 - Generating a JSON schema

  A JSON schema can be derived from the classes and their attributes
  - useful for Swagger/OpenAPI, for documenting
  an interface or as a validation template for the partner.

  Shows: schema from attributes, schema for nested documents,
         polymorphism (oneOf) and the influence of the fluent configuration.
}

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Demo.Assert in 'Demo.Assert.pas',
  Demo.Model in 'Demo.Model.pas',
  NativeJson.Main,
  NativeJson.Dom.JsonObject,
  NativeJson.Fluent;

procedure Step1_SchemaFromAttributes;
var
  Schema: TJsonObject;
  S: string;
begin
  Section('1. Schema from the attributes of the class');
  Schema := JsonConvert.GenerateSchema<TSupplier>;
  try
    S := Schema.ToJson;
    Writeln(S);
    Writeln;

    CheckContains('Type is object', '"type":"object"', S);
    CheckContains('Title from [JsonTitle]', '"title":"Supplier"', S);
    CheckContains('Description from [JsonDescription]',
      'supplier in the ERP master data', S);
    CheckContains('Properties block', '"properties"', S);
    CheckContains('Regular expression from [JsonPattern]', '"pattern"', S);
    CheckContains('Minimum length from [JsonMinLength]', '"minLength":2', S);
    CheckContains('Format from [JsonSchemaFormat]', '"format":"email"', S);
    CheckContains('Lower bound from [JsonRange]', '"minimum":0', S);
    CheckContains('Upper bound from [JsonRange]', '"maximum":100', S);
    CheckContains('Upper bound with a decimal place', '"maximum":0.5', S);
    CheckContains('Field description', 'Rating from 0 to 100', S);
  finally
    Schema.Free;
  end;
end;

procedure Step2_RequiredFieldsInSchema;
var
  Settings: TJsonSettings;
  Schema: TJsonObject;
  S: string;
begin
  Section('2. Adding required fields to the schema');
  Settings := TJsonSettings.Create;
  try
    // Note: the "required" block is fed from the
    // serialization configuration, not from [JsonRequired].
    // Whoever wants it in the schema sets the required field via fluent -
    // then it also applies when reading.
    Settings.Fluent.Entity<TSupplier>
      .Map('Name').Required(True).EndMember
      .Map('Email').Required(True).EndMember;

    Schema := JsonConvert.GenerateSchema<TSupplier>(Settings);
    try
      S := Schema.ToJson;
      Show('Schema', S);

      CheckContains('required block present', '"required"', S);
      CheckContains('Name is required', '"Name"', S);
      CheckContains('Email is required', '"Email"', S);
    finally
      Schema.Free;
    end;
  finally
    Settings.Free;
  end;
end;

procedure Step3_NestedInvoice;
var
  Schema: TJsonObject;
  S: string;
begin
  Section('3. Schema of a complete order');
  Schema := JsonConvert.GenerateSchema<TOrder>;
  try
    S := Schema.ToJson;
    Show('Schema', S);

    CheckContains('Order number', '"OrderNo"', S);
    CheckContains('Date as date-time', '"format":"date-time"', S);
    // Nullable fields get a type vector: "type":["array","null"]
    CheckContains('Line items as array', '"array"', S);
    CheckContains('Shown as nullable', '["array","null"]', S);
    CheckContains('Enumeration as enum', '"enum"', S);
    CheckContains('Value of the enumeration', 'bsConfirmed', S);
  finally
    Schema.Free;
  end;
end;

procedure Step4_Polymorphism;
var
  Schema: TJsonObject;
  S: string;
begin
  Section('4. Polymorphism in the schema (oneOf + discriminator)');

  // Important: the case distinction is created in the definitions
  // ($defs) that are referenced - i.e. for the order that contains the
  // line items, not for a direct call for TLineItem.
  Schema := JsonConvert.GenerateSchema<TOrder>;
  try
    S := Schema.ToJson;
    Writeln(S);
    Writeln;

    CheckContains('Definitions block present', '"$ref"', S);
    CheckContains('oneOf for the subclasses', '"oneOf"', S);
    CheckContains('Discriminator', '"discriminator"', S);
    CheckContains('Discriminator is $type', '"propertyName":"$type"', S);

    // The names in the $defs block have no leading T -
    // GetTypeName strips it: TOrderLine -> OrderLine.
    CheckNotContains('oneOf is not empty', '"oneOf":[]', S);
    CheckContains('Order line is known', 'OrderLine', S);
    CheckContains('Text line is known', 'TextLine', S);
  finally
    Schema.Free;
  end;
end;

procedure Step5_FluentAffectsSchema;
var
  Settings: TJsonSettings;
  Schema: TJsonObject;
  S: string;
begin
  Section('5. Renamed fields also appear in the schema');
  Settings := TJsonSettings.Create;
  try
    Settings.Fluent.Entity<TSupplier>
      .Map('Name').Name('supplier_name').EndMember
      .Map('Rating').Ignore;

    Schema := JsonConvert.GenerateSchema<TSupplier>(Settings);
    try
      S := Schema.ToJson;
      Show('Schema', S);

      CheckContains('New field name', '"supplier_name"', S);
      CheckNotContains('Ignored field is missing', '"Rating"', S);
    finally
      Schema.Free;
    end;
  finally
    Settings.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 8 - JSON-SCHEMA');

    Step1_SchemaFromAttributes;
    Step2_RequiredFieldsInSchema;
    Step3_NestedInvoice;
    Step4_Polymorphism;
    Step5_FluentAffectsSchema;

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
