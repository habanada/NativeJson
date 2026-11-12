{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Memory.Model;

{
  Model for the memory test.

  Deliberately built so that as many ownership relations as possible occur:
  owned sub-objects, lists with and without ownership, streams, byte arrays,
  dictionaries, cycles and polymorphic subclasses. Each of these places
  is a candidate for a leak.

  The classes live in a unit (not in the .dpr), because they are rebuilt
  via $type - RTTI does not find types declared in the program.
  JsonKeepTypes additionally protects them against the linker.
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  NativeJson.Attributes;

type
  TNodeKind = (nkRoot, nkBranch, nkLeaf);

  TBranchNode = class;
  TLeafNode = class;

  // Polymorphic hierarchy
  [JsonKnownType('TBranchNode')]
  [JsonKnownType('TLeafNode')]
  TNode = class
  private
    FName: string;
    FCategory: TNodeKind;
  public
    property Name: string read FName write FName;
    property Art: TNodeKind read FCategory write FCategory;
  end;

  TBranchNode = class(TNode)
  private
    FChildren: TObjectList<TNode>;
  public
    constructor Create;
    destructor Destroy; override;
    property Children: TObjectList<TNode> read FChildren;
  end;

  TLeafNode = class(TNode)
  private
    FPayload: TBytes;
    FWeight: Double;
  public
    property Payload: TBytes read FPayload write FPayload;
    property Weight: Double read FWeight write FWeight;
  end;

  // Collection object with everything that can hold memory
  THeavyLoad = class
  private
    FDesignation: string;
    FAttachment: TMemoryStream;
    FLines: TStringList;
    FFeatures: TDictionary<string, string>;
    FRawData: TBytes;
    FTree: TBranchNode;
    FNeighbor: THeavyLoad;
  public
    constructor Create;
    destructor Destroy; override;

    property Designation: string read FDesignation write FDesignation;
    property Attachment: TMemoryStream read FAttachment;
    property Lines: TStringList read FLines;
    property Features: TDictionary<string, string> read FFeatures;
    property RawData: TBytes read FRawData write FRawData;
    property Tree: TBranchNode read FTree;

    // Deliberately writable: allows a cycle for $id/$ref
    property Neighbor: THeavyLoad read FNeighbor write FNeighbor;
  end;

function CreateHeavyLoad(TreeDepth, BytesPerLeaf: Integer): THeavyLoad;

implementation

{ TBranchNode }

constructor TBranchNode.Create;
begin
  inherited Create;
  FChildren := TObjectList<TNode>.Create(True);
  Art := nkBranch;
end;

destructor TBranchNode.Destroy;
begin
  FChildren.Free;
  inherited;
end;

{ THeavyLoad }

constructor THeavyLoad.Create;
begin
  inherited Create;
  FAttachment := TMemoryStream.Create;
  FLines := TStringList.Create;
  FFeatures := TDictionary<string, string>.Create;
  FTree := TBranchNode.Create;
end;

destructor THeavyLoad.Destroy;
begin
  // Neighbor is NOT freed - ownership stays with the creator.
  FTree.Free;
  FFeatures.Free;
  FLines.Free;
  FAttachment.Free;
  inherited;
end;

function CreateHeavyLoad(TreeDepth, BytesPerLeaf: Integer): THeavyLoad;

  procedure BuildLevel(Parents: TBranchNode; RemainingDepth: Integer);
  var
    I, J: Integer;
    Branch: TBranchNode;
    Leaf: TLeafNode;
    Data: TBytes;
  begin
    if RemainingDepth <= 0 then Exit;
    for I := 1 to 3 do
    begin
      if RemainingDepth > 1 then
      begin
        Branch := TBranchNode.Create;
        Branch.Name := Format('Branch-%d-%d', [RemainingDepth, I]);
        Parents.Children.Add(Branch);
        BuildLevel(Branch, RemainingDepth - 1);
      end
      else
      begin
        Leaf := TLeafNode.Create;
        Leaf.Name := Format('Leaf-%d', [I]);
        Leaf.Art := nkLeaf;
        Leaf.Weight := I * 1.5;
        SetLength(Data, BytesPerLeaf);
        for J := 0 to BytesPerLeaf - 1 do
          Data[J] := Byte((I * 31 + J) mod 256);
        Leaf.Payload := Data;
        Parents.Children.Add(Leaf);
      end;
    end;
  end;

var
  RawData: TBytes;
  I: Integer;
begin
  Result := THeavyLoad.Create;
  Result.Designation := 'Memory test record';

  SetLength(RawData, 4096);
  for I := 0 to High(RawData) do
    RawData[I] := Byte(I mod 256);
  Result.RawData := RawData;

  Result.Attachment.WriteBuffer(RawData[0], Length(RawData));
  Result.Attachment.Position := 0;

  for I := 1 to 50 do
    Result.Lines.Add('Line ' + IntToStr(I));

  for I := 1 to 50 do
    Result.Features.Add('Key' + IntToStr(I), 'Value ' + IntToStr(I));

  Result.Tree.Name := 'Root';
  Result.Tree.Art := nkRoot;
  BuildLevel(Result.Tree, TreeDepth);
end;

initialization
  JsonKeepTypes([TNode, TBranchNode, TLeafNode]);

end.
