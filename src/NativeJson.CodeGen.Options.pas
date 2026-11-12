{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.CodeGen.Options;

interface

{$I NativeJson.inc}

{$SCOPEDENUMS ON}

type
  TJsonCodeGenEntityKind = (Classes, Records);
  TJsonCodeGenArrayKind = (DynamicArrays, GenericLists, ObjectLists);
  TJsonCodeGenUnionKind = (BestCommonType, VariantForScalars, FallbackType);
  TJsonCodeGenNullableKind = (NativeDefaults, VariantForScalars, FallbackType);
  TJsonCodeGenEnumKind = (SafeDelphiEnum, ScalarConstants);
  TJsonCodeGenAdditionalPropertiesKind = (Ignore, DictionaryWhenPossible, FallbackType);
  TJsonCodeGenFormatKind = (StringsOnly, NativeTypes);

  TJsonCodeGenOptions = record
  public
    EntityKind: TJsonCodeGenEntityKind;
    ArrayKind: TJsonCodeGenArrayKind;
    UnionKind: TJsonCodeGenUnionKind;
    NullableKind: TJsonCodeGenNullableKind;
    EnumKind: TJsonCodeGenEnumKind;
    AdditionalPropertiesKind: TJsonCodeGenAdditionalPropertiesKind;
    FormatKind: TJsonCodeGenFormatKind;
    TypePrefix: string;
    RootTypeName: string;
    UnknownType: string;
    UnknownTypeUnit: string;
    IndentSize: Integer;
    GenerateUnusedDefinitions: Boolean;
    EmitJsonPropertyAttributes: Boolean;
    EmitSchemaAttributes: Boolean;
    EmitDefaults: Boolean;
    EmbedSchema: Boolean;
    OwnsGeneratedObjects: Boolean;
    UseTitlesForTypeNames: Boolean;
    DetectOpenApi: Boolean;
    PreferInt32WhenSafe: Boolean;
    PreferCurrencyForDecimal: Boolean;
    class function Default: TJsonCodeGenOptions; static;
    class function Records: TJsonCodeGenOptions; static;
    function SetEntityKind(Value: TJsonCodeGenEntityKind): TJsonCodeGenOptions;
    function SetArrayKind(Value: TJsonCodeGenArrayKind): TJsonCodeGenOptions;
    function SetUnionKind(Value: TJsonCodeGenUnionKind): TJsonCodeGenOptions;
    function SetNullableKind(Value: TJsonCodeGenNullableKind): TJsonCodeGenOptions;
    function SetEnumKind(Value: TJsonCodeGenEnumKind): TJsonCodeGenOptions;
    function SetAdditionalPropertiesKind(Value: TJsonCodeGenAdditionalPropertiesKind): TJsonCodeGenOptions;
    function SetFormatKind(Value: TJsonCodeGenFormatKind): TJsonCodeGenOptions;
    function SetTypePrefix(const Value: string): TJsonCodeGenOptions;
    function SetRootTypeName(const Value: string): TJsonCodeGenOptions;
    function SetUnknownType(const Value: string): TJsonCodeGenOptions;
    function SetUnknownTypeUnit(const Value: string): TJsonCodeGenOptions;
    function SetIndentSize(Value: Integer): TJsonCodeGenOptions;
    function SetGenerateUnusedDefinitions(Value: Boolean): TJsonCodeGenOptions;
    function SetEmitJsonPropertyAttributes(Value: Boolean): TJsonCodeGenOptions;
    function SetEmitSchemaAttributes(Value: Boolean): TJsonCodeGenOptions;
    function SetEmitDefaults(Value: Boolean): TJsonCodeGenOptions;
    function SetEmbedSchema(Value: Boolean): TJsonCodeGenOptions;
    function SetOwnsGeneratedObjects(Value: Boolean): TJsonCodeGenOptions;
    function SetUseTitlesForTypeNames(Value: Boolean): TJsonCodeGenOptions;
    function SetDetectOpenApi(Value: Boolean): TJsonCodeGenOptions;
    function SetPreferInt32WhenSafe(Value: Boolean): TJsonCodeGenOptions;
    function SetPreferCurrencyForDecimal(Value: Boolean): TJsonCodeGenOptions;
  end;

implementation

class function TJsonCodeGenOptions.Default: TJsonCodeGenOptions;
begin
  Result.EntityKind := TJsonCodeGenEntityKind.Classes;
  Result.ArrayKind := TJsonCodeGenArrayKind.DynamicArrays;
  Result.UnionKind := TJsonCodeGenUnionKind.BestCommonType;
  Result.NullableKind := TJsonCodeGenNullableKind.NativeDefaults;
  Result.EnumKind := TJsonCodeGenEnumKind.SafeDelphiEnum;
  Result.AdditionalPropertiesKind := TJsonCodeGenAdditionalPropertiesKind.DictionaryWhenPossible;
  Result.FormatKind := TJsonCodeGenFormatKind.NativeTypes;
  Result.TypePrefix := 'T';
  Result.RootTypeName := 'Root';
  Result.UnknownType := 'Variant';
  Result.UnknownTypeUnit := '';
  Result.IndentSize := 2;
  Result.GenerateUnusedDefinitions := True;
  Result.EmitJsonPropertyAttributes := True;
  Result.EmitSchemaAttributes := True;
  Result.EmitDefaults := True;
  Result.EmbedSchema := True;
  Result.OwnsGeneratedObjects := True;
  Result.UseTitlesForTypeNames := True;
  Result.DetectOpenApi := True;
  Result.PreferInt32WhenSafe := True;
  Result.PreferCurrencyForDecimal := False;
end;

class function TJsonCodeGenOptions.Records: TJsonCodeGenOptions;
begin
  Result := Default;
  Result.EntityKind := TJsonCodeGenEntityKind.Records;
  Result.OwnsGeneratedObjects := False;
end;

function TJsonCodeGenOptions.SetEntityKind(Value: TJsonCodeGenEntityKind): TJsonCodeGenOptions;
begin Result := Self; Result.EntityKind := Value; end;
function TJsonCodeGenOptions.SetArrayKind(Value: TJsonCodeGenArrayKind): TJsonCodeGenOptions;
begin Result := Self; Result.ArrayKind := Value; end;
function TJsonCodeGenOptions.SetUnionKind(Value: TJsonCodeGenUnionKind): TJsonCodeGenOptions;
begin Result := Self; Result.UnionKind := Value; end;
function TJsonCodeGenOptions.SetNullableKind(Value: TJsonCodeGenNullableKind): TJsonCodeGenOptions;
begin Result := Self; Result.NullableKind := Value; end;
function TJsonCodeGenOptions.SetEnumKind(Value: TJsonCodeGenEnumKind): TJsonCodeGenOptions;
begin Result := Self; Result.EnumKind := Value; end;
function TJsonCodeGenOptions.SetAdditionalPropertiesKind(Value: TJsonCodeGenAdditionalPropertiesKind): TJsonCodeGenOptions;
begin Result := Self; Result.AdditionalPropertiesKind := Value; end;
function TJsonCodeGenOptions.SetFormatKind(Value: TJsonCodeGenFormatKind): TJsonCodeGenOptions;
begin Result := Self; Result.FormatKind := Value; end;
function TJsonCodeGenOptions.SetTypePrefix(const Value: string): TJsonCodeGenOptions;
begin Result := Self; Result.TypePrefix := Value; end;
function TJsonCodeGenOptions.SetRootTypeName(const Value: string): TJsonCodeGenOptions;
begin Result := Self; Result.RootTypeName := Value; end;
function TJsonCodeGenOptions.SetUnknownType(const Value: string): TJsonCodeGenOptions;
begin Result := Self; Result.UnknownType := Value; end;
function TJsonCodeGenOptions.SetUnknownTypeUnit(const Value: string): TJsonCodeGenOptions;
begin Result := Self; Result.UnknownTypeUnit := Value; end;
function TJsonCodeGenOptions.SetIndentSize(Value: Integer): TJsonCodeGenOptions;
begin Result := Self; if Value < 0 then Value := 0; Result.IndentSize := Value; end;
function TJsonCodeGenOptions.SetGenerateUnusedDefinitions(Value: Boolean): TJsonCodeGenOptions;
begin Result := Self; Result.GenerateUnusedDefinitions := Value; end;
function TJsonCodeGenOptions.SetEmitJsonPropertyAttributes(Value: Boolean): TJsonCodeGenOptions;
begin Result := Self; Result.EmitJsonPropertyAttributes := Value; end;
function TJsonCodeGenOptions.SetEmitSchemaAttributes(Value: Boolean): TJsonCodeGenOptions;
begin Result := Self; Result.EmitSchemaAttributes := Value; end;
function TJsonCodeGenOptions.SetEmitDefaults(Value: Boolean): TJsonCodeGenOptions;
begin Result := Self; Result.EmitDefaults := Value; end;
function TJsonCodeGenOptions.SetEmbedSchema(Value: Boolean): TJsonCodeGenOptions;
begin Result := Self; Result.EmbedSchema := Value; end;
function TJsonCodeGenOptions.SetOwnsGeneratedObjects(Value: Boolean): TJsonCodeGenOptions;
begin Result := Self; Result.OwnsGeneratedObjects := Value; end;
function TJsonCodeGenOptions.SetUseTitlesForTypeNames(Value: Boolean): TJsonCodeGenOptions;
begin Result := Self; Result.UseTitlesForTypeNames := Value; end;
function TJsonCodeGenOptions.SetDetectOpenApi(Value: Boolean): TJsonCodeGenOptions;
begin Result := Self; Result.DetectOpenApi := Value; end;
function TJsonCodeGenOptions.SetPreferInt32WhenSafe(Value: Boolean): TJsonCodeGenOptions;
begin Result := Self; Result.PreferInt32WhenSafe := Value; end;
function TJsonCodeGenOptions.SetPreferCurrencyForDecimal(Value: Boolean): TJsonCodeGenOptions;
begin Result := Self; Result.PreferCurrencyForDecimal := Value; end;

end.
