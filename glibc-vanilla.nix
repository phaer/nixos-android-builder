{ lib, stdenv, glibc, linuxHeaders, libgcc }:

let
  customLibGcc = stdenv.mkDerivation {
    pname = "libgcc-from-gcc-static";
    inherit (libgcc) version buildInputs nativeBuildInputs;

    src = libgcc.src;

    outputs = [ "out" ];  # Only one output

    dontFixup = true;     # No patchelf, no stripping, no rpath fiddling

    configurePhase = ''
      ./configure \
        --disable-multilib \
        --enable-languages=c \
        --disable-bootstrap \
        --with-glibc-version=${glibc.version} \
        --disable-nls \
        --enable-static \
        --disable-shared
    '';

    CFLAGS   = libgcc.CFLAGS_FOR_BUILD or "";
    CXXFLAGS = libgcc.CXXFLAGS_FOR_BUILD or "";

    buildPhase = ''
      make
    '';

    #installPhase = ''
    #  mkdir -p $out/lib
    #  cp libgcc/libgcc.a $out/lib/
    #'';
  };
in
glibc.overrideAttrs (oldAttrs: {
  separateDebugInfo = false;
  outputs = [ "out" ];

  configureFlags = (oldAttrs.configureFlags or []) ++ [
    "--with-headers=${linuxHeaders}/include"
    "--prefix=/"
    "--libdir=/lib"
    "--libexecdir=/lib"
    "--sysconfdir=/etc"
    "--enable-kernel=6.12"
    "--disable-werror"
  ];

  nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ customLibGcc ];

  # We link with static libgcc.a, so add its path to LDFLAGS
  NIX_LDFLAGS = "-L${customLibGcc}/lib -lgcc";

  dontFixup = true;

  installPhase = ''
    make install DESTDIR=$out
  '';
})
