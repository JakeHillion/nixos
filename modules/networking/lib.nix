{ lib }:

# IPv4 arithmetic on dotted-quad addresses and CIDR prefixes.

let
  pow2 = n: lib.lists.foldl (acc: _: acc * 2) 1 (lib.lists.range 1 n);

  toInt = address:
    lib.lists.foldl (acc: octet: acc * 256 + lib.strings.toInt octet) 0 (lib.strings.splitString "." address);

  fromInt = n:
    lib.strings.concatMapStringsSep "." (shift: toString (lib.trivial.mod (n / pow2 shift) 256)) [ 24 16 8 0 ];

  parse = cidr:
    let
      parts = lib.strings.splitString "/" cidr;
      prefixLength = lib.strings.toInt (lib.lists.elemAt parts 1);
      size = pow2 (32 - prefixLength);
    in
    {
      inherit prefixLength size;
      base = (toInt (lib.lists.elemAt parts 0)) / size * size;
    };
in
{
  inherit toInt;

  prefixLength = cidr: (parse cidr).prefixLength;

  # The nth address of a prefix, counting the network address as 0.
  host = cidr: n: fromInt ((parse cidr).base + n);

  broadcast = cidr: let p = parse cidr; in fromInt (p.base + p.size - 1);

  contains = cidr: address:
    let p = parse cidr; in (toInt address) / p.size * p.size == p.base;
}
