#!/bin/zsh
# Regenerates the emulator gRPC client from the vendored protos.
# Needs: brew install protobuf swift-protobuf protoc-gen-grpc-swift
# To update the protos, copy them from <sdk>/emulator/lib/*.proto into Packages/ADHKit/Protos/emulator/.
set -euo pipefail
cd "$(dirname "$0")/../Packages/ADHKit"
protos=Protos/emulator
out=Sources/EmulatorGRPC/Generated
rm -rf "$out"
mkdir -p "$out"
protoc \
  --proto_path="$protos" \
  --swift_out="$out" \
  --swift_opt=Visibility=Public,UseAccessLevelOnImports=true \
  --grpc-swift-2_out="$out" \
  --grpc-swift-2_opt=Visibility=Public,Client=true,Server=false,UseAccessLevelOnImports=true \
  "$protos"/emulator_controller.proto "$protos"/snapshot_service.proto "$protos"/snapshot.proto \
  "$protos"/ui_controller_service.proto
for file in "$out"/*.swift; do
  printf '// swift-format-ignore-file\n// swiftlint:disable all\n' | cat - "$file" > "$file.tmp" && mv "$file.tmp" "$file"
done
ls "$out"
