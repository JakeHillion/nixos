# SSH host public keys for all managed systems.
#
# `systems` mirrors the domain hierarchy for convenient nested access:
#   systems.me.jakehillion.neb.<location>.<hostname>
#
# `byFqdn` flattens to FQDN → key for direct lookups.
rec {
  systems = {
    me = {
      jakehillion = {
        neb = {
          cx = {
            boron = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDtcJ7HY/vjtheMV8EN2wlTw1hU53CJebGIeRJcSkzt5 root@boron";
            fanboy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIef6aIA1FBDoj8r2EQc8jPHxDLEUlNkkb6znMYtJhAp root@fanboy";
            maverick = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMoaX0F3ytrDVfDuCr09dRazk1ZdQaD7/+e9SuMDl8gN root@maverick";
            rooster = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEVOycZ4M9JYWtKnMeHwUgtJ1H+cECHE+67n1JDCLGle root@rooster";
            warlock = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAPwB61OXWt+hpCV+T68MHTk06NptNBRgUTr/44Q6itT root@warlock";
          };
          gw = {
            cyclone = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJM3XMKyjK4gYWkZ2byGewWiNI0RfVXK/wynv7bKzMmJ root@cyclone";
          };
          home = {
            router = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlCj/i2xprN6h0Ik2tthOJQy6Qwq3Ony73+yfbHYTFu root@router";
          };
          lt = {
            be = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILV3OSUT+cqFqrFHZGfn7/xi5FW3n1qjUFy8zBbYs2Sm root@be";
            bob = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBZHzsley+mbIio2UHmmraS0lHnYTwAKb3aOCfi/veoZ root@bob";
          };
          pop = {
            hangman = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPsgC5Q7UXbYpjxsGZaMMVmPA+NKnIvTDYOskbEx88AT root@hangman";
            li = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQWgcDFL9UZBDKHPiEGepT1Qsc4gz3Pee0/XVHJ6V6u root@li";
            slider = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFABZxZAYPVqQ4+ZShrOvPopUrWHrnj47BnFJJwjdpwD root@slider";
            stinger = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID28NGGSaK1OtpQkQnYqSZWSahX25uboiHwhsYQoKKbL root@stinger";
          };
          rig = {
            merlin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN99UrXe3puoW0Jr1bSPRHL6ImLZD9A9sXeE54JFggIC root@merlin";
          };
          st = {
            phoenix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBPQcp9MzabvwbViNmILVNfipMUnwV+5okRfhOuV7+Mt root@phoenix";
          };
          storage = {
            theon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN59psLVu3/sQORA4x3p8H3ei8MCQlcwX5T+k3kBeBMf root@theon";
          };
        };
      };
    };
  };

  # Flatten the nested structure to { "boron.cx.neb.jakehillion.me" = "ssh-ed25519 ..."; ... }
  byFqdn =
    let
      go = path: attrs:
        builtins.foldl'
          (acc: name:
            let
              value = attrs.${name};
              fqdn = if path == "" then name else "${name}.${path}";
            in
            if builtins.isString value
            then acc // { ${fqdn} = value; }
            else acc // (go fqdn value))
          { }
          (builtins.attrNames attrs);
    in
    go "" systems;
}
