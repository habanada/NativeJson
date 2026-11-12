{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Sequence;

// Process a large array element by element.
//
//   The normal route first loads the whole JSON into memory as a DOM and
//   then walks it with RTTI. For a file with 200,000 records
//   all 200,000 nodes AND all 200,000 objects exist at the same
//   time. Peak memory is the sum of everything.
//
//   Here instead one element is read, processed and freed again
//   right away. Peak memory is the text plus ONE
//   element - regardless of how many there are in total.
//
//   What this is NOT: the tokenizer works on a string in
//   memory. So the text itself is still loaded
//   completely. What is saved is the DOM and the object graph - for typical
//   records that is the larger part, but it is not zero.
//
//   This unit does not touch the deserializer. It only uses it
//   for one element at a time.

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  {$ENDIF}
  NativeJson.Core.Reader,
  NativeJson.Core.Tokens,
  NativeJson.Dom.Value,
  NativeJson.Dom.Io;

type
  EJsonSequenceError = class(Exception);

  /// <summary>
  ///   Walks a top-level JSON array and returns the
  ///   elements one by one as DOM. The caller owns every returned
  ///   element and must free it.
  /// </summary>
  TJsonElementSequence = class
  private
    FReader: TJsonReader;
    FIndex: Integer;
    FDone: Boolean;
    FStarted: Boolean;
    procedure Starte;
  public
    constructor Create(const Json: string);
    destructor Destroy; override;

    /// <summary>
    ///   Returns the next element. False means: the array has
    ///   ended. The returned element belongs to the caller.
    /// </summary>
    function NextItem(out Element: TJsonValue): Boolean;

    /// <summary>How many elements have been returned so far.</summary>
    property Index: Integer read FIndex;
  end;

implementation

constructor TJsonElementSequence.Create(const Json: string);
begin
  inherited Create;
  FReader := TJsonReader.Create(Json);
  FIndex := 0;
  FDone := False;
  FStarted := False;
end;

destructor TJsonElementSequence.Destroy;
begin
  FReader.Free;
  inherited;
end;

procedure TJsonElementSequence.Starte;
begin
  FStarted := True;
  if not FReader.Read then
  begin
    FDone := True;
    raise EJsonSequenceError.Create('Empty JSON input');
  end;
  // Deliberately arrays only. Reading a single object piece by piece would be
  // something else - the normal route exists for that, and a half
  // read object is not a usable record.
  if FReader.TokenType <> TJsonToken.StartArray then
  begin
    FDone := True;
    raise EJsonSequenceError.Create(
      'The sequence reader expects a JSON array at the top level. ' +
      'Use JsonConvert.DeserializeObject for anything else.');
  end;
end;

function TJsonElementSequence.NextItem(out Element: TJsonValue): Boolean;
begin
  Element := nil;
  if FDone then Exit(False);
  if not FStarted then Starte;

  if not FReader.Read then
  begin
    FDone := True;
    raise EJsonSequenceError.Create('Unterminated array');
  end;
  if FReader.TokenType = TJsonToken.EndArray then
  begin
    FDone := True;
    Exit(False);
  end;

  // DomFromReader builds exactly ONE element - afterwards the reader is on
  // its last token, the next Read returns the comma or the
  // start of the next element.
  Element := DomFromReader(FReader);
  Inc(FIndex);
  Result := True;
end;

end.
