{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Schema.Decimal;

interface

{$I NativeJson.inc}

uses
  NativeJson.ExactNumber;

type
  // Backward-compatible alias. TJsonExactNumber is a JSON core primitive now,
  // but existing code using NativeJson.Schema.Decimal keeps compiling.
  TJsonExactNumber = NativeJson.ExactNumber.TJsonExactNumber;

implementation

end.
