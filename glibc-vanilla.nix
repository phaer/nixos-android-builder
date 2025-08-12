{stdenv, glibc, linuxHeaders, gcc, overrideCC, wrapCC}:
let
  customGCC = gcc.cc.overrideAttrs (old: {
    configureFlags = old.configureFlags ++ [
      "--enable-version-specific-runtime-libs=no"
      "--libdir=/lib"
    ];

    separateDebugInfo = false;
    outputs = [ "out" ];
    preFixupPhases = [];
    #dontFixup = true;
    installPhase = ''
      make install DESTDIR=$out
    '';
  });
  customStdenv = overrideCC stdenv (wrapCC customGCC);
in
  (glibc.override { stdenv = customStdenv; })
  .overrideAttrs (oldAttrs: {
    separateDebugInfo = false;
    outputs = [ "out" ];

    configureFlags = oldAttrs.configureFlags ++ [
      "--with-headers=${linuxHeaders}/include"
      "--prefix="
      "--libdir=/lib"
      "--libexecdir=/lib"
      "--sysconfdir=/etc"
      "--enable-kernel=6.12"
      "--disable-werror"

    ];

    patches = [];
    dontFixup = true;
    installPhase = ''
      make install DESTDIR=$out
    '';

    #postInstall = (oldAttrs.postInstall or "") + ''
    #  mkdir -p $out/lib
    #  ln -sf $out/lib/ld-linux-x86-64.so.2 $out/lib/ld.so
    #'';
  })
