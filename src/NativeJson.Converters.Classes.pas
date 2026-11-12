{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Converters.Classes;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  TypInfo,
  Rtti,
  System.NetEncoding,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  System.Rtti,
  System.NetEncoding,
  {$ENDIF}
  NativeJson.Serializer.Converter,
  NativeJson.Serializer.Writer,
  NativeJson.Core.Reader,
  NativeJson.Core.Tokens;

type
  // ===========================================================================
  // TEXT & STRINGS
  // ===========================================================================

  /// <summary>
  ///   Serializes TStrings and TStringList as a JSON array ["Line1", "Line2"].
  ///   Handles nil and empty lists robustly.
  /// </summary>
  TStringsConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  // ===========================================================================
  // BINARY DATA
  // ===========================================================================

  /// <summary>
  ///   Serializes TStream, TMemoryStream, TFileStream as a Base64 string.
  ///   Takes care of stream positions.
  /// </summary>
  TStreamConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  // ===========================================================================
  // COLLECTIONS & LISTS
  // ===========================================================================

  /// <summary>
  ///   Serializes TCollection and TOwnedCollection.
  ///   Uses the serializer recursively for the items.
  /// </summary>
  TCollectionConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  /// <summary>
  ///   Serializes TInterfaceList as an array of objects.
  ///   Essential for interface-based architectures (Spring4D etc.).
  /// </summary>
  TInterfaceListConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

  // ===========================================================================
  // SPECIALS
  // ===========================================================================

  /// <summary>
  ///   Serializes TBits (bit array) as a JSON array of booleans [true, false, ...].
  /// </summary>
  TBitsConverter = class(TJsonConverter)
  public
    function CanConvert(TypeInfo: PTypeInfo): Boolean; override;
    procedure WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext); override;
    function ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue; override;
  end;

implementation

// To avoid circular references the context is cast internally,
// but the unit is imported for access to TJsonSerializer.
uses
  NativeJson.Serializer.Core,
  NativeJson.Deserializer.Core,
  NativeJson.Dom.Value; // For DOM-based deserialization of interfaces

{ TStringsConverter }

function TStringsConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var
  Ctx: TRttiContext;
  T: TRttiType;
begin
  if TypeInfo.Kind = tkClass then
  begin
    T := Ctx.GetType(TypeInfo);
    // Covers TStringList, TMemoStrings, etc.
    Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TStrings);
  end
  else
    Result := False;
end;

procedure TStringsConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  List: TStrings;
  S: string;
begin
  if Value.IsEmpty or (Value.AsObject = nil) then
  begin
    Writer.WriteNull;
    Exit;
  end;

  List := TStrings(Value.AsObject);
  
  Writer.WriteStartArray;
  for S in List do
    Writer.WriteValue(S);
  Writer.WriteEndArray;
end;

function TStringsConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  List: TStrings;
begin
  if Reader.TokenType = TJsonToken.Null then
    Exit(TValue.From<TStrings>(nil));

  if Reader.TokenType <> TJsonToken.StartArray then
    raise Exception.Create('Expected JSON Array for TStrings');

  // Use the existing instance or create a new TStringList
  if (not ExistingValue.IsEmpty) and (ExistingValue.AsObject <> nil) and (ExistingValue.AsObject is TStrings) then
    List := TStrings(ExistingValue.AsObject)
  else
    List := TStringList.Create;

  List.BeginUpdate;
  try
    // If it is a new list or we want to overwrite:
    if (ExistingValue.IsEmpty) or (ExistingValue.AsObject = nil) then
      List.Clear; 
      
    // If ExistingValue is present, do we append (default) or clear?
    // Standard JSON behavior: replace content. So clear.
    List.Clear;

    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndArray then Break;
      
      // Robustness: also accept numbers/bools as strings
      if Reader.TokenType in [TJsonToken.Str, TJsonToken.Integer, TJsonToken.Float, TJsonToken.Boolean] then
        List.Add(Reader.Value)
      else if Reader.TokenType = TJsonToken.Null then
        List.Add(''); // Null as empty string
    end;
  finally
    List.EndUpdate;
  end;

  Result := TValue.From<TStrings>(List);
end;

{ TStreamConverter }

function TStreamConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var
  Ctx: TRttiContext;
  T: TRttiType;
begin
  if TypeInfo.Kind = tkClass then
  begin
    T := Ctx.GetType(TypeInfo);
    Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TStream);
  end
  else
    Result := False;
end;

procedure TStreamConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  Stream: TStream;
  MemStream: TMemoryStream;
  Bytes: TBytes;
  OldPos: Int64;
begin
  if Value.IsEmpty or (Value.AsObject = nil) then
  begin
    Writer.WriteNull;
    Exit;
  end;

  Stream := TStream(Value.AsObject);
  
  // Robustness: remember the position and restore it
  OldPos := Stream.Position;
  try
    Stream.Position := 0;
    
    // Optimization: if it is already a MemoryStream, access it directly
    if Stream is TMemoryStream then
    begin
      MemStream := TMemoryStream(Stream);
      SetLength(Bytes, MemStream.Size);
      if MemStream.Size > 0 then
        Move(MemStream.Memory^, Bytes[0], MemStream.Size);
    end
    else
    begin
      // Generic stream: copy into memory for encoding
      MemStream := TMemoryStream.Create;
      try
        MemStream.CopyFrom(Stream, Stream.Size); // Copy entire stream
        MemStream.Position := 0;
        SetLength(Bytes, MemStream.Size);
        if MemStream.Size > 0 then
          MemStream.ReadBuffer(Bytes[0], MemStream.Size);
      finally
        MemStream.Free;
      end;
    end;
    
    Writer.WriteValue(TNetEncoding.Base64.EncodeBytesToString(Bytes));
  finally
    // Restore the position (side-effect free)
    Stream.Position := OldPos;
  end;
end;

function TStreamConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  Bytes: TBytes;
  Stream: TMemoryStream;
begin
  if Reader.TokenType = TJsonToken.Null then
    Exit(TValue.From<TStream>(nil));

  if Reader.TokenType <> TJsonToken.Str then
    raise Exception.Create('Expected Base64 String for TStream');

  Bytes := TNetEncoding.Base64.DecodeStringToBytes(Reader.Value);
  
  // Always create a new TMemoryStream, because we do not know
  // whether the existing stream is writable/large enough.
  Stream := TMemoryStream.Create;
  if Length(Bytes) > 0 then
    Stream.WriteBuffer(Bytes[0], Length(Bytes));
    
  Stream.Position := 0;
  Result := TValue.From<TStream>(Stream);
end;

{ TCollectionConverter }

function TCollectionConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var
  Ctx: TRttiContext;
  T: TRttiType;
begin
  if TypeInfo.Kind = tkClass then
  begin
    T := Ctx.GetType(TypeInfo);
    Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TCollection);
  end
  else
    Result := False;
end;

procedure TCollectionConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  Coll: TCollection;
  Item: TCollectionItem;
  Ser: TJsonSerializer;
begin
  if Value.IsEmpty or (Value.AsObject = nil) then
  begin
    Writer.WriteNull;
    Exit;
  end;

  Coll := TCollection(Value.AsObject);
  Ser := TJsonSerializer(Serializer);

  Writer.WriteStartArray;
  for Item in Coll do
  begin
    // Recursive serializer call for each item
    // TCollectionItem has RTTI, so it is serialized as an object
    Ser.SerializeValue(Writer, Item);
  end;
  Writer.WriteEndArray;
end;

function TCollectionConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  Coll: TCollection;
  Deser: TJsonDeserializer;
  ItemDom: TJsonValue;
  NewItem: TCollectionItem;
begin
  // Collections must exist, because they are often created in the owner's constructor
  if (ExistingValue.IsEmpty) or (ExistingValue.AsObject = nil) then
    raise Exception.Create('TCollection deserialization requires an existing instance (Collection is usually owned)');

  Coll := TCollection(ExistingValue.AsObject);
  Deser := TJsonDeserializer(Serializer);

  if Reader.TokenType = TJsonToken.Null then
  begin
    Coll.Clear;
    Exit(ExistingValue);
  end;

  if Reader.TokenType <> TJsonToken.StartArray then
    raise Exception.Create('Expected JSON Array for TCollection');

  Coll.BeginUpdate;
  try
    Coll.Clear;
    while Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.EndArray then Break;

      // Read the item as DOM, then map it onto the object
      ItemDom := Deser.BuildDomFromCurrent(Reader);
      try
        NewItem := Coll.Add;
        // Populate the new item
        Deser.Populate(NewItem, ItemDom);
      finally
        ItemDom.Free;
      end;
    end;
  finally
    Coll.EndUpdate;
  end;

  Result := ExistingValue;
end;

{ TInterfaceListConverter }

function TInterfaceListConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var
  Ctx: TRttiContext;
  T: TRttiType;
begin
  if TypeInfo.Kind = tkClass then
  begin
    T := Ctx.GetType(TypeInfo);
    Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TInterfaceList);
  end
  else
    Result := False;
end;

procedure TInterfaceListConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  List: TInterfaceList;
  I: Integer;
  Intf: IInterface;
  Ser: TJsonSerializer;
begin
  if Value.IsEmpty or (Value.AsObject = nil) then
  begin
    Writer.WriteNull;
    Exit;
  end;

  List := TInterfaceList(Value.AsObject);
  Ser := TJsonSerializer(Serializer);

  Writer.WriteStartArray;
  for I := 0 to List.Count - 1 do
  begin
    Intf := List[I];
    // The interface must be wrapped in a TValue so the serializer recognizes it as an interface
    if Intf = nil then
      Writer.WriteNull
    else
      Ser.SerializeValue(Writer, TValue.From<IInterface>(Intf));
  end;
  Writer.WriteEndArray;
end;

function TInterfaceListConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  List: TInterfaceList;
  Depth: Integer;
begin
  // The implementing class of an interface is unknown here, so the array content is skipped
  // and nothing is added. Interface lists are restored by the regular deserializer
  // with TypeNameHandling.Auto.

  if (ExistingValue.IsEmpty) or (ExistingValue.AsObject = nil) then
     List := TInterfaceList.Create
  else
     List := TInterfaceList(ExistingValue.AsObject);
     
  if Reader.TokenType = TJsonToken.Null then
  begin
    List.Clear;
    Exit(TValue.From<TInterfaceList>(List));
  end;
  
  if Reader.TokenType = TJsonToken.StartArray then
  begin
    Depth := 1;
    while (Depth > 0) and Reader.Read do
    begin
      if Reader.TokenType = TJsonToken.StartArray then Inc(Depth)
      else if Reader.TokenType = TJsonToken.EndArray then Dec(Depth);
    end;
  end;
  
  Result := TValue.From<TInterfaceList>(List);
end;

{ TBitsConverter }

function TBitsConverter.CanConvert(TypeInfo: PTypeInfo): Boolean;
var
  Ctx: TRttiContext;
  T: TRttiType;
begin
  if TypeInfo.Kind = tkClass then
  begin
    T := Ctx.GetType(TypeInfo);
    Result := (T is TRttiInstanceType) and TRttiInstanceType(T).MetaclassType.InheritsFrom(TBits);
  end
  else
    Result := False;
end;

procedure TBitsConverter.WriteJson(Writer: TJsonWriter; const Value: TValue; Serializer: TJsonSerializerContext);
var
  Bits: TBits;
  I: Integer;
begin
  if Value.IsEmpty or (Value.AsObject = nil) then
  begin
    Writer.WriteNull;
    Exit;
  end;

  Bits := TBits(Value.AsObject);
  Writer.WriteStartArray;
  for I := 0 to Bits.Size - 1 do
    Writer.WriteValue(Bits.Bits[I]);
  Writer.WriteEndArray;
end;

function TBitsConverter.ReadJson(Reader: TJsonReader; ObjectType: PTypeInfo; const ExistingValue: TValue; Serializer: TJsonSerializerContext): TValue;
var
  Bits: TBits;
  Val: Boolean;
begin
  if (ExistingValue.IsEmpty) or (ExistingValue.AsObject = nil) then
    Bits := TBits.Create
  else
    Bits := TBits(ExistingValue.AsObject);

  if Reader.TokenType = TJsonToken.Null then
  begin
    Bits.Size := 0;
    Exit(TValue.From<TBits>(Bits));
  end;

  if Reader.TokenType <> TJsonToken.StartArray then raise Exception.Create('Expected JSON Array for TBits');

  Bits.Size := 0; 
  while Reader.Read do
  begin
    if Reader.TokenType = TJsonToken.EndArray then Break;
    
    // Add the next index
    Bits.Size := Bits.Size + 1;
    
    // Set the value
    if Reader.TokenType = TJsonToken.Boolean then
      Val := Reader.ValueAsBool
    else if Reader.TokenType = TJsonToken.Integer then
      Val := Reader.ValueAsInt <> 0
    else
      Val := False; // Default
      
    Bits.Bits[Bits.Size - 1] := Val;
  end;

  Result := TValue.From<TBits>(Bits);
end;

end.