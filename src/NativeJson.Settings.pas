{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Settings;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  TypInfo,
  Rtti,
  Generics.Collections,
  {$ELSE}
  System.TypInfo,
  System.Rtti,
  System.Generics.Collections,
  {$ENDIF}
  
  NativeJson.Attributes,
  NativeJson.Serializer.Writer,
  NativeJson.NamingStrategy,
  NativeJson.Deserializer.Generics,
  NativeJson.Fluent;

type
  TObjectFactoryProc = reference to function(RType: TRttiType): TObject;
  TKeySerializerProc = reference to function(const Key: TValue): string;
  TKeyDeserializerProc = reference to function(const Key: string): TValue;
  TValueTransformerProc = reference to procedure(const FieldName: string; var Value: TValue);

  TJsonSettings = class
  private
    FFormatting: TJsonFormatting;
    FEnumHandling: TJsonEnumHandling;
    FDateFormat: string;
    FPreserveReferences: TJsonPreserveReferences;
    FTypeNameHandling: TJsonTypeNameHandling;
    
    FNamingStrategy: TJsonNamingStrategyClass;
    FCaseStyle: TJsonCaseStyle;

    FMemberSelection: TJsonMemberTypes;

    FNullValueHandling: TJsonNullValueHandling;
    FDefaultValueHandling: TJsonDefaultValueHandling;
    FMissingMemberHandling: TJsonMissingMemberHandling;
    FStrictTypes: Boolean;
    FJson5: Boolean;
    FWrapBytes: Boolean;
    
    FCollectionAdapters: TDictionary<PTypeInfo, TCollectionAddProc>;
    FFactories: TDictionary<PTypeInfo, TObjectFactoryProc>;
    FKeySerializers: TDictionary<PTypeInfo, TKeySerializerProc>;
    FKeyDeserializers: TDictionary<PTypeInfo, TKeyDeserializerProc>;
    FValueTransformers: TDictionary<PTypeInfo, TValueTransformerProc>;
    
    FFluentConfig: TJsonFluentContext;

  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterCollectionAdapter<T>(Proc: TCollectionAddProc);
    procedure RegisterFactory<T>(const Factory: TObjectFactoryProc);
    procedure RegisterKeySerializer<T>(const Proc: TKeySerializerProc);
    procedure RegisterKeyDeserializer<T>(const Proc: TKeyDeserializerProc);
    procedure RegisterValueTransformer<T>(const Proc: TValueTransformerProc);

    /// <summary>
    ///   Determines the NamingStrategy to use.
    ///   Priority: explicit strategy class > CaseStyle enum > default.
    /// </summary>
    function GetEffectiveNamingStrategy: TJsonNamingStrategyClass;

    property Fluent: TJsonFluentContext read FFluentConfig;

    property Formatting: TJsonFormatting read FFormatting write FFormatting;
    property DateFormat: string read FDateFormat write FDateFormat;

    property EnumHandling: TJsonEnumHandling read FEnumHandling write FEnumHandling;
    property PreserveReferences: TJsonPreserveReferences read FPreserveReferences write FPreserveReferences;
    property TypeNameHandling: TJsonTypeNameHandling read FTypeNameHandling write FTypeNameHandling;
    
    property NamingStrategy: TJsonNamingStrategyClass read FNamingStrategy write FNamingStrategy;
    property CaseStyle: TJsonCaseStyle read FCaseStyle write FCaseStyle;

    /// <summary>
    ///   Globally defines which member kinds are serialized.
    ///   Empty set = default behavior (classes: properties only, records: fields only).
    ///   [TJsonMemberType.mtProperties, TJsonMemberType.mtFields] also includes public fields.
    ///   Overridden by [JsonMemberSelection] on the type and by the fluent configuration.
    /// </summary>
    property MemberSelection: TJsonMemberTypes read FMemberSelection write FMemberSelection;

    property NullValueHandling: TJsonNullValueHandling read FNullValueHandling write FNullValueHandling;
    property DefaultValueHandling: TJsonDefaultValueHandling read FDefaultValueHandling write FDefaultValueHandling;
    property MissingMemberHandling: TJsonMissingMemberHandling read FMissingMemberHandling write FMissingMemberHandling;

    /// <summary>
    ///   True rejects a string where a number or a boolean
    ///   is required. Default is False, because many partner systems deliberately
    ///   send amounts as text so no parser touches them on the way.
    /// </summary>
    property StrictTypes: Boolean read FStrictTypes write FStrictTypes;
    property Json5: Boolean read FJson5 write FJson5;
    property WrapBytes: Boolean read FWrapBytes write FWrapBytes;
    
    property CollectionAdapters: TDictionary<PTypeInfo, TCollectionAddProc> read FCollectionAdapters;
    property Factories: TDictionary<PTypeInfo, TObjectFactoryProc> read FFactories;
    property KeySerializers: TDictionary<PTypeInfo, TKeySerializerProc> read FKeySerializers;
    property KeyDeserializers: TDictionary<PTypeInfo, TKeyDeserializerProc> read FKeyDeserializers;
    property ValueTransformers: TDictionary<PTypeInfo, TValueTransformerProc> read FValueTransformers;
  end;

implementation

{ TJsonSettings }

constructor TJsonSettings.Create;
begin
  inherited;
  FFormatting := TJsonFormatting.None;
  FEnumHandling := TJsonEnumHandling.ByName;
  FDateFormat := ''; 
  FPreserveReferences := TJsonPreserveReferences.None;
  FTypeNameHandling := TJsonTypeNameHandling.None;
  
  FNamingStrategy := nil;
  FCaseStyle := TJsonCaseStyle.jcUnchanged;
  FMemberSelection := [];
  
  FNullValueHandling := TJsonNullValueHandling.Include;
  FDefaultValueHandling := TJsonDefaultValueHandling.Include;
  FMissingMemberHandling := TJsonMissingMemberHandling.Ignore;
  FStrictTypes := False;
  FJson5 := False;
  FWrapBytes := False;

  FCollectionAdapters := TDictionary<PTypeInfo, TCollectionAddProc>.Create;
  FFactories := TDictionary<PTypeInfo, TObjectFactoryProc>.Create;
  FKeySerializers := TDictionary<PTypeInfo, TKeySerializerProc>.Create;
  FKeyDeserializers := TDictionary<PTypeInfo, TKeyDeserializerProc>.Create;
  FValueTransformers := TDictionary<PTypeInfo, TValueTransformerProc>.Create;
  
  FFluentConfig := TJsonFluentContext.Create;
end;

destructor TJsonSettings.Destroy;
begin
  FFluentConfig.Free;
  FValueTransformers.Free;
  FKeyDeserializers.Free;
  FKeySerializers.Free;
  FFactories.Free;
  FCollectionAdapters.Free;
  inherited;
end;

function TJsonSettings.GetEffectiveNamingStrategy: TJsonNamingStrategyClass;
begin
  // 1. An explicit class takes precedence
  if FNamingStrategy <> nil then
    Exit(FNamingStrategy);

  // 2. Mapping enum -> class
  case FCaseStyle of
    jcUnchanged:      Result := TDefaultNamingStrategy;
    jcLower:          Result := TLowerCaseNamingStrategy;
    jcUpper:          Result := TUpperCaseNamingStrategy;
    jcPascal:         Result := TPascalCaseNamingStrategy;
    jcCamel:          Result := TCamelCaseNamingStrategy;
    jcSnake:          Result := TSnakeCaseNamingStrategy;
    jcKebab:          Result := TKebabCaseNamingStrategy;
    jcScreamingSnake: Result := TScreamingSnakeCaseNamingStrategy;
    jcCustom:         Result := TDefaultNamingStrategy; // Fallback for Custom without a class
  else
    Result := TDefaultNamingStrategy;
  end;
end;

procedure TJsonSettings.RegisterCollectionAdapter<T>(Proc: TCollectionAddProc);
begin
  FCollectionAdapters.AddOrSetValue(System.TypeInfo(T), Proc);
end;

procedure TJsonSettings.RegisterFactory<T>(const Factory: TObjectFactoryProc);
begin
  FFactories.AddOrSetValue(System.TypeInfo(T), Factory);
end;

procedure TJsonSettings.RegisterKeySerializer<T>(const Proc: TKeySerializerProc);
begin
  FKeySerializers.AddOrSetValue(System.TypeInfo(T), Proc);
end;

procedure TJsonSettings.RegisterKeyDeserializer<T>(const Proc: TKeyDeserializerProc);
begin
  FKeyDeserializers.AddOrSetValue(System.TypeInfo(T), Proc);
end;

procedure TJsonSettings.RegisterValueTransformer<T>(const Proc: TValueTransformerProc);
begin
  FValueTransformers.AddOrSetValue(System.TypeInfo(T), Proc);
end;

end.