{ lib, stdenv, swift, swiftpm, makeWrapper, rcodesign, open-apple-macros }:

stdenv.mkDerivation {
  pname = "browser-router";
  version = "0.1.2";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Package.swift
      ../Sources
      ../Tests
      ../scripts/Info.plist
    ];
  };

  nativeBuildInputs = [ swift swiftpm makeWrapper rcodesign ];
  depsBuildBuild = [ open-apple-macros ];
  enableParallelBuilding = true;

  preBuild = ''
    export CLANG_MODULE_CACHE_PATH="$TMPDIR/clang-module-cache"
    swiftpmFlagsArray+=(
      --cache-path "$TMPDIR/swift-cache"
      --config-path "$TMPDIR/swift-config"
      --security-path "$TMPDIR/swift-security"
    )
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    "$(swiftpmBinPath)/RouterCoreChecks"
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    app="$out/Applications/Browser Router.app"
    mkdir -p "$app/Contents/MacOS" "$out/bin"
    cp "$(swiftpmBinPath)/BrowserRouter" "$app/Contents/MacOS/BrowserRouter"
    cp scripts/Info.plist "$app/Contents/Info.plist"
    makeWrapper /usr/bin/open "$out/bin/browser-router" \
      --add-flags "\"$app\""
    runHook postInstall
  '';

  postFixup = ''
    rcodesign sign "$out/Applications/Browser Router.app"
  '';

  meta = {
    description = "Route web links to browsers and profiles with configurable overrides";
    homepage = "https://github.com/ditsuke/browser-router";
    platforms = [ "aarch64-darwin" ];
    mainProgram = "browser-router";
  };
}
