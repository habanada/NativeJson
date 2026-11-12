{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Xml;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Generics.Collections,
  {$ELSE}
  System.SysUtils,
  System.Generics.Collections,
  {$ENDIF}
  NativeJson.Dom.Value;

type
  EJsonXmlError = class(Exception);

  TJsonXmlOptions = class
  private
    FAttributePrefix: string;
    FTextKey: string;
    FRootName: string;
    FInferTypes: Boolean;
    FIndent: Boolean;
    FWriteDeclaration: Boolean;
    FMaxDepth: Integer;
    FForceArrays: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    property AttributePrefix: string read FAttributePrefix write FAttributePrefix;
    property TextKey: string read FTextKey write FTextKey;
    property RootName: string read FRootName write FRootName;
    property InferTypes: Boolean read FInferTypes write FInferTypes;
    property Indent: Boolean read FIndent write FIndent;
    property WriteDeclaration: Boolean read FWriteDeclaration write FWriteDeclaration;
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
    property ForceArrays: TList<string> read FForceArrays;
  end;

function XmlToDom(const Xml: string; Options: TJsonXmlOptions = nil): TJsonValue;
function XmlToJson(const Xml: string; Options: TJsonXmlOptions = nil): string;
function DomToXml(Value: TJsonValue; Options: TJsonXmlOptions = nil): string;
function JsonToXml(const Json: string; Options: TJsonXmlOptions = nil): string;
function EncodeXmlName(const Name: string): string;
function DecodeXmlName(const Name: string): string;

implementation

uses
  NativeJson.Dom.Primitive,
  NativeJson.Dom.JsonArray,
  NativeJson.Dom.JsonObject,
  NativeJson.Dom.Io,
  NativeJson.Serializer.Writer;

type
  TXmlAttribute = TPair<string, string>;
  TXmlChild = TPair<string, TJsonValue>;
  TXmlAttributes = TList<TXmlAttribute>;
  TXmlChildren = TList<TXmlChild>;

  TXmlOutput = class
  private
    FText: string;
    FLen: Integer;
  public
    procedure Append(const S: string);
    function Text: string;
    property Len: Integer read FLen;
  end;

  TDomXmlWriter = class
  private
    FOptions: TJsonXmlOptions;
    FOutput: TXmlOutput;
    function IsAttributeKey(const Key: string): Boolean;
    procedure StartLine(Level: Integer);
    procedure WriteEscaped(const S: string; InAttribute: Boolean);
    procedure WriteText(Value: TJsonValue);
    procedure WriteElement(const Name: string; Value: TJsonValue; Level: Integer; Pretty: Boolean);
    procedure WriteObjectElement(const Name: string; Value: TJsonObject; Level: Integer; Pretty: Boolean);
  public
    constructor Create(Options: TJsonXmlOptions);
    destructor Destroy; override;
    function Write(Value: TJsonValue): string;
  end;

  TXmlDomReader = class
  private
    FText: string;
    FPos: Integer;
    FLen: Integer;
    FOptions: TJsonXmlOptions;
    procedure Fail(const Msg: string);
    function Peek(const S: string): Boolean;
    procedure Expect(const S: string);
    function SkipWhitespace: Boolean;
    procedure SkipUntil(const Terminator, What: string);
    procedure SkipDoctype;
    procedure SkipMisc(AllowDoctype: Boolean);
    function ReadName: string;
    function ReadReference: string;
    function ReadAttributeValue: string;
    function MakeScalar(const Text: string): TJsonValue;
    function IsForcedArray(const Name, Path: string): Boolean;
    function BuildValue(const Path: string; Attributes: TXmlAttributes;
      Children: TXmlChildren; Texts: TList<string>): TJsonValue;
    function ParseElement(const ParentPath: string; Depth: Integer; out Name: string): TJsonValue;
  public
    constructor Create(const Xml: string; Options: TJsonXmlOptions);
    function Parse: TJsonValue;
  end;

function IsNameStartChar(C: Char): Boolean;
begin
  case C of
    'A'..'Z', 'a'..'z', '_', ':':
      Result := True;
  else
    Result := (Ord(C) >= $C0) and (Ord(C) <> $D7) and (Ord(C) <> $F7) and (Ord(C) < $FFFE);
  end;
end;

function IsNameChar(C: Char): Boolean;
begin
  case C of
    '0'..'9', '-', '.':
      Result := True;
  else
    Result := IsNameStartChar(C) or (Ord(C) = $B7);
  end;
end;

function IsHexChar(C: Char): Boolean;
begin
  case C of
    '0'..'9', 'A'..'F', 'a'..'f':
      Result := True;
  else
    Result := False;
  end;
end;

function IsWhiteChar(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

function IsEncodedSequence(const Name: string; I: Integer): Boolean;
begin
  Result := (I + 6 <= Length(Name)) and (Name[I] = '_') and (Name[I + 1] = 'x') and
    IsHexChar(Name[I + 2]) and IsHexChar(Name[I + 3]) and IsHexChar(Name[I + 4]) and
    IsHexChar(Name[I + 5]) and (Name[I + 6] = '_');
end;

function EncodeXmlName(const Name: string): string;
var
  I: Integer;
  Valid: Boolean;
begin
  if Name = '' then raise EJsonXmlError.Create('An empty name cannot be written as an XML name');
  Result := '';
  for I := 1 to Length(Name) do
  begin
    if I = 1 then Valid := IsNameStartChar(Name[I]) else Valid := IsNameChar(Name[I]);
    if Valid and not IsEncodedSequence(Name, I) then
      Result := Result + Name[I]
    else
      Result := Result + '_x' + IntToHex(Ord(Name[I]), 4) + '_';
  end;
end;

function DecodeXmlName(const Name: string): string;
var
  I: Integer;
begin
  if Pos('_x', Name) = 0 then Exit(Name);
  Result := '';
  I := 1;
  while I <= Length(Name) do
    if IsEncodedSequence(Name, I) then
    begin
      Result := Result + Char(Word(StrToInt('$' + Copy(Name, I + 2, 4))));
      Inc(I, 7);
    end
    else
    begin
      Result := Result + Name[I];
      Inc(I);
    end;
end;

function IsJsonNumber(const S: string): Boolean;
var
  I, N: Integer;

  function Digits: Boolean;
  var
    Start: Integer;
  begin
    Start := I;
    while (I <= N) and (S[I] >= '0') and (S[I] <= '9') do Inc(I);
    Result := I > Start;
  end;

begin
  Result := False;
  N := Length(S);
  I := 1;
  if (I <= N) and (S[I] = '-') then Inc(I);
  if I > N then Exit;
  if S[I] = '0' then
    Inc(I)
  else if not Digits then
    Exit;
  if (I <= N) and (S[I] = '.') then
  begin
    Inc(I);
    if not Digits then Exit;
  end;
  if (I <= N) and ((S[I] = 'e') or (S[I] = 'E')) then
  begin
    Inc(I);
    if (I <= N) and ((S[I] = '+') or (S[I] = '-')) then Inc(I);
    if not Digits then Exit;
  end;
  Result := I > N;
end;

function NormalizeLineEnds(const S: string): string;
begin
  Result := StringReplace(StringReplace(S, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
end;

constructor TJsonXmlOptions.Create;
begin
  inherited Create;
  FAttributePrefix := '@';
  FTextKey := '#text';
  FRootName := '';
  FInferTypes := False;
  FIndent := False;
  FWriteDeclaration := False;
  FMaxDepth := 256;
  FForceArrays := TList<string>.Create;
end;

destructor TJsonXmlOptions.Destroy;
begin
  FForceArrays.Free;
  inherited;
end;

procedure TXmlOutput.Append(const S: string);
var
  N: Integer;
begin
  N := Length(S);
  if N = 0 then Exit;
  if FLen + N > Length(FText) then SetLength(FText, (FLen + N) * 2 + 64);
  Move(PChar(S)^, FText[FLen + 1], N * SizeOf(Char));
  Inc(FLen, N);
end;

function TXmlOutput.Text: string;
begin
  Result := Copy(FText, 1, FLen);
end;

constructor TDomXmlWriter.Create(Options: TJsonXmlOptions);
begin
  inherited Create;
  FOptions := Options;
  FOutput := TXmlOutput.Create;
end;

destructor TDomXmlWriter.Destroy;
begin
  FOutput.Free;
  inherited;
end;

function TDomXmlWriter.IsAttributeKey(const Key: string): Boolean;
begin
  Result := (Key <> FOptions.TextKey) and (Length(Key) > Length(FOptions.AttributePrefix)) and
    (Copy(Key, 1, Length(FOptions.AttributePrefix)) = FOptions.AttributePrefix);
end;

procedure TDomXmlWriter.StartLine(Level: Integer);
begin
  if FOutput.Len > 0 then FOutput.Append(sLineBreak + StringOfChar(' ', 2 * Level));
end;

procedure TDomXmlWriter.WriteEscaped(const S: string; InAttribute: Boolean);
var
  I, RunStart: Integer;
  C: Char;
  Replacement: string;
begin
  RunStart := 1;
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '&': Replacement := '&amp;';
      '<': Replacement := '&lt;';
      '>': Replacement := '&gt;';
      '"': if InAttribute then Replacement := '&quot;' else Continue;
      #9: if InAttribute then Replacement := '&#x9;' else Continue;
      #10: if InAttribute then Replacement := '&#xA;' else Continue;
      #13: Replacement := '&#xD;';
    else
      if (C < ' ') or (Ord(C) >= $FFFE) then
        raise EJsonXmlError.CreateFmt('Character U+%.4X cannot be represented in XML 1.0', [Ord(C)]);
      Continue;
    end;
    FOutput.Append(Copy(S, RunStart, I - RunStart));
    FOutput.Append(Replacement);
    RunStart := I + 1;
  end;
  FOutput.Append(Copy(S, RunStart, Length(S) - RunStart + 1));
end;

function ScalarText(Value: TJsonValue): string;
begin
  if Value is TJsonNumber then
  begin
    Result := Value.AsRawText;
    if Result = '' then Result := '0';
  end
  else if Value is TJsonBoolean then
  begin
    if Value.AsBoolean then Result := 'true' else Result := 'false';
  end
  else if Value is TJsonNull then
    Result := ''
  else
    Result := Value.AsString;
end;

procedure TDomXmlWriter.WriteText(Value: TJsonValue);
var
  I: Integer;
begin
  if Value is TJsonArray then
  begin
    for I := 0 to TJsonArray(Value).Count - 1 do
      WriteText(TJsonArray(Value)[I]);
    Exit;
  end;
  if Value is TJsonObject then
    raise EJsonXmlError.CreateFmt('"%s" must hold a string, a number or an array of them', [FOptions.TextKey]);
  WriteEscaped(ScalarText(Value), False);
end;

procedure TDomXmlWriter.WriteElement(const Name: string; Value: TJsonValue; Level: Integer; Pretty: Boolean);
var
  I: Integer;
  XmlName: string;
begin
  if Level > FOptions.MaxDepth then
    raise EJsonXmlError.CreateFmt('Nesting deeper than MaxDepth (%d)', [FOptions.MaxDepth]);
  if Value is TJsonArray then
  begin
    for I := 0 to TJsonArray(Value).Count - 1 do
    begin
      if TJsonArray(Value)[I] is TJsonArray then
        raise EJsonXmlError.CreateFmt('An array inside the array "%s" has no XML form', [Name]);
      WriteElement(Name, TJsonArray(Value)[I], Level, Pretty);
    end;
    Exit;
  end;
  if Value is TJsonObject then
  begin
    WriteObjectElement(Name, TJsonObject(Value), Level, Pretty);
    Exit;
  end;
  XmlName := EncodeXmlName(Name);
  if Pretty then StartLine(Level);
  if (Value = nil) or (Value is TJsonNull) then
  begin
    FOutput.Append('<' + XmlName + '/>');
    Exit;
  end;
  FOutput.Append('<' + XmlName + '>');
  WriteEscaped(ScalarText(Value), False);
  FOutput.Append('</' + XmlName + '>');
end;

procedure TDomXmlWriter.WriteObjectElement(const Name: string; Value: TJsonObject; Level: Integer; Pretty: Boolean);
var
  Pair: TPair<string, TJsonValue>;
  XmlName: string;
  HasText, HasChildren, ChildPretty: Boolean;
begin
  XmlName := EncodeXmlName(Name);
  if Pretty then StartLine(Level);
  FOutput.Append('<' + XmlName);
  HasText := False;
  HasChildren := False;
  for Pair in Value do
    if Pair.Key = FOptions.TextKey then
      HasText := True
    else if IsAttributeKey(Pair.Key) then
    begin
      if Pair.Value.IsContainer then
        raise EJsonXmlError.CreateFmt('Attribute "%s" must hold a scalar value', [Pair.Key]);
      if Pair.Value is TJsonNull then Continue;
      FOutput.Append(' ' + EncodeXmlName(Copy(Pair.Key, Length(FOptions.AttributePrefix) + 1, MaxInt)) + '="');
      WriteEscaped(ScalarText(Pair.Value), True);
      FOutput.Append('"');
    end
    else
      HasChildren := True;
  if not HasText and not HasChildren then
  begin
    FOutput.Append('/>');
    Exit;
  end;
  FOutput.Append('>');
  ChildPretty := Pretty and not HasText;
  for Pair in Value do
    if Pair.Key = FOptions.TextKey then
      WriteText(Pair.Value)
    else if not IsAttributeKey(Pair.Key) then
      WriteElement(Pair.Key, Pair.Value, Level + 1, ChildPretty);
  if ChildPretty then StartLine(Level);
  FOutput.Append('</' + XmlName + '>');
end;

function TDomXmlWriter.Write(Value: TJsonValue): string;
var
  RootName: string;
  RootValue: TJsonValue;
  Pair: TPair<string, TJsonValue>;
begin
  if Value = nil then raise EArgumentNilException.Create('Value');
  if FOptions.RootName <> '' then
  begin
    RootName := FOptions.RootName;
    RootValue := Value;
  end
  else
  begin
    if not (Value is TJsonObject) or (TJsonObject(Value).Count <> 1) then
      raise EJsonXmlError.Create('The JSON value needs exactly one property to become the document element, or set RootName');
    RootValue := nil;
    for Pair in TJsonObject(Value) do
    begin
      RootName := Pair.Key;
      RootValue := Pair.Value;
    end;
    if (RootName = FOptions.TextKey) or IsAttributeKey(RootName) then
      raise EJsonXmlError.CreateFmt('"%s" cannot be the document element', [RootName]);
  end;
  if RootValue is TJsonArray then
    raise EJsonXmlError.Create('An array cannot be the document element; wrap it in an object');
  if FOptions.WriteDeclaration then FOutput.Append('<?xml version="1.0" encoding="UTF-8"?>');
  WriteElement(RootName, RootValue, 0, FOptions.Indent);
  Result := FOutput.Text;
end;

constructor TXmlDomReader.Create(const Xml: string; Options: TJsonXmlOptions);
begin
  inherited Create;
  FText := Xml;
  FLen := Length(Xml);
  FPos := 1;
  FOptions := Options;
end;

procedure TXmlDomReader.Fail(const Msg: string);
var
  I, Line, LineStart: Integer;
begin
  Line := 1;
  LineStart := 1;
  for I := 1 to FPos - 1 do
    if (I <= FLen) and (FText[I] = #10) then
    begin
      Inc(Line);
      LineStart := I + 1;
    end;
  raise EJsonXmlError.CreateFmt('%s at line %d, column %d', [Msg, Line, FPos - LineStart + 1]);
end;

function TXmlDomReader.Peek(const S: string): Boolean;
begin
  Result := (FPos + Length(S) - 1 <= FLen) and
    CompareMem(@FText[FPos], PChar(S), Length(S) * SizeOf(Char));
end;

procedure TXmlDomReader.Expect(const S: string);
begin
  if not Peek(S) then Fail('"' + S + '" expected');
  Inc(FPos, Length(S));
end;

function TXmlDomReader.SkipWhitespace: Boolean;
var
  Start: Integer;
begin
  Start := FPos;
  while (FPos <= FLen) and IsWhiteChar(FText[FPos]) do Inc(FPos);
  Result := FPos > Start;
end;

procedure TXmlDomReader.SkipUntil(const Terminator, What: string);
begin
  while (FPos <= FLen) and not Peek(Terminator) do Inc(FPos);
  if FPos > FLen then Fail('Unterminated ' + What);
  Inc(FPos, Length(Terminator));
end;

procedure TXmlDomReader.SkipDoctype;
var
  InSubset: Boolean;
  Quote: Char;
begin
  Inc(FPos, Length('<!DOCTYPE'));
  InSubset := False;
  while FPos <= FLen do
  begin
    case FText[FPos] of
      '"', '''':
        begin
          Quote := FText[FPos];
          Inc(FPos);
          while (FPos <= FLen) and (FText[FPos] <> Quote) do Inc(FPos);
        end;
      '[': InSubset := True;
      ']': InSubset := False;
      '>':
        if not InSubset then
        begin
          Inc(FPos);
          Exit;
        end;
    end;
    Inc(FPos);
  end;
  Fail('Unterminated DOCTYPE');
end;

procedure TXmlDomReader.SkipMisc(AllowDoctype: Boolean);
begin
  repeat
    SkipWhitespace;
    if Peek('<?') then
    begin
      Inc(FPos, 2);
      SkipUntil('?>', 'processing instruction');
    end
    else if Peek('<!--') then
    begin
      Inc(FPos, 4);
      SkipUntil('-->', 'comment');
    end
    else if AllowDoctype and Peek('<!DOCTYPE') then
    begin
      SkipDoctype;
      AllowDoctype := False;
    end
    else
      Break;
  until False;
end;

function TXmlDomReader.ReadName: string;
var
  Start: Integer;
begin
  if (FPos > FLen) or not IsNameStartChar(FText[FPos]) then Fail('Name expected');
  Start := FPos;
  Inc(FPos);
  while (FPos <= FLen) and IsNameChar(FText[FPos]) do Inc(FPos);
  Result := Copy(FText, Start, FPos - Start);
end;

function TXmlDomReader.ReadReference: string;
var
  Start, I, Base: Integer;
  Ref: string;
  Code: Int64;
  Digit: Integer;
begin
  Inc(FPos);
  Start := FPos;
  while (FPos <= FLen) and (FText[FPos] <> ';') and (FPos - Start < 12) do Inc(FPos);
  if (FPos > FLen) or (FText[FPos] <> ';') then Fail('Unterminated character or entity reference');
  Ref := Copy(FText, Start, FPos - Start);
  Inc(FPos);
  if Ref = 'amp' then Exit('&');
  if Ref = 'lt' then Exit('<');
  if Ref = 'gt' then Exit('>');
  if Ref = 'quot' then Exit('"');
  if Ref = 'apos' then Exit('''');
  if (Length(Ref) < 2) or (Ref[1] <> '#') then Fail('Unknown entity &' + Ref + ';');
  if Ref[2] = 'x' then
  begin
    Base := 16;
    I := 3;
  end
  else
  begin
    Base := 10;
    I := 2;
  end;
  if I > Length(Ref) then Fail('Invalid character reference &' + Ref + ';');
  Code := 0;
  while I <= Length(Ref) do
  begin
    case Ref[I] of
      '0'..'9': Digit := Ord(Ref[I]) - Ord('0');
      'a'..'f': Digit := Ord(Ref[I]) - Ord('a') + 10;
      'A'..'F': Digit := Ord(Ref[I]) - Ord('A') + 10;
    else
      Digit := Base;
    end;
    if Digit >= Base then Fail('Invalid character reference &' + Ref + ';');
    Code := Code * Base + Digit;
    Inc(I);
  end;
  if not ((Code = 9) or (Code = 10) or (Code = 13) or ((Code >= $20) and (Code <= $D7FF)) or
    ((Code >= $E000) and (Code <= $FFFD)) or ((Code >= $10000) and (Code <= $10FFFF))) then
    Fail('Character reference &' + Ref + '; is not an XML character');
  if Code >= $10000 then
  begin
    Code := Code - $10000;
    Result := Char(Word($D800 + (Code shr 10))) + Char(Word($DC00 + (Code and $3FF)));
  end
  else
    Result := Char(Word(Code));
end;

function TXmlDomReader.ReadAttributeValue: string;
var
  Quote: Char;
  RunStart: Integer;
  Value: string;

  procedure Flush;
  begin
    Value := Value + Copy(FText, RunStart, FPos - RunStart);
  end;

begin
  if (FPos > FLen) or ((FText[FPos] <> '"') and (FText[FPos] <> '''')) then Fail('Quoted attribute value expected');
  Quote := FText[FPos];
  Inc(FPos);
  Value := '';
  RunStart := FPos;
  while True do
  begin
    if FPos > FLen then Fail('Unterminated attribute value');
    case FText[FPos] of
      '<': Fail('"<" is not allowed in an attribute value');
      '&':
        begin
          Flush;
          Value := Value + ReadReference;
          RunStart := FPos;
        end;
      #9, #10, #13:
        begin
          Flush;
          if (FText[FPos] = #13) and (FPos < FLen) and (FText[FPos + 1] = #10) then Inc(FPos);
          Inc(FPos);
          Value := Value + ' ';
          RunStart := FPos;
        end;
    else
      if FText[FPos] = Quote then
      begin
        Flush;
        Inc(FPos);
        Exit(Value);
      end;
      Inc(FPos);
    end;
  end;
end;

function TXmlDomReader.MakeScalar(const Text: string): TJsonValue;
begin
  if FOptions.InferTypes then
  begin
    if Text = 'true' then Exit(TJsonBoolean.Create(True));
    if Text = 'false' then Exit(TJsonBoolean.Create(False));
    if IsJsonNumber(Text) then
      Exit(TJsonNumber.Create(Text, (Pos('.', Text) > 0) or (Pos('e', Text) > 0) or (Pos('E', Text) > 0)));
  end;
  Result := TJsonString.Create(Text);
end;

function TXmlDomReader.IsForcedArray(const Name, Path: string): Boolean;
var
  Entry: string;
begin
  for Entry in FOptions.ForceArrays do
    if (Entry = Name) or (Entry = Path) then Exit(True);
  Result := False;
end;

function TXmlDomReader.BuildValue(const Path: string; Attributes: TXmlAttributes;
  Children: TXmlChildren; Texts: TList<string>): TJsonValue;
var
  Obj: TJsonObject;
  TextArray, Arr: TJsonArray;
  Counts: TDictionary<string, Integer>;
  Arrays: TDictionary<string, TJsonArray>;
  Order: TList<string>;
  Meaningful: TList<string>;
  Name, Text: string;
  I, Count: Integer;
begin
  if (Attributes.Count = 0) and (Children.Count = 0) then
  begin
    Text := '';
    for I := 0 to Texts.Count - 1 do
      Text := Text + Texts[I];
    if Text = '' then Exit(TJsonNull.Create);
    Exit(MakeScalar(Text));
  end;
  Obj := TJsonObject.Create;
  Counts := TDictionary<string, Integer>.Create;
  Arrays := TDictionary<string, TJsonArray>.Create;
  Order := TList<string>.Create;
  Meaningful := TList<string>.Create;
  try
    try
      for I := 0 to Attributes.Count - 1 do
        Obj.AddPair(FOptions.AttributePrefix + DecodeXmlName(Attributes[I].Key), MakeScalar(Attributes[I].Value));
      for I := 0 to Texts.Count - 1 do
        if Trim(Texts[I]) <> '' then Meaningful.Add(Texts[I]);
      if Meaningful.Count = 1 then
        Obj.AddPair(FOptions.TextKey, MakeScalar(Meaningful[0]))
      else if Meaningful.Count > 1 then
      begin
        TextArray := TJsonArray.Create;
        Obj.AddPair(FOptions.TextKey, TextArray);
        for I := 0 to Meaningful.Count - 1 do
          TextArray.Add(MakeScalar(Meaningful[I]));
      end;
      for I := 0 to Children.Count - 1 do
      begin
        Name := Children[I].Key;
        if Counts.TryGetValue(Name, Count) then
          Counts[Name] := Count + 1
        else
        begin
          Counts.Add(Name, 1);
          Order.Add(Name);
        end;
      end;
      for Name in Order do
        if (Counts[Name] > 1) or IsForcedArray(Name, Path + '/' + Name) then
        begin
          Arr := TJsonArray.Create;
          Obj.AddPair(Name, Arr);
          Arrays.Add(Name, Arr);
        end;
      for I := 0 to Children.Count - 1 do
      begin
        Name := Children[I].Key;
        if Arrays.TryGetValue(Name, Arr) then
          Arr.Add(Children[I].Value)
        else
          Obj.AddPair(Name, Children[I].Value);
        Children[I] := TXmlChild.Create(Name, nil);
      end;
    except
      Obj.Free;
      raise;
    end;
  finally
    Meaningful.Free;
    Order.Free;
    Arrays.Free;
    Counts.Free;
  end;
  Result := Obj;
end;

function TXmlDomReader.ParseElement(const ParentPath: string; Depth: Integer; out Name: string): TJsonValue;
var
  RawName, Path, AttrName, AttrValue, ChildName, Segment: string;
  Attributes: TXmlAttributes;
  Children: TXmlChildren;
  Texts: TList<string>;
  Child: TJsonValue;
  Empty, HadSpace: Boolean;
  I, RunStart, CDataStart, TagStart: Integer;

  procedure Flush;
  begin
    Segment := Segment + Copy(FText, RunStart, FPos - RunStart);
  end;

begin
  if Depth > FOptions.MaxDepth then Fail(Format('Nesting deeper than MaxDepth (%d)', [FOptions.MaxDepth]));
  Inc(FPos);
  RawName := ReadName;
  Name := DecodeXmlName(RawName);
  if ParentPath = '' then Path := Name else Path := ParentPath + '/' + Name;
  Attributes := TXmlAttributes.Create;
  Children := TXmlChildren.Create;
  Texts := TList<string>.Create;
  try
    Empty := False;
    while True do
    begin
      HadSpace := SkipWhitespace;
      if Peek('/>') then
      begin
        Inc(FPos, 2);
        Empty := True;
        Break;
      end;
      if Peek('>') then
      begin
        Inc(FPos);
        Break;
      end;
      if FPos > FLen then Fail('Unterminated start tag <' + RawName + '>');
      if not HadSpace then Fail('Whitespace expected before an attribute');
      AttrName := ReadName;
      SkipWhitespace;
      Expect('=');
      SkipWhitespace;
      AttrValue := ReadAttributeValue;
      for I := 0 to Attributes.Count - 1 do
        if Attributes[I].Key = AttrName then Fail('Duplicate attribute "' + AttrName + '"');
      Attributes.Add(TXmlAttribute.Create(AttrName, AttrValue));
    end;
    if not Empty then
    begin
      Segment := '';
      RunStart := FPos;
      while True do
      begin
        if FPos > FLen then Fail('Unterminated element <' + RawName + '>');
        case FText[FPos] of
          '<':
            begin
              Flush;
              if Peek('</') then
              begin
                TagStart := FPos;
                Inc(FPos, 2);
                ChildName := ReadName;
                if ChildName <> RawName then
                begin
                  FPos := TagStart;
                  Fail('End tag </' + ChildName + '> does not match <' + RawName + '>');
                end;
                SkipWhitespace;
                Expect('>');
                Break;
              end
              else if Peek('<!--') then
              begin
                Inc(FPos, 4);
                SkipUntil('-->', 'comment');
              end
              else if Peek('<![CDATA[') then
              begin
                Inc(FPos, 9);
                CDataStart := FPos;
                SkipUntil(']]>', 'CDATA section');
                Segment := Segment + NormalizeLineEnds(Copy(FText, CDataStart, FPos - 3 - CDataStart));
              end
              else if Peek('<?') then
              begin
                Inc(FPos, 2);
                SkipUntil('?>', 'processing instruction');
              end
              else if Peek('<!') then
                Fail('Unexpected markup declaration')
              else
              begin
                if Segment <> '' then Texts.Add(Segment);
                Segment := '';
                Child := ParseElement(Path, Depth + 1, ChildName);
                try
                  Children.Add(TXmlChild.Create(ChildName, Child));
                except
                  Child.Free;
                  raise;
                end;
              end;
              RunStart := FPos;
            end;
          '&':
            begin
              Flush;
              Segment := Segment + ReadReference;
              RunStart := FPos;
            end;
          #13:
            begin
              Flush;
              Inc(FPos);
              if (FPos <= FLen) and (FText[FPos] = #10) then Inc(FPos);
              Segment := Segment + #10;
              RunStart := FPos;
            end;
          ']':
            begin
              if Peek(']]>') then Fail('"]]>" is not allowed in text');
              Inc(FPos);
            end;
        else
          Inc(FPos);
        end;
      end;
      if Segment <> '' then Texts.Add(Segment);
    end;
    Result := BuildValue(Path, Attributes, Children, Texts);
  finally
    for I := 0 to Children.Count - 1 do
      Children[I].Value.Free;
    Texts.Free;
    Children.Free;
    Attributes.Free;
  end;
end;

function TXmlDomReader.Parse: TJsonValue;
var
  Name: string;
  Value: TJsonValue;
  Obj: TJsonObject;
begin
  if (FLen > 0) and (FText[1] = #$FEFF) then Inc(FPos);
  SkipMisc(True);
  if not Peek('<') then Fail('Document element expected');
  Value := ParseElement('', 1, Name);
  try
    SkipMisc(False);
    if FPos <= FLen then Fail('Content after the document element');
    Obj := TJsonObject.Create;
  except
    Value.Free;
    raise;
  end;
  Obj.AddPair(Name, Value);
  Result := Obj;
end;

function XmlToDom(const Xml: string; Options: TJsonXmlOptions): TJsonValue;
var
  OwnOptions: TJsonXmlOptions;
  Reader: TXmlDomReader;
begin
  OwnOptions := nil;
  if Options = nil then
  begin
    OwnOptions := TJsonXmlOptions.Create;
    Options := OwnOptions;
  end;
  try
    Reader := TXmlDomReader.Create(Xml, Options);
    try
      Result := Reader.Parse;
    finally
      Reader.Free;
    end;
  finally
    OwnOptions.Free;
  end;
end;

function XmlToJson(const Xml: string; Options: TJsonXmlOptions): string;
var
  Dom: TJsonValue;
begin
  Dom := XmlToDom(Xml, Options);
  try
    if (Options <> nil) and Options.Indent then
      Result := DomToText(Dom, TJsonFormatting.Indented)
    else
      Result := DomToText(Dom);
  finally
    Dom.Free;
  end;
end;

function DomToXml(Value: TJsonValue; Options: TJsonXmlOptions): string;
var
  OwnOptions: TJsonXmlOptions;
  Writer: TDomXmlWriter;
begin
  OwnOptions := nil;
  if Options = nil then
  begin
    OwnOptions := TJsonXmlOptions.Create;
    Options := OwnOptions;
  end;
  try
    Writer := TDomXmlWriter.Create(Options);
    try
      Result := Writer.Write(Value);
    finally
      Writer.Free;
    end;
  finally
    OwnOptions.Free;
  end;
end;

function JsonToXml(const Json: string; Options: TJsonXmlOptions): string;
var
  Dom: TJsonValue;
begin
  Dom := DomFromText(Json);
  try
    Result := DomToXml(Dom, Options);
  finally
    Dom.Free;
  end;
end;

end.
