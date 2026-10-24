{ ... }:

{
  # Lets prebuilt, dynamically linked Linux binaries run here.
  #
  # NixOS has no /lib64/ld-linux-x86-64.so.2, only a stub that refuses with
  # "Could not start dynamically linked executable". Anything downloaded
  # instead of built by Nix hits it: Mason's language servers for LazyVim
  # (lua-language-server and stylua were both failing, 2026-10-22), VSCodium
  # and JetBrains plugin binaries, prebuilt npm/pip packages, release tarballs.
  #
  # nix-ld puts a real loader at that path and points it at a small set of
  # common libraries. The module's default set is kept on purpose: Mason's
  # binaries need only glibc and libgcc_s, both already in it. Add to
  # programs.nix-ld.libraries when a binary reports a missing .so.
  #
  # It takes effect for new sessions (it exports NIX_LD and
  # NIX_LD_LIBRARY_PATH), and cannot affect anything Nix built, since those
  # binaries never use /lib64.
  programs.nix-ld.enable = true;
}
