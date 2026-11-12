{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit Package3.CodeGen.RepositoryTests;

interface

{$I NativeJson.inc}

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('codegen.repository')]
  TCodeGenRepositoryTests = class
  public
    [Test] procedure ResolveFragmentAgainstBase;
    [Test] procedure ResolveSiblingFile;
    [Test] procedure ResolveParentDirectory;
    [Test] procedure ResolveRootRelativePath;
    [Test] procedure ResolveAbsoluteUri;
    [Test] procedure ResolveQuery;
    [Test] procedure ResolveDotPathKeepsDirectory;
    [Test] procedure ResolveDotDotPathKeepsParentDirectory;
    [Test] procedure ResolveNormalizesDotSegments;
    [Test] procedure RegisteredRootCanBeResolved;
    [Test] procedure JsonPointerCanBeResolved;
    [Test] procedure JsonPointerEscapedSlashCanBeResolved;
    [Test] procedure JsonPointerEscapedTildeCanBeResolved;
    [Test] procedure AnchorCanBeResolved;
    [Test] procedure NestedIdCanBeResolvedAsResource;
    [Test] procedure MissingResourceReturnsFalse;
    [Test] procedure MissingPointerReturnsFalse;
    [Test] procedure SourceUriFragmentIsRemovedForResourceBase;
  end;

implementation

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE}
  System.SysUtils,
  {$ENDIF}
  NativeJson.CodeGen.Repository;

procedure TCodeGenRepositoryTests.ResolveFragmentAgainstBase;
begin
  Assert.AreEqual('https://example.test/a/root.json#/$defs/x', TJsonCodeGenRepository.ResolveUri('https://example.test/a/root.json', '#/$defs/x'));
end;

procedure TCodeGenRepositoryTests.ResolveSiblingFile;
begin
  Assert.AreEqual('https://example.test/a/child.json', TJsonCodeGenRepository.ResolveUri('https://example.test/a/root.json', 'child.json'));
end;

procedure TCodeGenRepositoryTests.ResolveParentDirectory;
begin
  Assert.AreEqual('https://example.test/common.json', TJsonCodeGenRepository.ResolveUri('https://example.test/a/root.json', '../common.json'));
end;

procedure TCodeGenRepositoryTests.ResolveRootRelativePath;
begin
  Assert.AreEqual('https://example.test/common/schema.json', TJsonCodeGenRepository.ResolveUri('https://example.test/a/root.json', '/common/schema.json'));
end;

procedure TCodeGenRepositoryTests.ResolveAbsoluteUri;
begin
  Assert.AreEqual('https://other.test/schema.json', TJsonCodeGenRepository.ResolveUri('https://example.test/a/root.json', 'https://other.test/schema.json'));
end;

procedure TCodeGenRepositoryTests.ResolveQuery;
begin
  Assert.AreEqual('https://example.test/a/root.json?v=2', TJsonCodeGenRepository.ResolveUri('https://example.test/a/root.json?v=1', '?v=2'));
end;

procedure TCodeGenRepositoryTests.ResolveDotPathKeepsDirectory;
begin
  Assert.AreEqual('https://example.test/a/', TJsonCodeGenRepository.ResolveUri('https://example.test/a/root.json', '.'));
end;

procedure TCodeGenRepositoryTests.ResolveDotDotPathKeepsParentDirectory;
begin
  Assert.AreEqual('https://example.test/', TJsonCodeGenRepository.ResolveUri('https://example.test/a/root.json', '..'));
end;

procedure TCodeGenRepositoryTests.ResolveNormalizesDotSegments;
begin
  Assert.AreEqual('https://example.test/a/c/schema.json', TJsonCodeGenRepository.ResolveUri('https://example.test/a/b/root.json', '../c/./schema.json'));
end;

procedure TCodeGenRepositoryTests.RegisteredRootCanBeResolved;
var
  Repository: TJsonCodeGenRepository;
  Location: TJsonCodeGenLocation;
begin
  Repository := TJsonCodeGenRepository.Create;
  try
    Repository.RegisterSchema('{"type":"string"}', 'https://example.test/root.json');
    Assert.IsTrue(Repository.Resolve('https://example.test/root.json', '', Location));
    Assert.AreEqual('https://example.test/root.json', Location.BaseUri);
  finally
    Repository.Free;
  end;
end;

procedure TCodeGenRepositoryTests.JsonPointerCanBeResolved;
var
  Repository: TJsonCodeGenRepository;
  Location: TJsonCodeGenLocation;
begin
  Repository := TJsonCodeGenRepository.Create;
  try
    Repository.RegisterSchema('{"$defs":{"x":{"type":"integer"}}}', 'https://example.test/root.json');
    Assert.IsTrue(Repository.Resolve('#/$defs/x', 'https://example.test/root.json', Location));
    Assert.AreEqual('/$defs/x', Location.Pointer);
  finally
    Repository.Free;
  end;
end;

procedure TCodeGenRepositoryTests.JsonPointerEscapedSlashCanBeResolved;
var
  Repository: TJsonCodeGenRepository;
  Location: TJsonCodeGenLocation;
begin
  Repository := TJsonCodeGenRepository.Create;
  try
    Repository.RegisterSchema('{"$defs":{"a/b":{"type":"string"}}}', 'https://example.test/root.json');
    Assert.IsTrue(Repository.Resolve('#/$defs/a~1b', 'https://example.test/root.json', Location));
  finally
    Repository.Free;
  end;
end;

procedure TCodeGenRepositoryTests.JsonPointerEscapedTildeCanBeResolved;
var
  Repository: TJsonCodeGenRepository;
  Location: TJsonCodeGenLocation;
begin
  Repository := TJsonCodeGenRepository.Create;
  try
    Repository.RegisterSchema('{"$defs":{"a~b":{"type":"string"}}}', 'https://example.test/root.json');
    Assert.IsTrue(Repository.Resolve('#/$defs/a~0b', 'https://example.test/root.json', Location));
  finally
    Repository.Free;
  end;
end;

procedure TCodeGenRepositoryTests.AnchorCanBeResolved;
var
  Repository: TJsonCodeGenRepository;
  Location: TJsonCodeGenLocation;
begin
  Repository := TJsonCodeGenRepository.Create;
  try
    Repository.RegisterSchema('{"$defs":{"x":{"$anchor":"here","type":"string"}}}', 'https://example.test/root.json');
    Assert.IsTrue(Repository.Resolve('#here', 'https://example.test/root.json', Location));
    Assert.AreEqual('/$defs/x', Location.Pointer);
  finally
    Repository.Free;
  end;
end;

procedure TCodeGenRepositoryTests.NestedIdCanBeResolvedAsResource;
var
  Repository: TJsonCodeGenRepository;
  Location: TJsonCodeGenLocation;
begin
  Repository := TJsonCodeGenRepository.Create;
  try
    Repository.RegisterSchema('{"$id":"https://example.test/root.json","$defs":{"x":{"$id":"child.json","type":"integer"}}}', 'https://example.test/root.json');
    Assert.IsTrue(Repository.Resolve('child.json', 'https://example.test/root.json', Location));
    Assert.AreEqual('https://example.test/child.json', Location.BaseUri);
  finally
    Repository.Free;
  end;
end;

procedure TCodeGenRepositoryTests.MissingResourceReturnsFalse;
var
  Repository: TJsonCodeGenRepository;
  Location: TJsonCodeGenLocation;
begin
  Repository := TJsonCodeGenRepository.Create;
  try
    Repository.RegisterSchema('{}', 'https://example.test/root.json');
    Assert.IsTrue(not Repository.Resolve('missing.json', 'https://example.test/root.json', Location));
  finally
    Repository.Free;
  end;
end;

procedure TCodeGenRepositoryTests.MissingPointerReturnsFalse;
var
  Repository: TJsonCodeGenRepository;
  Location: TJsonCodeGenLocation;
begin
  Repository := TJsonCodeGenRepository.Create;
  try
    Repository.RegisterSchema('{}', 'https://example.test/root.json');
    Assert.IsTrue(not Repository.Resolve('#/$defs/missing', 'https://example.test/root.json', Location));
  finally
    Repository.Free;
  end;
end;

procedure TCodeGenRepositoryTests.SourceUriFragmentIsRemovedForResourceBase;
var
  Repository: TJsonCodeGenRepository;
  Location: TJsonCodeGenLocation;
begin
  Repository := TJsonCodeGenRepository.Create;
  try
    Location := Repository.RegisterSchema('{}', 'https://example.test/root.json#ignored');
    Assert.AreEqual('https://example.test/root.json', Location.BaseUri);
  finally
    Repository.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeGenRepositoryTests);

end.
