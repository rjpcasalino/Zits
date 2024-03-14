{ lib, stdenv, fetchFromGitHub, kernel, bc, nukeReferences }:

stdenv.mkDerivation {
  pname = "rtl8852bu";
  version = "${kernel.version}-unstable-2024-03-11";

  src = fetchFromGitHub {
    owner = "lwfinger";
    repo = "rtl8852bu";
    rev = "446ccb1a0e4b6445ae3978bb093500eb95f3bf2a";
    hash = "sha256-0mkC39PZw/Te0kENxWJTWv+mmH2QpmUcuSLAXv0Dj9g=";
  };

  nativeBuildInputs = [ bc nukeReferences ] ++ kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" "format" ];

  prePatch = ''
    substituteInPlace ./Makefile \
      --replace /lib/modules/ "${kernel.dev}/lib/modules/" \
      --replace /sbin/depmod \# \
      --replace '$(MODDESTDIR)' "$out/lib/modules/${kernel.modDirVersion}/kernel/net/wireless/" \
      --replace '/usr/lib/systemd/system-sleep' "$out/usr/lib/systemd/system-sleep"
    substituteInPlace ./platform/i386_pc.mk \
      --replace /lib/modules "${kernel.dev}/lib/modules"
  '';

  makeFlags = [
    "ARCH=${stdenv.hostPlatform.linuxArch}"
    ("CONFIG_PLATFORM_I386_PC=" + (if stdenv.hostPlatform.isx86 then "y" else "n"))
    ("CONFIG_PLATFORM_ARM_RPI=" + (if stdenv.hostPlatform.isAarch then "y" else "n"))
  ] ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
  ];

  preInstall = ''
    mkdir -p "$out/lib/modules/${kernel.modDirVersion}/kernel/net/wireless/"
    mkdir -p "$out/usr/lib/systemd/system-sleep"
  '';

  postInstall = ''
    nuke-refs $out/lib/modules/*/kernel/net/wireless/*.ko
  '';

  enableParallelBuilding = true;

  meta = with lib; {
    description = "Driver for Realtek 802.11ax, rtl8852bu, provides the 8852bu mod";
    homepage = "https://github.com/lwfinger/rtl8852bu";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
    maintainers = with maintainers; [ lonyelon ];
  };
}

