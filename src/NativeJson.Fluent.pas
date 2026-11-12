{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Fluent;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  Generics.Collections,
  Generics.Defaults,
  Rtti,
  TypInfo,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Rtti,
  System.TypInfo,
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.Attributes; // For TJsonNullValueHandling, etc.

type
  // Forward declarations
  TJsonTypeConfig = class;
  TJsonMemberConfig = class;

  // --- Delegate definitions for maximum flexibility ---
  TSerializationPredicate = reference to function(const Instance: TObject): Boolean;
  TValueTransformer = reference to function(const InValue: TValue): TValue;
  TObjectFactoryFunc = reference to function: TObject;
  TSerializationCallback = reference to procedure(const Instance: TObject);
  TDeserializationCallback = reference to procedure(const Instance: TObject);

  // ---------------------------------------------------------------------------
  // TJsonMemberConfig
  // Configuration for a single property or field
  // ---------------------------------------------------------------------------
  TJsonMemberConfig = class
  private
    FOwner: TJsonTypeConfig;
    FMemberName: string;         // The actual name in the Delphi code
    FJsonName: string;           // The name in the JSON
    FIgnored: Boolean;
    FOrder: Integer;
    FHasOrder: Boolean;
    FIsRequired: Boolean;
    FHasRequired: Boolean;
    FConverterType: TClass;
    
    // Fine-Grained Control
    FNullHandling: TJsonNullValueHandling;
    FHasNullHandling: Boolean;
    FDefaultHandling: TJsonDefaultValueHandling;
    FHasDefaultHandling: Boolean;
    FDefaultValue: TValue;
    FHasDefaultValue: Boolean;
    
    // Logic Hooks
    FShouldSerialize: TSerializationPredicate;
    FTransformer: TValueTransformer;
  public
    constructor Create(Owner: TJsonTypeConfig; const AMemberName: string);

    // Fluent API
    function Name(const AJsonName: string): TJsonMemberConfig;
    function Ignore: TJsonMemberConfig;
    function Required(Value: Boolean = True): TJsonMemberConfig;
    function Order(AOrder: Integer): TJsonMemberConfig;
    function Converter(AConverterClass: TClass): TJsonMemberConfig;
    
    /// <summary>
    /// Controls how null values are handled for this property.
    /// </summary>
    function NullHandling(AHandling: TJsonNullValueHandling): TJsonMemberConfig;
    
    /// <summary>
    /// Controls whether default values are written.
    /// </summary>
    function DefaultHandling(AHandling: TJsonDefaultValueHandling): TJsonMemberConfig;
    
    /// <summary>
    /// Defines an explicit default value for this property.
    /// </summary>
    function DefaultValue(const AValue: TValue): TJsonMemberConfig;

    /// <summary>
    /// Conditional serialization: the function must return True for the value to be written.
    /// </summary>
    function ShouldSerialize(APredicate: TSerializationPredicate): TJsonMemberConfig;
    
    /// <summary>
    /// Transforms the value before writing (e.g. masking, trimming).
    /// </summary>
    function Transform(ATransformer: TValueTransformer): TJsonMemberConfig;

    // Back to the parent (method chaining)
    function EndMember: TJsonTypeConfig;

    // Internal getters for the serializer (read-only)
    property InternalName: string read FMemberName;
    property InternalJsonName: string read FJsonName;
    property InternalIgnored: Boolean read FIgnored;
    property InternalOrder: Integer read FOrder;
    property InternalHasOrder: Boolean read FHasOrder;
    property InternalIsRequired: Boolean read FIsRequired;
    property InternalHasRequired: Boolean read FHasRequired;
    property InternalConverter: TClass read FConverterType;
    property InternalNullHandling: TJsonNullValueHandling read FNullHandling;
    property InternalHasNullHandling: Boolean read FHasNullHandling;
    property InternalDefaultHandling: TJsonDefaultValueHandling read FDefaultHandling;
    property InternalHasDefaultHandling: Boolean read FHasDefaultHandling;
    property InternalDefaultValue: TValue read FDefaultValue;
    property InternalHasDefaultValue: Boolean read FHasDefaultValue;
    property InternalShouldSerialize: TSerializationPredicate read FShouldSerialize;
    property InternalTransformer: TValueTransformer read FTransformer;
  end;

  // ---------------------------------------------------------------------------
  // TJsonTypeConfig
  // Base class for the type configuration (non-generic)
  // ---------------------------------------------------------------------------
  TJsonTypeConfig = class
  private
    FTypeInfo: PTypeInfo;
    FMembers: TObjectDictionary<string, TJsonMemberConfig>;
    
    // Class Settings
    FNamingStrategy: TClass;
    FIgnoreAllAttributes: Boolean; // When True, [JsonProperty] in the code is ignored
    FMemberSerialization: TJsonMemberSerialization; // OptIn, OptOut, Fields
    FMemberSelection: TJsonMemberTypes; // Empty = default of the type
    
    // Lifecycle Hooks
    FOnSerializing: TSerializationCallback;
    FOnSerialized: TSerializationCallback;
    FOnDeserializing: TDeserializationCallback;
    FOnDeserialized: TDeserializationCallback;
    
    // Construction
    FObjectFactory: TObjectFactoryFunc;
    
    // Polymorphism
    FDiscriminatorProperty: string;
    FSubTypes: TDictionary<string, TClass>;
    FOnChanged: TProc;
    procedure Changed;
  protected
    function GetMemberConfig(const AName: string): TJsonMemberConfig;
  public
    constructor Create(ATypeInfo: PTypeInfo; const AOnChanged: TProc = nil);
    destructor Destroy; override;

    /// <summary>
    /// Configures a specific property or field.
    /// </summary>
    function Map(const AName: string): TJsonMemberConfig;

    function FindMember(const AName: string): TJsonMemberConfig;

    // Getters for the cache
    property TypeInfo: PTypeInfo read FTypeInfo;
    property InternalNamingStrategy: TClass read FNamingStrategy;
    property InternalIgnoreAttributes: Boolean read FIgnoreAllAttributes;
    property InternalMemberSerialization: TJsonMemberSerialization read FMemberSerialization;
    property InternalMemberSelection: TJsonMemberTypes read FMemberSelection;
    property InternalFactory: TObjectFactoryFunc read FObjectFactory;
    property InternalOnSerializing: TSerializationCallback read FOnSerializing;
    property InternalOnSerialized: TSerializationCallback read FOnSerialized;
    property InternalOnDeserializing: TDeserializationCallback read FOnDeserializing;
    property InternalOnDeserialized: TDeserializationCallback read FOnDeserialized;

    // Polymorphism. An empty discriminator means this type is not
    // configured as polymorphic, the built-in $type is used.
    property InternalDiscriminator: string read FDiscriminatorProperty;

    /// <summary>
    ///   Finds the class for a discriminator value. nil if not found.
    /// </summary>
    function FindSubType(const AKey: string; out AClass: TClass): Boolean;

    /// <summary>
    ///   Finds the discriminator value for a class - the reverse direction
    ///   used when writing. Empty if not found.
    /// </summary>
    function FindSubTypeKey(AClass: TClass; out AKey: string): Boolean;
  end;

  // ---------------------------------------------------------------------------
  // TJsonTypeConfig<T>
  // Type-safe wrapper class for the configuration
  // ---------------------------------------------------------------------------
  TJsonTypeConfig<T{$IFNDEF FPC}: class{$ENDIF}> = class(TJsonTypeConfig)
  private
    class function AsT(const Instance: TObject): T; static; inline;
    class function IsT(const Instance: TObject): Boolean; static; inline;
    class function AsObj(const InputValue: T): TObject; static; inline;
  public
    /// <summary>
    /// Shortcut: ignores a property immediately.
    /// </summary>
    function Ignore(const PropertyName: string): TJsonTypeConfig<T>;
    
    /// <summary>
    /// Sets the naming strategy (e.g. SnakeCase) for this type only.
    /// </summary>
    function SetNamingStrategy(AStrategyClass: TClass): TJsonTypeConfig<T>;
    
    /// <summary>
    /// Ignores all attributes (JsonProperty etc.) in the source code.
    /// Pure Fluent Configuration!
    /// </summary>
    function IgnoreAttributes: TJsonTypeConfig<T>;
    
    /// <summary>
    /// Controls what is serialized by default (Properties, Fields, OptIn).
    /// </summary>
    function SerializationMode(AMode: TJsonMemberSerialization): TJsonTypeConfig<T>;

    /// <summary>
    /// Defines which member kinds are serialized for this type.
    /// Example: SelectMembers([TJsonMemberType.mtProperties, TJsonMemberType.mtFields]).
    /// </summary>
    function SelectMembers(AMembers: TJsonMemberTypes): TJsonTypeConfig<T>;

    /// <summary>
    /// Defines a factory method for creating the instance (e.g. dependency injection).
    /// </summary>
    function ConstructWith(AFunc: TFunc<T>): TJsonTypeConfig<T>;

    /// <summary>
    /// Type-safe hook: called BEFORE serialization.
    /// </summary>
    function OnSerializing(ACallback: TProc<T>): TJsonTypeConfig<T>;
    function OnSerialized(ACallback: TProc<T>): TJsonTypeConfig<T>;
    function OnDeserializing(ACallback: TProc<T>): TJsonTypeConfig<T>;
    function OnDeserialized(ACallback: TProc<T>): TJsonTypeConfig<T>;

    /// <summary>
    /// Defines a type-safe condition predicate.
    /// </summary>
    function SetShouldSerialize(const PropertyName: string; APredicate: TFunc<T, Boolean>): TJsonTypeConfig<T>;

    /// <summary>
    ///   Defines which JSON field names the subclass. Without this
    ///   call the built-in "$type" with the fully
    ///   qualified Delphi name is used - mostly useless for foreign JSON.
    /// </summary>
    function Discriminator(const APropertyName: string): TJsonTypeConfig<T>;

    /// <summary>
    ///   Maps a value of the discriminator field to a class.
    ///   Example: SubType('dog', TDog). The class must descend from T.
    /// </summary>
    function SubType(const AKey: string; AClass: TClass): TJsonTypeConfig<T>;
  end;

  // ---------------------------------------------------------------------------
  // TJsonFluentContext
  // The central entry point (registry)
  // ---------------------------------------------------------------------------
  TJsonFluentContext = class
  private
    FConfigs: TObjectDictionary<PTypeInfo, TJsonTypeConfig>;
    FRevision: UInt64;
    procedure Changed;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Configures a generic type. Creates the config if it does not exist.
    /// </summary>
    function Entity<T: class>: TJsonTypeConfig<T>;
    
    /// <summary>
    /// Checks whether a configuration exists for this type.
    /// </summary>
    function HasConfig(ATypeInfo: PTypeInfo): Boolean;
    
    /// <summary>
    /// Gets the configuration (for internal use).
    /// </summary>
    function GetConfig(ATypeInfo: PTypeInfo): TJsonTypeConfig;
    
    /// <summary>
    /// Clears all configurations.
    /// </summary>
    procedure Clear;
    property Revision: UInt64 read FRevision;
  end;

implementation

uses
  // Only in the implementation: NativeJson.Rtti.Cache uses this unit
  // in its interface. Mutual use is only allowed when
  // at most one side is in the interface.
  NativeJson.Rtti.Cache;

var
  // Running counter across ALL fluent contexts.
  // Reason: the RTTI cache keys its entries partly by
  // (context pointer, revision). If a TJsonSettings is freed and
  // a new one is created right after, the heap very often returns the same
  // address. If every context started counting at 0, the new object could
  // hit exactly the same key as the old one and get a stale
  // member set from the cache. With a global counter
  // every change is unique, no matter which address is recycled.
  GFluentRevisionCounter: Int64 = 0;

{ TJsonMemberConfig }

constructor TJsonMemberConfig.Create(Owner: TJsonTypeConfig; const AMemberName: string);
begin
  inherited Create;
  FOwner := Owner;
  FMemberName := AMemberName;
  FJsonName := '';
  FIgnored := False;
  FHasOrder := False;
  FOrder := 0;
  FIsRequired := False;
  FHasRequired := False;
  FConverterType := nil;
  FNullHandling := TJsonNullValueHandling.Include; // Default, overwritten by the TypeInfo cache if not set
  FHasNullHandling := False;
  FDefaultHandling := TJsonDefaultValueHandling.Include;
  FHasDefaultHandling := False;
  FHasDefaultValue := False;
end;

function TJsonMemberConfig.Converter(AConverterClass: TClass): TJsonMemberConfig;
begin
  FConverterType := AConverterClass;
  FOwner.Changed;
  Result := Self;
end;

function TJsonMemberConfig.DefaultHandling(AHandling: TJsonDefaultValueHandling): TJsonMemberConfig;
begin
  FDefaultHandling := AHandling;
  FHasDefaultHandling := True;
  FOwner.Changed;
  Result := Self;
end;

function TJsonMemberConfig.DefaultValue(const AValue: TValue): TJsonMemberConfig;
begin
  FDefaultValue := AValue;
  FHasDefaultValue := True;
  FOwner.Changed;
  Result := Self;
end;

function TJsonMemberConfig.EndMember: TJsonTypeConfig;
begin
  Result := FOwner;
end;

function TJsonMemberConfig.Ignore: TJsonMemberConfig;
begin
  FIgnored := True;
  FOwner.Changed;
  Result := Self;
end;

function TJsonMemberConfig.Name(const AJsonName: string): TJsonMemberConfig;
begin
  FJsonName := AJsonName;
  FOwner.Changed;
  Result := Self;
end;

function TJsonMemberConfig.NullHandling(AHandling: TJsonNullValueHandling): TJsonMemberConfig;
begin
  FNullHandling := AHandling;
  FHasNullHandling := True;
  FOwner.Changed;
  Result := Self;
end;

function TJsonMemberConfig.Order(AOrder: Integer): TJsonMemberConfig;
begin
  FOrder := AOrder;
  FHasOrder := True;
  FOwner.Changed;
  Result := Self;
end;

function TJsonMemberConfig.Required(Value: Boolean): TJsonMemberConfig;
begin
  FIsRequired := Value;
  FHasRequired := True;
  FOwner.Changed;
  Result := Self;
end;

function TJsonMemberConfig.ShouldSerialize(APredicate: TSerializationPredicate): TJsonMemberConfig;
begin
  FShouldSerialize := APredicate;
  FOwner.Changed;
  Result := Self;
end;

function TJsonMemberConfig.Transform(ATransformer: TValueTransformer): TJsonMemberConfig;
begin
  FTransformer := ATransformer;
  FOwner.Changed;
  Result := Self;
end;

{ TJsonTypeConfig }

constructor TJsonTypeConfig.Create(ATypeInfo: PTypeInfo; const AOnChanged: TProc);
begin
  inherited Create;
  FTypeInfo := ATypeInfo;
  FOnChanged := AOnChanged;
  FMembers := TObjectDictionary<string, TJsonMemberConfig>.Create([doOwnsValues], TJsonIStringComparer.Ordinal);
  FNamingStrategy := nil;
  FIgnoreAllAttributes := False;
  FMemberSerialization := TJsonMemberSerialization.OptOut; // Default behavior
  FMemberSelection := [];
  FSubTypes := TDictionary<string, TClass>.Create;
end;

destructor TJsonTypeConfig.Destroy;
begin
  FSubTypes.Free;
  FMembers.Free;
  inherited;
end;


procedure TJsonTypeConfig.Changed;
begin
  if Assigned(FOnChanged) then FOnChanged;
end;

function TJsonTypeConfig.Map(const AName: string): TJsonMemberConfig;
begin
  Result := GetMemberConfig(AName);
end;

function TJsonTypeConfig.FindMember(const AName: string): TJsonMemberConfig;
begin
  if not FMembers.TryGetValue(AName, Result) then
    Result := nil;
end;

function TJsonTypeConfig.GetMemberConfig(const AName: string): TJsonMemberConfig;
begin
  if not FMembers.TryGetValue(AName, Result) then
  begin
    Result := TJsonMemberConfig.Create(Self, AName);
    FMembers.Add(AName, Result);
    Changed;
  end;
end;

{ TJsonTypeConfig<T> }

class function TJsonTypeConfig<T>.AsT(const Instance: TObject): T;
begin
  {$IFDEF FPC}
  Result := TValue.From<TObject>(Instance).AsType<T>;
  {$ELSE}
  Result := T(Instance);
  {$ENDIF}
end;

class function TJsonTypeConfig<T>.IsT(const Instance: TObject): Boolean;
begin
  {$IFDEF FPC}
  Result := (Instance <> nil) and Instance.InheritsFrom(GetTypeData(System.TypeInfo(T))^.ClassType);
  {$ELSE}
  Result := Instance is T;
  {$ENDIF}
end;

class function TJsonTypeConfig<T>.AsObj(const InputValue: T): TObject;
begin
  {$IFDEF FPC}
  Result := TValue.From<T>(InputValue).AsObject;
  {$ELSE}
  Result := InputValue;
  {$ENDIF}
end;

function TJsonTypeConfig<T>.Ignore(const PropertyName: string): TJsonTypeConfig<T>;
begin
  GetMemberConfig(PropertyName).Ignore;
  Result := Self;
end;

function TJsonTypeConfig<T>.IgnoreAttributes: TJsonTypeConfig<T>;
begin
  FIgnoreAllAttributes := True;
  Changed;
  Result := Self;
end;

function TJsonTypeConfig<T>.SetNamingStrategy(AStrategyClass: TClass): TJsonTypeConfig<T>;
begin
  FNamingStrategy := AStrategyClass;
  Changed;
  Result := Self;
end;

function TJsonTypeConfig<T>.SerializationMode(AMode: TJsonMemberSerialization): TJsonTypeConfig<T>;
begin
  FMemberSerialization := AMode;
  Changed;
  Result := Self;
end;

function TJsonTypeConfig<T>.SelectMembers(AMembers: TJsonMemberTypes): TJsonTypeConfig<T>;
begin
  FMemberSelection := AMembers;
  Changed;
  Result := Self;
end;

function TJsonTypeConfig.FindSubType(const AKey: string; out AClass: TClass): Boolean;
var
  SubTypePair: TPair<string, TClass>;
begin
  AClass := nil;
  if (FSubTypes = nil) or (AKey = '') then Exit(False);
  // Deliberately case-insensitive: foreign
  // JSON writes "Dog" or "dog", depending on the other side.
  for SubTypePair in FSubTypes do
    if SameText(SubTypePair.Key, AKey) then
    begin
      AClass := SubTypePair.Value;
      Exit(True);
    end;
  Result := False;
end;

function TJsonTypeConfig.FindSubTypeKey(AClass: TClass; out AKey: string): Boolean;
var
  SubTypePair: TPair<string, TClass>;
begin
  AKey := '';
  if (FSubTypes = nil) or (AClass = nil) then Exit(False);
  for SubTypePair in FSubTypes do
    if SubTypePair.Value = AClass then
    begin
      AKey := SubTypePair.Key;
      Exit(True);
    end;
  Result := False;
end;

function TJsonTypeConfig<T>.ConstructWith(AFunc: TFunc<T>): TJsonTypeConfig<T>;
begin
  // Wrap the typed func in an untyped func for the cache
  FObjectFactory := function: TObject
    begin
      Result := AsObj(AFunc());
    end;
  Changed;
  Result := Self;
end;

function TJsonTypeConfig<T>.OnSerializing(ACallback: TProc<T>): TJsonTypeConfig<T>;
begin
  FOnSerializing := procedure(const Instance: TObject)
    begin
      ACallback(AsT(Instance));
    end;
  Changed;
  Result := Self;
end;

function TJsonTypeConfig<T>.OnSerialized(ACallback: TProc<T>): TJsonTypeConfig<T>;
begin
  FOnSerialized := procedure(const Instance: TObject)
    begin
      ACallback(AsT(Instance));
    end;
  Changed;
  Result := Self;
end;

function TJsonTypeConfig<T>.OnDeserializing(ACallback: TProc<T>): TJsonTypeConfig<T>;
begin
  FOnDeserializing := procedure(const Instance: TObject)
    begin
      ACallback(AsT(Instance));
    end;
  Changed;
  Result := Self;
end;

function TJsonTypeConfig<T>.OnDeserialized(ACallback: TProc<T>): TJsonTypeConfig<T>;
begin
  FOnDeserialized := procedure(const Instance: TObject)
    begin
      ACallback(AsT(Instance));
    end;
  Changed;
  Result := Self;
end;

function TJsonTypeConfig<T>.SetShouldSerialize(const PropertyName: string; APredicate: TFunc<T, Boolean>): TJsonTypeConfig<T>;
begin
  GetMemberConfig(PropertyName).ShouldSerialize(
    function(const Instance: TObject): Boolean
    begin
      if IsT(Instance) then
        Result := APredicate(AsT(Instance))
      else
        Result := True; // Safe Fallback
    end
  );
  Result := Self;
end;

{ TJsonFluentContext }

constructor TJsonFluentContext.Create;
begin
  inherited;
  FRevision := 0;
  FConfigs := TObjectDictionary<PTypeInfo, TJsonTypeConfig>.Create([doOwnsValues]);
end;

destructor TJsonFluentContext.Destroy;
begin
  // The RTTI cache keeps analysis results under a key that
  // contains this context. Without this unregistration they would stay
  // forever - a leak that no free counter finds.
  TJsonRttiCache.ForgetContext(Self);
  FConfigs.Free;
  inherited;
end;

procedure TJsonFluentContext.Changed;
begin
  // No local counting: see the comment at GFluentRevisionCounter.
  FRevision := UInt64(AtomicIncrement(GFluentRevisionCounter));
end;

procedure TJsonFluentContext.Clear;
begin
  FConfigs.Clear;
  Changed;
end;

function TJsonFluentContext.Entity<T>: TJsonTypeConfig<T>;
var
  Info: PTypeInfo;
  BaseConfig: TJsonTypeConfig;
begin
  Info := System.TypeInfo(T);
  if Info = nil then
    raise Exception.Create('TypeInfo not available for T. Ensure generic instantiation.');

  if not FConfigs.TryGetValue(Info, BaseConfig) then
  begin
    BaseConfig := TJsonTypeConfig<T>.Create(Info, Changed);
    FConfigs.Add(Info, BaseConfig);
    Changed;
  end;

  if BaseConfig is TJsonTypeConfig<T> then
    Result := TJsonTypeConfig<T>(BaseConfig)
  else
    // This should technically never happen unless the pointer key collides (impossible)
    raise Exception.Create('Type configuration type mismatch');
end;

function TJsonTypeConfig<T>.Discriminator(const APropertyName: string): TJsonTypeConfig<T>;
begin
  FDiscriminatorProperty := APropertyName;
  Changed;
  Result := Self;
end;

function TJsonTypeConfig<T>.SubType(const AKey: string; AClass: TClass): TJsonTypeConfig<T>;
var
  Base: TClass;
begin
  if AKey = '' then raise EArgumentException.Create('SubType requires a discriminator value');
  if AClass = nil then raise EArgumentNilException.Create('AClass');
  // TClass(T) does not exist - a type parameter is not a metaclass value.
  // The base class comes from the type information, which the base class
  // already holds anyway.
  Base := GetTypeData(FTypeInfo)^.ClassType;
  // The assignability test must happen here. If it only fails during
  // deserialization, the error is far away from its cause.
  if not AClass.InheritsFrom(Base) then
    raise EArgumentException.CreateFmt('%s does not descend from %s',
      [AClass.ClassName, Base.ClassName]);
  FSubTypes.AddOrSetValue(AKey, AClass);
  Changed;
  Result := Self;
end;

function TJsonFluentContext.GetConfig(ATypeInfo: PTypeInfo): TJsonTypeConfig;
begin
  if not FConfigs.TryGetValue(ATypeInfo, Result) then
    Result := nil;
end;

function TJsonFluentContext.HasConfig(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := FConfigs.ContainsKey(ATypeInfo);
end;

end.