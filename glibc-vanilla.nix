{glibc, linuxHeaders}:
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

  dontFixup = true;

  installPhase = ''
    make install DESTDIR=$out
  '';
})
